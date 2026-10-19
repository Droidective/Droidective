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
    static func dumpsys(granted: Set<String>) -> String {
        var lines = [
            "Packages:",
            "  Package [com.droidective.android] (8c1e2d4):",
            "    appId=10215",
            "    versionCode=1 minSdk=26 targetSdk=36",
            "    versionName=0.1.0",
            "    requested permissions:",
            "      android.permission.WRITE_SECURE_SETTINGS",
            "      android.permission.DUMP",
            "      android.permission.INTERNET",
            "    install permissions:",
            "      android.permission.INTERNET: granted=true",
        ]
        for permission in PhoneAppSetupService.requiredPermissions where granted.contains(permission) {
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
            Captured.dumpsys(granted: Set(PhoneAppSetupService.requiredPermissions)))
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
        let all = PhoneAppSetupService.requiredPermissions
        func status(installed: Bool = true, granted: [String] = all, shizuku: Bool, running: Bool)
            -> PhoneAppSetupStatus
        {
            PhoneAppSetupStatus(
                appInstalled: installed, appVersion: "0.1.0", grantedPermissions: granted,
                shizukuInstalled: shizuku, shizukuRunning: running)
        }
        #expect(!status(shizuku: true, running: true).needsSetup)
        #expect(!status(shizuku: false, running: false).needsSetup)
        #expect(status(shizuku: true, running: false).needsSetup)
        #expect(status(granted: [all[0]], shizuku: false, running: false).needsSetup)
        #expect(!status(installed: false, granted: [], shizuku: true, running: false).needsSetup)
        #expect(status(granted: [all[1]], shizuku: false, running: false).missingPermissions == [all[0]])
        #expect(PhoneAppSetupService.shortName("android.permission.DUMP") == "DUMP")
    }
}

@Suite struct PhoneAppSetupCommandTests {
    @Test func grantsArePinnedToTheAndroidAppsLines() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1"], stdout: "")
        let service = PhoneAppSetupService(client: await makeTestClient(runner: runner))

        let result = try await service.grant(PhoneAppSetupService.requiredPermissions, serial: "S1")

        #expect(result.ok)
        #expect(runner.invocations.map(\.arguments) == [
            ["-s", "S1", "shell", "pm", "grant", "'com.droidective.android'",
             "android.permission.WRITE_SECURE_SETTINGS"],
            ["-s", "S1", "shell", "pm", "grant", "'com.droidective.android'",
             "android.permission.DUMP"],
        ])
        // What the device's shell receives once adb joins the words.
        #expect(runner.invocations.map { $0.arguments.dropFirst(3).joined(separator: " ") } == [
            "pm grant 'com.droidective.android' android.permission.WRITE_SECURE_SETTINGS",
            "pm grant 'com.droidective.android' android.permission.DUMP",
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

        let result = try await service.grant(PhoneAppSetupService.requiredPermissions, serial: "S1")

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
            appInstalled: true, appVersion: "0.1.0", grantedPermissions: ["android.permission.DUMP"],
            shizukuInstalled: true, shizukuRunning: true))
        #expect(status.missingPermissions == ["android.permission.WRITE_SECURE_SETTINGS"])
    }

    @Test func anUnreachableDeviceIsAnErrorNotANotInstalled() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1"], stderr: "error: device offline", exitCode: 1)
        let service = PhoneAppSetupService(client: await makeTestClient(runner: runner))

        await #expect(throws: PhoneAppSetupError(message: "Device is offline.")) {
            try await service.status(serial: "S1")
        }
        #expect(await !service.needsSetup(serial: "S1"))
    }
}

/// A phone that answers the set-up commands the way a real one does and keeps
/// the state they change, so a set-up run is tested as a sequence rather than
/// against one frozen output per command.
private final class FakePhone: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var appInstalled: Bool
    private var granted: Set<String>
    private let shizukuInstalled: Bool
    private var shizukuRunning: Bool
    private let grantRefusal: String?
    private let starterFails: Bool
    private var recorded: [[String]] = []

    init(
        appInstalled: Bool = true, granted: Set<String> = [], shizukuInstalled: Bool = true,
        shizukuRunning: Bool = false, grantRefusal: String? = nil, starterFails: Bool = false
    ) {
        self.appInstalled = appInstalled
        self.granted = granted
        self.shizukuInstalled = shizukuInstalled
        self.shizukuRunning = shizukuRunning
        self.grantRefusal = grantRefusal
        self.starterFails = starterFails
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
        let (stdout, stderr, exit) = answer(arguments.dropFirst(3).joined(separator: " "))
        return ProcessOutput(
            stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), exitCode: exit, timedOut: false)
    }

    private func answer(_ line: String) -> (String, String, Int32) {
        switch line {
        case "pm list packages 'com.droidective.android'":
            return (appInstalled ? "package:com.droidective.android\n" : "", "", 0)
        case "dumpsys package 'com.droidective.android'":
            return (Captured.dumpsys(granted: granted), "", 0)
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
        let lastGrant = try #require(phone.commands.lastIndex(of: grantLines[1]))
        let starter = try #require(phone.commands.firstIndex(of: starterLine))
        #expect(lastGrant < starter)
    }

    @Test func onlyMissingPermissionsAreGranted() async throws {
        let phone = FakePhone(granted: ["android.permission.WRITE_SECURE_SETTINGS"])
        let outcome = try await service(phone).setUp(serial: "S1")

        #expect(outcome.failure == nil)
        #expect(phone.commands.filter { $0.hasPrefix("pm grant") } == [grantLines[1]])
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

    @Test func theBarsProbeCostsOneCommandWhenTheAppIsAbsent() async throws {
        let phone = FakePhone(appInstalled: false)
        #expect(await !service(phone).needsSetup(serial: "S1"))
        #expect(phone.commands == ["pm list packages 'com.droidective.android'"])

        let fresh = FakePhone()
        #expect(await service(fresh).needsSetup(serial: "S1"))
        let done = FakePhone(granted: Set(PhoneAppSetupService.requiredPermissions), shizukuRunning: true)
        #expect(await !service(done).needsSetup(serial: "S1"))
    }
}
