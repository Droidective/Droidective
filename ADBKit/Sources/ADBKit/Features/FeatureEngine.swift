import Foundation

/// Outcome of running one feature against one target.
public struct FeatureResult: Sendable, Equatable {
    public var ok: Bool
    public var message: String
    /// When set, the UI offers a one-click copy (e.g. device IP).
    public var copyText: String?
    /// When set, the UI offers Reveal in Finder (e.g. screenshot path).
    public var revealPath: String?
    /// True when the failure is the missing ADBKeyboard IME — the UI offers
    /// a one-click install.
    public var needsAdbKeyboard: Bool

    public init(
        ok: Bool,
        message: String,
        copyText: String? = nil,
        revealPath: String? = nil,
        needsAdbKeyboard: Bool = false
    ) {
        self.ok = ok
        self.message = message
        self.copyText = copyText
        self.revealPath = revealPath
        self.needsAdbKeyboard = needsAdbKeyboard
    }
}

/// Backend command-spec mirror of the feature registry. Each runner executes
/// one feature against a device (or globally) and returns a friendly result.
/// Keyed by the same feature ids the registry uses — ids are the contract.
public struct FeatureEngine: Sendable {
    public let client: AdbClient
    /// simctl twin of `client` — shares the process runner and command log,
    /// so tests script both toolchains through one MockProcessRunner and the
    /// Command Log shows adb and simctl calls side by side.
    public let simctl: SimctlClient
    public let locator: ToolLocator
    public let managedTools: ManagedToolStore
    public let toolchain: ApkToolchain
    public let monitor: DeviceMonitor
    public let appControl: AppControlService
    public let appInstall: AppInstallService
    public let apkInspection: ApkInspectionService
    public let apkSigning: ApkSigningService
    public let decompile: DecompileService
    public let aabConvert: AabConvertService
    public let frida: FridaService
    public let inspection: AppInspectionService
    public let toolDetection: ToolDetectionService
    public let overrides: OverridesService
    public let connection: ConnectionService
    public let crash: CrashExtractor
    public let bugReport: BugReportService
    public let customCommands: CustomCommandService
    public let adbKeyboard: AdbKeyboardInstaller
    public let fileExplorer: FileExplorerService
    public let appsExplorer: AppsExplorerService
    public let appIcons: AppIconService
    public let emulators: EmulatorService
    public let performance: PerformanceService
    public let networkSpeed: NetworkSpeedService
    public let root: RootService
    public let wifi: WifiService
    public let systemApps: SystemAppsService
    public let dns: DnsService
    public let restrictions: RestrictionsService
    public let developerSettings: DeveloperSettingsService
    public let simulators: SimulatorService
    let textInput: TextInputService
    let screenCapture: ScreenCaptureService

    public init(
        client: AdbClient, locator: ToolLocator, monitor: DeviceMonitor,
        overridesStore: JSONStore<OverridesMap>, toolsDirectory: URL
    ) {
        self.client = client
        self.simctl = SimctlClient(runner: client.runner, log: client.log)
        self.simulators = SimulatorService(client: simctl)
        self.locator = locator
        self.monitor = monitor
        self.managedTools = ManagedToolStore(rootDirectory: toolsDirectory)
        self.toolchain = ApkToolchain(locator: locator, store: managedTools)
        self.appControl = AppControlService(client: client)
        self.appInstall = AppInstallService(client: client)
        self.apkInspection = ApkInspectionService(client: client, toolchain: toolchain)
        self.apkSigning = ApkSigningService(toolchain: toolchain)
        self.decompile = DecompileService(toolchain: toolchain)
        self.aabConvert = AabConvertService(toolchain: toolchain)
        self.frida = FridaService(client: client)
        self.inspection = AppInspectionService(client: client)
        self.toolDetection = ToolDetectionService(locator: locator)
        self.overrides = OverridesService(client: client, store: overridesStore)
        self.connection = ConnectionService(client: client, monitor: monitor)
        self.crash = CrashExtractor(client: client)
        self.bugReport = BugReportService(client: client)
        self.customCommands = CustomCommandService(client: client)
        self.adbKeyboard = AdbKeyboardInstaller(client: client)
        self.fileExplorer = FileExplorerService(client: client)
        self.appsExplorer = AppsExplorerService(client: client)
        self.appIcons = AppIconService(client: client)
        self.emulators = EmulatorService(client: client, locator: locator)
        self.performance = PerformanceService(client: client)
        self.networkSpeed = NetworkSpeedService(client: client)
        self.root = RootService(client: client)
        self.wifi = WifiService(client: client)
        self.systemApps = SystemAppsService(client: client)
        self.dns = DnsService(client: client)
        self.restrictions = RestrictionsService(client: client)
        self.developerSettings = DeveloperSettingsService(client: client)
        self.textInput = TextInputService(client: client)
        self.screenCapture = ScreenCaptureService(client: client)
    }

