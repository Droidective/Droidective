import ADBKit
import Foundation

/// What every streaming feed is holding right now, in one place.
///
/// Each feed already publishes its own shape as a Sentry context
/// (`ReactotronSession.publishDiagnostics` and the JS Console's equivalent),
/// and that is genuinely useful on a crash — but it is *per feed*, so nothing
/// could answer "how much is the app holding across all of them", which is the
/// question that mattered when a session sat at 1.5 GB with two feeds open.
/// Reconstructing it took joining three event types by hour, after knowing to
/// look. One snapshot makes it one field.
///
/// Deliberately **not** `@Observable`, for the reason `MainThreadLoad` is not:
/// feeds report on every flush, and anything observing this would re-render the
/// UI at flush rate — the exact cost these numbers exist to measure.
@MainActor
final class FeedHealth {
    static let shared = FeedHealth()

    /// One feed's current shape. Rows and bytes are what it retains, not what
    /// it has ever seen.
    struct Snapshot: Equatable {
        var rows: Int
        /// Wire bytes retained. The resident cost is a multiple of this — see
        /// `FeedMemoryBudget`, which is the whole reason that distinction is
        /// worth reporting rather than assuming.
        var wireBytes: Int
        /// Whether any mounted view could see this feed when it last reported.
        var watched: Bool
    }

    private var feeds: [String: Snapshot] = [:]

    private init() {}

    /// Called from a feed's own diagnostics publish, so it costs one
    /// dictionary write on a path that was already crossing two telemetry
    /// SDKs.
    func report(_ feed: String, _ snapshot: Snapshot) {
        feeds[feed] = snapshot
    }

    /// A feed that has gone away entirely (its tab closed, its session torn
    /// down) must stop counting toward the total, or a closed feed's last
    /// snapshot is reported as live memory for the rest of the session.
    func forget(_ feed: String) {
        feeds.removeValue(forKey: feed)
    }

    var totalWireBytes: Int { feeds.values.reduce(0) { $0 + $1.wireBytes } }
    var totalRows: Int { feeds.values.reduce(0) { $0 + $1.rows } }
    /// How many feeds believe someone can see them. Zero alongside a large
    /// `totalWireBytes` is the state that produced the incident: work being
    /// done, nobody reading it.
    var watchedCount: Int { feeds.values.count { $0.watched } }
    var feedCount: Int { feeds.count }

    /// Flattened for telemetry — numbers and feed ids only, never contents.
    /// Per-feed rows and megabytes are included because "which feed" is the
    /// first question after "how much".
    var properties: [String: Int] {
        var result: [String: Int] = [
            "feeds": feedCount,
            "feeds_watched": watchedCount,
            "feed_rows": totalRows,
            "feed_mb": totalWireBytes / 1_048_576,
        ]
        for (feed, snapshot) in feeds {
            // `rt`/`js` rather than the feature id, so the key set is fixed
            // and a renamed feature cannot silently start a new column.
            let key = Self.shortName(feed)
            result["\(key)_rows"] = snapshot.rows
            result["\(key)_mb"] = snapshot.wireBytes / 1_048_576
        }
        return result
    }

    private static func shortName(_ feed: String) -> String {
        switch feed {
        case "reactotron": return "rt"
        case "js-console": return "js"
        default: return feed.replacingOccurrences(of: "-", with: "_")
        }
    }
}
