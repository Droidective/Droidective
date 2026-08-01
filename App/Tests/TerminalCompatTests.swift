import SwiftTerm
import Testing

/// The Terminal feature couldn't scroll an agent CLI or a pager, and once the
/// wheel did reach them their output came back as two frames interleaved
/// character by character. The cause is upstream: SwiftTerm leaves the
/// alternate screen's right margin at 0, and `CSI T` (scroll down) copies
/// `marginRight - marginLeft + 1` columns — one column — per row. These tests
/// hold the repair in place, so a SwiftTerm bump that changes the behavior
/// shows up here rather than as smeared text on screen.
@Suite struct TerminalCompatTests {
    private final class Sink: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    private func makeTerminal(cols: Int = 6, rows: Int = 5) -> Terminal {
        Terminal(delegate: Sink(), options: TerminalOptions(cols: cols, rows: rows, scrollback: 0))
    }

    /// The screen as plain rows, with SwiftTerm's null padding read as blanks.
    private func screen(_ terminal: Terminal) -> [String] {
        (0..<terminal.rows).map { row in
            var line = ""
            for col in 0..<terminal.cols {
                let character = terminal.buffer.getChar(at: Position(col: col, row: row)).getCharacter()
                line.append(character == "\0" ? " " : character)
            }
            while line.hasSuffix(" ") { line.removeLast() }
            return line
        }
    }

    // MARK: - The margin itself

    @Test func alternateScreenMarginIsRepairedToTheFullWidth() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?1049h")
        TerminalCompat.repairAlternateScreenMargins(terminal)
        #expect(terminal.buffer.marginRight == terminal.cols - 1)
        #expect(terminal.buffer.marginLeft == 0)
    }

    @Test func normalScreenIsLeftAlone() {
        let terminal = makeTerminal()
        let before = terminal.buffer.marginRight
        TerminalCompat.repairAlternateScreenMargins(terminal)
        #expect(terminal.buffer.marginRight == before)
    }

    @Test func aProgramsOwnMarginsAreLeftAlone() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?1049h")
        terminal.buffer.marginRight = 3
        terminal.buffer.marginLeft = 1
        TerminalCompat.repairAlternateScreenMargins(terminal)
        #expect(terminal.buffer.marginRight == 3)
        #expect(terminal.buffer.marginLeft == 1)
    }

    // MARK: - What it buys: a scroll that moves whole rows

    /// `ESC[2;4r ESC[1T ESC[r` — set a scroll region, scroll it down one line,
    /// release it: the shape an agent CLI or pager uses per wheel notch. Rows
    /// 2…4 move down one, row 2 blanks, rows 1 and 5 stay put.
    @Test func scrollDownMovesWholeRowsOnTheAlternateScreen() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?1049h")
        TerminalCompat.repairAlternateScreenMargins(terminal)
        terminal.feed(text: "AAA\r\nBBB\r\nCCC\r\nDDD\r\nEEE")
        terminal.feed(text: "\u{1b}[2;4r\u{1b}[1T\u{1b}[r")
        #expect(screen(terminal) == ["AAA", "", "BBB", "CCC", "EEE"])
    }

    @Test func fullScreenScrollDownMovesWholeRowsOnTheAlternateScreen() {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?1049h")
        TerminalCompat.repairAlternateScreenMargins(terminal)
        terminal.feed(text: "AAA\r\nBBB\r\nCCC\r\nDDD\r\nEEE")
        terminal.feed(text: "\u{1b}[1T")
        #expect(screen(terminal) == ["", "AAA", "BBB", "CCC", "DDD"])
    }

    /// The normal screen never had the defect — the repair must not change it.
    @Test func scrollDownIsUnchangedOnTheNormalScreen() {
        let terminal = makeTerminal()
        TerminalCompat.repairAlternateScreenMargins(terminal)
        terminal.feed(text: "AAA\r\nBBB\r\nCCC\r\nDDD\r\nEEE")
        terminal.feed(text: "\u{1b}[2;4r\u{1b}[1T\u{1b}[r")
        #expect(screen(terminal) == ["AAA", "", "BBB", "CCC", "EEE"])
    }
}
