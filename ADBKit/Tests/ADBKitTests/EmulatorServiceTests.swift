import Foundation
import Testing

@testable import ADBKit

@Suite struct EmulatorServiceTests {
    /// A service whose AVD home is a fresh temp dir (no adb/emulator needed
    /// for the file-level wipe paths).
    private func makeService(avdHome: URL) async -> EmulatorService {
        let runner = MockProcessRunner()
        let locator = ToolLocator(runner: runner, environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        return EmulatorService(
            client: AdbClient(locator: locator, runner: runner, log: CommandLog()),
            locator: locator, runner: runner, avdHome: avdHome
        )
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("avd-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func avdIniPathParses() {
        #expect(EmulatorService.parseAvdIniPath(
            "avd.ini.encoding=UTF-8\r\npath=/Users/dev/.android/avd/Pixel_8.avd\r\ntarget=android-35\r\n"
        ) == "/Users/dev/.android/avd/Pixel_8.avd")
        #expect(EmulatorService.parseAvdIniPath("target=android-35") == nil)
        #expect(EmulatorService.parseAvdIniPath("") == nil)
    }

    @Test func wipeDeletesUserDataButKeepsConfig() async throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let dataDir = home.appendingPathComponent("Pixel_8.avd")
        let snapshots = dataDir.appendingPathComponent("snapshots/default_boot")
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        for file in ["userdata-qemu.img", "userdata-qemu.img.qcow2", "cache.img", "config.ini"] {
            try Data("x".utf8).write(to: dataDir.appendingPathComponent(file))
        }
        try Data("s".utf8).write(to: snapshots.appendingPathComponent("ram.bin"))
        try Data("path=\(dataDir.path)\n".utf8)
            .write(to: home.appendingPathComponent("Pixel_8.ini"))

        let service = await makeService(avdHome: home)
        let result = await service.wipeData(avd: "Pixel_8")

        #expect(result.ok)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dataDir.path).sorted()
        #expect(remaining == ["config.ini"])
    }

    @Test func wipeFallsBackToTheConventionalDirWithoutAnIni() async throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let dataDir = home.appendingPathComponent("NoIni.avd")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dataDir.appendingPathComponent("userdata-qemu.img"))

        let service = await makeService(avdHome: home)
        let result = await service.wipeData(avd: "NoIni")

        #expect(result.ok)
        #expect(!FileManager.default.fileExists(
            atPath: dataDir.appendingPathComponent("userdata-qemu.img").path))
    }

    @Test func wipeOfAMissingAvdFailsWithThePathInTheMessage() async throws {
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let service = await makeService(avdHome: home)
        let result = await service.wipeData(avd: "Ghost")
        #expect(!result.ok)
        #expect(result.message.contains("Ghost.avd"))
    }

    @Test func stopSendsEmuKillToTheSerial() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "emulator-5554", "emu", "kill"], stdout: "OK: killing emulator")
        let locator = ToolLocator(runner: runner, environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        let service = EmulatorService(
            client: AdbClient(locator: locator, runner: runner, log: CommandLog()),
            locator: locator, runner: runner
        )
        let result = try await service.stop(serial: "emulator-5554")
        #expect(result.ok)
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "emulator-5554", "emu", "kill"]
        })
    }

    @Test func stopFailureSurfacesAFriendlyMessage() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stderr: "error: device offline", exitCode: 1)
        let locator = ToolLocator(runner: runner, environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        let service = EmulatorService(
            client: AdbClient(locator: locator, runner: runner, log: CommandLog()),
            locator: locator, runner: runner
        )
        let result = try await service.stop(serial: "emulator-5554")
        #expect(!result.ok)
        #expect(!result.message.isEmpty)
    }
}
