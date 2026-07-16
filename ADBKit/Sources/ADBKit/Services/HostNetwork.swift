import Darwin
import Foundation

/// The Mac's own LAN address — what a device on the same network dials to
/// reach this machine (e.g. Metro's "Debug server host" is `<mac-ip>:8081`).
/// Interface enumeration is the only I/O; choosing among the candidates is
/// pure and tested (`pickPrimary`).
public enum HostNetwork {
    public struct Candidate: Sendable, Equatable {
        public let interface: String
        public let address: String

        public init(interface: String, address: String) {
            self.interface = interface
            self.address = address
        }
    }

    /// The Mac's primary IPv4 address, or nil when it has no LAN address.
    public static func primaryIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        var candidates: [Candidate] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = entry.pointee.ifa_flags
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET),
                  flags & UInt32(IFF_UP) != 0,
                  flags & UInt32(IFF_LOOPBACK) == 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address, socklen_t(address.pointee.sa_len),
                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }
            candidates.append(Candidate(
                interface: String(cString: entry.pointee.ifa_name),
                address: String(cString: host)))
        }
        return pickPrimary(from: candidates)
    }

    /// Picks the address a teammate would call "the Mac's IP": real network
    /// interfaces (`enN`, lowest number first — en0 is Wi-Fi or built-in
    /// Ethernet) beat virtual ones (utun/bridge/awdl). Self-assigned
    /// link-local addresses (169.254.x.x) are unreachable from a device and
    /// never returned.
    public static func pickPrimary(from candidates: [Candidate]) -> String? {
        var best: (rank: Int, address: String)?
        for candidate in candidates where !candidate.address.hasPrefix("169.254.") {
            let rank = enInterfaceNumber(candidate.interface) ?? Int.max
            if let current = best, current.rank <= rank { continue }
            best = (rank, candidate.address)
        }
        return best?.address
    }

    /// "en0" → 0, "en12" → 12; nil for anything that isn't an `enN` interface.
    private static func enInterfaceNumber(_ name: String) -> Int? {
        guard name.hasPrefix("en") else { return nil }
        return Int(name.dropFirst(2))
    }
}
