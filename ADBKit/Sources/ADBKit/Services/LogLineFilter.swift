import Foundation

/// Pure helpers behind the log views' Filter field and Find bar. Filter hides
/// non-matching lines; Find keeps every line visible and walks the matches.
/// Both match case-insensitively against `LogLine.searchKey` (the raw line
/// pre-lowercased at ingest).
public enum LogLineFilter {
    /// Lines surviving the tag filter and the free-text filter, in stream
    /// order (oldest first).
    public static func visible(_ lines: [LogLine], tag: String?, filter: String) -> [LogLine] {
        let query = filter.lowercased()
        return lines.filter { line in
            if let tag, line.tag != tag { return false }
            if !query.isEmpty && !line.searchKey.contains(query) { return false }
            return true
        }
    }

    /// IDs of the lines matching the Find query, in *display* order (top of
    /// the screen first), so "next" always moves down the screen whichever
    /// way the feed is flipped.
    public static func findMatches(
        in lines: [LogLine], query: String, newestFirst: Bool
    ) -> [UUID] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        let ordered = newestFirst ? Array(lines.reversed()) : lines
        return ordered.filter { $0.searchKey.contains(needle) }.map(\.id)
    }

    /// The match to move to from `current`, wrapping at either end. With no
    /// usable current match — Find just opened, or the line was trimmed out
    /// of the ring buffer — forward starts at the first match, backward at
    /// the last.
    public static func advance(from current: UUID?, in matches: [UUID], forward: Bool) -> UUID? {
        guard !matches.isEmpty else { return nil }
        guard let current, let index = matches.firstIndex(of: current) else {
            return forward ? matches.first : matches.last
        }
        let count = matches.count
        return matches[forward ? (index + 1) % count : (index - 1 + count) % count]
    }
}
