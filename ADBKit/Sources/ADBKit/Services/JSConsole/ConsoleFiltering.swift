import Foundation

/// A normalized, case-insensitive console filter/find query. Build once per
/// filter change and match against text that was lowercased once at ingest —
/// never re-lowercase entries per keystroke or per flush.
public struct ConsoleQuery: Equatable, Sendable {
    public let normalized: String

    public init(_ raw: String) {
        normalized = raw.trimmingCharacters(in: .whitespaces).lowercased()
    }

    public var isEmpty: Bool { normalized.isEmpty }

    /// Whether the query occurs in `cachedLowercasedText` (which the caller
    /// lowercased once when the entry was created). An empty query matches all.
    public func matches(_ cachedLowercasedText: String) -> Bool {
        normalized.isEmpty || cachedLowercasedText.contains(normalized)
    }
}

/// A capped, append-only feed plus its filtered projection, maintained
/// incrementally: appending a batch evaluates the predicate on that batch only,
/// and a `nil` predicate (no active filter) mirrors the feed with no per-entry
/// work at all. The projection is recomputed from scratch only when the filter
/// itself changes (`refilter`). This keeps a high-rate feed (e.g. a console
/// replay burst flushing every frame) O(batch) per flush instead of O(buffer).
///
/// Entries must be appended in strictly increasing `id` order — cap eviction
/// relies on it to drop evicted rows from the projection's front.
public struct FilteredLogBuffer<Entry: Identifiable> where Entry.ID: Comparable {
    public private(set) var entries: [Entry] = []
    public private(set) var filtered: [Entry] = []
    private let capacity: Int
    /// Optional retained-size ceiling: when the summed `cost` of the buffer
    /// exceeds it, oldest entries are evicted (the newest always survives).
    /// Guards against a count cap alone retaining gigabytes when every entry
    /// carries a multi-megabyte payload.
    private let byteBudget: Int
    private let cost: (Entry) -> Int
    /// Per-entry costs aligned with `entries`, so eviction never re-measures.
    private var costs: [Int] = []
    private var totalCost = 0

    public init(capacity: Int, byteBudget: Int = .max, cost: @escaping (Entry) -> Int = { _ in 0 }) {
        self.capacity = max(1, capacity)
        self.byteBudget = byteBudget
        self.cost = cost
    }

    /// Append a batch, extending `filtered` with just the batch's matches.
    /// `isIncluded` must be the same filter the current projection was built
    /// with; pass `nil` when no filter is active (the fast path).
    public mutating func append(_ batch: [Entry], isIncluded: ((Entry) -> Bool)?) {
        entries.append(contentsOf: batch)
        for entry in batch {
            let entryCost = cost(entry)
            costs.append(entryCost)
            totalCost += entryCost
        }
        if let isIncluded {
            filtered.append(contentsOf: batch.filter(isIncluded))
        } else {
            filtered = entries
        }
        evictOverflow()
    }

    /// Recompute the projection over the whole buffer — for when the filter
    /// itself changed, not for appends.
    public mutating func refilter(isIncluded: ((Entry) -> Bool)?) {
        if let isIncluded {
            filtered = entries.filter(isIncluded)
        } else {
            filtered = entries
        }
    }

    public mutating func removeAll() {
        entries.removeAll()
        filtered.removeAll()
        costs.removeAll()
        totalCost = 0
    }

    private mutating func evictOverflow() {
        var evict = max(0, entries.count - capacity)
        var freed = costs.prefix(evict).reduce(0, +)
        // Byte budget: keep growing the eviction window while over, always
        // leaving the newest entry (one oversized entry mustn't empty the feed).
        while totalCost - freed > byteBudget, evict < entries.count - 1 {
            freed += costs[evict]
            evict += 1
        }
        guard evict > 0 else { return }
        let lastEvictedID = entries[evict - 1].id
        entries.removeFirst(evict)
        costs.removeFirst(evict)
        totalCost -= freed
        let evictedFromFiltered = filtered.prefix { $0.id <= lastEvictedID }.count
        if evictedFromFiltered > 0 { filtered.removeFirst(evictedFromFiltered) }
    }
}
