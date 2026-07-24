import ADBKit
import Testing

/// The memo must be invisible to callers: same spans as direct detection,
/// stable across repeated calls, and correct straight through an eviction.
@MainActor
@Suite struct ConsoleLinkSpanMemoTests {
    @Test func matchesDirectDetection() {
        let samples = [
            "loading http://localhost:8081/index.bundle done",
            "no links in this line",
            "two: https://react.dev and http://example.com/a?b=1",
            "emoji 🚀 before https://example.com shifts offsets",
        ]
        for text in samples {
            #expect(ConsoleLinkSpanMemo.spans(in: text) == ConsoleLinkDetector.linkSpans(in: text))
        }
    }

    @Test func repeatedCallsReturnTheSameSpans() {
        let text = "bundle at http://localhost:8081/index.bundle?platform=android"
        let first = ConsoleLinkSpanMemo.spans(in: text)
        #expect(ConsoleLinkSpanMemo.spans(in: text) == first)
        #expect(!first.isEmpty)
    }

    @Test func survivesEviction() {
        let text = "kept: https://example.com/kept"
        let before = ConsoleLinkSpanMemo.spans(in: text)
        // Overflow the cache so it clears wholesale, then re-ask.
        for index in 0 ..< (ConsoleLinkSpanMemo.capacity + 1) {
            _ = ConsoleLinkSpanMemo.spans(in: "filler line \(index) http://example.com/\(index)")
        }
        #expect(ConsoleLinkSpanMemo.spans(in: text) == before)
    }

    /// Transparency also holds for a no-op cache — these two pin the memo's
    /// actual point: entries are stored (not recomputed) and the store stays
    /// bounded by the wholesale clear.
    @Test func storesEachTextOnceAndRepeatsDoNotGrowIt() {
        let text = "unique-\(#function) https://example.com/memo"
        let before = ConsoleLinkSpanMemo.cachedTextCount
        _ = ConsoleLinkSpanMemo.spans(in: text)
        #expect(ConsoleLinkSpanMemo.cachedTextCount == before + 1)
        _ = ConsoleLinkSpanMemo.spans(in: text)
        #expect(ConsoleLinkSpanMemo.cachedTextCount == before + 1)
    }

    @Test func clearsWholesaleAtCapacity() {
        // Top the cache up to exactly capacity (other tests may have left
        // entries behind — the count, not the iteration total, is what
        // arms the clear), then one more insert must clear wholesale and
        // leave only itself.
        var index = 0
        while ConsoleLinkSpanMemo.cachedTextCount < ConsoleLinkSpanMemo.capacity {
            _ = ConsoleLinkSpanMemo.spans(in: "fill-\(#function)-\(index)")
            index += 1
        }
        _ = ConsoleLinkSpanMemo.spans(in: "overflow-\(#function)")
        #expect(ConsoleLinkSpanMemo.cachedTextCount == 1)
    }
}
