import Foundation

/// The checks that decide whether a request is allowed to reach a route.
///
/// Pure and static so they are tested directly rather than through a socket —
/// the project's parser convention, and these are the security boundary.
///
/// Binding to loopback is **not** sufficient on its own. Any local process can
/// reach `127.0.0.1`, and a browser tab can be steered at it via DNS
/// rebinding, which is why `Host` and `Origin` are checked as well as the
/// token. `McpHTTPListener` already makes the same three checks for MCP.
public enum DaemonGuards {
    /// Why a request was refused. Distinct cases so the listener can map each
    /// to its own status without re-deriving the reason.
    public enum Refusal: String, Sendable, Equatable {
        case missingToken = "missing_token"
        case badToken = "bad_token"
        case badHost = "bad_host"
        case badOrigin = "bad_origin"
    }

    /// A `Bearer <token>` header against the expected token.
    ///
    /// Compared in constant time: a byte-at-a-time early exit leaks the shared
    /// secret's prefix to anything that can time requests, and on loopback the
    /// timing signal is not buried in network noise.
    public static func checkAuthorization(
        header: String?, expected: String
    ) -> Refusal? {
        guard let header, header.hasPrefix("Bearer ") else { return .missingToken }
        let presented = String(header.dropFirst("Bearer ".count))
        return constantTimeEquals(presented, expected) ? nil : .badToken
    }

    /// True only when the two strings match, taking the same time regardless of
    /// where they first differ. Length is not secret — the token's length is
    /// fixed and public — so an early length exit is fine.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8)
        let rhs = Array(b.utf8)
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }

    /// `Host` must name loopback on the port we actually bound.
    ///
    /// A DNS-rebinding attack arrives with an attacker-controlled `Host`, so
    /// pinning it to `127.0.0.1`/`localhost` plus the live port is what stops a
    /// browser from reaching the daemon even though the socket is loopback.
    public static func checkHost(header: String?, port: Int) -> Refusal? {
        guard let header else { return .badHost }
        let allowed = ["127.0.0.1:\(port)", "localhost:\(port)", "[::1]:\(port)"]
        return allowed.contains(header.lowercased()) ? nil : .badHost
    }

    /// `Origin`, when present, must be loopback.
    ///
    /// Absent is allowed: a native UI sends no `Origin`, and requiring one
    /// would reject the only client this is built for. Present-and-foreign is
    /// a browser trying its luck, and is refused. The port is deliberately not
    /// pinned here — any loopback origin is equally (un)trusted, and the token
    /// is what actually authorises.
    public static func checkOrigin(header: String?) -> Refusal? {
        guard let header, !header.isEmpty else { return nil }
        let normalized = header.lowercased()
        let allowedHosts = ["127.0.0.1", "localhost", "[::1]"]
        for scheme in ["http://", "https://"] where normalized.hasPrefix(scheme) {
            let authority = String(normalized.dropFirst(scheme.count))
            let host = authority.split(separator: "/").first.map(String.init) ?? authority
            // Exact match only, never a prefix: `localhost.evil.example` starts
            // with an allowed name but is an attacker's domain. The bracketed
            // IPv6 form has to be pulled off before the port split, because its
            // address is full of colons.
            let bare: String
            if host.hasPrefix("["), let close = host.firstIndex(of: "]") {
                bare = String(host[host.startIndex...close])
            } else {
                bare = host.split(separator: ":").first.map(String.init) ?? host
            }
            if allowedHosts.contains(bare) { return nil }
        }
        return .badOrigin
    }

    /// All three, in the order that gives the least away: transport-shape
    /// checks before the secret, so a foreign origin never learns whether its
    /// guessed token was close.
    public static func check(
        authorization: String?, host: String?, origin: String?, port: Int, expectedToken: String
    ) -> Refusal? {
        if let refusal = checkHost(header: host, port: port) { return refusal }
        if let refusal = checkOrigin(header: origin) { return refusal }
        return checkAuthorization(header: authorization, expected: expectedToken)
    }
}
