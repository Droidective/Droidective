import Foundation

/// Expands `{placeholder}` tokens in a Send Text snippet at insert time —
/// e.g. `{clipboard}` becomes the Mac's current pasteboard string and `{ip}`
/// the Mac's LAN address. Pure: the caller supplies the live values, unknown
/// tokens stay exactly as typed.
public enum SnippetPlaceholders {
    /// The placeholders the Send Text UI offers, for hints and docs.
    public static let known = ["clipboard", "ip"]

    /// Single pass over the snippet text: substituted values are never
    /// re-scanned, so a clipboard that happens to contain "{ip}" is inserted
    /// verbatim instead of expanding (sequential replaces did, and in
    /// dictionary order — nondeterministically).
    public static func expand(_ text: String, values: [String: String]) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else {
                // Unclosed brace — keep the tail exactly as typed.
                result += rest[open...]
                return result
            }
            if let value = values[String(rest[afterOpen..<close])] {
                result += value
                rest = rest[rest.index(after: close)...]
            } else {
                // Unknown token: emit the brace and rescan right after it, so
                // "{{clipboard}}" still finds the inner known token.
                result += rest[open..<afterOpen]
                rest = rest[afterOpen...]
            }
        }
        result += rest
        return result
    }
}
