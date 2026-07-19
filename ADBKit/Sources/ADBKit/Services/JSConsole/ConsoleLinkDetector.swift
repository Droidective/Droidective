import Foundation

/// Finds explicit-scheme http(s) URLs in console text, as *Character* offsets.
///
/// `NSDataDetector` speaks UTF-16 while SwiftUI's `AttributedString` indexes
/// by `Character`, and that conversion is the regression-prone part — an
/// emoji before a URL shifts the two units by different amounts. So the
/// detection and offset mapping live here, pure and tested, and the view
/// layer only applies attributes at the returned offsets.
///
/// Only matches whose *source text* spells a scheme count: the detector also
/// flags bare domains (`config.io`, `react.dev`) with an inferred `http://`,
/// and code output like that must not become a link. The guard inspects the
/// matched substring, not the inferred URL — the URL always contains `://`.
public enum ConsoleLinkDetector {
    /// One linkified span; `start`/`count` are Character offsets into the
    /// scanned string.
    public struct Span: Equatable, Sendable {
        public let url: URL
        public let start: Int
        public let count: Int

        public init(url: URL, start: Int, count: Int) {
            self.url = url
            self.start = start
            self.count = count
        }
    }

    /// Built once — construction compiles the detector and would dominate
    /// per-row render cost. `NSDataDetector` is immutable and thread-safe
    /// (an `NSRegularExpression` subclass, `Sendable` in the SDK).
    private static let detector =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    public static func linkSpans(in text: String) -> [Span] {
        guard text.contains("://"), let detector else { return [] }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var spans: [Span] = []
        for match in matches {
            guard let url = match.url,
                  url.scheme == "http" || url.scheme == "https",
                  let range = Range(match.range, in: text),
                  text[range].contains("://") else { continue }
            spans.append(Span(
                url: url,
                start: text.distance(from: text.startIndex, to: range.lowerBound),
                count: text.distance(from: range.lowerBound, to: range.upperBound)
            ))
        }
        return spans
    }
}
