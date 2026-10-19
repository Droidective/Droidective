import Foundation

/// Where Droidective for Android stands on one device.
///
/// Shizuku is optional: a phone without it is set up once the grants land,
/// and one with it installed also needs its server running — which it stops
/// being after every reboot, since the adb-started server does not survive one.
public struct PhoneAppSetupStatus: Sendable, Equatable, Codable {
    public let appInstalled: Bool
    /// `versionName` from `dumpsys package`, when the app is installed.
    public let appVersion: String?
    /// `ro.build.version.sdk`, read whether or not the app is there: below
    /// Android 11 it can't be installed at all.
    public let sdk: Int?
    /// What this phone's Android version needs granted
    /// (`PhoneAppSetupService.requiredPermissions(sdk:)`).
    public let requiredPermissions: [String]
    /// The required permissions Android reports as `granted=true`.
    public let grantedPermissions: [String]
    public let shizukuInstalled: Bool
    public let shizukuRunning: Bool

    public init(
        appInstalled: Bool, appVersion: String?, sdk: Int?, requiredPermissions: [String],
        grantedPermissions: [String], shizukuInstalled: Bool, shizukuRunning: Bool
    ) {
        self.appInstalled = appInstalled
        self.appVersion = appVersion
        self.sdk = sdk
        self.requiredPermissions = requiredPermissions
        self.grantedPermissions = grantedPermissions
        self.shizukuInstalled = shizukuInstalled
        self.shizukuRunning = shizukuRunning
    }

    public var missingPermissions: [String] {
        requiredPermissions.filter { !grantedPermissions.contains($0) }
    }

    public var permissionsGranted: Bool { missingPermissions.isEmpty }

    /// Nothing left for Shizuku: running, or not installed at all.
    public var shizukuReady: Bool { !shizukuInstalled || shizukuRunning }

    /// The app is on the phone and something one click can fix is still undone.
    public var needsSetup: Bool { appInstalled && !(permissionsGranted && shizukuReady) }
}

/// What a set-up run did: the status read back afterwards, and the reason the
/// first failing step gave, if one failed.
public struct PhoneAppSetupOutcome: Sendable, Equatable {
    public let status: PhoneAppSetupStatus
    public let failure: String?

    public init(status: PhoneAppSetupStatus, failure: String?) {
        self.status = status
        self.failure = failure
    }
}

/// The device could not be read at all — offline, unauthorized, gone.
public struct PhoneAppSetupError: Error, LocalizedError, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Sets up Droidective for Android on a connected phone: installs or updates
/// the app from its latest GitHub release when given one, grants the
/// development permissions only a shell can grant, and starts Shizuku when it
/// is installed but not running.
///
/// The grant lines are a contract with the Android app, whose own test vector
/// pins the identical `pm grant 'com.droidective.android' <permission>`, so
/// both apps grant the same way.
///
/// Shizuku 13.x does not ship the `start.sh` its documentation describes: the
/// starter is a native binary inside its APK, run straight from the app's
/// extracted library directory. It kills any server already running before it
/// starts a new one, which is why it only runs when none is.
public struct PhoneAppSetupService: Sendable {
    public static let appPackage = "com.droidective.android"
    public static let shizukuPackage = "moe.shizuku.privileged.api"
    /// WRITE_SECURE_SETTINGS and DUMP, which are the app's Granted level, and
    /// the permission Android files crash reports under for its Crash Catcher:
    /// READ_DROPBOX_DATA from Android 15 (API 35), READ_LOGS before it. The
    /// Android app's `Grants.permissions(sdk)` is the same list. An unread SDK
    /// asks for the two that don't depend on it.
    public static func requiredPermissions(sdk: Int?) -> [String] {
        let granted = ["android.permission.WRITE_SECURE_SETTINGS", "android.permission.DUMP"]
        guard let sdk else { return granted }
        let crashReports = sdk >= 35
            ? "android.permission.READ_DROPBOX_DATA" : "android.permission.READ_LOGS"
        return granted + [crashReports]
    }
    static let shizukuServerProcess = "shizuku_server"

