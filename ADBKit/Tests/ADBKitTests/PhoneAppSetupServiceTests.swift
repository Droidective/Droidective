import Foundation
import Testing
@testable import ADBKit

/// Real output, captured from an API 36 emulator running Droidective for
/// Android 0.1.0 and Shizuku 13.6.0.
private enum Captured {
    static let shizukuApk =
        "/data/app/~~Tqv0ajxx7ZKViSFmu0dX_g==/moe.shizuku.privileged.api-Nejv767lxtTyLy4tWw7v-w=="
    static let pmPath = "package:\(shizukuApk)/base.apk\n"
    /// The starter as the device shell receives it: one quoted word.
    static let starterWord = "'\(shizukuApk)/lib/arm64/libshizuku.so'"
    static let starter = """
        info: starter begin
        info: killing old process...
        info: killed 9456 (shizuku_server)
        info: apk path is \(shizukuApk)/base.apk
        info: starting server...
        info: shizuku_server pid is 16869
        info: shizuku_starter exit with 0

        """

    /// The relevant slice of `dumpsys package com.droidective.android`.
    static func dumpsys(granted: Set<String>, version: String = "0.1.0") -> String {
        var lines = [
            "Packages:",
            "  Package [com.droidective.android] (8c1e2d4):",
            "    appId=10215",
            "    versionCode=1 minSdk=26 targetSdk=36",
            "    versionName=\(version)",
            "    requested permissions:",
            "      android.permission.WRITE_SECURE_SETTINGS",
            "      android.permission.DUMP",
            "      android.permission.INTERNET",
            "    install permissions:",
            "      android.permission.INTERNET: granted=true",
        ]
        for permission in granted.sorted() {
            lines.append("      \(permission): granted=true")
        }
        lines += [
            "    User 0: ceDataInode=31337 installed=true hidden=false suspended=false",
            "      runtime permissions:",
            "        android.permission.POST_NOTIFICATIONS: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED]",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}

@Suite struct PhoneAppSetupParserTests {
    @Test func installedMeansTheExactPackageLine() {
        let app = PhoneAppSetupService.appPackage
        #expect(PhoneAppSetupService.listsPackage("package:com.droidective.android\n", package: app))
        #expect(PhoneAppSetupService.listsPackage("package:com.droidective.android\r\n", package: app))
        // `pm list packages x` prefix-matches; a debug build is a different app.
        #expect(!PhoneAppSetupService.listsPackage(
            "package:com.droidective.android.debug\n", package: app))
        #expect(!PhoneAppSetupService.listsPackage("", package: app))
        #expect(PhoneAppSetupService.listsPackage(
            "package:com.droidective.android.debug\npackage:com.droidective.android\n", package: app))
    }

    @Test func onlyGrantedTrueLinesCountAsGranted() {
        let granted = PhoneAppSetupService.parseGrantedPermissions(
            Captured.dumpsys(granted: Set(PhoneAppSetupService.requiredPermissions(sdk: 36))))
        #expect(granted.contains("android.permission.WRITE_SECURE_SETTINGS"))
        #expect(granted.contains("android.permission.DUMP"))
        #expect(!granted.contains("android.permission.POST_NOTIFICATIONS"))

        // Before the grant the names are only *requested* — no grant line.
        let requestedOnly = PhoneAppSetupService.parseGrantedPermissions(Captured.dumpsys(granted: []))
        #expect(!requestedOnly.contains("android.permission.WRITE_SECURE_SETTINGS"))
        #expect(!requestedOnly.contains("android.permission.DUMP"))
        #expect(requestedOnly.contains("android.permission.INTERNET"))
    }

    @Test func grantedParsingHandlesFlagsFalseAndCRLF() {
        let text = "      android.permission.DUMP: granted=true, flags=[ GRANTED_BY_DEFAULT]\r\n"
            + "      android.permission.WRITE_SECURE_SETTINGS: granted=false\r\n"
        #expect(PhoneAppSetupService.parseGrantedPermissions(text) == ["android.permission.DUMP"])
        #expect(PhoneAppSetupService.parseGrantedPermissions("").isEmpty)
        #expect(PhoneAppSetupService.parseGrantedPermissions(": granted=true").isEmpty)
    }

    @Test func versionNameComesFromDumpsys() {
        #expect(PhoneAppSetupService.parseVersionName(Captured.dumpsys(granted: [])) == "0.1.0")
        #expect(PhoneAppSetupService.parseVersionName("    versionName=2.3\r\n") == "2.3")
        #expect(PhoneAppSetupService.parseVersionName("    versionName=\n") == nil)
        #expect(PhoneAppSetupService.parseVersionName("Unable to find package") == nil)
    }

    @Test func apkDirectoryIsTheBaseApksParent() {
        #expect(PhoneAppSetupService.parseApkDirectory(Captured.pmPath) == Captured.shizukuApk)
        #expect(PhoneAppSetupService.parseApkDirectory("package:/data/app/x/base.apk\r\n") == "/data/app/x")
        let split = "package:/data/app/x/split_config.arm64_v8a.apk\npackage:/data/app/x/base.apk\n"
        #expect(PhoneAppSetupService.parseApkDirectory(split) == "/data/app/x")
        #expect(PhoneAppSetupService.parseApkDirectory("") == nil)
        #expect(PhoneAppSetupService.parseApkDirectory("package:/data/app/x/split_a.apk") == nil)
    }

    @Test func starterPathFollowsTheAbi() {
        let dir = Captured.shizukuApk
        #expect(PhoneAppSetupService.starterPath(apkDirectory: dir, abi: "arm64-v8a\n")
            == "\(dir)/lib/arm64/libshizuku.so")
        #expect(PhoneAppSetupService.starterPath(apkDirectory: "/d", abi: "armeabi-v7a")
            == "/d/lib/arm/libshizuku.so")
        #expect(PhoneAppSetupService.starterPath(apkDirectory: "/d", abi: "x86_64\r\n")
            == "/d/lib/x86_64/libshizuku.so")
        #expect(PhoneAppSetupService.starterPath(apkDirectory: "/d", abi: "x86")
            == "/d/lib/x86/libshizuku.so")
        #expect(PhoneAppSetupService.starterPath(apkDirectory: "/d", abi: "mips") == nil)
        #expect(PhoneAppSetupService.starterPath(apkDirectory: "/d", abi: "") == nil)
    }

    @Test func starterSucceedsOnlyOnExitZeroAndItsOwnLine() {
        func result(_ stdout: String, exit: Int32?) -> AdbResult {
            AdbResult(stdout: stdout, stderr: "", exitCode: exit, timedOut: false)
        }
        #expect(PhoneAppSetupService.starterSucceeded(result(Captured.starter, exit: 0)))
        #expect(PhoneAppSetupService.starterSucceeded(
            result(Captured.starter.replacingOccurrences(of: "\n", with: "\r\n"), exit: 0)))
        #expect(!PhoneAppSetupService.starterSucceeded(result("info: starter begin\n", exit: 0)))
        #expect(!PhoneAppSetupService.starterSucceeded(result(Captured.starter, exit: 1)))
        #expect(!PhoneAppSetupService.starterSucceeded(result("", exit: nil)))
    }

    @Test func starterFailureNamesTheStartersOwnComplaint() {
        let fatal = AdbResult(
            stdout: "info: starter begin\n",
            stderr: "fatal: can't access /data/app/x/base.apk\n", exitCode: 9, timedOut: false)
        #expect(PhoneAppSetupService.starterFailureReason(fatal)
            == "fatal: can't access /data/app/x/base.apk")

        let quiet = AdbResult(
            stdout: "info: starter begin\ninfo: starting server...\n", stderr: "adb command failed",
            exitCode: 1, timedOut: false)
        #expect(PhoneAppSetupService.starterFailureReason(quiet) == "info: starting server...")

        let missing = AdbResult(
            stdout: "", stderr: "/system/bin/sh: /d/lib/arm64/libshizuku.so: not found\n",
            exitCode: 127, timedOut: false)
        #expect(PhoneAppSetupService.starterFailureReason(missing)
            == "/system/bin/sh: /d/lib/arm64/libshizuku.so: not found")

        let hung = AdbResult(stdout: "", stderr: "", exitCode: nil, timedOut: true)
        #expect(PhoneAppSetupService.starterFailureReason(hung) == "the starter timed out.")
    }

    @Test func grantFailureShowsTheExceptionMessage() {
        let refused = AdbResult(
            stdout: "",
            stderr: """
                Exception occurred while executing 'grant':
                java.lang.SecurityException: Package com.droidective.android has not requested permission android.permission.DUMP
                \tat com.android.server.pm.permission.PermissionManagerServiceImpl.grantRuntimePermissionInternal(PermissionManagerServiceImpl.java:1449)

                """,
            exitCode: 255, timedOut: false)
        #expect(PhoneAppSetupService.grantFailureReason(refused)
            == "Package com.droidective.android has not requested permission android.permission.DUMP")

        let xiaomi = AdbResult(
            stdout: "",
            stderr: "java.lang.SecurityException: grantRuntimePermission: Neither user 2000 nor "
                + "current process has android.permission.GRANT_RUNTIME_PERMISSIONS.\r\n",
            exitCode: 255, timedOut: false)
        let reason = PhoneAppSetupService.grantFailureReason(xiaomi)
        #expect(reason.hasPrefix("grantRuntimePermission: Neither user 2000"))
        #expect(reason.contains("USB debugging (Security settings)"))

        let offline = AdbResult(stdout: "", stderr: "error: device offline", exitCode: 1, timedOut: false)
        #expect(PhoneAppSetupService.grantFailureReason(offline) == "Device is offline.")
    }

    @Test func runningMeansExitZeroAndAPid() {
        #expect(PhoneAppSetupService.isRunning(
            AdbResult(stdout: "16869\n", stderr: "", exitCode: 0, timedOut: false)))
        #expect(!PhoneAppSetupService.isRunning(
            AdbResult(stdout: "", stderr: "", exitCode: 1, timedOut: false)))
        #expect(!PhoneAppSetupService.isRunning(
            AdbResult(stdout: "16869\n", stderr: "", exitCode: 1, timedOut: false)))
    }

    @Test func needsSetupTreatsShizukuAsOptional() {
        let all = PhoneAppSetupService.requiredPermissions(sdk: 36)
        func status(installed: Bool = true, granted: [String] = all, shizuku: Bool, running: Bool)
            -> PhoneAppSetupStatus
        {
            PhoneAppSetupStatus(
                appInstalled: installed, appVersion: "0.1.0", sdk: 36, requiredPermissions: all,
                grantedPermissions: granted, shizukuInstalled: shizuku, shizukuRunning: running)
        }
        #expect(!status(shizuku: true, running: true).needsSetup)
        #expect(!status(shizuku: false, running: false).needsSetup)
        #expect(status(shizuku: true, running: false).needsSetup)
        #expect(status(granted: [all[0]], shizuku: false, running: false).needsSetup)
        #expect(!status(installed: false, granted: [], shizuku: true, running: false).needsSetup)
        #expect(status(granted: [all[1]], shizuku: false, running: false).missingPermissions
            == [all[0], all[2]])
        #expect(PhoneAppSetupService.shortName("android.permission.DUMP") == "DUMP")
    }

    @Test func crashReportsNeedReadLogsBeforeAndroid15() {
        let granted = ["android.permission.WRITE_SECURE_SETTINGS", "android.permission.DUMP"]
        #expect(PhoneAppSetupService.requiredPermissions(sdk: 34)
            == granted + ["android.permission.READ_LOGS"])
        #expect(PhoneAppSetupService.requiredPermissions(sdk: 35)
            == granted + ["android.permission.READ_DROPBOX_DATA"])
        #expect(PhoneAppSetupService.requiredPermissions(sdk: nil) == granted)
    }

    @Test func sdkComesFromGetprop() {
        #expect(PhoneAppSetupService.parseSdk("36\n") == 36)
        #expect(PhoneAppSetupService.parseSdk("34\r\n") == 34)
        #expect(PhoneAppSetupService.parseSdk("") == nil)
        #expect(PhoneAppSetupService.parseSdk("error: closed") == nil)
    }

    @Test func permissionNamesReadAsAList() {
        #expect(PhoneAppSetupService.readableList([]) == "")
        #expect(PhoneAppSetupService.readableList(["DUMP"]) == "DUMP")
        #expect(PhoneAppSetupService.readableList(["A", "B"]) == "A and B")
        #expect(PhoneAppSetupService.readableList(["A", "B", "C"]) == "A, B and C")
    }
}

