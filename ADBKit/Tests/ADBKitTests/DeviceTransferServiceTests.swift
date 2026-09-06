import Foundation
import Testing
@testable import ADBKit

@Suite struct DeviceTransferServiceTests {
    private func makeService(_ runner: MockProcessRunner) async -> DeviceTransferService {
        DeviceTransferService(client: await makeTestClient(runner: runner))
    }

    /// A device that accepts everything and reports Android 14.
    private func scriptHealthyDevice(_ runner: MockProcessRunner) {
        runner.script(argsPrefix: ["-s", "S1"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop", "ro.build.version.sdk"], stdout: "34\n")
    }

    private func args(_ runner: MockProcessRunner) -> [[String]] {
        runner.invocations.map(\.arguments)
    }

    // MARK: - The happy path, as an argument vector

    @Test func aCopyMakesTheFolderPushesThenIndexes() async throws {
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        let service = await makeService(runner)
        let outcome = try await service.copyToDevice(
            paths: ["/Users/me/notes.pdf"], toDir: "/sdcard/Download", serial: "S1")

        #expect(outcome.ok)
        #expect(outcome.copied == 1)
        let vectors = args(runner)
        #expect(vectors.contains(["-s", "S1", "shell", "mkdir", "-p", "'/sdcard/Download'"]))
        // The push rides the sync protocol: no device shell, so no quoting.
        #expect(vectors.contains(["-s", "S1", "push", "/Users/me/notes.pdf", "/sdcard/Download/notes.pdf"]))
        #expect(vectors.contains([
            "-s", "S1", "shell", "content", "call",
            "--uri", "content://media/external/file",
            "--method", "scan_file", "--arg", "'/sdcard/Download/notes.pdf'",
        ]))
    }

    @Test func theDestinationIsMadeBeforeAnythingIsPushed() async throws {
        // /sdcard/Download is missing on a freshly wiped emulator, and an
        // `adb push` into a directory that isn't there fails obscurely.
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        let service = await makeService(runner)
        _ = try await service.copyToDevice(paths: ["/a.txt"], toDir: "/sdcard/Drops", serial: "S1")
        let vectors = args(runner)
        let mkdir = try #require(vectors.firstIndex { $0.contains("mkdir") })
        let push = try #require(vectors.firstIndex { $0.contains("push") })
        #expect(mkdir < push)
    }

    @Test func indexingRunsAfterEveryPushNotBetweenThem() async throws {
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        let service = await makeService(runner)
        _ = try await service.copyToDevice(paths: ["/a.png", "/b.png"], toDir: "/sdcard/Download", serial: "S1")
        let vectors = args(runner)
        let lastPush = try #require(vectors.lastIndex { $0.contains("push") })
        let firstScan = try #require(vectors.firstIndex { $0.contains("scan_file") })
        #expect(lastPush < firstScan)
    }

    // MARK: - Quoting, which is the security boundary here

    @Test func aHostileFolderNameIsQuotedIntoMkdir() async throws {
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        let service = await makeService(runner)
        let dir = "/sdcard/a'; touch /sdcard/pwned; echo '"
        _ = try await service.copyToDevice(paths: ["/a.txt"], toDir: dir, serial: "S1")
        #expect(args(runner).contains(["-s", "S1", "shell", "mkdir", "-p", shellQuote(dir)]))
    }

    @Test func aHostileFileNameIsQuotedIntoTheScanAndTheCleanup() async throws {
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        let service = await makeService(runner)
        // The name is whatever Finder had. It reaches `adb shell` through the
        // media scan and through the cancel cleanup; both must quote it.
        let local = "/Users/me/x'; touch /sdcard/pwned; echo '.png"
        _ = try await service.copyToDevice(paths: [local], toDir: "/sdcard/Download", serial: "S1")
        let remote = DeviceTransferService.remotePath(forLocal: local, inDir: "/sdcard/Download")
        #expect(args(runner).contains { $0.last == shellQuote(remote) })

        await service.removeRemote(path: remote, serial: "S1")
        #expect(args(runner).contains(["-s", "S1", "shell", "rm", "-f", shellQuote(remote)]))
    }

    @Test func remoteSizeQuotesTheStatPath() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "stat"], stdout: "40108\n")
        let service = await makeService(runner)
        let size = await service.remoteSize(of: "/sdcard/Download/a b.mp4", serial: "S1")
        #expect(size == 40108)
        #expect(args(runner).contains([
            "-s", "S1", "shell", "stat", "-c", "%s", "'/sdcard/Download/a b.mp4'",
        ]))
    }

    // MARK: - Destination paths

    @Test func aTrailingSlashDoesNotDoubleUp() {
        #expect(DeviceTransferService.remotePath(forLocal: "/a/b.txt", inDir: "/sdcard/Download/")
            == "/sdcard/Download/b.txt")
        #expect(DeviceTransferService.remotePath(forLocal: "/a/b.txt", inDir: "/sdcard/Download")
            == "/sdcard/Download/b.txt")
    }

    @Test func aFolderKeepsItsOwnNameOnTheDevice() {
        #expect(DeviceTransferService.remotePath(forLocal: "/Users/me/assets", inDir: "/sdcard/Download")
            == "/sdcard/Download/assets")
    }

    // MARK: - Failure

    @Test func oneBadFileDoesNotAbandonTheRest() async throws {
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        runner.script(
            argsPrefix: ["-s", "S1", "push", "/b.txt"],
            stderr: "adb: error: failed to copy: No space left on device", exitCode: 1)
        let service = await makeService(runner)
        let outcome = try await service.copyToDevice(
            paths: ["/a.txt", "/b.txt", "/c.txt"], toDir: "/sdcard/Download", serial: "S1")

        #expect(outcome.ok == false)
        #expect(outcome.copied == 2)
        #expect(outcome.total == 3)
        #expect(outcome.failures.count == 1)
        #expect(outcome.failures[0].hasPrefix("b.txt: "))
        #expect(outcome.summary == "Copied 2 of 3 — 1 failed")
        // c.txt was still tried.
        #expect(args(runner).contains { $0.contains("/c.txt") })
    }

    @Test func aFileThatFailedIsNotHandedToTheMediaScanner() async throws {
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        runner.script(argsPrefix: ["-s", "S1", "push", "/b.png"], stderr: "failed", exitCode: 1)
        let service = await makeService(runner)
        _ = try await service.copyToDevice(paths: ["/a.png", "/b.png"], toDir: "/sdcard/Download", serial: "S1")
        let scans = args(runner).filter { $0.contains("scan_file") }
        #expect(scans.count == 1)
        #expect(scans[0].last == "'/sdcard/Download/a.png'")
    }

    @Test func everythingFailingReportsTheReasonNotACount() async throws {
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        runner.script(argsPrefix: ["-s", "S1", "push"], stderr: "adb: error: no space", exitCode: 1)
        let service = await makeService(runner)
        let outcome = try await service.copyToDevice(paths: ["/a.txt"], toDir: "/sdcard/Download", serial: "S1")
        #expect(outcome.copied == 0)
        #expect(outcome.summary.hasPrefix("a.txt: "))
        #expect(outcome.detail?.isEmpty == false)
    }

    @Test func aFailedScanNeverFailsTheCopy() async throws {
        // The bytes are on the device; an unindexed file is a cosmetic loss.
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        runner.script(argsPrefix: ["-s", "S1", "shell", "content"], stderr: "no such provider", exitCode: 1)
        let service = await makeService(runner)
        let outcome = try await service.copyToDevice(paths: ["/a.png"], toDir: "/sdcard/Download", serial: "S1")
        #expect(outcome.ok)
    }

    @Test func nothingDroppedRunsNoCommands() async throws {
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        let service = await makeService(runner)
        let outcome = try await service.copyToDevice(paths: [], toDir: "/sdcard/Download", serial: "S1")
        #expect(outcome.total == 0)
        #expect(runner.invocations.isEmpty)
    }

    @Test func anOldDeviceGetsTheBroadcastScan() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop", "ro.build.version.sdk"], stdout: "26\n")
        let service = await makeService(runner)
        _ = try await service.copyToDevice(paths: ["/a.png"], toDir: "/sdcard/Download", serial: "S1")
        #expect(args(runner).contains { $0.contains("android.intent.action.MEDIA_SCANNER_SCAN_FILE") })
    }

    @Test func anUnreadableSdkPropStillCopies() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop"], stderr: "boom", exitCode: 1)
        let service = await makeService(runner)
        let outcome = try await service.copyToDevice(paths: ["/a.png"], toDir: "/sdcard/Download", serial: "S1")
        #expect(outcome.ok)
        #expect(args(runner).contains { $0.contains("scan_file") })
    }

    @Test func remoteSizeIsNilWhenTheFileIsNotThereYet() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "stat"], stderr: "No such file", exitCode: 1)
        let service = await makeService(runner)
        #expect(await service.remoteSize(of: "/sdcard/Download/a", serial: "S1") == nil)
    }

    @Test func remoteSizeIsNilWhenStatAnswersWithSomethingElse() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "stat"], stdout: "stat: unknown option\r\n")
        let service = await makeService(runner)
        #expect(await service.remoteSize(of: "/sdcard/Download/a", serial: "S1") == nil)
    }

    @Test func remoteSizeSurvivesCarriageReturns() async throws {
        // adb hands back CRLF on some devices, and "40108\r" is not an Int.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "stat"], stdout: "40108\r\n")
        let service = await makeService(runner)
        #expect(await service.remoteSize(of: "/sdcard/Download/a", serial: "S1") == 40108)
    }

    // MARK: - Stages

    @Test func stagesNameEachFileAsItGoes() async throws {
        let runner = MockProcessRunner()
        scriptHealthyDevice(runner)
        let service = await makeService(runner)
        let box = StageBox()
        _ = try await service.copyToDevice(
            paths: ["/a.txt", "/b.txt"], toDir: "/sdcard/Download", serial: "S1",
            onStage: { box.append($0) })
        #expect(box.stages == [
            .preparing,
            .copying(name: "a.txt", index: 1, total: 2),
            .copying(name: "b.txt", index: 2, total: 2),
            .indexing,
        ])
    }
}

/// Collects stage callbacks from the transfer's `@Sendable` closure.
private final class StageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [DeviceTransferService.Stage] = []

    var stages: [DeviceTransferService.Stage] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func append(_ stage: DeviceTransferService.Stage) {
        lock.lock(); recorded.append(stage); lock.unlock()
    }
}
