import Foundation

/// Row geometry for the Reactotron object tree. A value wraps with the pane
/// rather than being cut at one line, so the only thing the view has to decide
/// per row is whether the value still overflows those wrapped lines — that row
/// earns a disclosure that opens the value in full. Pure, so the decision is
/// testable without laying out a view.
public enum JSONTreeLayout {
    /// Wrapped lines a collapsed value gets before the rest is hidden.
    public static let collapsedLines = 3

    /// A monospaced glyph's advance as a fraction of the point size — SF Mono,
    /// what `.monospaced` resolves to, is exactly 0.6 em. Estimating from the
    /// font size lets one measurement of the tree's width answer for every row,
    /// and it tracks the user's text-size scale for free.
    public static let advanceRatio: Double = 0.6

    /// Indent a nesting level adds ahead of the disclosure column.
    public static let indentPerDepth: Double = 12

    /// Fixed width ahead of the value on every row: the disclosure column (14)
    /// plus the four 4pt gaps `HStack(spacing: 4)` puts between the row's parts.
    public static let gutter: Double = 14 + 16

    /// Characters one wrapped line of the value column holds, for a row at
    /// `depth` whose key is `keyCharacters` long. Never below 1: a
    /// pathologically narrow pane reports a line that holds something instead
    /// of dividing a value by zero.
    public static func columnCharacters(
        rowWidth: Double, fontSize: Double, depth: Int, keyCharacters: Int
    ) -> Int {
        let advance = fontSize * advanceRatio
        guard advance > 0, rowWidth.isFinite else { return 1 }
        let indent = Double(max(0, depth)) * indentPerDepth
        // The key and its ":" sit on the value's first line — charge the value
        // column for both, plus the space between them.
        let key = Double(max(0, keyCharacters) + 2) * advance
        let capacity = (rowWidth - indent - gutter - key) / advance
        guard capacity.isFinite, capacity > 1 else { return 1 }
        // Bounded before the Int conversion — an absurd width would trap, and
        // no real value is longer than this anyway.
        return Int(min(capacity, 100_000))
    }

    /// True when a value of `characters` still overflows `lines` wrapped lines
    /// of a `columnCharacters`-wide column, i.e. the row keeps its disclosure.
    public static func overflows(
        characters: Int, columnCharacters: Int, lines: Int = collapsedLines
    ) -> Bool {
        characters > max(1, columnCharacters) * max(1, lines)
    }
}