@Suite struct PhoneAppSetupCommandTests {
    @Test func grantsArePinnedToTheAndroidAppsLines() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1"], stdout: "")
        let service = PhoneAppSetupService(client: await makeTestClient(runner: runner))

        let result = try await service.grant(
            PhoneAppSetupService.requiredPermissions(sdk: 36), serial: "S1")

        #expect(result.ok)
        #expect(runner.invocations.map(\.arguments) == [
            ["-s", "S1", "shell", "pm", "grant", "'com.droidective.android'",
             "android.permission.WRITE_SECURE_SETTINGS"],
            ["-s", "S1", "shell", "pm", "grant", "'com.droidective.android'",
             "android.permission.DUMP"],
            ["-s", "S1", "shell", "pm", "grant", "'com.droidective.android'",
             "android.permission.READ_DROPBOX_DATA"],
        ])
        // What the device's shell receives once adb joins the words.
        #expect(runner.invocations.map { $0.arguments.dropFirst(3).joined(separator: " ") } == [
            "pm grant 'com.droidective.android' android.permission.WRITE_SECURE_SETTINGS",
            "pm grant 'com.droidective.android' android.permission.DUMP",
            "pm grant 'com.droidective.android' android.permission.READ_DROPBOX_DATA",
        ])
    }

    @Test func aRefusedGrantStopsAndSaysWhy() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "pm", "grant"],
            stderr: "java.lang.SecurityException: Package com.droidective.android has not requested "
                + "permission android.permission.WRITE_SECURE_SETTINGS",
            exitCode: 255)
        let service = PhoneAppSetupService(client: await makeTestClient(runner: runner))

        let result = try await service.grant(
            PhoneAppSetupService.requiredPermissions(sdk: 36), serial: "S1")

        #expect(!result.ok)
        #expect(result.message.hasPrefix("Couldn't grant WRITE_SECURE_SETTINGS: Package"))
        #expect(runner.invocations.count == 1)
    }

    @Test func shizukuStartsFromItsBundledStarterAsOneQuotedWord() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "pm", "path"], stdout: Captured.pmPath)
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop"], stdout: "arm64-v8a\n")
        runner.script(argsPrefix: ["-s", "S1", "shell", Captured.starterWord], stdout: Captured.starter)
        let service = PhoneAppSetupService(client: await makeTestClient(runner: runner))

        let result = try await service.startShizuku(serial: "S1")

        #expect(result.ok)
        #expect(runner.invocations.map(\.arguments) == [
            ["-s", "S1", "shell", "pm", "path", "'moe.shizuku.privileged.api'"],
            ["-s", "S1", "shell", "getprop", "ro.product.cpu.abi"],
            ["-s", "S1", "shell", "'\(Captured.shizukuApk)/lib/arm64/libshizuku.so'"],
        ])
    }

    @Test func aStarterPathIsQuotedAgainstTheDeviceShell() {
        #expect(PhoneAppSetupService.starterArguments("/data/app/a b;reboot/lib/arm64/libshizuku.so")
            == ["shell", "'/data/app/a b;reboot/lib/arm64/libshizuku.so'"])
        #expect(PhoneAppSetupService.starterArguments("/data/app/it's/libshizuku.so")
            == ["shell", "'/data/app/it'\\''s/libshizuku.so'"])
    }

    @Test func noApkMeansNoStarterRun() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "pm", "path"], stdout: "")
        let service = PhoneAppSetupService(client: await makeTestClient(runner: runner))

        let result = try await service.startShizuku(serial: "S1")

        #expect(!result.ok)
        #expect(result.message == "Couldn't find Shizuku's APK on this phone.")
        #expect(runner.invocations.count == 1)
    }

    @Test func anUnknownAbiIsNamed() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "pm", "path"], stdout: Captured.pmPath)
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop"], stdout: "mips\n")
        let service = PhoneAppSetupService(client: await makeTestClient(runner: runner))

        let result = try await service.startShizuku(serial: "S1")

        #expect(!result.ok)
        #expect(result.message == "Shizuku has no starter for this phone's CPU (mips).")
        #expect(runner.invocations.count == 2)
    }

    @Test func aFailingStarterReportsItsReason() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "pm", "path"], stdout: Captured.pmPath)
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop"], stdout: "arm64-v8a\n")
        runner.script(
            argsPrefix: ["-s", "S1", "shell", Captured.starterWord], stdout: "info: starter begin\n",
            stderr: "fatal: run Shizuku from non root nor adb user (uid=10215).\n", exitCode: 9)
        let service = PhoneAppSetupService(client: await makeTestClient(runner: runner))

        let result = try await service.startShizuku(serial: "S1")

        #expect(!result.ok)
        #expect(result.message
            == "Shizuku didn't start: fatal: run Shizuku from non root nor adb user (uid=10215).")
    }

    @Test func statusReadsEveryRow() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "pm", "list", "packages", "'com.droidective.android'"],
            stdout: "package:com.droidective.android\n")
        runner.script(argsPrefix: ["-s", "S1", "shell", "getprop", "ro.build.version.sdk"], stdout: "36\n")
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "dumpsys", "package", "'com.droidective.android'"],
            stdout: Captured.dumpsys(granted: ["android.permission.DUMP"]))
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "pm", "list", "packages", "'moe.shizuku.privileged.api'"],
            stdout: "package:moe.shizuku.privileged.api\n")
        runner.script(argsPrefix: ["-s", "S1", "shell", "pidof", "shizuku_server"], stdout: "16869\n")
        let service = PhoneAppSetupService(client: await makeTestClient(runner: runner))

        let status = try await service.status(serial: "S1")

        #expect(status == PhoneAppSetupStatus(
            appInstalled: true, appVersion: "0.1.0", sdk: 36,
            requiredPermissions: PhoneAppSetupService.requiredPermissions(sdk: 36),
            grantedPermissions: ["android.permission.DUMP"],
            shizukuInstalled: true, shizukuRunning: true))
        #expect(status.missingPermissions
            == ["android.permission.WRITE_SECURE_SETTINGS", "android.permission.READ_DROPBOX_DATA"])
    }

    @Test func anUnreachableDeviceIsAnErrorNotANotInstalled() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1"], stderr: "error: device offline", exitCode: 1)
        let service = PhoneAppSetupService(client: await makeTestClient(runner: runner))

        await #expect(throws: PhoneAppSetupError(message: "Device is offline.")) {
            try await service.status(serial: "S1")
        }
        #expect(await service.offer(serial: "S1", latest: { nil }) == nil)
    }
}

