import Foundation

/// App-scoped operations keyed by package id: lifecycle control and the
/// installed-package list (used by the "pick from device" bundle flow).
public struct AppControlService: Sendable {
    public enum AppAction: String, Sendable, CaseIterable {
        case open
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
            let result = try await client.run(on: serial, [
                "shell", "monkey", "-p", shellQuote(packageId), "-c", "android.intent.category.LAUNCHER", "1",
            ])
            let combined = result.stdout + result.stderr
            let launched = result.succeeded && combined.range(of: "No activities found", options: .caseInsensitive) == nil
            return launched
                ? FeatureResult(ok: true, message: "Opened app")
                : FeatureResult(ok: false, message: "Couldn't launch — no launcher activity found.")

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
