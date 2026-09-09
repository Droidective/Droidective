import ADBKit
import Foundation

/// What the app is holding, in one place — and how much of its own footprint
/// it cannot explain.
///
/// This began as a feed-only reporter, because the two streaming feeds were
/// the suspects in every high-memory incident. They were capped
/// (`FeedMemoryBudget`), the caps held — the field reports 21–33 MB of wire
/// retained — and the footprint still peaked at 1636 MB with four tabs open. A
/// reporter that can only describe feeds cannot tell you the feeds are not the
/// problem, which is exactly what the next report needed to say.
///
/// So the accounting is `MemoryLedger` (ADBKit, pure, tested) and this is the
/// main-actor holder plus the two things that belong to the App layer:
///
/// - **The wire/resident conversion.** Feeds report wire bytes, the size of
///   the frames as they came off the socket, because that is what they cap and
///   what their diagnostics contexts have always carried. Only the resident
///   cost (`FeedMemoryBudget.decodedGraphMultiplier`) is comparable to a
///   process footprint. Both are kept: the wire keys unchanged for continuity,
///   the ledger given the resident estimate.
/// - **Summing the instances.** A retainer is not a singleton. Two windows
///   each hold a JS Console with its own buffer, and a screenshot editor
///   exists per tab; the flat table this replaces was keyed by feed name, so
///   the second instance silently overwrote the first and the total under-read
///   by however many the user had open. Entries are keyed by the reporting
///   object and summed per owner.
///
/// References to reporters are weak and dead ones are pruned on read, the way
/// `MirrorSessions` does it — a model that goes away without calling `forget`
/// stops counting rather than pinning its last reading as live memory forever.
///
/// Deliberately **not** `@Observable`, for the reason `MainThreadLoad` is not:
/// feeds report on every flush, and anything observing this would re-render
/// the UI at flush rate — the exact cost these numbers exist to measure.
@MainActor
final class AppMemory {
    static let shared = AppMemory()

    /// One reporter's current holding.
    ///
    /// `wireBytes` is nil for retainers that hold object or image memory with
    /// no wire equivalent — a decoded capture is not frames off a socket, and
    /// counting it in `feed_mb` would quietly change what that key has always
    /// meant.
    /// What a retainer holds right now.
    struct Measurement {
        var residentBytes: Int
        var items: Int = 0
        var watched: Bool = false
    }

    private struct Holding {
        weak var reporter: AnyObject?
        var owner: MemoryLedger.Owner
        var residentBytes: Int
        var wireBytes: Int?
        var items: Int
        var watched: Bool
        /// The pull half. A ring of log lines cannot report its size for free
        /// the way the two feeds can — they track bytes as frames arrive,
        /// while a logcat buffer would have to walk five thousand strings, and
        /// doing that on the flush path puts a cost on the very thing these
        /// numbers exist to reduce. A measured retainer is walked only when a
        /// report is built: every five minutes, or on a hang or an alert.
        var measure: ((AnyObject) -> Measurement)?
    }

    private var holdings: [ObjectIdentifier: Holding] = [:]

    private init() {}

    // MARK: - Reporting

    /// A streaming feed's current buffer. `wireBytes` is what it caps against;
    /// the ledger is given what that costs decoded.
    func reportFeed(
        _ owner: MemoryLedger.Owner, from reporter: AnyObject,
        rows: Int, wireBytes: Int, watched: Bool
    ) {
        holdings[ObjectIdentifier(reporter)] = Holding(
            reporter: reporter,
            owner: owner,
            residentBytes: wireBytes * FeedMemoryBudget.decodedGraphMultiplier,
            wireBytes: wireBytes,
            items: rows,
            watched: watched)
    }

    /// A retainer holding object or image memory directly — a decoded capture,
    /// a parsed tree. `residentBytes` is what it actually costs.
    func report(
        _ owner: MemoryLedger.Owner, from reporter: AnyObject,
        residentBytes: Int, items: Int = 0, watched: Bool = false
    ) {
        holdings[ObjectIdentifier(reporter)] = Holding(
            reporter: reporter,
            owner: owner,
            residentBytes: residentBytes,
            wireBytes: nil,
            items: items,
            watched: watched)
    }

