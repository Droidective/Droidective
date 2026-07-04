import Foundation

public enum SimulatorServiceError: Error, LocalizedError, Sendable {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        }
    }
}

/// iOS Simulator operations over `simctl` — boot/shutdown for the Emulators
/// screen plus the per-feature runners (screenshot, appearance, status bar,
/// push, openurl). The simctl counterpart of the adb-backed services: one
/// service per domain, callable without any UI.
public struct SimulatorService: Sendable {
    /// RocketSim-style clean status bar: Apple's keynote time, full signal
    /// and battery. Public so the arg-vector test and the engine share one
    /// definition.
    public static let demoStatusBarArguments: [String] = [
        "--time", "9:41",
        "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
        "--cellularMode", "active", "--cellularBars", "4",
        "--batteryState", "charged", "--batteryLevel", "100",
    ]

    let client: SimctlClient

    public init(client: SimctlClient) {
        self.client = client
    }

    /// All simulators (any state) for the Emulators screen. Failures — no
    /// Xcode, malformed output — read as "none installed".
    public func listAll() async -> [Simulator] {
        guard let result = try? await client.run(["list", "-j", "devices"]), result.succeeded else {
            return []
        }
        return SimulatorListParser.parse(result.stdout)
    }

    /// Boot a simulator, then surface the Simulator app so the window is
    /// actually visible (simctl boots headless on its own).
    public func boot(udid: String) async throws(SimctlError) -> FeatureResult {
        let result = try await client.run(["boot", udid], timeout: .seconds(90))
        guard result.succeeded else {
            return FeatureResult(
                ok: false,
                message: friendlySimctlError(result, fallback: "Failed to boot the simulator")
            )
        }
        _ = await client.runner.run(
            executable: "/usr/bin/open", arguments: ["-a", "Simulator"],
            timeout: .seconds(15), maxOutputBytes: 64 * 1024
        )
        return FeatureResult(ok: true, message: "Simulator booted")
    }

    public func shutdown(udid: String) async throws(SimctlError) -> FeatureResult {
        let result = try await client.run(["shutdown", udid], timeout: .seconds(60))
        return result.succeeded
            ? FeatureResult(ok: true, message: "Simulator shut down")
            : FeatureResult(
                ok: false,
                message: friendlySimctlError(result, fallback: "Failed to shut down the simulator")
            )
    }

    /// Open a URL (deep link, universal link, or plain https) on a simulator.
    public func openURL(udid: String, url: String) async throws(SimctlError) -> FeatureResult {
        let result = try await client.run(["openurl", udid, url])
        return result.succeeded
            ? FeatureResult(ok: true, message: "Opened \(url)")
            : FeatureResult(
                ok: false,
                message: friendlySimctlError(result, fallback: "Failed to open the URL")
            )
    }

    public func setAppearance(udid: String, dark: Bool) async throws(SimctlError) -> AdbResult {
        try await client.run(["ui", udid, "appearance", dark ? "dark" : "light"])
    }

    /// Current appearance ("light"/"dark"), or nil when unreadable.
    public func currentAppearance(udid: String) async -> String? {
        guard let result = try? await client.run(["ui", udid, "appearance"]), result.succeeded else {
            return nil
        }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func statusBarOverride(udid: String, arguments: [String]) async throws(SimctlError) -> AdbResult {
        try await client.run(["status_bar", udid, "override"] + arguments)
    }

    public func statusBarClear(udid: String) async throws(SimctlError) -> AdbResult {
        try await client.run(["status_bar", udid, "clear"])
    }

    /// Whether any status-bar override is active. `status_bar list` prints the
    /// override table, or nothing / a "no overrides" note when clear — treat
    /// anything unexpected as "no" so the pill never lies about a clean bar.
    public func statusBarOverridden(udid: String) async -> Bool {
        guard let result = try? await client.run(["status_bar", udid, "list"]), result.succeeded else {
            return false
        }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && !text.lowercased().contains("no overrides")
    }

    /// iOS counterpart of `OverridesService.active` — reads state from the
    /// simulator itself (appearance query + status-bar list), no stored file.
    public func activeOverrides(udid: String) async -> [ActiveOverride] {
        var active: [ActiveOverride] = []
        if await currentAppearance(udid: udid) == "dark" {
            active.append(ActiveOverride(kind: .darkMode, value: "dark", setAt: 0))
        }
        if await statusBarOverridden(udid: udid) {
            active.append(ActiveOverride(kind: .demo, value: "status bar overridden", setAt: 0))
        }
        return active
    }

    /// Reset one override kind on a simulator. Battery rides on the status
    /// bar, so `.battery` and `.demo` both clear it.
    public func reset(udid: String, kind: OverrideKind) async throws(SimctlError) {
        switch kind {
        case .darkMode:
            _ = try await setAppearance(udid: udid, dark: false)
        case .demo, .battery:
            _ = try await statusBarClear(udid: udid)
        case .proxy, .layout, .animation, .locale:
            break // Android-only kinds — nothing to reset on a simulator.
        }
    }

    public func resetAll(udid: String) async throws(SimctlError) {
        _ = try await setAppearance(udid: udid, dark: false)
        _ = try await statusBarClear(udid: udid)
    }

    /// Screenshot to disk; nil destination falls back to a timestamped file
    /// in the shared capture folder (same convention as Android captures).
    public func screenshot(udid: String, to destination: URL? = nil) async throws -> URL {
        let file: URL
        if let destination {
            file = destination
        } else {
            let dir = try ScreenCaptureService.ensureCaptureDir()
            file = dir.appendingPathComponent("screenshot_\(ScreenCaptureService.stamp()).png")
        }
        let result = try await client.run(["io", udid, "screenshot", file.path])
        guard result.succeeded else {
            throw SimulatorServiceError.commandFailed(
                friendlySimctlError(result, fallback: "Screenshot failed")
            )
        }
        return file
    }

    /// Screenshot as raw PNG bytes for the in-app editor — simctl only writes
    /// files, so this stages through a temp file.
    public func screenshotData(udid: String) async throws -> Data {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sim-screenshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await screenshot(udid: udid, to: tmp)
        return try Data(contentsOf: tmp)
    }

    /// Minimal APNS payload for `simctl push`. Pure and deterministic
    /// (sorted keys) so the arg-vector test can assert the exact bytes.
    public static func apnsPayload(title: String, body: String, badge: Int?) -> Data {
        var aps: [String: Any] = [
            "alert": ["title": title, "body": body],
            "sound": "default",
        ]
        if let badge {
            aps["badge"] = badge
        }
        // Keys are strings and values JSON-safe, so serialization can't fail.
        return (try? JSONSerialization.data(
            withJSONObject: ["aps": aps],
            options: [.sortedKeys]
        )) ?? Data()
    }

    /// Deliver a test push to an app on a simulator. simctl reads the payload
    /// from a file, so the JSON stages through a temp `.apns` file.
    public func push(udid: String, bundleId: String, payload: Data) async throws -> FeatureResult {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sim-push-\(UUID().uuidString).apns")
        try payload.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let result = try await client.run(["push", udid, bundleId, tmp.path])
        return result.succeeded
            ? FeatureResult(ok: true, message: "Notification delivered — check the simulator")
            : FeatureResult(
                ok: false,
                message: friendlySimctlError(result, fallback: "Failed to deliver the notification")
            )
    }
}
