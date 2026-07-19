import Foundation
import Testing
@testable import ADBKit

/// URL detection for JS Console rows: explicit-scheme http(s) only, with
/// span offsets measured in Characters so the view's `AttributedString`
/// mapping (`index(_:offsetByCharacters:)`) lands exactly on the URL even
/// when emoji or accented text precedes it.
@Suite struct ConsoleLinkDetectorTests {
    /// Slice `text` by a span's Character offsets — what the view layer does.
    private func slice(_ text: String, _ span: ConsoleLinkDetector.Span) -> String {
        let start = text.index(text.startIndex, offsetBy: span.start)
        let end = text.index(start, offsetBy: span.count)
        return String(text[start ..< end])
    }

    @Test func findsAnExplicitHTTPSURL() {
        let text = "see https://example.com/a?b=1 now"
        let spans = ConsoleLinkDetector.linkSpans(in: text)
        #expect(spans.count == 1)
        #expect(spans.first?.url.absoluteString == "https://example.com/a?b=1")
        #expect(spans.first.map { slice(text, $0) } == "https://example.com/a?b=1")
    }

    @Test func emojiBeforeTheURLDoesNotShiftTheSpan() {
        // The ZWJ family emoji is one Character but many UTF-16 units — a
        // UTF-16-offset regression lands the span several characters left.
        let text = "👨‍👩‍👧‍👦 fetch http://example.com/x"
        let spans = ConsoleLinkDetector.linkSpans(in: text)
        #expect(spans.count == 1)
        #expect(spans.first.map { slice(text, $0) } == "http://example.com/x")
    }

    @Test func accentedTextBeforeTheURLDoesNotShiftTheSpan() {
        let text = "café menu → https://example.com/café"
        let spans = ConsoleLinkDetector.linkSpans(in: text)
        #expect(spans.count == 1)
        #expect(spans.first.map { slice(text, $0) }?.hasPrefix("https://example.com") == true)
    }

    @Test func urlAtTheVeryStartAndEnd() {
        let atStart = ConsoleLinkDetector.linkSpans(in: "https://example.com then text")
        #expect(atStart.first?.start == 0)
        let text = "text then https://example.com"
        let atEnd = ConsoleLinkDetector.linkSpans(in: text)
        #expect(atEnd.first.map { $0.start + $0.count } == text.count)
    }

    @Test func findsEveryURLInOneLine() {
        let text = "a http://one.example.com b https://two.example.com c"
        let spans = ConsoleLinkDetector.linkSpans(in: text)
        #expect(spans.map(\.url.absoluteString) == ["http://one.example.com", "https://two.example.com"])
    }

    @Test func bareDomainsNeverBecomeLinks() {
        // NSDataDetector flags these with an inferred http:// — the source
        // text spells no scheme, so they must not linkify.
        #expect(ConsoleLinkDetector.linkSpans(in: "config.io react.dev app.sh").isEmpty)
        #expect(ConsoleLinkDetector.linkSpans(in: "www.example.com").isEmpty)
    }

    @Test func nonHTTPSchemesAreRejected() {
        #expect(ConsoleLinkDetector.linkSpans(in: "write to mailto:a@b.com please").isEmpty)
        #expect(ConsoleLinkDetector.linkSpans(in: "open ftp://example.com/file").isEmpty)
    }

    @Test func plainTextYieldsNothing() {
        #expect(ConsoleLinkDetector.linkSpans(in: "").isEmpty)
        #expect(ConsoleLinkDetector.linkSpans(in: "no urls here at all").isEmpty)
    }
}