    /// Feature ids with a working runner. The UI shows a "coming soon"
    /// placeholder for registry entries not yet listed here.
    public static let implementedIDs: Set<String> = [
        "terminal",
        "send-text", "get-ip", "reverse-port",
        "open-dev-menu", "reload-js", "screenshot",
        "scrcpy", "deep-link", "app-management", "logcat", "ios-logs",
        "demo-mode", "dark-mode", "animation-scale", "fake-battery",
        "layout-overrides", "locale", "network-toggles", "http-proxy",
        "permissions", "app-info", "current-activity", "foreground-package",
        "meminfo", "sandbox-browser", "monkey", "device-info",
        "screen-record", "crash-catcher", "bug-report", "wireless-adb",
        "rn-dev-host", "process-death", "custom-commands", "push-notification",
        "file-explorer", "apps", "apk-studio", "apk-inspector", "apk-sign", "apk-decompile", "aab-convert",
        "frida-console",
        "emulators", "performance", "network-speed",
        "root-status", "wifi", "private-dns", "system-restrictions", "dev-settings",
        "reactotron", "js-console",
    ]

    /// Screenshot with an explicit destination (UI asks the user first).
    public func captureScreenshot(
        serial: String, platform: DevicePlatform = .android, to destination: URL
    ) async throws -> URL {
        switch platform {
        case .android: return try await screenCapture.captureScreenshot(serial: serial, to: destination)
        case .iosSimulator: return try await simulators.screenshot(udid: serial, to: destination)
        }
    }

    /// Screenshot returned as raw PNG bytes — for the editor, which saves on demand.
    public func captureScreenshotData(serial: String, platform: DevicePlatform = .android) async throws -> Data {
        switch platform {
        case .android: return try await screenCapture.captureScreenshotData(serial: serial)
        case .iosSimulator: return try await simulators.screenshotData(udid: serial)
        }
    }

    /// Run a feature against one serial (or globally for global-scope ids).
    /// `platform` routes cross-platform ids to the matching toolchain —
    /// adb runners for Android, simctl runners for iOS Simulators.
    public func run(
        featureID: String,
        serial: String,
        platform: DevicePlatform = .android,
        params: [String: FeatureValue]
    ) async -> FeatureResult {
        do {
            switch platform {
            case .android:
                return try await dispatch(featureID: featureID, serial: serial, params: params)
            case .iosSimulator:
                return try await dispatchIOS(featureID: featureID, udid: serial, params: params)
            }
        } catch {
            return FeatureResult(ok: false, message: error.localizedDescription)
        }
    }

