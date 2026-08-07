import ADBKit
import Foundation

/// Wire shapes for the device's network settings: Wi-Fi and Private DNS.
///
/// Both reads are **one** round-trip each, matching what the Mac's screens do
/// on open. `WiFiView.load` reads the status, the saved networks and — on a
/// rooted device — the saved passwords, and renders nothing until all of it has
/// arrived; splitting that across three routes would only invent three ways to
/// be half-loaded.
public enum NetworkProtocol {
    // MARK: - Wi-Fi

    public struct Status: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let connected: Bool
        public let ssid: String?
        public let ipAddress: String?
        public let linkSpeed: String?
        public let frequency: String?
        public let signal: String?

        public init(_ status: WifiStatus) {
            enabled = status.enabled
            connected = status.connected
            ssid = status.ssid
            ipAddress = status.ipAddress
            linkSpeed = status.linkSpeed
            frequency = status.frequency
            signal = status.signal
        }
    }

    public struct SavedNetwork: Codable, Equatable, Sendable {
        public let id: String
        public let ssid: String
        public let security: String?
        /// Only ever present on a rooted device — it comes from
        /// `WifiConfigStore.xml`, which needs `su` to read. Absent otherwise,
        /// which is what the "Passwords need root" note in the UI reflects.
        public let password: String?

        public init(_ network: WifiNetwork) {
            id = network.id
            ssid = network.ssid
            security = network.security
            password = network.password
        }
    }

    public struct WifiResponse: Codable, Equatable, Sendable {
        public let status: Status
        public let networks: [SavedNetwork]
        /// Whether passwords could be read at all, so the UI can say why they
        /// are missing rather than implying there are none.
        public let hasRootShell: Bool
    }

    /// Everything the Wi-Fi screen can do to a device.
    public enum WifiWrite: Equatable, Sendable {
        case setEnabled(Bool)
        case connect(ssid: String, security: String, password: String)
    }

    /// `enabled` for the radio toggle, `ssid` for a connect — which is present
    /// is what picks the verb.
    public struct WifiWriteRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let enabled: Bool?
        public let ssid: String?
        public let security: String?
        public let password: String?

        public init(
            serial: String, enabled: Bool? = nil, ssid: String? = nil,
            security: String? = nil, password: String? = nil
        ) {
            self.serial = serial
            self.enabled = enabled
            self.ssid = ssid
            self.security = security
            self.password = password
        }

        /// The security modes `cmd wifi connect-network` accepts. A closed set
        /// here rather than a passed-through string: it lands in an adb
        /// argument vector unquoted (it is a keyword, not a value), so it is
        /// the one field on this request that must not be free text.
        public static let securities = ["open", "owe", "wpa2", "wpa3"]

        public var resolved: WifiWrite? {
            if let enabled { return .setEnabled(enabled) }
            guard let ssid, !ssid.isEmpty, let security, Self.securities.contains(security) else {
                return nil
            }
            return .connect(ssid: ssid, security: security, password: password ?? "")
        }
    }

    // MARK: - Private DNS

    public struct DnsResponse: Codable, Equatable, Sendable {
        /// off | automatic | hostname — `DnsStatus.Mode`'s raw values.
        public let mode: String
        public let hostname: String?

        public init(_ status: DnsStatus) {
            mode = status.mode.rawValue
            hostname = status.hostname
        }
    }

    public struct DnsWriteRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let mode: String
        /// Required when `mode` is hostname; ignored otherwise.
        public let hostname: String?

        public init(serial: String, mode: String, hostname: String? = nil) {
            self.serial = serial
            self.mode = mode
            self.hostname = hostname
        }

        public var resolved: DnsStatus.Mode? {
            guard let mode = DnsStatus.Mode(rawValue: mode) else { return nil }
            // A hostname mode with nothing to point at would write an empty
            // specifier and leave DNS broken, so it is refused here rather
            // than half-applied.
            if mode == .hostname, (hostname ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                return nil
            }
            return mode
        }
    }

    public static let badWifiRequest = DaemonProtocol.ErrorBody(
        code: "bad_wifi_request",
        message: "Say enabled to toggle the radio, or an ssid and a known security mode to connect.")
    public static let badDnsRequest = DaemonProtocol.ErrorBody(
        code: "bad_dns_request",
        message: "mode must be off, automatic, or hostname — and hostname needs one.")
}

/// The four network routes.
enum NetworkRoutes {
    static func wifiRead(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            DaemonProtocol.DeviceRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        let (status, networks, rooted) = await backend.wifi(serial: request.serial)
        return (200, DaemonProtocol.encoded(NetworkProtocol.WifiResponse(
            status: NetworkProtocol.Status(status),
            networks: networks.map(NetworkProtocol.SavedNetwork.init),
            hasRootShell: rooted)))
    }

    static func wifiWrite(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            NetworkProtocol.WifiWriteRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        guard let write = request.resolved else {
            return (400, DaemonProtocol.encoded(NetworkProtocol.badWifiRequest))
        }
        do {
            let result = try await backend.writeWifi(serial: request.serial, write)
            return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(
                outcome(result, write: write))))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "The Wi-Fi command failed.", detail: "\(error)")))
        }
    }

    static func dnsRead(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            DaemonProtocol.DeviceRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        let status = await backend.privateDns(serial: request.serial)
        return (200, DaemonProtocol.encoded(NetworkProtocol.DnsResponse(status)))
    }

    static func dnsWrite(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            NetworkProtocol.DnsWriteRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        guard let mode = request.resolved else {
            return (400, DaemonProtocol.encoded(NetworkProtocol.badDnsRequest))
        }
        do {
            let result = try await backend.writePrivateDns(
                serial: request.serial, mode: mode,
                hostname: (request.hostname ?? "").trimmingCharacters(in: .whitespaces))
            return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(
                result.succeeded
                    ? FeatureResult(ok: true, message: "Private DNS updated")
                    : failure(result))))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "Could not set Private DNS.", detail: "\(error)")))
        }
    }

    /// The Mac's own wording for each Wi-Fi outcome.
    ///
    /// `cmd wifi connect-network` is the awkward one: plenty of ROMs print
    /// "failed" and still exit 0, so the exit code alone would report a
    /// success that never happened. `WiFiView.connect` checks the output for
    /// it, and that check has to live here or the two apps would disagree
    /// about whether a connect worked.
    private static func outcome(
        _ result: AdbResult, write: NetworkProtocol.WifiWrite
    ) -> FeatureResult {
        switch write {
        case .setEnabled(let on):
            guard result.succeeded else {
                return FeatureResult(
                    ok: false,
                    message: "Couldn't toggle Wi-Fi — the ROM may block svc wifi over adb.")
            }
            return FeatureResult(ok: true, message: "Wi-Fi \(on ? "on" : "off")")
        case .connect(let ssid, _, _):
            let output = (result.stdout + result.stderr).lowercased()
            let ok = result.succeeded && !output.contains("fail") && !output.contains("error")
            return FeatureResult(
                ok: ok,
                message: ok
                    ? "Connecting to \(ssid)…"
                    : "Connect failed — the ROM may block it over adb.")
        }
    }

    private static func failure(_ result: AdbResult) -> FeatureResult {
        let detail = result.stderr.isEmpty ? result.stdout : result.stderr
        return FeatureResult(ok: false, message: "Failed — \(detail)")
    }
}