/// A phone that answers the set-up commands the way a real one does and keeps
/// the state they change, so a set-up run is tested as a sequence rather than
/// against one frozen output per command.
private final class FakePhone: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var appInstalled: Bool
    private var version: String
    private let sdk: String
    private var granted: Set<String>
    private let shizukuInstalled: Bool
    private var shizukuRunning: Bool
    private let grantRefusal: String?
    private let starterFails: Bool
    /// What `adb install` prints, and the version a successful one leaves.
    private let installOutput: String
    private let installsVersion: String
    private var recorded: [[String]] = []
    private var installedPaths: [String] = []
    private var installedFileExisted: [Bool] = []

    init(
        appInstalled: Bool = true, version: String = "0.1.0", sdk: String = "36\n",
        granted: Set<String> = [], shizukuInstalled: Bool = true, shizukuRunning: Bool = false,
        grantRefusal: String? = nil, starterFails: Bool = false,
        installOutput: String = "Performing Streamed Install\nSuccess\n",
        installsVersion: String = "0.1.1"
    ) {
        self.appInstalled = appInstalled
        self.version = version
        self.sdk = sdk
        self.granted = granted
        self.shizukuInstalled = shizukuInstalled
        self.shizukuRunning = shizukuRunning
        self.grantRefusal = grantRefusal
        self.starterFails = starterFails
        self.installOutput = installOutput
        self.installsVersion = installsVersion
    }

    /// The local paths `adb install -r` was handed, and whether each file was
    /// there when it was.
    var installs: [(path: String, existed: Bool)] {
        lock.lock()
        defer { lock.unlock() }
        return Array(zip(installedPaths, installedFileExisted))
    }

    /// Each device-shell line, as the phone's `sh` receives it.
    var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.map { $0.dropFirst(3).joined(separator: " ") }
    }

    func run(
        executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int
    ) async -> ProcessOutput {
        respond(to: arguments)
    }

    private func respond(to arguments: [String]) -> ProcessOutput {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(arguments)
        if arguments.count == 5, Array(arguments[2...3]) == ["install", "-r"] {
            return install(arguments[4])
        }
        let (stdout, stderr, exit) = answer(arguments.dropFirst(3).joined(separator: " "))
        return ProcessOutput(
            stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), exitCode: exit, timedOut: false)
    }

    private func install(_ path: String) -> ProcessOutput {
        installedPaths.append(path)
        installedFileExisted.append(FileManager.default.fileExists(atPath: path))
        if installOutput.contains("Success") {
            appInstalled = true
            version = installsVersion
        }
        return ProcessOutput(
            stdout: Data(installOutput.utf8), stderr: Data(), exitCode: 0, timedOut: false)
    }

    private func answer(_ line: String) -> (String, String, Int32) {
        switch line {
        case "pm list packages 'com.droidective.android'":
            return (appInstalled ? "package:com.droidective.android\n" : "", "", 0)
        case "getprop ro.build.version.sdk":
            return (sdk, "", 0)
        case "dumpsys package 'com.droidective.android'":
            return (Captured.dumpsys(granted: granted, version: version), "", 0)
        case "pm list packages 'moe.shizuku.privileged.api'":
            return (shizukuInstalled ? "package:moe.shizuku.privileged.api\n" : "", "", 0)
        case "pidof shizuku_server":
            return shizukuRunning ? ("16869\n", "", 0) : ("", "", 1)
        case "pm path 'moe.shizuku.privileged.api'":
            return (Captured.pmPath, "", 0)
        case "getprop ro.product.cpu.abi":
            return ("arm64-v8a\n", "", 0)
        case Captured.starterWord:
            if starterFails { return ("info: starter begin\n", "fatal: can't start server\n", 9) }
            shizukuRunning = true
            return (Captured.starter, "", 0)
        default:
            let prefix = "pm grant 'com.droidective.android' "
            guard line.hasPrefix(prefix) else { return ("", "unscripted: \(line)", 1) }
            if let grantRefusal { return ("", "java.lang.SecurityException: \(grantRefusal)", 255) }
            granted.insert(String(line.dropFirst(prefix.count)))
            return ("", "", 0)
        }
    }
}

