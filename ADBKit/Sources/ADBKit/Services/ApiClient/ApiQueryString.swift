import Foundation

/// Moves a URL's `?a=1&b=2` into the Params table and back out again.
///
/// The two are not kept in lockstep — the builder merges the table on top of
/// whatever the URL already carries, so a silent two-way sync would be a good
/// way to lose a parameter. This is the explicit extraction the Params tab
/// offers instead, and it is pure so the round trip is testable.
public enum ApiQueryString: Sendable {

    /// The parameters in a URL's query string, in the order they appear.
    /// A bare `?flag` (no `=`) becomes a parameter with an empty value, which
    /// is how servers read it.
    public static func parameters(in url: String) -> [ApiKeyValue] {
        let query = HttpRequestBuilder.split(url).query
        guard !query.isEmpty else { return [] }
        var found: [ApiKeyValue] = []
        for pair in query.components(separatedBy: "&") where !pair.isEmpty {
            guard let separator = pair.firstIndex(of: "=") else {
                found.append(ApiKeyValue(key: decode(pair), value: ""))
                continue
            }
            let name = decode(String(pair[pair.startIndex..<separator]))
            let value = decode(String(pair[pair.index(after: separator)...]))
            guard !name.isEmpty else { continue }
            found.append(ApiKeyValue(key: name, value: value))
        }
        return found
    }

    /// The same URL with its query removed, fragment kept. Pairs with
    /// `parameters(in:)`: extract into the table, strip from the bar, and the
    /// request the builder produces is unchanged.
    public static func removingQuery(from url: String) -> String {
        let parts = HttpRequestBuilder.split(url)
        guard !parts.query.isEmpty else { return url }
        return parts.fragment.isEmpty ? parts.base : parts.base + "#" + parts.fragment
    }

    public static func hasQuery(_ url: String) -> Bool {
        !HttpRequestBuilder.split(url).query.isEmpty
    }

    private static func decode(_ text: String) -> String {
        let plus = text.replacingOccurrences(of: "+", with: " ")
        return plus.removingPercentEncoding ?? plus
    }
}
