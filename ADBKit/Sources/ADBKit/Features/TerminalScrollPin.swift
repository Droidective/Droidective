import Foundation

/// Keeps a terminal's viewport where the user parked it while the program
/// underneath keeps writing.
///
/// SwiftTerm moves the viewport back to the newest line on *every* line the
/// program scrolls: `Terminal.scroll` ends with `yDisp = yBase` unless its
/// internal `userScrolling` flag is set, and nothing in the package ever sets
/// it. Anything that draws continuously — an agent CLI redrawing its prompt,
/// `tail -f`, a build log — therefore snaps the view back the instant it is
/// scrolled, which reads as "scrolling is broken". This model carries the
/// "the user is reading history" state the terminal doesn't, and answers the
/// one question the view asks on every scrolled line: which row does the
/// viewport belong at?
///
/// Rows are absolute indices into the terminal's line buffer. The bottom row
/// grows by one per line until the scrollback is full, then saturates — which
/// is exactly how a *trimmed* line (the oldest line dropped, everything above
/// shifted up one) is told apart from a *grown* buffer, and why the pin has to
/// follow the text down on a trim to keep the same rows on screen.
public struct TerminalScrollPin: Sendable, Equatable {
    /// The buffer row the viewport is held at; nil while it follows the output.
    public private(set) var pinnedRow: Int?

    /// The bottom row reported by the previous scrolled line, to spot the
    /// saturation that means the buffer trimmed instead of grew.
    private var lastBottomRow: Int?

    /// The bottom row a full buffer saturates at — the scrollback size.
    private let capacityRow: Int

    /// - Parameter scrollbackLines: the terminal's scrollback size in lines.
    public init(scrollbackLines: Int) {
        capacityRow = max(0, scrollbackLines)
    }

    public var isPinned: Bool { pinnedRow != nil }

    /// The user moved the viewport themselves (wheel, drag-select autoscroll).
    /// Landing at the bottom means "follow the output again".
    public mutating func userScrolled(to row: Int, atBottom: Bool) {
        pinnedRow = atBottom ? nil : max(0, row)
    }

    /// Follow the output again — typing, a switch to the alternate screen, a
    /// reset.
    public mutating func release() {
        pinnedRow = nil
    }

    /// The program scrolled the buffer one line and the terminal moved the
    /// viewport to `bottomRow` with it. Returns the row to put the viewport
    /// back to, or nil while it is following the output.
    public mutating func bufferScrolled(bottomRow: Int) -> Int? {
        let previous = lastBottomRow
        lastBottomRow = bottomRow
        guard let row = pinnedRow else { return nil }
        // The bottom didn't move on a buffer that has reached its scrollback
        // limit: the oldest line was dropped and every row above shifted up
        // one, so the pin follows the text to keep it still on screen. Once
        // the pin reaches the top, the text it held scrolls away — the same
        // thing every terminal does when history overruns the buffer.
        guard previous == bottomRow, bottomRow >= capacityRow else { return row }
        let shifted = max(0, row - 1)
        pinnedRow = shifted
        return shifted
    }
}

/// What a wheel event is worth, for the two places a terminal can send it.
public enum TerminalWheel {
    /// Lines of viewport movement, mirroring SwiftTerm's own velocity curve so
    /// the feel is unchanged where the view takes the wheel over from it.
    public static func lines(delta: Double, rows: Int) -> Int {
        switch Int(abs(delta)) {
        case 10...: return max(rows, 20)
        case 6...9: return 10
        case 2...5: return 3
        default: return 1
        }
    }

    /// Wheel reports to send to a program that took the mouse over: one per
    /// line the event carries, since the program applies its own scroll speed
    /// on top — the accelerated viewport curve would overshoot by pages. A
    /// trackpad's sub-line deltas still send one, which is what makes its
    /// stream of small events feel smooth.
    public static func reports(delta: Double, rows: Int) -> Int {
        max(1, min(Int(abs(delta)), max(1, rows)))
    }
}
