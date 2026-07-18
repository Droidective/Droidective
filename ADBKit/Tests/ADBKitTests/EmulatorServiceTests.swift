import Testing

@testable import ADBKit

@Suite struct EmulatorServiceTests {
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
