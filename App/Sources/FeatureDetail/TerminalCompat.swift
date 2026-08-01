import Foundation
import SwiftTerm

/// Repairs for SwiftTerm state the library itself leaves inconsistent.
enum TerminalCompat {
    /// SwiftTerm initializes the *normal* screen's right margin to `cols - 1`
    /// but never the alternate screen's, which keeps the 0 it was born with.
    /// `Terminal.cmdScrollDown` — `CSI T`, the sequence a full-screen program
    /// uses to scroll its view down a line — then copies
    /// `marginRight - marginLeft + 1` columns *unconditionally*: with the
    /// margin left at 0 that is exactly ONE column, so each scroll smears the
    /// first column down the screen and leaves the rest of every row stale.
    /// The program repaints only the rows it believes changed, and the screen
    /// ends up holding two frames interleaved character by character.
    ///
    /// Agent CLIs and pagers scroll exactly this way (`ESC[2;48r ESC[1T
    /// ESC[r`, then repaint the exposed row), so the alternate screen is
    /// where it bites. Restoring the margin restores the full-width copy.
    /// (Upstream's `cmdScrollUp` takes the margin path only when
    /// `marginMode` is set, which is why `CSI S` is unaffected.)
    ///
    /// Only the uninitialized state is touched: a program that set its own
    /// margins with DECSLRM has a non-zero right margin and is left alone.
    static func repairAlternateScreenMargins(_ terminal: Terminal) {
        guard terminal.isCurrentBufferAlternate, terminal.cols > 1 else { return }
        guard terminal.buffer.marginRight == 0 else { return }
        terminal.buffer.marginLeft = 0
        terminal.buffer.marginRight = terminal.cols - 1
    }
}
