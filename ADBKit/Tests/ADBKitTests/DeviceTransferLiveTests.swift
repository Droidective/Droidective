import Foundation
import Testing

@testable import ADBKit

/// Tier 3: the drop's copy path against a real device.
///
/// The mock suite proves the argument vectors. This proves the device actually
/// accepts them: that `mkdir -p` makes a destination, that a push with a name
/// full of shell metacharacters lands under that exact name, that `stat -c %s`
/// answers with a number (the whole basis of the progress readout), and that
/// the media-scan command for this device's API level isn't rejected. Every
/// one of those is a device behaviour a mock can only assume.
///
/// Disabled by default. Run with
/// `DEVICE_LIVE_TEST=1 MIRROR_SERIAL=emulator-5554 swift test --filter DeviceTransferLiveTests`.
@Suite struct DeviceTransferLiveTests {
    private static var liveEnabled: Bool {
        ProcessInfo.processInfo.environment["DEVICE_LIVE_TEST"] == "1"
    }

    private static var serial: String {
        ProcessInfo.processInfo.environment["MIRROR_SERIAL"] ?? "emulator-5554"
    }

    private static var adb: AdbClient { AdbClient(locator: ToolLocator()) }

    /// A scratch directory on the device, unique per test and swept afterwards.
    ///
    /// Unique per test on purpose: swift-testing runs a suite's cases in
    /// parallel, and one shared directory means each case's cleanup deletes
    /// what its siblings are still asserting against.
    private func makeRemoteRoot() -> String {
        "/sdcard/Download/droidective-drop-\(UUID().uuidString.prefix(8))"
    }

    private func makeLocalFile(named name: String, bytes: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("droidective-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    private func sweep(_ root: String) async {
        _ = try? await Self.adb.run(
            on: Self.serial, ["shell", "rm", "-rf", shellQuote(root)])
    }

    @Test(.enabled(if: liveEnabled))
    func aCopyLandsAndTheDeviceReportsItsSize() async throws {
        let service = DeviceTransferService(client: Self.adb)
        let local = try makeLocalFile(named: "drop sample.txt", bytes: 4096)
        defer { try? FileManager.default.removeItem(at: local.deletingLastPathComponent()) }
        let root = makeRemoteRoot()
        defer { Task { await sweep(root) } }

        let outcome = try await service.copyToDevice(
            paths: [local.path], toDir: root, serial: Self.serial)
        #expect(outcome.ok, "copy failed: \(outcome.failures)")

        // The destination directory did not exist before this call.
        let remote = DeviceTransferService.remotePath(forLocal: local.path, inDir: root)
        let size = await service.remoteSize(of: remote, serial: Self.serial)
        #expect(size == 4096, "stat -c %s is what the progress readout is built on")
    }

    @Test(.enabled(if: liveEnabled))
    func aNameFullOfShellMetacharactersSurvivesIntact() async throws {
        // The name comes from Finder. If any step joins it into a device shell
        // command unquoted, this either fails or does something else entirely.
        let service = DeviceTransferService(client: Self.adb)
        let awkward = "a b'c$d`e;f&g.txt"
        let local = try makeLocalFile(named: awkward, bytes: 128)
        defer { try? FileManager.default.removeItem(at: local.deletingLastPathComponent()) }
        let root = makeRemoteRoot()
        defer { Task { await sweep(root) } }

        let outcome = try await service.copyToDevice(
            paths: [local.path], toDir: root, serial: Self.serial)
        #expect(outcome.ok, "copy failed: \(outcome.failures)")

        let listing = try await Self.adb.run(
            on: Self.serial, ["shell", "ls", "-a", shellQuote(root)])
        #expect(listing.stdout.contains(awkward), "landed as something else: \(listing.stdout)")

        let remote = DeviceTransferService.remotePath(forLocal: local.path, inDir: root)
        #expect(await service.remoteSize(of: remote, serial: Self.serial) == 128)

        // …and the cleanup path can address it again.
        await service.removeRemote(path: remote, serial: Self.serial)
        let after = try await Self.adb.run(
            on: Self.serial, ["shell", "ls", "-a", shellQuote(root)])
        #expect(!after.stdout.contains(awkward))
    }

    @Test(.enabled(if: liveEnabled))
    func theMediaScanCommandIsAcceptedByThisDevice() async throws {
        // A rejected scan doesn't fail a copy by design, so nothing else would
        // ever tell us the command is wrong for this API level.
        let sdk = Int(try await DeviceProps.get(
            client: Self.adb, serial: Self.serial, "ro.build.version.sdk"
        ).trimmingCharacters(in: .whitespaces))
        let service = DeviceTransferService(client: Self.adb)
        let local = try makeLocalFile(named: "scan-me.png", bytes: 64)
        defer { try? FileManager.default.removeItem(at: local.deletingLastPathComponent()) }
        let root = makeRemoteRoot()
        defer { Task { await sweep(root) } }

        _ = try await service.copyToDevice(
            paths: [local.path], toDir: root, serial: Self.serial)
        let remote = DeviceTransferService.remotePath(forLocal: local.path, inDir: root)
        let scan = try await Self.adb.run(
            on: Self.serial, MediaScan.command(sdk: sdk, path: remote))
        #expect(scan.succeeded, "scan rejected: \(scan.stderr)")
        #expect(!scan.stderr.localizedCaseInsensitiveContains("unknown"), "\(scan.stderr)")
    }

    @Test(.enabled(if: liveEnabled))
    func aFolderCopiesWithItsContents() async throws {
        let service = DeviceTransferService(client: Self.adb)
        let localRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("droidective-drop-\(UUID().uuidString)")
        let folder = localRoot.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: folder.appendingPathComponent("one.txt"))
        try Data("two".utf8).write(to: folder.appendingPathComponent("two.txt"))
        defer { try? FileManager.default.removeItem(at: localRoot) }
        let root = makeRemoteRoot()
        defer { Task { await sweep(root) } }

        let outcome = try await service.copyToDevice(
            paths: [folder.path], toDir: root, serial: Self.serial)
        #expect(outcome.ok, "copy failed: \(outcome.failures)")
        let listing = try await Self.adb.run(
            on: Self.serial, ["shell", "ls", shellQuote(root + "/assets")])
        #expect(listing.stdout.contains("one.txt"))
        #expect(listing.stdout.contains("two.txt"))
    }
}
