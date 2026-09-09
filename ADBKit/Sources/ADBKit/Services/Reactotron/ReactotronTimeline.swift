import Foundation

/// Budget for the Reactotron timeline ring buffer.
///
/// RN clients stream frames of arbitrary size (api.response bodies, base64
/// display images, big state payloads), so a count cap alone still lets the
/// retained timeline reach gigabytes — and freeing that graph inline hangs the
/// main thread for seconds (a giant nested-dictionary release cascade). The
/// timeline is therefore bounded by count *and* cumulative frame bytes,
/// trimmed oldest-first in batches.
public enum ReactotronTimeline {
    /// Most items the timeline retains.
    public static let maxItems = 2000
    /// Most cumulative wire bytes the timeline retains.
    ///
    /// Was a flat 128 MB, on the reasoning that the decoded Swift graph is
    /// "a small multiple" of the wire size. It is — about eight times — and
    /// that made this a one-gigabyte *resident* cap, which is what put 8 GB
    /// machines into swap and turned a slow feed into an unresponsive Mac.
    /// `FeedMemoryBudget` sizes it against the machine instead; see there for
    /// the incidents and the arithmetic.
    public static var maxTotalBytes: Int { FeedMemoryBudget.wireBudget }

    /// How many *unflushed* rows to drop so the pending buffer can't outgrow
    /// what the ring is going to keep anyway.
    ///
    /// A feed nobody can see schedules no flush (`FeedFlushCadence.interval`
    /// answers nil), so rows pile up until the byte bound trips. Bytes are not
    /// what a flush costs: at a few hundred bytes a row that bound is tens of
    /// thousands of rows, and `dropCount` evicts all but `maxItems` of them the
    /// moment they land — after the whole batch has already been appended and
    /// walked. Trimming while they wait makes the flush cost what the buffer is
    /// allowed to keep, and drops nothing the append wouldn't have.
    ///
    /// Hysteresis matches `dropCount`: once over the cap, trim to 7/8 of it, so
    /// a full pending buffer doesn't shift its whole array on every append.
    ///
    /// - Parameters:
    ///   - count: rows waiting to be flushed.
    ///   - maxCount: the ring's count cap (defaults to `maxItems`).
    public static func pendingDropCount(count: Int, maxCount: Int = maxItems) -> Int {
        guard count > maxCount else { return 0 }
        return count - (maxCount - maxCount / 8)
    }

    /// How many items to drop from the front so the buffer fits its caps.
    ///
    /// Trims with hysteresis — once a cap is exceeded it trims down to 7/8 of
    /// that cap — so steady-state appends trim in batches instead of shifting
    /// the array on every append. The newest item is always kept, even when it
    /// alone exceeds the byte budget.
    ///
    /// - Parameters:
    ///   - sizes: Per-item byte sizes, oldest first. Only the dropped prefix
    ///     is walked, so a lazy view over the buffer is fine.
    ///   - count: Current item count.
    ///   - totalBytes: Current sum of `sizes`.
    ///   - maxCount: Count cap (defaults to `maxItems`).
    ///   - maxBytes: Byte cap (defaults to `maxTotalBytes`).
    public static func dropCount(
        sizes: some Sequence<Int>,
        count: Int,
        totalBytes: Int,
        maxCount: Int = maxItems,
        maxBytes: Int = maxTotalBytes
    ) -> Int {
        guard count > maxCount || totalBytes > maxBytes else { return 0 }
        let targetCount = maxCount - maxCount / 8
        let targetBytes = maxBytes - maxBytes / 8
        var drop = 0
        var kept = count
        var bytes = totalBytes
        var iterator = sizes.makeIterator()
        while kept > 1, kept > targetCount || bytes > targetBytes {
            guard let size = iterator.next() else { break }
            drop += 1
            kept -= 1
            bytes -= size
        }
        return drop
    }
}
