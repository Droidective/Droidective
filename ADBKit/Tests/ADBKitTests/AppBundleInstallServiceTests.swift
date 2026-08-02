import Foundation
import Testing

@testable import ADBKit

@Suite struct AppBundleInstallServiceTests {
    // MARK: argument builders

    @Test func aSingleApkInstallsWithPlainInstallAndReinstall() {
        #expect(AppBundleInstallService.installArguments(apks: ["/w/base.apk"])
            == ["install", "-r", "/w/base.apk"])
    }

    @Test func aSplitSetInstallsInOneInstallMultipleTransaction() {
        #expect(
            AppBundleInstallService.installArguments(
                apks: ["/w/base.apk", "/w/config.arm64_v8a.apk", "/w/config.xxhdpi.apk"])
                == ["install-multiple", "-r", "/w/base.apk", "/w/config.arm64_v8a.apk", "/w/config.xxhdpi.apk"])
    }

    @Test func apksGoBackToBundletoolPinnedToThisAdbAndDevice() {
        #expect(
            AppBundleInstallService.installApksArguments(
                jar: "/t/bundletool.jar", apks: "/in/My App.apks", adb: "/sdk/adb", serial: "emulator-5554")
                == ["-jar", "/t/bundletool.jar", "install-apks", "--apks=/in/My App.apks",
                    "--adb=/sdk/adb", "--device-id=emulator-5554"])
    }

    @Test func expansionsLandUnderExternalStorage() {
        #expect(AppBundleInstallService.remoteExpansionPath("Android/obb/com.a/main.1.com.a.obb")
            == "/sdcard/Android/obb/com.a/main.1.com.a.obb")
        // A leading slash in the container's path doesn't double up.
        #expect(AppBundleInstallService.remoteExpansionPath("/Android/obb/com.a/m.obb")
            == "/sdcard/Android/obb/com.a/m.obb")
    }

    @Test func bundletoolFailuresSurfaceThePackageManagersReasonWhenThereIsOne() {
        #expect(AppBundleInstallService.friendlyBundletoolReason(
            "Error: Installation failed. INSTALL_FAILED_INSUFFICIENT_STORAGE: no space")
            == "Not enough storage on the device.")
        // No adb code in the text → bundletool's own line is the best we have.
        #expect(AppBundleInstallService.friendlyBundletoolReason("Error: The APKs are not signed.")
            == "Error: The APKs are not signed.")
        #expect(AppBundleInstallService.friendlyBundletoolReason("")
            == "bundletool couldn't install this archive.")
    }

    @Test func relativePathsSurviveTheTempDirectorysSymlink() throws {
        // macOS reaches the temp directory through /var → /private/var, so a
        // character-count prefix trim would leak part of the work directory's
        // name into the device path.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("relative-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Android/obb/com.a/main.obb")

        #expect(AppBundleInstallService.relativePath(of: file, under: root) == "Android/obb/com.a/main.obb")
        #expect(AppBundleInstallService.relativePath(of: root, under: root) == nil)
        #expect(AppBundleInstallService.relativePath(
            of: URL(fileURLWithPath: "/elsewhere/x.obb"), under: root) == nil)
    }

    // MARK: format gating

    @Test func rejectsAFileItCannotInstall() async throws {
        let (service, _, cleanup) = try await Self.makeService(runner: BundleRunner())
        defer { cleanup() }
        await #expect(throws: AppBundleInstallService.BundleError.unsupportedFormat("aab")) {
            try await service.install(bundlePath: "/in/app.aab", serial: "S")
        }
        await #expect(throws: AppBundleInstallService.BundleError.unsupportedFormat("")) {
            try await service.install(bundlePath: "/in/app", serial: "S")
        }
    }

    @Test func aPlainApkTakesTheDirectAdbPathWithNoUnpacking() async throws {
        let runner = BundleRunner()
        runner.installOutput = "Success"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        let result = try await service.install(bundlePath: "/in/app.apk", serial: "S")

        #expect(result.ok)
        #expect(runner.invocations.count == 1)
        #expect(runner.invocations[0].arguments == ["-s", "S", "install", "-r", "/in/app.apk"])
    }

    // MARK: .xapk / .apkm

    @Test func aXapkUnpacksSelectsForTheDeviceAndInstallsInOneTransaction() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = [
            "manifest.json": Self.manifestJSON,
            "com.example.game.apk": "base",
            "config.arm64_v8a.apk": "abi",
            "config.armeabi_v7a.apk": "abi",
            "config.x86.apk": "abi",
            "config.xxhdpi.apk": "density",
            "config.hdpi.apk": "density",
            "config.en.apk": "lang",
            "config.fr.apk": "lang",
        ]
        runner.installOutput = "Success"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        let stages = StageLog()
        let result = try await service.install(bundlePath: "/in/game.xapk", serial: "S") { stages.add($0) }

        #expect(result.ok)
        // Unpack first, into a directory the service owns.
        let unpack = try #require(runner.invocations.first)
        #expect(unpack.executable == HostArchive.unzipExecutable)
        #expect(unpack.arguments.contains("/in/game.xapk"))
        // One install-multiple carrying exactly the base, the device's ABI, the
        // nearest density, and its languages — not the whole archive.
        let install = try #require(runner.invocations.last { $0.arguments.contains("install-multiple") })
        let names = install.arguments
            .filter { $0.hasSuffix(".apk") }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        #expect(names == ["com.example.game.apk", "config.arm64_v8a.apk", "config.xxhdpi.apk", "config.en.apk"])
        #expect(install.arguments.starts(with: ["-s", "S", "install-multiple", "-r"]))
        #expect(stages.all.contains(.unpacking))
        #expect(stages.all.contains(.installing(count: 4)))
    }

    @Test func anApkmWithoutASplitListScansTheUnpackedTree() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = [
            "info.json": #"{"pname":"com.example.app","release_version":"8.4.2"}"#,
            "base.apk": "base",
            "split_config.arm64_v8a.apk": "abi",
            "split_config.x86_64.apk": "abi",
        ]
        runner.installOutput = "Success"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        let result = try await service.install(bundlePath: "/in/app.apkm", serial: "S")

        #expect(result.ok)
        let install = try #require(runner.invocations.last { $0.arguments.contains("install-multiple") })
        let names = install.arguments
            .filter { $0.hasSuffix(".apk") }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        #expect(names == ["base.apk", "split_config.arm64_v8a.apk"])
    }

    @Test func aContainerHoldingASingleApkUsesPlainInstall() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = ["standalone.apk": "base"]
        runner.installOutput = "Success"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        #expect(try await service.install(bundlePath: "/in/one.xapk", serial: "S").ok)
        let install = try #require(runner.invocations.last { $0.arguments.contains("install") })
        #expect(install.arguments.starts(with: ["-s", "S", "install", "-r"]))
        #expect(!install.arguments.contains("install-multiple"))
    }

    @Test func refusesToInstallWhenNoAbiSplitMatchesTheDevice() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = ["base.apk": "base", "config.x86.apk": "abi", "config.x86_64.apk": "abi"]
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        await #expect(throws: AppBundleInstallService.BundleError.abiUnmatched(
            deviceABIs: ["arm64-v8a", "armeabi-v7a"])
        ) {
            try await service.install(bundlePath: "/in/app.xapk", serial: "S")
        }
        // Nothing was pushed to the device — the failure happens on the host.
        #expect(!runner.invocations.contains { $0.arguments.contains("install-multiple") })
    }

    @Test func anArchiveWithNoApksInsideFailsWithAClearReason() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = ["manifest.json": "{}", "readme.txt": "hi"]
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        await #expect(throws: AppBundleInstallService.BundleError.noPackagesFound("XAPK")) {
            try await service.install(bundlePath: "/in/empty.xapk", serial: "S")
        }
    }

    @Test func aFailedUnpackDoesNotReachTheDevice() async throws {
        let runner = BundleRunner()
        runner.unzipExitCode = 2
        runner.unzipStderr = "End-of-central-directory signature not found"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        await #expect(throws: AppBundleInstallService.BundleError.self) {
            try await service.install(bundlePath: "/in/corrupt.xapk", serial: "S")
        }
        #expect(runner.invocations.count == 1)
    }

    @Test func aUnzipWarningStillInstallsWhenTheApksLanded() async throws {
        // unzip exits 1 for recoverable warnings having written the archive.
        let runner = BundleRunner()
        runner.unzipExitCode = 1
        runner.extractedFiles = ["base.apk": "base"]
        runner.installOutput = "Success"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        #expect(try await service.install(bundlePath: "/in/warned.xapk", serial: "S").ok)
    }

    @Test func adbsOwnInstallFailureComesBackAsAResultNotTheThrownError() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = ["base.apk": "base", "config.arm64_v8a.apk": "abi"]
        runner.installOutput = "Failure [INSTALL_FAILED_VERSION_DOWNGRADE]"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        let result = try await service.install(bundlePath: "/in/app.xapk", serial: "S")
        #expect(!result.ok)
        #expect(result.message == "A newer version is already installed.")
    }

    @Test func theUnpackDirectoryIsSweptEvenWhenTheInstallFails() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = ["base.apk": "base"]
        runner.installOutput = "Failure [INSTALL_FAILED_INVALID_APK]"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        _ = try await service.install(bundlePath: "/in/app.xapk", serial: "S")
        let unpackDir = try #require(runner.lastUnpackDirectory)
        #expect(!FileManager.default.fileExists(atPath: unpackDir.path))
    }

    // MARK: OBB expansions

    @Test func expansionFilesArePushedAfterASuccessfulInstall() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = [
            "manifest.json": Self.manifestJSON,
            "com.example.game.apk": "base",
            "config.arm64_v8a.apk": "abi",
            "config.xxhdpi.apk": "density",
            "config.en.apk": "lang",
            "Android/obb/com.example.game/main.310.com.example.game.obb": "obb bytes",
        ]
        runner.installOutput = "Success"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        let stages = StageLog()
        let result = try await service.install(bundlePath: "/in/game.xapk", serial: "S") { stages.add($0) }

        #expect(result.ok)
        #expect(result.message == "Installed with 1 expansion file")
        // The parent directory is created through the device shell, so its path
        // must arrive quoted; the push itself rides the sync protocol unquoted.
        let mkdir = try #require(runner.invocations.last { $0.arguments.contains("mkdir") })
        #expect(mkdir.arguments == [
            "-s", "S", "shell", "mkdir", "-p", "'/sdcard/Android/obb/com.example.game'",
        ])
        let push = try #require(runner.invocations.last { $0.arguments.contains("push") })
        #expect(push.arguments.last == "/sdcard/Android/obb/com.example.game/main.310.com.example.game.obb")
        #expect(stages.all.contains(.pushingExpansion(
            name: "main.310.com.example.game.obb", index: 1, total: 1)))
        // Expansions come after the install, never before it.
        let installIndex = try #require(runner.invocations.firstIndex { $0.arguments.contains("install-multiple") })
        let pushIndex = try #require(runner.invocations.firstIndex { $0.arguments.contains("push") })
        #expect(installIndex < pushIndex)
    }

    @Test func obbFilesAreFoundByConventionWhenTheManifestOmitsThem() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = [
            "base.apk": "base",
            "Android/obb/com.example.app/patch.2.com.example.app.obb": "obb",
        ]
        runner.installOutput = "Success"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        #expect(try await service.install(bundlePath: "/in/app.xapk", serial: "S").ok)
        let push = try #require(runner.invocations.last { $0.arguments.contains("push") })
        #expect(push.arguments.last == "/sdcard/Android/obb/com.example.app/patch.2.com.example.app.obb")
    }

    @Test func aFailedExpansionPushReportsTheAppAsInstalledButIncomplete() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = ["base.apk": "base", "Android/obb/com.a/main.1.com.a.obb": "obb"]
        runner.installOutput = "Success"
        runner.pushFails = true
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        let result = try await service.install(bundlePath: "/in/app.xapk", serial: "S")
        #expect(!result.ok)
        #expect(result.message.contains("Installed, but couldn't copy main.1.com.a.obb"))
    }

    @Test func aBundleWithNoExpansionsNeverTouchesTheDeviceFilesystem() async throws {
        let runner = BundleRunner()
        runner.extractedFiles = ["base.apk": "base"]
        runner.installOutput = "Success"
        let (service, _, cleanup) = try await Self.makeService(runner: runner)
        defer { cleanup() }

        #expect(try await service.install(bundlePath: "/in/app.xapk", serial: "S").message == "Installed")
        #expect(!runner.invocations.contains { $0.arguments.contains("push") })
        #expect(!runner.invocations.contains { $0.arguments.contains("mkdir") })
    }

    // MARK: .apks

    @Test func anApksArchiveIsHandedToBundletool() async throws {
        let runner = BundleRunner()
        let (service, _, cleanup) = try await Self.makeService(runner: runner, bundletoolInstalled: true)
        defer { cleanup() }

        let result = try await service.install(bundlePath: "/in/app.apks", serial: "S")

        #expect(result.ok)
        let call = try #require(runner.invocations.first)
        #expect(call.executable == "/fake/java")
        #expect(call.arguments[2] == "install-apks")
        #expect(call.arguments.contains("--apks=/in/app.apks"))
        #expect(call.arguments.contains("--adb=/fake/adb"))
        #expect(call.arguments.contains("--device-id=S"))
        // Nothing is unpacked on the host — bundletool reads the archive itself.
        #expect(!runner.invocations.contains { $0.executable == HostArchive.unzipExecutable })
    }

    @Test func anApksArchiveWithoutBundletoolPointsAtTheToolsSettings() async throws {
        let (service, _, cleanup) = try await Self.makeService(runner: BundleRunner(), bundletoolInstalled: false)
        defer { cleanup() }
        await #expect(throws: AppBundleInstallService.BundleError.toolMissing("bundletool")) {
            try await service.install(bundlePath: "/in/app.apks", serial: "S")
        }
    }

    @Test func bundletoolsFailureBecomesAFailedResultCarryingItsOutput() async throws {
        let runner = BundleRunner()
        runner.bundletoolExitCode = 1
        runner.bundletoolStderr = "Error: Installation failed. INSTALL_FAILED_NO_MATCHING_ABIS"
        let (service, _, cleanup) = try await Self.makeService(runner: runner, bundletoolInstalled: true)
        defer { cleanup() }

        let result = try await service.install(bundlePath: "/in/app.apks", serial: "S")
        #expect(!result.ok)
        #expect(result.message == "The APK has no native code for this device's CPU.")
        #expect(result.copyText?.contains("INSTALL_FAILED_NO_MATCHING_ABIS") == true)
    }

    // MARK: helpers

    private static let manifestJSON = """
    {"package_name": "com.example.game", "name": "Example Game", "version_code": 310,
     "split_apks": [
       {"file": "com.example.game.apk"}, {"file": "config.arm64_v8a.apk"},
       {"file": "config.armeabi_v7a.apk"}, {"file": "config.x86.apk"},
       {"file": "config.xxhdpi.apk"}, {"file": "config.hdpi.apk"},
       {"file": "config.en.apk"}, {"file": "config.fr.apk"}],
     "expansions": [
       {"file": "Android/obb/com.example.game/main.310.com.example.game.obb",
        "install_path": "Android/obb/com.example.game/main.310.com.example.game.obb"}]}
    """

    /// A service over a seeded adb, java, and (optionally) an installed
    /// bundletool. Returns a cleanup closure removing the tool store root.
    private static func makeService(
        runner: BundleRunner, bundletoolInstalled: Bool = false
    ) async throws -> (AppBundleInstallService, AdbClient, () -> Void) {
        let locator = ToolLocator(runner: runner, environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        await locator.seedJava("/fake/java")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-store-\(UUID().uuidString)")
        if bundletoolInstalled {
            let versionDir = root.appendingPathComponent("bundletool/1.18.3")
            try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
            try Data("jar".utf8).write(to: versionDir.appendingPathComponent("bundletool-all-1.18.3.jar"))
            try Data("1.18.3".utf8).write(to: root.appendingPathComponent("bundletool/current.txt"))
        }
        let client = AdbClient(locator: locator, runner: runner, log: CommandLog())
        let service = AppBundleInstallService(
            client: client, toolchain: ApkToolchain(locator: locator, store: ManagedToolStore(rootDirectory: root)),
            runner: runner)
        return (service, client, { try? FileManager.default.removeItem(at: root) })
    }
}

