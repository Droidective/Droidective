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

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// Append a batch, extending `filtered` with just the batch's matches.
    /// `isIncluded` must be the same filter the current projection was built
    /// with; pass `nil` when no filter is active (the fast path).
    public mutating func append(_ batch: [Entry], isIncluded: ((Entry) -> Bool)?) {
        entries.append(contentsOf: batch)
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
    }

    private mutating func evictOverflow() {
        let overflow = entries.count - capacity
        guard overflow > 0 else { return }
        let lastEvictedID = entries[overflow - 1].id
        entries.removeFirst(overflow)
        let evictedFromFiltered = filtered.prefix { $0.id <= lastEvictedID }.count
        if evictedFromFiltered > 0 { filtered.removeFirst(evictedFromFiltered) }
    }
}