@Suite struct PhoneAppSetupRunTests {
    private let grantLines = [
        "pm grant 'com.droidective.android' android.permission.WRITE_SECURE_SETTINGS",
        "pm grant 'com.droidective.android' android.permission.DUMP",
        "pm grant 'com.droidective.android' android.permission.READ_DROPBOX_DATA",
    ]
    private let starterLine = Captured.starterWord

    private func service(_ phone: FakePhone) async -> PhoneAppSetupService {
        let locator = ToolLocator(runner: phone, environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        return PhoneAppSetupService(client: AdbClient(locator: locator, runner: phone, log: CommandLog()))
    }

    @Test func aFreshPhoneIsGrantedThenShizukuStarted() async throws {
        let phone = FakePhone()
        let outcome = try await service(phone).setUp(serial: "S1")

        #expect(outcome.failure == nil)
        #expect(outcome.status.permissionsGranted)
        #expect(outcome.status.shizukuRunning)
        #expect(!outcome.status.needsSetup)
        #expect(phone.commands.filter { $0.hasPrefix("pm grant") } == grantLines)
        #expect(phone.commands.filter { $0 == starterLine }.count == 1)
        // Granted before Shizuku is touched.
        let lastGrant = try #require(phone.commands.lastIndex(of: grantLines[2]))
        let starter = try #require(phone.commands.firstIndex(of: starterLine))
        #expect(lastGrant < starter)
    }

    @Test func onlyMissingPermissionsAreGranted() async throws {
        let phone = FakePhone(granted: ["android.permission.WRITE_SECURE_SETTINGS"])
        let outcome = try await service(phone).setUp(serial: "S1")

        #expect(outcome.failure == nil)
        #expect(phone.commands.filter { $0.hasPrefix("pm grant") } == [grantLines[1], grantLines[2]])
    }

    @Test func anAndroid14PhoneGetsReadLogsForCrashReports() async throws {
        let phone = FakePhone(sdk: "34\n", shizukuInstalled: false)
        let outcome = try await service(phone).setUp(serial: "S1")

        #expect(outcome.failure == nil)
        #expect(phone.commands.filter { $0.hasPrefix("pm grant") }.last
            == "pm grant 'com.droidective.android' android.permission.READ_LOGS")
        #expect(outcome.status.grantedPermissions.contains("android.permission.READ_LOGS"))
    }

