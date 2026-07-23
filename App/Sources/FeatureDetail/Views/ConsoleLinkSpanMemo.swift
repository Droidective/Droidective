import ADBKit

/// Memoized `ConsoleLinkDetector` for console-row rendering. Detection runs
/// `NSDataDetector` over up to 10k characters, and rows re-render on every
/// feed flush — a Metro stream is URL-dense (bundle URLs, network logs), so
/// per-render detection was a sustained main-thread cost (Sentry
/// DROIDECTIVE-MAC-49). The same text always yields the same spans, so cache
/// by text; entries are immutable, making the steady state all hits.
///
/// Bounded by wholesale clearing at `capacity` instead of LRU bookkeeping —
/// the worst case after a clear is re-detecting one screenful of rows.
@MainActor
enum ConsoleLinkSpanMemo {
    static let capacity = 2048
    private static var cache: [String: [ConsoleLinkDetector.Span]] = [:]

    static func spans(in text: String) -> [ConsoleLinkDetector.Span] {
        if let hit = cache[text] { return hit }
        let spans = ConsoleLinkDetector.linkSpans(in: text)
        if cache.count >= capacity { cache.removeAll(keepingCapacity: true) }
        cache[text] = spans
        return spans
    }
}
