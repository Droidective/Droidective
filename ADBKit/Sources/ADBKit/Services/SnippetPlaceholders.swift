import Foundation

/// Expands `{placeholder}` tokens in a Send Text snippet at insert time —
/// e.g. `{clipboard}` becomes the Mac's current pasteboard string and `{ip}`
/// the Mac's LAN address. Pure: the caller supplies the live values, unknown
/// tokens stay exactly as typed.
public enum SnippetPlaceholders {
    /// The placeholders the Send Text UI offers, for hints and docs.
    public static let known = ["clipboard", "ip"]

    public static func expand(_ text: String, values: [String: String]) -> String {
        var result = text
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