    /// Register a retainer that is walked when a report is built, rather than
    /// pushing a figure it would have to compute on its own hot path.
    ///
    /// The block takes the reporter rather than capturing it, so registering
    /// never keeps a closed tab's buffer alive: the reference here stays weak
    /// and a dead one is pruned on the next read.
    func measure<Reporter: AnyObject>(
        _ owner: MemoryLedger.Owner, from reporter: Reporter,
        _ measure: @escaping (Reporter) -> Measurement
    ) {
        holdings[ObjectIdentifier(reporter)] = Holding(
            reporter: reporter,
            owner: owner,
            residentBytes: 0,
            wireBytes: nil,
            items: 0,
            watched: false,
            measure: { object in
                guard let typed = object as? Reporter else { return Measurement(residentBytes: 0) }
                return measure(typed)
            })
    }

    /// A reporter that has gone away — its tab closed, its session torn down.
    /// The weak reference means forgetting to call this is not fatal, but
    /// calling it is still what makes the figure drop at the moment the memory
    /// is actually released rather than whenever ARC gets there.
    func forget(from reporter: AnyObject) {
        holdings.removeValue(forKey: ObjectIdentifier(reporter))
    }

    // MARK: - Reading

    /// How many feeds believe someone can see them. Zero alongside a large
    /// retained buffer is the state that produced every incident so far: work
    /// being done, nobody reading it.
    var watchedFeedCount: Int {
        live().count { $0.wireBytes != nil && $0.watched }
    }

    /// Flattened for telemetry — numbers and fixed owner keys only, never
    /// contents.
    ///
    /// Two namespaces on purpose. The `feed_*` / `rt_*` / `js_*` keys are wire
    /// megabytes and mean exactly what they always did, so the historical
    /// series still compares. The `mem_*` keys are the ledger: resident
    /// estimates, every retainer, and the subtraction against the real
    /// footprint that says whether any of this explains it.
    func properties(footprintBytes: UInt64) -> [String: Int] {
        let holdings = live()
        let feeds = holdings.filter { $0.wireBytes != nil }

        var result: [String: Int] = [
            "feeds": feeds.count,
            "feeds_watched": feeds.count { $0.watched },
            "feed_rows": feeds.reduce(0) { $0 + $1.items },
            "feed_mb": feeds.reduce(0) { $0 + ($1.wireBytes ?? 0) } / 1_048_576,
        ]
        // Wire keys, summed per owner so two windows' consoles add up rather
        // than the later one replacing the earlier.
        for owner in Set(feeds.map(\.owner)) {
            let mine = feeds.filter { $0.owner == owner }
            result["\(owner.rawValue)_rows"] = mine.reduce(0) { $0 + $1.items }
            result["\(owner.rawValue)_mb"] = mine.reduce(0) { $0 + ($1.wireBytes ?? 0) } / 1_048_576
        }

        var ledger = MemoryLedger()
        for owner in Set(holdings.map(\.owner)) {
            let mine = holdings.filter { $0.owner == owner }
            ledger.report(owner, MemoryLedger.Entry(
                residentBytes: mine.reduce(0) { $0 + $1.residentBytes },
                items: mine.reduce(0) { $0 + $1.items },
                watched: mine.contains { $0.watched }))
        }
        for (key, value) in ledger.properties(footprintBytes: footprintBytes) {
            result[key] = value
        }
        return result
    }

    /// Holdings whose reporter is still alive, pruning the rest as it goes so
    /// nothing has to sweep the table separately.
    private func live() -> [Holding] {
        holdings = holdings.filter { $0.value.reporter != nil }
        return holdings.values.map { holding in
            guard let measure = holding.measure, let reporter = holding.reporter else {
                return holding
            }
            var resolved = holding
            let measurement = measure(reporter)
            resolved.residentBytes = measurement.residentBytes
            resolved.items = measurement.items
            resolved.watched = measurement.watched
            return resolved
        }
    }
}
