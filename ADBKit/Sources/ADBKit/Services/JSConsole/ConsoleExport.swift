import Foundation

/// One console line flattened for export — the view maps its feed entries
/// (already filtered by the active level/text filter) into these.
public struct ConsoleExportEntry: Sendable, Equatable {
    public let at: Date
    /// `log` · `input` · `result` · `error` · `notice`.
    public let type: String
    /// The console level for `log` entries; nil otherwise (omitted from JSON).
    public let level: String?
    public let text: String

    public init(at: Date, type: String, level: String? = nil, text: String) {
        self.at = at
        self.type = type
        self.level = level
        self.text = text
    }
}

/// Serializes a console feed for the Export button — one deterministic JSON
/// shape shared by "save as file" and "copy to clipboard".
public enum ConsoleExport {
    private struct Line: Encodable {
        let timestamp: String
        let type: String
        let level: String?
        let text: String
    }

    /// ISO 8601 with fractional seconds — console bursts land several entries
    /// in the same second, so whole-second stamps would read as ties.
    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// A pretty-printed JSON array of the entries, in the order given (the
    /// caller passes them in display/chronological order). `level` is omitted
    /// for entries that have none.
    public static func json(_ entries: [ConsoleExportEntry]) -> String {
        let lines = entries.map {
            Line(timestamp: stamp($0.at), type: $0.type, level: $0.level, text: $0.text)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(lines) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