    let client: AdbClient
    let http: any HTTPFetching

    public init(client: AdbClient, http: any HTTPFetching = URLSessionHTTP()) {
        self.client = client
        self.http = http
    }

    // MARK: - Status

    /// Throws `PhoneAppSetupError` when the device cannot be read at all; every
    /// later probe is lenient, so a failed `dumpsys` reads as nothing granted
    /// and a set-up run then says why.
    public func status(serial: String) async throws -> PhoneAppSetupStatus {
        let listing = try await client.run(on: serial, Self.listArguments(Self.appPackage))
        guard listing.succeeded else {
            throw PhoneAppSetupError(
                message: friendlyAdbError(listing, fallback: "Couldn't read this phone's apps."))
        }
        return try await status(serial: serial, appListing: listing.stdout)
    }

    /// What the device bar should offer for this phone, or nil, which is also
    /// the answer to any failure, since a menu entry is no place to report one.
    /// Two commands when the app is not on the phone, the common case, and
    /// `latest` is asked only when it is, so a phone without the app never
    /// costs a GitHub request.
    public func offer(
        serial: String, latest: @Sendable () async -> PhoneAppRelease?
    ) async -> PhoneAppOffer? {
        let arguments = Self.listArguments(Self.appPackage)
        guard let listing = try? await client.run(on: serial, arguments), listing.succeeded
        else { return nil }
        guard Self.listsPackage(listing.stdout, package: Self.appPackage) else {
            let sdk = try? await client.run(on: serial, Self.sdkArguments())
            let absent = PhoneAppSetupStatus(
                appInstalled: false, appVersion: nil, sdk: sdk.flatMap { Self.parseSdk($0.stdout) },
                requiredPermissions: [], grantedPermissions: [], shizukuInstalled: false,
                shizukuRunning: false)
            return PhoneAppOffer.decide(status: absent, latest: nil)
        }
        guard let status = try? await status(serial: serial, appListing: listing.stdout)
        else { return nil }
        return PhoneAppOffer.decide(status: status, latest: await latest())
    }

    private func status(serial: String, appListing: String) async throws -> PhoneAppSetupStatus {
        let installed = Self.listsPackage(appListing, package: Self.appPackage)
        let sdk = Self.parseSdk(try await client.run(on: serial, Self.sdkArguments()).stdout)
        var required: [String] = []
        var granted: [String] = []
        var version: String?
        if installed {
            required = Self.requiredPermissions(sdk: sdk)
            let dump = try await client.run(on: serial, Self.dumpsysArguments())
            let reported = Self.parseGrantedPermissions(dump.stdout)
            granted = required.filter(reported.contains)
            version = Self.parseVersionName(dump.stdout)
        }
        let shizuku = try await client.run(on: serial, Self.listArguments(Self.shizukuPackage))
        let shizukuInstalled = Self.listsPackage(shizuku.stdout, package: Self.shizukuPackage)
        var running = false
        if shizukuInstalled {
            running = Self.isRunning(try await client.run(on: serial, Self.pidofArguments()))
        }
        return PhoneAppSetupStatus(
            appInstalled: installed, appVersion: version, sdk: sdk, requiredPermissions: required,
            grantedPermissions: granted, shizukuInstalled: shizukuInstalled,
            shizukuRunning: running)
    }

    // MARK: - Set up

