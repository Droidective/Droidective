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
    /// Most cumulative wire bytes the timeline retains. The decoded Swift
    /// graph is proportional to the wire size (typically a small multiple).
    public static let maxTotalBytes = 128 * 1024 * 1024

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
