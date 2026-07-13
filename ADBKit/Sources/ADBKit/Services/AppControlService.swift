import Foundation

/// App-scoped operations keyed by package id: lifecycle control and the
/// installed-package list (used by the "pick from device" bundle flow).
public struct AppControlService: Sendable {
    public enum AppAction: String, Sendable, CaseIterable {
        case open
        case restart
        case stop
        case minimize
        case clearCache
        case clearData
        case uninstall

        public var isDestructive: Bool {
            self == .clearData || self == .uninstall
        }
    }

    let client: AdbClient

    public init(client: AdbClient) {
        self.client = client
    }

    public func control(serial: String, packageId: String, action: AppAction) async throws(AdbError) -> FeatureResult {
        switch action {
        case .open:
            return try await launch(serial: serial, packageId: packageId, successMessage: "Opened app")

        case .restart:
            // Stop first; its outcome doesn't gate the relaunch — force-stop
            // of a not-running app is a no-op.
            _ = try await client.run(on: serial, ["shell", "am", "force-stop", shellQuote(packageId)])
            return try await launch(serial: serial, packageId: packageId, successMessage: "Restarted")

        case .stop:
            let result = try await client.run(on: serial, ["shell", "am", "force-stop", shellQuote(packageId)])
            return fromResult(result, success: "Force-stopped", fallback: "Failed to force-stop")

        case .minimize:
            let result = try await client.run(on: serial, ["shell", "input", "keyevent", "3"])
            return fromResult(result, success: "Sent to background", fallback: "Failed to minimize")

        case .clearCache:
            let result = try await client.run(on: serial, ["shell", "pm", "clear", "--cache-only", shellQuote(packageId)])
            // `pm clear` prints "Success"/"Failed" and exits 0 either way, so the
            // stdout text — not the exit code — is authoritative.
            return Self.pmClearSucceeded(result)
                ? FeatureResult(ok: true, message: "Cleared cache")
                : FeatureResult(ok: false, message: "Clearing cache needs Android 14+ (or use Clear Data).")

        case .clearData:
            let result = try await client.run(on: serial, ["shell", "pm", "clear", shellQuote(packageId)])
            return Self.pmClearSucceeded(result)
                ? FeatureResult(ok: true, message: "Cleared app data")
                : FeatureResult(ok: false, message: friendlyAdbError(result, fallback: "Failed to clear data"))

        case .uninstall:
            let result = try await client.run(on: serial, ["uninstall", packageId])
            return result.stdout.range(of: "Success", options: .caseInsensitive) != nil
                ? FeatureResult(ok: true, message: "Uninstalled")
                : FeatureResult(ok: false, message: friendlyAdbError(result, fallback: "Failed to uninstall"))
        }
    }

    /// Launch the package's launcher activity. Resolution-first: ask the
    /// device for the component (`cmd package resolve-activity`) and start it
    /// by name (`am start -n`) — the old `monkey` mechanism is a do-nothing
    /// stub on some OEM/custom builds, exiting 0 without launching anything.
    /// Monkey stays as the fallback for pre-7.1 devices without `cmd`. A
    /// failure is honest about why: not installed vs no enabled launcher.
    private func launch(
        serial: String, packageId: String, successMessage: String
    ) async throws(AdbError) -> FeatureResult {
        if let component = try await resolveLauncherComponent(serial: serial, packageId: packageId) {
            let start = try await client.run(on: serial, ["shell", "am", "start", "-n", shellQuote(component)])
            let failed = !start.succeeded
                || (start.stdout + start.stderr).range(of: "Error", options: .caseInsensitive) != nil
            if !failed { return FeatureResult(ok: true, message: successMessage) }
        }
        // Fallback: fire the launcher intent with monkey. Success requires
        // the injected-events line — a stub monkey exits 0 injecting nothing.
        let monkey = try await client.run(on: serial, [
            "shell", "monkey", "-p", shellQuote(packageId), "-c", "android.intent.category.LAUNCHER", "1",
        ])
        let combined = monkey.stdout + monkey.stderr
        if monkey.succeeded,
           combined.range(of: "Events injected", options: .caseInsensitive) != nil,
           combined.range(of: "No activities found", options: .caseInsensitive) == nil {
            return FeatureResult(ok: true, message: successMessage)
        }
        let installed = try await listInstalledPackages(serial: serial, includeSystem: true)
            .contains(packageId)
        return FeatureResult(
            ok: false,
            message: installed
                ? "Couldn't launch \(packageId) — it has no enabled launcher activity."
                : "\(packageId) isn't installed on this device."
        )
    }

    /// The launcher component `cmd package resolve-activity` reports, or nil
    /// when unresolvable: no launcher activity, a pre-7.1 device without
    /// `cmd`, or a multi-launcher package that resolves to the system chooser
    /// (a component outside the package, which must not be started).
    func resolveLauncherComponent(serial: String, packageId: String) async throws(AdbError) -> String? {
        let result = try await client.run(on: serial, [
            "shell", "cmd", "package", "resolve-activity", "--brief", "--user", "current",
            "-c", "android.intent.category.LAUNCHER", shellQuote(packageId),
        ])
        guard result.succeeded else { return nil }
        return Self.launcherComponent(in: result.stdout, packageId: packageId)
    }

    /// Pure parser: the `<packageId>/<activity>` component line from
    /// `resolve-activity --brief` output (the component is the last line;
    /// anything outside the package — e.g. the chooser — is rejected).
    static func launcherComponent(in output: String, packageId: String) -> String? {
        for line in output.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(packageId + "/") { return trimmed }
        }
        return nil
    }

    /// Installed package ids, sorted. `includeSystem: false` lists only
    /// third-party apps (`pm list packages -3`).
    public func listInstalledPackages(serial: String, includeSystem: Bool = false) async throws(AdbError) -> [String] {
        var args = ["shell", "pm", "list", "packages"]
        if !includeSystem {
            args.append("-3")
        }
        let result = try await client.run(on: serial, args)
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "package:", with: "") }
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// Launch a deep link via the system VIEW intent. The URL is quoted for
    /// the device-side shell — adb joins shell args with spaces, so `&`, `?`,
    /// and spaces in the URL would otherwise be interpreted by `sh`.
    public func launchDeepLink(serial: String, url: String) async throws(AdbError) -> FeatureResult {
        let result = try await client.run(on: serial, [
            "shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", shellQuote(url),
        ])
        let failed = !result.succeeded || result.stdout.contains("Error:") || result.stderr.contains("Error:")
        return failed
            ? FeatureResult(ok: false, message: friendlyAdbError(result, fallback: "Couldn't launch the deep link"))
            : FeatureResult(ok: true, message: "Launched \(url)")
    }

    /// `pm clear` reports the outcome in stdout ("Success" / "Failed") while
    /// exiting 0 in both cases, so success means the word "Success" is present
    /// and "Failed" is not.
    static func pmClearSucceeded(_ result: AdbResult) -> Bool {
        let combined = result.stdout + result.stderr
        if combined.range(of: "Failed", options: .caseInsensitive) != nil { return false }
        return combined.range(of: "Success", options: .caseInsensitive) != nil
    }

    private func fromResult(_ result: AdbResult, success: String, fallback: String) -> FeatureResult {
        result.succeeded
            ? FeatureResult(ok: true, message: success)
            : FeatureResult(ok: false, message: friendlyAdbError(result, fallback: fallback))
    }
}