    @Test func anUnreadableSdkStillGrantsTheGrantedLevel() async throws {
        let phone = FakePhone(sdk: "", shizukuInstalled: false)
        let outcome = try await service(phone).setUp(serial: "S1")

        #expect(outcome.failure == nil)
        #expect(phone.commands.filter { $0.hasPrefix("pm grant") } == Array(grantLines.prefix(2)))
        #expect(!outcome.status.needsSetup)
    }

    @Test func aRunningShizukuIsNeverRestarted() async throws {
        // The starter kills a running server before starting a new one.
        let phone = FakePhone(shizukuRunning: true)
        let outcome = try await service(phone).setUp(serial: "S1")

        #expect(outcome.failure == nil)
        #expect(!phone.commands.contains(starterLine))
        #expect(!phone.commands.contains("pm path 'moe.shizuku.privileged.api'"))
    }

    @Test func withoutShizukuTheGrantsAreTheWholeJob() async throws {
        let phone = FakePhone(shizukuInstalled: false)
        let outcome = try await service(phone).setUp(serial: "S1")

        #expect(outcome.failure == nil)
        #expect(!outcome.status.needsSetup)
        #expect(!phone.commands.contains("pidof shizuku_server"))
        #expect(!phone.commands.contains(starterLine))
    }

    @Test func noAppMeansNothingIsTouched() async throws {
        let phone = FakePhone(appInstalled: false)
        let outcome = try await service(phone).setUp(serial: "S1")

        #expect(outcome.failure == "Droidective for Android isn't installed on this phone.")
        #expect(!phone.commands.contains { $0.hasPrefix("pm grant") })
        #expect(!phone.commands.contains(starterLine))
    }