    /// Installs or updates the app from `release` when the phone needs it,
    /// then grants whatever is missing, then starts Shizuku if it is installed
    /// and stopped. Stops at the first step that fails and says why; the status
    /// it returns is always read back from the device, so a partial run shows
    /// what did land. Without a release, a phone lacking the app is left alone.
    public func setUp(
        serial: String, release: PhoneAppRelease? = nil,
        onStage: @escaping @Sendable (PhoneAppSetupStage) -> Void = { _ in }
    ) async throws -> PhoneAppSetupOutcome {
        var before = try await status(serial: serial)
        switch PhoneAppStep.decide(status: before, latest: release) {
        case .install(let release), .update(let release):
            let installed = try await install(release, serial: serial, onStage: onStage)
            before = try await status(serial: serial)
            guard installed.ok else {
                return PhoneAppSetupOutcome(status: before, failure: installed.message)
            }
        case .none:
            break
        }
        guard before.appInstalled else {
            return PhoneAppSetupOutcome(
                status: before, failure: "Droidective for Android isn't installed on this phone.")
        }
        return try await grantThenStartShizuku(before, serial: serial, onStage: onStage)
    }

    private func grantThenStartShizuku(
        _ before: PhoneAppSetupStatus, serial: String,
        onStage: @Sendable (PhoneAppSetupStage) -> Void
    ) async throws -> PhoneAppSetupOutcome {
        if !before.missingPermissions.isEmpty { onStage(.granting) }
        let grant = try await grant(before.missingPermissions, serial: serial)
        guard grant.ok else {
            let after = try await status(serial: serial)
            return PhoneAppSetupOutcome(status: after, failure: grant.message)
        }
        let granted = try await status(serial: serial)
        guard granted.permissionsGranted else {
            let names = granted.missingPermissions.map(Self.shortName).joined(separator: ", ")
            return PhoneAppSetupOutcome(
                status: granted, failure: "Android didn't record the grant for \(names).")
        }
        guard granted.shizukuInstalled, !granted.shizukuRunning else {
            return PhoneAppSetupOutcome(status: granted, failure: nil)
        }
        onStage(.startingShizuku)
        let started = try await startShizuku(serial: serial)
        return PhoneAppSetupOutcome(
            status: try await status(serial: serial), failure: started.ok ? nil : started.message)
    }

    // MARK: - Install

    /// Downloads `release`, checks its digest and signer
    /// (`PhoneAppReleases.problem`), and installs it with `adb install -r`, so
    /// an update keeps the app's data and grants. Nothing is installed unless
    /// every check passes.
    public func install(
        _ release: PhoneAppRelease, serial: String,
        onStage: @escaping @Sendable (PhoneAppSetupStage) -> Void = { _ in }
    ) async throws(AdbError) -> FeatureResult {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory
            .appendingPathComponent("droidective-android-\(UUID().uuidString)", isDirectory: true)
        // The system purges its temporary directory, so a removal that fails
        // here costs one APK's worth of disk until it does.
        defer { try? fileManager.removeItem(at: work) }
        // `apkName` is `droidective-android-X.Y.Z.apk` with X, Y and Z digits,
        // checked by `PhoneAppReleases.release(from:)`, so it can't leave `work`.
        let apk = work.appendingPathComponent(release.apkName)
        guard let url = URL(string: release.apkURL), url.scheme == "https" else {
            return FeatureResult(ok: false, message: "The release's download address isn't HTTPS.")
        }
        onStage(.downloading(version: release.version, fraction: nil))
        do {
            try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
            try await http.download(from: url, to: apk) { fraction in
                onStage(.downloading(version: release.version, fraction: fraction))
            }
        } catch {
            return FeatureResult(
                ok: false,
                message: "Couldn't download \(release.version): \(error.localizedDescription)")
        }
        onStage(.verifying)
        if let problem = PhoneAppReleases.problem(apkAt: apk, release: release) {
            return FeatureResult(ok: false, message: problem)
        }
        onStage(.installing(version: release.version))
        let installed = try await AppInstallService(client: client)
            .install(apkPath: apk.path, serial: serial)
        guard installed.ok else {
            return FeatureResult(
                ok: false, message: "Couldn't install \(release.version): \(installed.message)",
                copyText: installed.copyText)
        }
        return FeatureResult(ok: true, message: "Installed \(release.version).")
    }

