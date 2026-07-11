import Foundation

/// Per-feature usage tally, persisted to `usage.json`. Drives Home's
/// "Frequently used" strip, so it becomes personal over time.
///
/// `CommandLog` is session-only (an in-memory actor), so cross-launch ranking
/// needs this durable store rather than the command log.
public struct UsageStat: Codable, Sendable, Equatable {
    public var count: Int
    public var lastUsed: Date

    public init(count: Int = 0, lastUsed: Date = .distantPast) {
        self.count = count
        self.lastUsed = lastUsed
    }
}

public struct UsageStats: Codable, Sendable, Equatable {
    /// Tally keyed by feature id.
    public var byFeature: [String: UsageStat]

    public init(byFeature: [String: UsageStat] = [:]) {
        self.byFeature = byFeature
    }

    public func count(for featureID: String) -> Int { byFeature[featureID]?.count ?? 0 }

    /// Record one user-initiated use of a feature at `date`.
    public mutating func record(_ featureID: String, at date: Date) {
        var stat = byFeature[featureID] ?? UsageStat()
        stat.count += 1
        stat.lastUsed = date
        byFeature[featureID] = stat
    }

    /// The ids used at least `minUses` times, ordered strictly by use count
    /// (descending) with the input order as the stable tiebreak — deliberately
    /// *not* recency, so a just-opened feature doesn't jump to the front (that
    /// made Home's "Frequently used" strip degenerate into "last used"). Callers
    /// pass an already-meaningfully-ordered list (e.g. sidebar order) so ties
    /// resolve to that. Pure so it's testable without an `AppState`.
    public func frequent(among ids: [String], minUses: Int) -> [String] {
        ids.enumerated()
            .filter { count(for: $0.element) >= minUses }
            .sorted { lhs, rhs in
                let countL = count(for: lhs.element)
                let countR = count(for: rhs.element)
                return countL != countR ? countL > countR : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
