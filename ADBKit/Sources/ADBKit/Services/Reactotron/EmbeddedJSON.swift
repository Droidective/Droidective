import Foundation

/// A JSON *string* that is itself JSON: an API request whose `data` field
/// carries a stringified body, a log whose message is a serialized object.
/// Reactotron shows what the app sent — a wall of escaped text — where the
/// reader wants the object.
///
/// The two halves are deliberately separate. `looksLikeJSON` is what a row
/// asks on every render to decide whether to offer the parse, so it only
/// touches the string's first and last non-whitespace characters. `parse` is
/// the walk of the whole payload, and is only ever called for the one value a
/// reader opened — a streaming timeline must never parse what nobody looked at.
public enum EmbeddedJSON {
    /// Longest string (in UTF-8 bytes) worth parsing. Past this the parse is
    /// itself the stall, so the value keeps its raw text and offers nothing.
    public static let maxBytes = 1_000_000

    /// True when `text` is *shaped* like a JSON object or array — the cheap
    /// check, whitespace-tolerant, made per row render.
    public static func looksLikeJSON(_ text: String) -> Bool {
        guard text.utf8.count <= maxBytes else { return false }
        guard let opener = text.first(where: { !$0.isWhitespace }) else { return false }
        let closer: Character
        switch opener {
        case "{": closer = "}"
        case "[": closer = "]"
        default: return false
        }
        // Scanning back from the end, not `trimmingCharacters`, so a megabyte
        // of body is never copied to look at one character.
        var index = text.endIndex
        while index > text.startIndex {
            index = text.index(before: index)
            guard text[index].isWhitespace else { return text[index] == closer }
        }
        return false
    }

    /// The parsed object or array, or nil when the string isn't one (or is
    /// bigger than `maxBytes`). Call this when the value is opened, never while
    /// building a row.
    public static func parse(_ text: String) -> JSONValue? {
        guard looksLikeJSON(text), let data = text.data(using: .utf8) else { return nil }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        switch value {
        case .object, .array: return value
        default: return nil
        }
    }
}