    @Test func aRefusedGrantLeavesShizukuAlone() async throws {
        let phone = FakePhone(grantRefusal: "Package com.droidective.android has not requested permission")
        let outcome = try await service(phone).setUp(serial: "S1")

        #expect(outcome.failure
            == "Couldn't grant WRITE_SECURE_SETTINGS: Package com.droidective.android has not requested permission")
        #expect(!outcome.status.permissionsGranted)
        #expect(!phone.commands.contains(starterLine))
    }

    @Test func aFailedStarterKeepsTheGrantsItLanded() async throws {
        let phone = FakePhone(starterFails: true)
        let outcome = try await service(phone).setUp(serial: "S1")

        #expect(outcome.failure == "Shizuku didn't start: fatal: can't start server")
        #expect(outcome.status.permissionsGranted)
        #expect(!outcome.status.shizukuRunning)
        #expect(outcome.status.needsSetup)
    }

    @Test func theBarsProbeNeverAsksGitHubAboutAPhoneWithoutTheApp() async throws {
        let phone = FakePhone(appInstalled: false)
        let asked = Asked()
        let offer = await service(phone).offer(serial: "S1") { await asked.note() }
        #expect(offer == .install)
        #expect(phone.commands
            == ["pm list packages 'com.droidective.android'", "getprop ro.build.version.sdk"])
        #expect(await asked.count == 0)

        let android10 = FakePhone(appInstalled: false, sdk: "29\n")
        #expect(await service(android10).offer(serial: "S1", latest: { nil }) == nil)
    }

    @Test func theBarsProbeOffersWhatThePhoneNeeds() async throws {
        let all = Set(PhoneAppSetupService.requiredPermissions(sdk: 36))
        let latest = TestRelease.make(version: "0.1.1")

        let fresh = FakePhone()
        #expect(await service(fresh).offer(serial: "S1", latest: { nil }) == .setUp)
        let old = FakePhone(granted: all, shizukuRunning: true)
        #expect(await service(old).offer(serial: "S1", latest: { latest })
            == .update(from: "0.1.0", to: "0.1.1"))
        let done = FakePhone(version: "0.1.1", granted: all, shizukuRunning: true)
        #expect(await service(done).offer(serial: "S1", latest: { latest }) == nil)
    }
}