    /// simctl runners for the feature ids that support iOS Simulators. The
    /// registry's `platforms` is the source of truth for what belongs here —
    /// a consistency test walks every iOS-capable action id through this path.
    private func dispatchIOS(
        featureID: String,
        udid: String,
        params: [String: FeatureValue]
    ) async throws -> FeatureResult {
        switch featureID {
        case "screenshot":
            let file = try await simulators.screenshot(udid: udid)
            return FeatureResult(ok: true, message: "Screenshot saved", revealPath: file.path)

        case "dark-mode":
            let on = params["on"]?.boolValue == true
            let result = try await simulators.setAppearance(udid: udid, dark: on)
            return fromResult(
                result,
                success: on ? "Switched to dark mode" : "Switched to light mode",
                fallback: "Failed to change the appearance"
            )

        case "demo-mode":
            let on = params["on"]?.boolValue == true
            let result = on
                ? try await simulators.statusBarOverride(udid: udid, arguments: SimulatorService.demoStatusBarArguments)
                : try await simulators.statusBarClear(udid: udid)
            return fromResult(
                result,
                success: on ? "Demo mode on (clean status bar)" : "Demo mode off",
                fallback: "Failed to change the status bar"
            )

        case "fake-battery":
            guard let raw = params["level"]?.numberValue, (0...100).contains(Int(raw.rounded())) else {
                return FeatureResult(ok: false, message: "Battery level must be 0–100.")
            }
            let level = Int(raw.rounded())
            let unplugged = params["unplugged"]?.boolValue ?? true
            let result = try await simulators.statusBarOverride(udid: udid, arguments: [
                "--batteryState", unplugged ? "discharging" : "charging",
                "--batteryLevel", String(level),
            ])
            return fromResult(
                result,
                success: "Battery shown as \(level)% \(unplugged ? "unplugged" : "charging") — reset via the Demo Mode pill",
                fallback: "Failed to override the battery"
            )

        case "push-notification":
            let bundleId = (params["bundleId"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            guard !bundleId.isEmpty else {
                return FeatureResult(ok: false, message: "Enter the app's bundle ID, e.g. com.example.app.")
            }
            let title = params["title"]?.stringValue ?? "Test Notification"
            let body = params["body"]?.stringValue ?? ""
            let badge = params["badge"]?.numberValue.map { Int($0.rounded()) }
            let payload = SimulatorService.apnsPayload(title: title, body: body, badge: badge)
            return try await simulators.push(udid: udid, bundleId: bundleId, payload: payload)

        default:
            let title = FeatureRegistry.byID[featureID]?.title ?? featureID
            return FeatureResult(
                ok: false,
                message: "\(title) isn't available for iOS Simulators — select an Android device."
            )
        }
    }

    private func dispatch(
        featureID: String,
        serial: String,
        params: [String: FeatureValue]
    ) async throws -> FeatureResult {
        switch featureID {
        case "push-notification":
            return FeatureResult(
                ok: false,
                message: "Push simulation works on iOS Simulators — select a booted simulator."
            )

        case "send-text":
            let text = params["text"]?.stringValue ?? ""
            return try await textInput.send(serial: serial, text: text)

        case "get-ip":
            return try await getIP(serial: serial)

        case "reverse-port":
            return try await reversePort(serial: serial, params: params)

        case "open-dev-menu":
            let result = try await client.run(on: serial, ["shell", "input", "keyevent", "82"])
            return fromResult(
                result,
                success: "Sent the dev-menu key — the menu opens in RN dev builds with the app in front",
                fallback: "Failed to send the dev-menu key"
            )

        case "reload-js":
            let result = try await client.run(on: serial, ["shell", "input", "keyevent", "46", "46"])
            return fromResult(
                result,
                success: "Sent reload (R·R) — RN dev builds with the app in front reload from Metro",
                fallback: "Failed to send the reload keys"
            )

        case "screenshot":
            let file = try await screenCapture.captureScreenshot(serial: serial)
            return FeatureResult(ok: true, message: "Screenshot saved", revealPath: file.path)

        case "demo-mode":
            let on = params["on"]?.boolValue == true
            try await overrides.applyDemo(serial: serial, on: on)
            return FeatureResult(ok: true, message: on ? "Demo mode on (clean status bar)" : "Demo mode off")

        case "dark-mode":
            let on = params["on"]?.boolValue == true
            try await overrides.applyDarkMode(serial: serial, on: on)
            return FeatureResult(ok: true, message: on ? "Switched to dark mode" : "Switched to light mode")

        case "animation-scale":
            let off = params["on"]?.boolValue == true
            try await overrides.applyAnimation(serial: serial, off: off)
            return FeatureResult(ok: true, message: off ? "Animations off (0×)" : "Animations on (1×)")

        case "fake-battery":
            guard let raw = params["level"]?.numberValue, (0...100).contains(Int(raw.rounded())) else {
                return FeatureResult(ok: false, message: "Battery level must be 0–100.")
            }
            let unplugged = params["unplugged"]?.boolValue ?? true
            let value = try await overrides.applyBattery(serial: serial, level: Int(raw.rounded()), unplugged: unplugged)
            return FeatureResult(ok: true, message: "Battery faked: \(value)")

        case "layout-overrides":
            guard let fontScale = params["fontScale"]?.numberValue else {
                return FeatureResult(ok: false, message: "Invalid font scale.")
            }
            let density = params["density"]?.numberValue.flatMap { $0 > 0 ? Int($0) : nil }
            let value = try await overrides.applyLayout(serial: serial, fontScale: fontScale, density: density)
            return FeatureResult(ok: true, message: "Applied \(value)")

        case "locale":
            guard let locale = params["locale"]?.stringValue, !locale.isEmpty else {
                return FeatureResult(ok: false, message: "Pick a locale.")
            }
            _ = try await overrides.applyLocale(serial: serial, locale: locale)
            return FeatureResult(
                ok: true,
                message: "Locale change to \(locale) requested — a full system change can require root."
            )

        case "http-proxy":
            let proxy = (params["proxy"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            if proxy.isEmpty {
                try await overrides.reset(serial: serial, kind: .proxy)
                return FeatureResult(ok: true, message: "Proxy cleared")
            }
            guard proxy.contains(":"), proxy.split(separator: ":").last.map({ Int($0) != nil }) == true else {
                return FeatureResult(ok: false, message: "Use host:port, e.g. 10.0.0.5:8888.")
            }
            _ = try await overrides.applyProxy(serial: serial, proxy: proxy)
            return FeatureResult(ok: true, message: "Proxy set to \(proxy)")

        case "bug-report":
            let packageId = params["packageId"]?.stringValue
            let zipPath = try await bugReport.create(serial: serial, packageId: packageId)
            return FeatureResult(ok: true, message: "Bug report saved", revealPath: zipPath.path)

        case "process-death":
            return try await simulateProcessDeath(serial: serial, params: params)

        case "rn-dev-host":
            return try await setDevServerHost(serial: serial, params: params)

        case "current-activity":
            guard let activity = try await inspection.getCurrentActivity(serial: serial) else {
                return FeatureResult(ok: false, message: "Couldn't determine the foreground activity.")
            }
            return FeatureResult(ok: true, message: "Foreground: \(activity)", copyText: activity)

        case "foreground-package":
            guard let package = try await inspection.getForegroundPackage(serial: serial) else {
                return FeatureResult(ok: false, message: "Couldn't read the foreground app — is the screen on?")
            }
            return FeatureResult(ok: true, message: "Foreground app: \(package)", copyText: package)

        case "monkey":
            guard let package = params["packageId"]?.stringValue, !package.isEmpty else {
                return FeatureResult(ok: false, message: "Pick a saved bundle first.")
            }
            let count = max(1, Int((params["count"]?.numberValue ?? 500).rounded()))
            let result = try await client.run(
                on: serial,
                ["shell", "monkey", "-p", shellQuote(package), "-v", String(count)],
                timeout: .seconds(120)
            )
            if result.timedOut {
                return FeatureResult(
                    ok: false,
                    message: "Monkey stopped after 120s — events already sent were delivered."
                )
            }
            return result.succeeded
                ? FeatureResult(ok: true, message: "Fired \(count) random events at \(package)")
                : FeatureResult(ok: false, message: friendlyAdbError(result, fallback: "Monkey run failed"))

        case "network-toggles":
            let wifi = params["wifi"]?.boolValue ?? true
            let data = params["data"]?.boolValue ?? true
            let airplane = params["airplane"]?.boolValue ?? false
            let wifiResult = try await client.run(on: serial, ["shell", "svc", "wifi", wifi ? "enable" : "disable"])
            let dataResult = try await client.run(on: serial, ["shell", "svc", "data", data ? "enable" : "disable"])
            let airplaneResult = try await client.run(on: serial, [
                "shell", "cmd", "connectivity", "airplane-mode", airplane ? "enable" : "disable",
            ])
            var failed: [String] = []
            if !wifiResult.succeeded { failed.append("Wi-Fi") }
            if !dataResult.succeeded { failed.append("data") }
            if !airplaneResult.succeeded { failed.append("airplane") }
            guard failed.isEmpty else {
                return FeatureResult(
                    ok: false,
                    message: "Couldn't set \(failed.joined(separator: ", ")) — the ROM may not allow it over adb."
                )
            }
            return FeatureResult(
                ok: true,
                message: "Wi-Fi \(wifi ? "on" : "off") · data \(data ? "on" : "off") · airplane \(airplane ? "on" : "off")"
            )

        default:
            return FeatureResult(ok: false, message: "\"\(featureID)\" isn't implemented yet.")
        }
    }

    func fromResult(_ result: AdbResult, success: String, fallback: String) -> FeatureResult {
        result.succeeded
            ? FeatureResult(ok: true, message: success)
            : FeatureResult(ok: false, message: friendlyAdbError(result, fallback: fallback))
    }

    static func parseIP(_ output: String) -> String? {
        if let match = output.firstMatch(of: /inet (\d{1,3}(?:\.\d{1,3}){3})/) {
            return String(match.1)
        }
        if let match = output.firstMatch(of: /src (\d{1,3}(?:\.\d{1,3}){3})/) {
            return String(match.1)
        }
        return nil
    }

    private func getIP(serial: String) async throws(AdbError) -> FeatureResult {
        let wlan = try await client.run(on: serial, ["shell", "ip", "-f", "inet", "addr", "show", "wlan0"])
        var ip = Self.parseIP(wlan.stdout)
        if ip == nil {
            let route = try await client.run(on: serial, ["shell", "ip", "route"])
            ip = Self.parseIP(route.stdout)
        }
        guard let ip else {
            return FeatureResult(ok: false, message: "Couldn't determine the device IP (is Wi-Fi on?).")
        }
        return FeatureResult(ok: true, message: "Device IP: \(ip)", copyText: ip)
    }

    /// Background-then-kill for state-restoration testing. Uses the chosen
    /// bundle, or whatever app is in front when none is chosen (read before
    /// HOME backgrounds it). `am kill` exits 0 even when the system declines
    /// to kill (e.g. a foreground service holds the process), so the process
    /// is re-checked to report what actually happened.
    private func simulateProcessDeath(serial: String, params: [String: FeatureValue]) async throws -> FeatureResult {
        var package = params["packageId"]?.stringValue ?? ""
        if package.isEmpty {
            package = (try await inspection.getForegroundPackage(serial: serial)) ?? ""
        }
        guard !package.isEmpty else {
            return FeatureResult(
                ok: false,
                message: "Couldn't read the app in front — open the app on the device, or pick a saved bundle."
            )
        }
        _ = try await client.run(on: serial, ["shell", "input", "keyevent", "3"]) // HOME → background
        let kill = try await client.run(on: serial, ["shell", "am", "kill", shellQuote(package)])
        guard kill.succeeded else {
            return FeatureResult(ok: false, message: friendlyAdbError(kill, fallback: "Failed to kill the app"))
        }
        try? await Task.sleep(for: .milliseconds(600))
        let alive = try await client.run(on: serial, ["shell", "pidof", shellQuote(package)])
        return alive.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? FeatureResult(ok: true, message: "Killed \(package) in the background — reopen it to test state restoration.")
            : FeatureResult(
                ok: false,
                message: "\(package) is still running — the system kept it alive (a foreground service?). Use Apps → Force Stop for a hard kill."
            )
    }

    /// Point the app at a Metro dev server, best mechanism first: a localhost
    /// host (or bare port) reverse-tunnels the port; a remote host writes RN's
    /// `debug_http_host` preference via `run-as` (dev builds are debuggable)
    /// and relaunches the app; where `run-as` is refused, the `metro.host`
    /// system property is tried (emulators, rooted devices); otherwise the dev
    /// menu is opened so the host can be set by hand.
    private func setDevServerHost(serial: String, params: [String: FeatureValue]) async throws -> FeatureResult {
        let raw = (params["host"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            return FeatureResult(ok: false, message: "Enter a host:port (e.g. 192.168.1.10:8081).")
        }
        guard !raw.contains("://") else {
            return FeatureResult(
                ok: false,
                message: "Enter just host:port (e.g. 192.168.1.10:8081) — drop the http:// prefix."
            )
        }
        let (host, portText) = Self.splitHostPort(raw)
        guard let port = Int(portText), (1...65535).contains(port) else {
            return FeatureResult(
                ok: false,
                message: "\"\(portText)\" isn't a valid port — use host:port, e.g. 192.168.1.10:8081."
            )
        }
        // splitHostPort takes the last colon as the port separator, so an IPv6
        // literal would be silently mangled into host+port — reject it instead.
        guard !host.contains(":") else {
            return FeatureResult(
                ok: false,
                message: "IPv6 hosts aren't supported here — use an IPv4 address or hostname, e.g. 192.168.1.10:8081."
            )
        }
        if host.isEmpty || host == "localhost" || host == "127.0.0.1" {
            let result = try await client.run(on: serial, ["reverse", "tcp:\(port)", "tcp:\(port)"])
            return fromResult(
                result,
                success: "Reverse-tunneled tcp:\(port) — the app's default localhost:\(port) now reaches Metro on this Mac.",
                fallback: "Failed to reverse tcp:\(port)"
            )
        }
        // The preference RN actually reads (DevInternalSettings.debug_http_host)
        // carries host *and* port, and dev builds are debuggable — so run-as
        // can write it directly. Chosen bundle first, else the app in front.
        var package = params["packageId"]?.stringValue ?? ""
        if package.isEmpty {
            package = (try await inspection.getForegroundPackage(serial: serial)) ?? ""
        }
        if !package.isEmpty,
           let result = try await writeDebugHTTPHost(serial: serial, package: package, host: host, port: port) {
            return result
        }
        _ = try await client.run(on: serial, ["shell", "setprop", "metro.host", shellQuote(host)])
        let readBack = try await client.run(on: serial, ["shell", "getprop", "metro.host"])
        if readBack.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == host {
            // RN pairs metro.host with the app's built-in Metro port, so the
            // prop alone can't carry a custom port — say so instead of
            // promising host:port.
            let followUp = port == 8081
                ? "reload JS (or relaunch the app) to load from \(host):\(port)."
                : "RN pairs it with the app's built-in Metro port (usually 8081) — for port \(port), "
                    + "set \(host):\(port) in the dev menu’s “Change Bundle Location” instead."
            return FeatureResult(ok: true, message: "Set metro.host=\(host) — \(followUp)")
        }
        _ = try await client.run(on: serial, ["shell", "input", "keyevent", "82"])
        return FeatureResult(
            ok: false,
            message: "This device blocks setting a dev host over adb — sent the dev-menu shortcut instead. "
                + "With your RN dev build in the foreground, choose “Change Bundle Location” and enter \(host):\(port)."
        )
    }

    /// Writes `debug_http_host` into the app's default SharedPreferences via
    /// `run-as` and relaunches the app so RN reads the new value. Returns nil
    /// when the device refuses (app not debuggable, `run-as` broken) so the
    /// caller can fall back to `metro.host`/the dev menu.
    private func writeDebugHTTPHost(
        serial: String, package: String, host: String, port: Int
    ) async throws(AdbError) -> FeatureResult? {
        let probe = try await client.run(on: serial, ["shell", "run-as", shellQuote(package), "id"])
        guard probe.succeeded else { return nil }

        // run-as starts in the app's data dir, so the prefs path is relative.
        let prefsPath = "shared_prefs/\(package)_preferences.xml"
        let existing = try await client.run(
            on: serial, ["shell", "run-as", shellQuote(package), "cat", shellQuote(prefsPath)]
        )
        let hostPort = "\(host):\(port)"
        let merged = Self.upsertDebugHTTPHost(existing.succeeded ? existing.stdout : nil, hostPort: hostPort)
        let script = "mkdir -p shared_prefs && printf '%s' \(shellQuote(merged)) > \(shellQuote(prefsPath))"
        let write = try await client.run(
            on: serial, ["shell", "run-as", shellQuote(package), "sh", "-c", shellQuote(script)]
        )
        guard write.succeeded else { return nil }
        let readBack = try await client.run(
            on: serial, ["shell", "run-as", shellQuote(package), "cat", shellQuote(prefsPath)]
        )
        guard readBack.stdout.contains(Self.xmlEscape(hostPort)) else { return nil }

        // The running app caches its prefs in memory — restart it so RN loads
        // the new host (stop only after the write verifiably landed, so the
        // fallback paths still have the app around if run-as flaked).
        _ = try await client.run(on: serial, ["shell", "am", "force-stop", shellQuote(package)])
        let relaunch = try await client.run(
            on: serial,
            ["shell", "monkey", "-p", shellQuote(package), "-c", "android.intent.category.LAUNCHER", "1"]
        )
        // monkey exits 0 even when the app has no LAUNCHER activity (custom
        // launch category, deep-link-only) — it just prints "No activities
        // found … aborted". Don't claim a relaunch that didn't happen, or the
        // user is told all is well while the app sits force-stopped.
        let relaunched = relaunch.succeeded
            && !relaunch.stdout.contains("No activities")
            && !relaunch.stderr.contains("No activities")
        let tail = relaunched
            ? "wrote debug_http_host and relaunched the app."
            : "wrote debug_http_host — reopen the app to load the new host."
        return FeatureResult(ok: true, message: "Pointed \(package) at \(hostPort) — \(tail)")
    }

    /// Inserts or replaces the `debug_http_host` entry in a SharedPreferences
    /// XML document; a missing/foreign document is replaced with a fresh map.
    /// Pure so it's testable without a device.
    static func upsertDebugHTTPHost(_ xml: String?, hostPort: String) -> String {
        let entry = "<string name=\"debug_http_host\">\(xmlEscape(hostPort))</string>"
        guard let xml, xml.contains("<map") else {
            return "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n    \(entry)\n</map>\n"
        }
        if let existing = xml.range(
            of: "<string name=\"debug_http_host\">[^<]*</string>", options: .regularExpression
        ) {
            return xml.replacingCharacters(in: existing, with: entry)
        }
        if let emptyMap = xml.range(of: "<map\\s*/>", options: .regularExpression) {
            return xml.replacingCharacters(in: emptyMap, with: "<map>\n    \(entry)\n</map>")
        }
        if let close = xml.range(of: "</map>") {
            return xml.replacingCharacters(in: close, with: "    \(entry)\n</map>")
        }
        return xml
    }

    static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// "host:port" → (host, port); a bare port means localhost; a bare host
    /// gets Metro's default 8081.
    static func splitHostPort(_ raw: String) -> (host: String, port: String) {
        if let colon = raw.lastIndex(of: ":") {
            return (String(raw[..<colon]), String(raw[raw.index(after: colon)...]))
        }
        return raw.allSatisfy(\.isNumber) ? ("", raw) : (raw, "8081")
    }

    private func reversePort(serial: String, params: [String: FeatureValue]) async throws(AdbError) -> FeatureResult {
        guard let raw = params["port"]?.numberValue,
              raw.truncatingRemainder(dividingBy: 1) == 0,
              (1...65535).contains(Int(raw))
        else {
            return FeatureResult(ok: false, message: "Enter a valid port (1–65535).")
        }
        let port = Int(raw)
        let result = try await client.run(on: serial, ["reverse", "tcp:\(port)", "tcp:\(port)"])
        return fromResult(result, success: "Reversed port \(port)", fallback: "Failed to reverse port")
    }

}
