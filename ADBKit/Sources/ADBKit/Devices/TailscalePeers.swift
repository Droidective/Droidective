import Foundation

/// One Android device on the user's tailnet that adb could reach.
public struct TailscalePeer: Sendable, Equatable, Identifiable, Codable {
    /// Tailscale's stable node id.
    public let id: String
    /// The machine name the admin console shows: the first label of its
    /// MagicDNS name, or its host name when it has none.
    public let name: String
    /// The peer's tailnet IPv4. adb connects by this rather than by the
    /// MagicDNS name, because `DeviceListParser` recognises an `ip:port`
    /// serial as wireless and a hostname serial as nothing at all.
    public let ipv4: String

    public init(id: String, name: String, ipv4: String) {
        self.id = id
        self.name = name
        self.ipv4 = ipv4
    }

    /// What `adb connect` takes, and so the serial the device then shows up
    /// under.
    public var adbEndpoint: String { "\(ipv4):\(TailscalePeers.adbPort)" }
}

/// The part of `tailscale status --json` the device bar needs.
public struct TailscaleNetwork: Sendable, Equatable {
    /// tailscaled's own state: "Running", "Stopped", "NeedsLogin", "Starting",
    /// "NeedsMachineAuth", …
    public let backendState: String
    /// Online Android peers with a tailnet IPv4, sorted by name.
    public let androidPeers: [TailscalePeer]

    public init(backendState: String, androidPeers: [TailscalePeer]) {
        self.backendState = backendState
        self.androidPeers = androidPeers
    }
}

/// Parses `tailscale status --json` and answers the tailnet questions the rest
/// of the app asks: which peers are Android phones adb could reach, and
/// whether a connected device is one of them.
public enum TailscalePeers {
    /// The port "Prepare for Tailscale" opens and every tailnet connect uses.
    public static let adbPort = "5555"

    private struct Payload: Decodable {
        let backendState: String?
        let peer: [String: Entry]?

        enum CodingKeys: String, CodingKey {
            case backendState = "BackendState"
            case peer = "Peer"
        }
    }

    private struct Entry: Decodable {
        let id: String?
        let publicKey: String?
        let hostName: String?
        let dnsName: String?
        let os: String?
        let online: Bool?
        let tailscaleIPs: [String]?

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case publicKey = "PublicKey"
            case hostName = "HostName"
            case dnsName = "DNSName"
            case os = "OS"
            case online = "Online"
            case tailscaleIPs = "TailscaleIPs"
        }
    }

    /// The network, or nil when the text is not a status document at all.
    ///
    /// A peer is kept only when it is Android, online, and has a tailnet IPv4
    /// to connect to: an offline phone is a menu row that can only fail, and
    /// every other OS is not something adb can debug. `Peer` is `null` while
    /// tailscaled is stopped, which is no peers rather than a parse failure.
    public static func parse(_ json: String) -> TailscaleNetwork? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)),
              let backendState = payload.backendState
        else { return nil }
        var peers: [TailscalePeer] = []
        for (key, entry) in payload.peer ?? [:] {
            guard entry.os?.lowercased() == "android", entry.online == true,
                  let ipv4 = entry.tailscaleIPs?.first(where: isTailnetAddress)
            else { continue }
            peers.append(TailscalePeer(
                id: entry.id ?? entry.publicKey ?? key,
                name: displayName(dnsName: entry.dnsName, hostName: entry.hostName, fallback: ipv4),
                ipv4: ipv4))
        }
        peers.sort { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.ipv4 < rhs.ipv4 : order == .orderedAscending
        }
        return TailscaleNetwork(backendState: backendState, androidPeers: peers)
    }

    /// "pixel-7.tail1234.ts.net." → "pixel-7". The DNS name carries a rename
    /// made in the admin console, which the host name does not.
    static func displayName(dnsName: String?, hostName: String?, fallback: String) -> String {
        if let label = dnsName?.split(separator: ".").first, !label.isEmpty {
            return String(label)
        }
        if let hostName, !hostName.trimmingCharacters(in: .whitespaces).isEmpty {
            return hostName
        }
        return fallback
    }

    /// The peers worth offering: those not already in adb's device list, in
    /// any state. A phone that dropped off shows as offline under its tailnet
    /// serial, and that row is where to deal with it.
    public static func connectable(_ peers: [TailscalePeer], devices: [Device]) -> [TailscalePeer] {
        let connectedHosts = Set(devices.compactMap { host(ofSerial: $0.serial) })
        return peers.filter { !connectedHosts.contains($0.ipv4) }
    }

    /// Whether `address` is in Tailscale's IPv4 range, 100.64.0.0/10. That is
    /// the carrier-grade NAT block, which an adb serial is otherwise never in:
    /// a phone behind a carrier's NAT is not reachable to connect to.
    public static func isTailnetAddress(_ address: String) -> Bool {
        let octets = address.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        var values: [Int] = []
        for octet in octets {
            guard (1...3).contains(octet.count), octet.allSatisfy(\.isASCII),
                  let value = Int(octet), (0...255).contains(value)
            else { return false }
            values.append(value)
        }
        return values[0] == 100 && (64...127).contains(values[1])
    }

    /// Whether a device serial is a tailnet `ip:port` — a phone connected over
    /// Tailscale rather than over USB or the local network.
    public static func isTailnet(serial: String) -> Bool {
        host(ofSerial: serial).map(isTailnetAddress) ?? false
    }

    /// The IPv4 host of an `ip:port` serial, or nil for any other serial.
    private static func host(ofSerial serial: String) -> String? {
        let parts = serial.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty, parts[1].allSatisfy(\.isASCII),
              parts[1].allSatisfy(\.isNumber)
        else { return nil }
        return String(parts[0])
    }
}