/// Set-up runs that install or update the app from a release first. The
/// "download" is the real release's signing block, which is what the signer
/// check reads, so the pin is exercised against apksigner's own output.
@Suite struct PhoneAppInstallRunTests {
    private let grantLines = [
        "pm grant 'com.droidective.android' android.permission.WRITE_SECURE_SETTINGS",
        "pm grant 'com.droidective.android' android.permission.DUMP",
        "pm grant 'com.droidective.android' android.permission.READ_DROPBOX_DATA",
    ]

    private func service(_ phone: FakePhone, host: ReleaseHost) async -> PhoneAppSetupService {
        let locator = ToolLocator(runner: phone, environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        return PhoneAppSetupService(
            client: AdbClient(locator: locator, runner: phone, log: CommandLog()), http: host)
    }

    private func genuine(version: String = "0.1.1") throws -> (ReleaseHost, PhoneAppRelease) {
        let apk = try ReleaseFixture.bytes()
        let release = TestRelease.make(version: version, digest: "sha256:" + ReleaseFixture.sha256(apk))
        return (ReleaseHost(apk: apk), release)
    }

    /// Stages as the sheet sees them.
    final class Stages: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [PhoneAppSetupStage] = []
        var all: [PhoneAppSetupStage] {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }
        func record(_ stage: PhoneAppSetupStage) {
            lock.lock()
            defer { lock.unlock() }
            seen.append(stage)
        }
    }

