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

    /// One row of `adb mdns services` output: instance name, service type,
    /// and the advertised endpoint.
    public struct MdnsService: Equatable, Sendable {
        public let name: String
        public let type: String
        public let endpoint: WirelessEndpoint
    }

    /// The wireless-debugging connect endpoint a freshly paired device
    /// advertises over mDNS (`_adb-tls-connect._tcp`), or nil when nothing
    /// matching `host` shows up. The advertisement can lag the pairing
    /// handshake by a beat, so this retries; every failure mode (mdns
    /// disabled in this adb, no matching host) is a nil — the caller falls
    /// back to asking for the port.
    public func discoverConnectEndpoint(
        host: String, attempts: Int = 3, delay: Duration = .seconds(1)
    ) async -> WirelessEndpoint? {
        for attempt in 0..<max(1, attempts) {
            guard !Task.isCancelled else { return nil }
            if attempt > 0 { try? await Task.sleep(for: delay) }
            guard let result = try? await client.run(["mdns", "services"], timeout: .seconds(5))
            else { return nil }
            let match = Self.parseMdnsServices(result.stdout).first { service in
                service.type.hasPrefix("_adb-tls-connect") && service.endpoint.host == host
            }
            if let match { return match.endpoint }
        }
        return nil
    }

    /// Pure parse of `adb mdns services` output:
    ///
    ///     List of discovered mdns services
    ///     adb-R58M4-xyz	_adb-tls-connect._tcp	192.168.1.42:40913
    ///
    /// Columns are whitespace-separated; the service type always leads with
    /// an underscore (which also skips the header line), and the endpoint
    /// must parse with a port.
    public static func parseMdnsServices(_ text: String) -> [MdnsService] {
        var services: [MdnsService] = []
        for line in text.components(separatedBy: .newlines) {
            let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard fields.count >= 3, fields[1].hasPrefix("_") else { continue }
            guard let endpoint = parseEndpoint(fields[2]), endpoint.port != nil else { continue }
            services.append(MdnsService(name: fields[0], type: fields[1], endpoint: endpoint))
        }
        return services
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
    /// inner spaces, a non-numeric or out-of-range port, or an implausible
    /// host (a truncated IPv4 like "1.1.1", a non-parsing IPv6, a malformed
    /// hostname).
    public static func parseEndpoint(_ text: String) -> WirelessEndpoint? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }

        func validated(host: String, port: String?) -> WirelessEndpoint? {
            guard isValidHost(host) else { return nil }
            if let port {
                // `Int(_:)` rejects the non-ASCII digits `isNumber` lets through.
                guard (1...5).contains(port.count), port.allSatisfy(\.isNumber),
                      let value = Int(port), (1...65535).contains(value)
                else { return nil }
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

    /// Validates an IPv6 literal in pure Swift.
    ///
    /// This replaced `inet_pton`, whose `in6_addr` / `AF_INET6` symbols don't
    /// exist on Windows — and a parser has no business needing libc anyway, per
    /// the pure-static-parser rule. Accepts the full grammar the app can
    /// plausibly be handed: 8 hex groups, one `::` run compressing one or more
    /// zero groups, and a trailing dotted-quad occupying the last two groups
    /// (`::ffff:192.168.1.1`).
    private static func isIPv6(_ text: String) -> Bool {
        // A zone index ("fe80::1%en0") rides after the address proper.
        let address = String(text.prefix { $0 != "%" })
        guard !address.isEmpty, address.count <= 45 else { return false }

        // At most one compression run.
        let halves = address.components(separatedBy: "::")
        guard halves.count <= 2 else { return false }
        let compressed = halves.count == 2

        // An empty half contributes no groups; a non-empty one splits on ":",
        // so a stray leading or trailing colon yields an empty group and fails
        // the width check below.
        func groups(_ part: String) -> [String] {
            part.isEmpty ? [] : part.components(separatedBy: ":")
        }
        var head = groups(halves[0])
        var tail = compressed ? groups(halves[1]) : []

        // A dotted-quad tail stands in for the final two groups.
        var ipv4GroupCount = 0
        if let last = (compressed ? tail : head).last, last.contains(".") {
            guard isIPv4(last) else { return false }
            ipv4GroupCount = 2
            if compressed { tail.removeLast() } else { head.removeLast() }
        }

        let hextets = head + tail
        guard hextets.allSatisfy({ (1...4).contains($0.count) && $0.allSatisfy(\.isHexDigit) })
        else { return false }

        let total = hextets.count + ipv4GroupCount
        // A compression run must stand for at least one group, so it caps at 7.
        return compressed ? total <= 7 : total == 8
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
