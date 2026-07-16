import Foundation

/// A parsed "ip:port" endpoint as shown on the phone's Wireless debugging
/// screen. `host` is ready for adb (IPv6 stays/gets bracketed).
public struct WirelessEndpoint: Equatable, Sendable {
    public let host: String
    public let port: String?

    public init(host: String, port: String?) {
        self.host = host
        self.port = port
    }
}

/// Wireless adb: USB→tcpip bootstrap, Android 11+ pairing, and connect.
///
/// The Android 11 pairing port (under "Pair device with pairing code")
/// differs from the connection port on the main Wireless Debugging screen —
/// the UI collects both.
public struct ConnectionService: Sendable {
    let client: AdbClient
    let monitor: DeviceMonitor

    public init(client: AdbClient, monitor: DeviceMonitor) {
        self.client = client
        self.monitor = monitor
    }

    /// Put a USB-connected device into tcpip mode and connect to its ip:5555.
    public func enableTcpip(serial: String) async throws(AdbError) -> FeatureResult {
        let tcp = try await client.run(on: serial, ["tcpip", "5555"])
        guard tcp.succeeded else {
            return FeatureResult(ok: false, message: friendlyAdbError(tcp, fallback: "Failed to switch to tcpip mode"))
        }
        let wlan = try await client.run(on: serial, ["shell", "ip", "-f", "inet", "addr", "show", "wlan0"])
        guard let ip = FeatureEngine.parseIP(wlan.stdout) else {
            return FeatureResult(ok: true, message: "tcpip enabled, but couldn't read the device IP — check Wi-Fi.")
        }
        let address = "\(ip):5555"
        let connected = try await client.run(["connect", address])
        await monitor.invalidate()
        let success = connected.stdout.range(of: "connected|already", options: [.regularExpression, .caseInsensitive]) != nil
        return FeatureResult(
            ok: true,
            message: success ? "Connected over Wi-Fi: \(address)" : "tcpip enabled — connect to \(address)",
            copyText: address
        )
    }

    /// Android 11+ pairing with a code. host/port come from the pairing screen.
    public func pair(host: String, port: String, code: String) async throws(AdbError) -> FeatureResult {
        let result = try await client.run(["pair", "\(host):\(port)", code], timeout: .seconds(20))
        if result.stdout.range(of: "Successfully paired", options: .caseInsensitive) != nil {
            return FeatureResult(ok: true, message: "Paired — now connect using the connection port.")
        }
        if result.stderr.range(of: "unknown command|usage: adb", options: [.regularExpression, .caseInsensitive]) != nil {
            return FeatureResult(ok: false, message: "Your adb is too old for pairing — update Android platform-tools (≥30).")
        }
        let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return FeatureResult(
            ok: false,
            message: reason.isEmpty ? (fallback.isEmpty ? "Pairing failed (check the code/port)." : fallback) : reason
        )
    }

    public func connect(host: String, port: String) async throws(AdbError) -> FeatureResult {
        let result = try await client.run(["connect", "\(host):\(port)"], timeout: .seconds(20))
        await monitor.invalidate()
        let success = result.stdout.range(of: "connected|already", options: [.regularExpression, .caseInsensitive]) != nil
        if success {
            return FeatureResult(ok: true, message: "Connected to \(host):\(port)")
        }
        let reason = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return FeatureResult(ok: false, message: reason.isEmpty ? "Connection failed." : reason)
    }

    /// adb's default connect port — what `adb connect <host>` assumes.
    public static let defaultConnectPort = "5555"

    /// `parseEndpoint` for *connect* inputs: a bare host gets adb's default
    /// port 5555 ("10.158.128.7" → "10.158.128.7:5555"), so the returned
    /// endpoint always carries a port. Never use this for pairing — the
    /// Android 11+ pairing port is random per session, so a default would
    /// silently target the wrong port.
    public static func parseConnectEndpoint(_ text: String) -> WirelessEndpoint? {
        guard let endpoint = parseEndpoint(text) else { return nil }
        guard endpoint.port == nil else { return endpoint }
        return WirelessEndpoint(host: endpoint.host, port: defaultConnectPort)
    }

    /// Parse a pasted endpoint — the "IP address & Port" string the phone
    /// displays — tolerating stray whitespace, a bare host, and IPv6 (bracketed
    /// or not). Returns nil when the text isn't a plausible endpoint: empty,
    /// inner spaces, a non-numeric port, or an implausible host (a truncated
    /// IPv4 like "1.1.1", a non-parsing IPv6, a malformed hostname).
    public static func parseEndpoint(_ text: String) -> WirelessEndpoint? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }

        func validated(host: String, port: String?) -> WirelessEndpoint? {
            guard isValidHost(host) else { return nil }
            if let port {
                guard (1...5).contains(port.count), port.allSatisfy(\.isNumber) else { return nil }
            }
            return WirelessEndpoint(host: host, port: port)
        }

        // Bracketed IPv6: "[fe80::1]:37123" or "[fe80::1]".
        if trimmed.hasPrefix("[") {
            guard let close = trimmed.firstIndex(of: "]") else { return nil }
            let host = String(trimmed[...close])
            let rest = trimmed[trimmed.index(after: close)...]
            if rest.isEmpty { return validated(host: host, port: nil) }
            guard rest.hasPrefix(":") else { return nil }
            return validated(host: host, port: String(rest.dropFirst()))
        }

        let colons = trimmed.filter { $0 == ":" }.count
        switch colons {
        case 0:
            return validated(host: trimmed, port: nil)
        case 1:
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            return validated(host: String(parts[0]), port: String(parts[1]))
        default:
            // Bare IPv6 with no port — bracket it for adb.
            return validated(host: "[\(trimmed)]", port: nil)
        }
    }

    /// A plausible adb host: a complete IPv4 address, a bracketed IPv6
    /// literal, or a DNS hostname. Digits-and-dots input that isn't valid
    /// IPv4 ("1.1.1", "256.1.1.1") is a truncated IP, not a hostname —
    /// rejected so the sheet's buttons don't enable on it.
    private static func isValidHost(_ host: String) -> Bool {
        if host.hasPrefix("[") {
            guard host.hasSuffix("]") else { return false }
            return isIPv6(String(host.dropFirst().dropLast()))
        }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return isIPv4(host) }
        return isHostname(host)
    }

    private static func isIPv4(_ text: String) -> Bool {
        let octets = text.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        // `Int(_:)` also rejects non-ASCII digits that `isNumber` lets through.
        return octets.allSatisfy { octet in
            (1...3).contains(octet.count) && (Int(octet).map { $0 <= 255 } ?? false)
        }
    }

    private static func isIPv6(_ text: String) -> Bool {
        // A zone index ("fe80::1%en0") rides after the address proper.
        let address = String(text.prefix { $0 != "%" })
        guard !address.isEmpty else { return false }
        var parsed = in6_addr()
        return inet_pton(AF_INET6, address, &parsed) == 1
    }

    private static func isHostname(_ text: String) -> Bool {
        guard text.count <= 253 else { return false }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            (1...63).contains(label.count)
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
                && label.first != "-" && label.last != "-"
        }
    }

    public func disconnect(target: String?) async throws(AdbError) -> FeatureResult {
        let args = target.map { ["disconnect", $0] } ?? ["disconnect"]
        let result = try await client.run(args)
        await monitor.invalidate()
        return FeatureResult(
            ok: result.succeeded,
            message: target.map { "Disconnected \($0)" } ?? "Disconnected all wireless devices"
        )
    }
}