    /// `pm grant` for each permission, in order, stopping at the first refusal.
    public func grant(
        _ permissions: [String], serial: String
    ) async throws(AdbError) -> FeatureResult {
        for permission in permissions {
            let result = try await client.run(on: serial, Self.grantArguments(permission))
            guard result.succeeded else {
                let reason = Self.grantFailureReason(result)
                return FeatureResult(
                    ok: false, message: "Couldn't grant \(Self.shortName(permission)): \(reason)")
            }
        }
        return FeatureResult(ok: true, message: "Permissions granted.")
    }

    /// Runs Shizuku's bundled starter: find the APK, pick the library directory
    /// for the device's ABI, and execute `libshizuku.so` from it.
    public func startShizuku(serial: String) async throws(AdbError) -> FeatureResult {
        let path = try await client.run(on: serial, Self.pathArguments())
        guard let apkDirectory = Self.parseApkDirectory(path.stdout) else {
            let missing = "Couldn't find Shizuku's APK on this phone."
            return FeatureResult(
                ok: false,
                message: path.succeeded ? missing : friendlyAdbError(path, fallback: missing))
        }
        let abi = try await client.run(on: serial, Self.abiArguments())
        guard let starter = Self.starterPath(apkDirectory: apkDirectory, abi: abi.stdout) else {
            let reported = abi.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let cpu = reported.isEmpty ? "unknown" : reported
            return FeatureResult(
                ok: false, message: "Shizuku has no starter for this phone's CPU (\(cpu)).")
        }
        let run = try await client.run(on: serial, Self.starterArguments(starter))
        guard Self.starterSucceeded(run) else {
            let reason = Self.starterFailureReason(run)
            return FeatureResult(ok: false, message: "Shizuku didn't start: \(reason)")
        }
        return FeatureResult(ok: true, message: "Shizuku started.")
    }

    // MARK: - Argument vectors (device-scoped; AdbClient prepends `-s <serial>`)

    static func listArguments(_ package: String) -> [String] {
        ["shell", "pm", "list", "packages", shellQuote(package)]
    }

    static func sdkArguments() -> [String] {
        ["shell", "getprop", "ro.build.version.sdk"]
    }

    static func dumpsysArguments() -> [String] {
        ["shell", "dumpsys", "package", shellQuote(appPackage)]
    }

    static func grantArguments(_ permission: String) -> [String] {
        ["shell", "pm", "grant", shellQuote(appPackage), permission]
    }

    static func pathArguments() -> [String] {
        ["shell", "pm", "path", shellQuote(shizukuPackage)]
    }

    static func abiArguments() -> [String] {
        ["shell", "getprop", "ro.product.cpu.abi"]
    }

    /// One shell word: the path is read off the device, and `pm path` puts `=`
    /// and `~` in it.
    static func starterArguments(_ starterPath: String) -> [String] {
        ["shell", shellQuote(starterPath)]
    }

    static func pidofArguments() -> [String] {
        ["shell", "pidof", shizukuServerProcess]
    }

    // MARK: - Pure parsing

