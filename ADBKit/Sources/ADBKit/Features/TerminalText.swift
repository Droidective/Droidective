import Foundation

/// Pure text helpers for the Terminal feature's UI — the collapsed rail's
/// tab badges and the line fragment typed for files dropped onto a shell.
public enum TerminalText {
    /// The short badge a collapsed rail shows for a tab: the first two
    /// characters of the trimmed name ("Terminal 1" → "Te", a renamed
    /// "build watcher" → "bu"). "?" only for a blank name, which the rename
    /// flow already rejects.
    public static func railBadge(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        return String(trimmed.prefix(2))
    }

    /// What dropping files on a shell types into it: each path quoted only
    /// when it needs to be (single-quoted, so spaces, newlines, and every
    /// metacharacter survive zsh literally), space-separated, with a trailing
    /// space so the user can keep typing — like dropping onto Terminal.app.
    public static func droppedPathsInsertion(_ paths: [String]) -> String {
        guard !paths.isEmpty else { return "" }
        return paths.map { needsQuoting($0) ? shellQuote($0) : $0 }
            .joined(separator: " ") + " "
    }

    /// Bare-safe characters for an argument word. Conservative: anything
    /// outside alphanumerics and this punctuation set gets the path quoted.
    private static let bareSafe = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "/._-+@%,"))

    private static func needsQuoting(_ path: String) -> Bool {
        path.isEmpty || path.unicodeScalars.contains { !bareSafe.contains($0) }
    }
}
