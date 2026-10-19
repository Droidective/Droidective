import Foundation

/// What the device menu's Tailscale section shows.
public struct TailscaleStatus: Sendable, Equatable {
    public let flavor: TailscaleCLI.Flavor
    /// tailscaled's `BackendState`, or nil when the CLI could not reach it —
    /// the Mac app not running, tailscaled not started.
    public let backendState: String?
    /// Online Android peers with a tailnet IPv4, sorted by name. Empty unless
    /// tailscaled is running.
    public let androidPeers: [TailscalePeer]

    public init(flavor: TailscaleCLI.Flavor, backendState: String?, androidPeers: [TailscalePeer]) {
        self.flavor = flavor
        self.backendState = backendState
        self.androidPeers = androidPeers
    }

    public var isRunning: Bool { backendState == "Running" }

    /// The line the section shows instead of a list, or nil when it has peers
    /// to list. Tailscale's own vocabulary where it has one ("stopped", "log
    /// in"), so the menu and the menu-bar app say the same thing.
    public var notice: String? {
        switch backendState {
        case nil: return "Tailscale isn't running"
        case "Running": return androidPeers.isEmpty ? "No Android devices online in your tailnet" : nil
        case "Stopped": return "Tailscale is stopped"
        case "NeedsLogin": return "Tailscale needs you to log in"
        case "NeedsMachineAuth": return "This Mac is waiting for approval in your tailnet"
        case "Starting", "NoState": return "Tailscale is starting"
        case let state?: return "Tailscale is \(state.lowercased())"
        }
    }
}

/// Tailscale mode: Android phones on the user's tailnet, reached by plain
/// `adb connect` over the 100.x address — no backend of ours in between.
///
/// Two adb verbs and one read. Reading the tailnet is a background poll, so it
/// runs the Tailscale CLI directly and stays out of the Command Log; the two
/// verbs go through `AdbClient` like every other user action.
public struct TailscaleService: Sendable {
    let client: AdbClient
    let locator: ToolLocator
    let monitor: DeviceMonitor

    public init(client: AdbClient, locator: ToolLocator, monitor: DeviceMonitor) {
        self.client = client
        self.locator = locator
        self.monitor = monitor
    }

    /// The tailnet as the device menu shows it, or nil when there is no
    /// Tailscale CLI on this machine — the menu then has no Tailscale section.
    public func status() async -> TailscaleStatus? {
        guard let cli = await locator.tailscaleCLI() else { return nil }
        let call = cli.invocation(["status", "--json"])
        // A tailnet of a thousand nodes is about a megabyte of JSON.
        let output = await client.runner.run(
            executable: call.executable, arguments: call.arguments,
            timeout: .seconds(8), maxOutputBytes: 8 * 1024 * 1024)
        // The document decides, not the exit code: a stopped or logged-out
        // tailscaled still answers with one, and no document means the CLI
        // could not reach tailscaled at all.
        guard let network = TailscalePeers.parse(output.stdoutText) else {
            return TailscaleStatus(flavor: cli.flavor, backendState: nil, androidPeers: [])
        }
        return TailscaleStatus(
            flavor: cli.flavor, backendState: network.backendState,
            androidPeers: network.backendState == "Running" ? network.androidPeers : [])
    }

    /// Whether "Prepare for Tailscale" applies to `device`: an Android phone
    /// on a USB cable and ready. A wireless one is already in tcpip mode, and
    /// an emulator is never on a tailnet.
    public static func canPrepare(_ device: Device) -> Bool {
        device.platform == .android && device.isReady && !device.isWireless
            && !device.serial.hasPrefix("emulator-")
    }

    /// `adb tcpip 5555` on a USB-connected phone, and nothing more.
    ///
    /// Not `ConnectionService.enableTcpip`, which goes on to read wlan0 and
    /// connect over Wi-Fi: here the phone is meant to be reached over the
    /// tailnet, from wherever it is, and connecting it on the local network
    /// would put a second row for the same phone in the device bar.
    public func prepare(serial: String) async throws(AdbError) -> FeatureResult {
        let result = try await client.run(on: serial, ["tcpip", TailscalePeers.adbPort])
        await monitor.invalidate()
        guard result.succeeded else {
            return FeatureResult(
                ok: false, message: friendlyAdbError(result, fallback: "Couldn't switch adb to tcpip."))
        }
        return FeatureResult(
            ok: true,
            message: "Ready for Tailscale until it restarts — connect it from the Tailscale section of the device menu.")
    }

    /// `adb connect <tailnet IPv4>:5555`.
    public func connect(_ peer: TailscalePeer) async throws(AdbError) -> FeatureResult {
        let result = try await client.run(["connect", peer.adbEndpoint], timeout: .seconds(20))
        await monitor.invalidate()
        return Self.connectOutcome(result, peerName: peer.name)
    }

    /// adb exits 0 even when it could not connect, so the words decide.
    /// "Connection refused" is the one answer with a known cause here: the
    /// phone is on the tailnet but adb is not listening, because it has
    /// restarted since it was last prepared.
    static func connectOutcome(_ result: AdbResult, peerName: String) -> FeatureResult {
        let output = result.stdout + result.stderr
        if output.range(
            of: "connected to|already connected", options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return FeatureResult(ok: true, message: "Connected to \(peerName) over Tailscale")
        }
        if output.range(of: "refused", options: .caseInsensitive) != nil {
            return FeatureResult(
                ok: false,
                message: "\(peerName) refused the connection. If it has restarted since it was last prepared, plug it in and choose Prepare for Tailscale.")
        }
        let reason = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return FeatureResult(
            ok: false, message: reason.isEmpty ? "Couldn't connect to \(peerName)." : reason)
    }

    // MARK: - Copy shared with the Windows/Linux app

    /// The confirmation "Prepare for Tailscale" asks before it runs. One copy,
    /// served to the Windows/Linux app, because this is a security warning and
    /// two wordings of it are two chances to understate it.
    public static func prepareTitle(deviceName: String) -> String {
        "Prepare \(deviceName) for Tailscale?"
    }

    public static let prepareWarning = """
        This runs adb tcpip \(TailscalePeers.adbPort). Until the phone restarts, its port and \
        serial stay the same, and you can connect to it over your tailnet from anywhere — on \
        mobile data too.

        That listener is plaintext, and it is open on every network the phone joins, not just \
        your tailnet. It disappears when the phone restarts.

        Switching restarts adb on the phone, which stops anything started over adb — Shizuku \
        included.
        """

    public static let prepareConfirmLabel = "Prepare"
}