/// Collects `onStage` callbacks from a `@Sendable` closure.
private final class StageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [AppBundleInstallService.Stage] = []

    var all: [AppBundleInstallService.Stage] {
        lock.lock()
        defer { lock.unlock() }
        return stages
    }

    func add(_ stage: AppBundleInstallService.Stage) {
        lock.lock()
        stages.append(stage)
        lock.unlock()
    }
}

/// Stands in for unzip, adb, and bundletool at once: unzip writes a configured
/// file tree into the destination the service chose, `getprop` answers with an
/// arm64 420 dpi English device, and the install/push calls return scripted
/// output. It records every invocation so tests can assert argument vectors.
private final class BundleRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation { let executable: String; let arguments: [String] }

    /// Archive-relative path → contents, written on the unzip call.
    var extractedFiles: [String: String] = [:]
    var unzipExitCode: Int32 = 0
    var unzipStderr = ""
    /// What `adb install`/`install-multiple` prints.
    var installOutput = "Success"
    var pushFails = false
    var bundletoolExitCode: Int32 = 0
    var bundletoolStderr = ""

    /// The temp directory the service unpacked into, for the sweep assertion.
    private(set) var lastUnpackDirectory: URL?

    private let lock = NSLock()
    private var recorded: [Invocation] = []

    var invocations: [Invocation] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private static let props = """
    [ro.product.cpu.abilist]: [arm64-v8a,armeabi-v7a]
    [ro.sf.lcd_density]: [420]
    [persist.sys.locale]: [en-US]
    """

    func run(executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int) async -> ProcessOutput {
        record(Invocation(executable: executable, arguments: arguments))
        if executable == HostArchive.unzipExecutable { return unzip(arguments) }
        if arguments.contains("install-apks") {
            return output(exitCode: bundletoolExitCode, stderr: bundletoolStderr)
        }
        if arguments.contains("getprop") { return output(stdout: Self.props) }
        if arguments.contains("push") {
            return pushFails
                ? output(exitCode: 1, stderr: "adb: error: failed to copy")
                : output(stdout: "1 file pushed")
        }
        if arguments.contains("install") || arguments.contains("install-multiple") {
            return output(stdout: installOutput)
        }
        return output()
    }

    private func record(_ invocation: Invocation) {
        lock.lock()
        recorded.append(invocation)
        lock.unlock()
    }

    /// Write the configured tree into the `-d` (POSIX) / `-C` (Windows)
    /// destination, the way the real unzip would.
    private func unzip(_ arguments: [String]) -> ProcessOutput {
        guard let flag = arguments.firstIndex(where: { $0 == "-d" || $0 == "-C" }),
              arguments.count > flag + 1
        else { return output(exitCode: unzipExitCode, stderr: unzipStderr) }
        let destination = URL(fileURLWithPath: arguments[flag + 1])
        lastUnpackDirectory = destination
        for (relative, contents) in extractedFiles {
            let file = destination.appendingPathComponent(relative)
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(contents.utf8).write(to: file)
        }
        return output(exitCode: unzipExitCode, stderr: unzipStderr)
    }

    private func output(stdout: String = "", exitCode: Int32 = 0, stderr: String = "") -> ProcessOutput {
        ProcessOutput(stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), exitCode: exitCode, timedOut: false)
    }
}