    @Test func aPhoneWithoutTheAppGetsItInstalledThenSetUp() async throws {
        let phone = FakePhone(appInstalled: false)
        let (host, release) = try genuine()
        let stages = Stages()

        let outcome = try await service(phone, host: host)
            .setUp(serial: "S1", release: release, onStage: stages.record)

        #expect(outcome.failure == nil)
        #expect(outcome.status.appInstalled)
        #expect(outcome.status.appVersion == "0.1.1")
        #expect(outcome.status.permissionsGranted)
        #expect(host.downloads.map(\.absoluteString) == [release.apkURL])
        let install = try #require(phone.installs.first)
        #expect(phone.installs.count == 1)
        #expect(install.existed)
        #expect(install.path.hasSuffix("/droidective-android-0.1.1.apk"))
        // The download goes once it's installed.
        #expect(!FileManager.default.fileExists(atPath: install.path))
        #expect(phone.commands.filter { $0.hasPrefix("pm grant") } == grantLines)
        #expect(stages.all == [
            .downloading(version: "0.1.1", fraction: nil),
            .downloading(version: "0.1.1", fraction: 0.5),
            .downloading(version: "0.1.1", fraction: 1),
            .verifying, .installing(version: "0.1.1"), .granting, .startingShizuku,
        ])
    }

    @Test func anOlderAppIsUpdatedInPlace() async throws {
        let all = Set(PhoneAppSetupService.requiredPermissions(sdk: 36))
        let phone = FakePhone(granted: all, shizukuRunning: true)
        let (host, release) = try genuine()

        let outcome = try await service(phone, host: host).setUp(serial: "S1", release: release)

        #expect(outcome.failure == nil)
        #expect(outcome.status.appVersion == "0.1.1")
        #expect(phone.installs.count == 1)
        #expect(!phone.commands.contains { $0.hasPrefix("pm grant") })
    }

    @Test func aCurrentAppIsNotDownloadedAgain() async throws {
        let phone = FakePhone(version: "0.1.1")
        let (host, release) = try genuine()

        let outcome = try await service(phone, host: host).setUp(serial: "S1", release: release)

        #expect(outcome.failure == nil)
        #expect(host.downloads.isEmpty)
        #expect(phone.installs.isEmpty)
        #expect(phone.commands.filter { $0.hasPrefix("pm grant") } == grantLines)
    }

    @Test func aDownloadThatFailsItsChecksIsNeverInstalled() async throws {
        let other = SyntheticApk.signed(by: [[Data("someone else".utf8)]])
        let cases: [(ReleaseHost, PhoneAppRelease, String)] = [
            (ReleaseHost(apk: try ReleaseFixture.bytes()),
             TestRelease.make(version: "0.1.1", digest: "sha256:" + String(repeating: "0", count: 64)),
             "The download doesn't match the release's checksum, so it wasn't installed."),
            (ReleaseHost(apk: other),
             TestRelease.make(version: "0.1.1", digest: "sha256:" + ReleaseFixture.sha256(other)),
             "The download isn't signed with Droidective's release key, so it wasn't installed."),
        ]
        for (host, release, failure) in cases {
            let phone = FakePhone(appInstalled: false)
            let outcome = try await service(phone, host: host).setUp(serial: "S1", release: release)

            #expect(outcome.failure == failure)
            #expect(phone.installs.isEmpty)
            #expect(!outcome.status.appInstalled)
            #expect(!phone.commands.contains { $0.hasPrefix("pm grant") })
        }
    }

    @Test func aRefusedInstallSaysWhyAndGrantsNothing() async throws {
        let phone = FakePhone(
            installOutput: "Performing Streamed Install\nadb: failed to install x.apk: Failure "
                + "[INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.droidective.android "
                + "signatures do not match newer version; ignoring!]\n")
        let (host, release) = try genuine()

        let outcome = try await service(phone, host: host).setUp(serial: "S1", release: release)

        #expect(outcome.failure == "Couldn't install 0.1.1: It conflicts with an installed copy "
            + "(signature or permission mismatch) — uninstall it first.")
        #expect(outcome.status.appVersion == "0.1.0")
        #expect(!phone.commands.contains { $0.hasPrefix("pm grant") })
    }

    @Test func aFailedDownloadSaysWhy() async throws {
        let phone = FakePhone(appInstalled: false)
        let host = ReleaseHost(failure: ManagedToolStore.StoreError.http(404))

        let outcome = try await service(phone, host: host)
            .setUp(serial: "S1", release: TestRelease.make(version: "0.1.1"))

        #expect(outcome.failure == "Couldn't download 0.1.1: Download failed (HTTP 404).")
        #expect(phone.installs.isEmpty)
    }

    @Test func onlyAnHttpsAddressIsDownloaded() async throws {
        let phone = FakePhone(appInstalled: false)
        let host = ReleaseHost(apk: try ReleaseFixture.bytes())
        let plain = PhoneAppRelease(
            version: "0.1.1", apkName: "droidective-android-0.1.1.apk",
            apkURL: "http://github.com/x.apk", apkSize: 1, apkDigest: nil)

        let outcome = try await service(phone, host: host).setUp(serial: "S1", release: plain)

        #expect(outcome.failure == "The release's download address isn't HTTPS.")
        #expect(host.downloads.isEmpty)
    }
}