    /// `pm list packages <name>` prefix-matches, so only the exact
    /// `package:<name>` line counts — `<name>.debug` is a different app.
    static func listsPackage(_ output: String, package: String) -> Bool {
        output.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespaces) == "package:\(package)"
        }
    }

    /// Permission names `dumpsys package` reports as granted. Only a
    /// `<name>: granted=true` line counts; the bare names under "requested
    /// permissions:" say the app *asked*, not that it holds them.
    static func parseGrantedPermissions(_ dumpsys: String) -> Set<String> {
        var granted: Set<String> = []
        for line in dumpsys.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.range(of: ": granted=") else { continue }
            let name = trimmed[..<separator.lowerBound]
            let value = trimmed[separator.upperBound...]
            guard !name.isEmpty, !name.contains(" "),
                  value == "true" || value.hasPrefix("true,")
            else { continue }
            granted.insert(String(name))
        }
        return granted
    }

    static func parseVersionName(_ dumpsys: String) -> String? {
        for line in dumpsys.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("versionName=") else { continue }
            let version = trimmed.dropFirst("versionName=".count)
            return version.isEmpty ? nil : String(version)
        }
        return nil
    }

    /// The directory holding Shizuku's `base.apk`, from `pm path`. A split
    /// install lists several APKs; the base is the one the libraries sit beside.
    static func parseApkDirectory(_ pmPath: String) -> String? {
        for line in pmPath.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("package:"), trimmed.hasSuffix("/base.apk") else { continue }
            let directory = trimmed.dropFirst("package:".count).dropLast("/base.apk".count)
            return directory.isEmpty ? nil : String(directory)
        }
        return nil
    }

    /// `<apk dir>/lib/<isa>/libshizuku.so`. Android extracts native libraries
    /// under the instruction-set name for the ABI — arm64-v8a → arm64 — which
    /// is the same token frida's release assets use, so `FridaArch` maps it.
    static func starterPath(apkDirectory: String, abi: String) -> String? {
        guard let isa = FridaArch.from(abilist: abi) else { return nil }
        return "\(apkDirectory)/lib/\(isa)/libshizuku.so"
    }

    /// Exit 0 *and* the starter's own "exit with 0" line: a shell that could
    /// not find the file exits non-zero, but only the line proves the starter
    /// itself ran to the end.
    static func starterSucceeded(_ result: AdbResult) -> Bool {
        guard result.succeeded else { return false }
        return (result.stdout + "\n" + result.stderr).components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespaces).hasSuffix("shizuku_starter exit with 0")
        }
    }

    /// The starter's own complaint when it has one (`fatal: …`/`error: …`),
    /// else the last thing it printed, else adb's reason.
    static func starterFailureReason(_ result: AdbResult) -> String {
        if result.timedOut { return "the starter timed out." }
        let lines = (result.stdout + "\n" + result.stderr).components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let complaint = lines.first { $0.hasPrefix("fatal:") || $0.hasPrefix("error:") }
        if let complaint { return complaint }
        let printed = result.stdout.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        if let printed { return printed }
        let code = result.exitCode.map(String.init) ?? "none"
        return friendlyAdbError(result, fallback: "the starter exited with code \(code).")
    }

    /// `pm grant` answers a refusal with a Java stack trace; the exception's
    /// message is the part worth showing. A Xiaomi phone refuses until
    /// "USB debugging (Security settings)" is on, and its message never says so.
    static func grantFailureReason(_ result: AdbResult) -> String {
        let exception = (result.stderr + "\n" + result.stdout).components(separatedBy: .newlines)
            .lazy
            .compactMap { line -> String? in
                guard let marker = line.range(of: "Exception: ") else { return nil }
                return line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
            }
            .first { !$0.isEmpty }
        let reason = exception ?? friendlyAdbError(result, fallback: "pm grant failed.")
        guard reason.contains("GRANT_RUNTIME_PERMISSIONS") else { return reason }
        return reason + " On a Xiaomi phone, also turn on USB debugging (Security settings)"
            + " in Developer options."
    }

    static func isRunning(_ pidof: AdbResult) -> Bool {
        pidof.succeeded
            && pidof.stdout.split(whereSeparator: \.isWhitespace).contains { Int($0) != nil }
    }

    /// `getprop ro.build.version.sdk`'s answer, or nil when it isn't a number.
    static func parseSdk(_ getprop: String) -> Int? {
        Int(getprop.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// "DUMP", "WRITE_SECURE_SETTINGS and DUMP", "A, B and C".
    public static func readableList(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// `android.permission.DUMP` → `DUMP`.
    public static func shortName(_ permission: String) -> String {
        permission.components(separatedBy: ".").last ?? permission
    }
}
