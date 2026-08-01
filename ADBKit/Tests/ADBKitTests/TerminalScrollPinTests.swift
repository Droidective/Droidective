import Foundation
import Testing
@testable import ADBKit

@Suite("TerminalScrollPin")
struct TerminalScrollPinTests {
    // MARK: - Following the output

    @Test func followsTheOutputUntilTheUserScrollsUp() {
        var pin = TerminalScrollPin(scrollbackLines: 500)
        #expect(!pin.isPinned)
        #expect(pin.bufferScrolled(bottomRow: 10) == nil)
        #expect(pin.bufferScrolled(bottomRow: 11) == nil)
    }

    @Test func scrollingBackToTheBottomFollowsTheOutputAgain() {
        var pin = TerminalScrollPin(scrollbackLines: 500)
        pin.userScrolled(to: 20, atBottom: false)
        #expect(pin.bufferScrolled(bottomRow: 100) == 20)
        pin.userScrolled(to: 100, atBottom: true)
        #expect(!pin.isPinned)
        #expect(pin.bufferScrolled(bottomRow: 101) == nil)
    }

    @Test func releaseFollowsTheOutputAgain() {
        var pin = TerminalScrollPin(scrollbackLines: 500)
        pin.userScrolled(to: 20, atBottom: false)
        pin.release()
        #expect(!pin.isPinned)
        #expect(pin.bufferScrolled(bottomRow: 300) == nil)
    }

    // MARK: - Holding the viewport

    @Test func holdsTheRowWhileTheBufferGrows() {
        var pin = TerminalScrollPin(scrollbackLines: 500)
        pin.userScrolled(to: 42, atBottom: false)
        for bottom in 100...120 {
            #expect(pin.bufferScrolled(bottomRow: bottom) == 42)
        }
        #expect(pin.pinnedRow == 42)
    }

    @Test func aStalledBottomBelowCapacityIsNotATrim() {
        // A program scrolling inside a margin region moves no line into the
        // scrollback: the bottom stalls, but nothing shifted, so the pin
        // must not chase it.
        var pin = TerminalScrollPin(scrollbackLines: 500)
        pin.userScrolled(to: 42, atBottom: false)
        #expect(pin.bufferScrolled(bottomRow: 120) == 42)
        #expect(pin.bufferScrolled(bottomRow: 120) == 42)
        #expect(pin.bufferScrolled(bottomRow: 120) == 42)
        #expect(pin.pinnedRow == 42)
    }

    // MARK: - Trimming

    @Test func followsTheTextWhenAFullBufferTrims() {
        var pin = TerminalScrollPin(scrollbackLines: 500)
        pin.userScrolled(to: 42, atBottom: false)
        #expect(pin.bufferScrolled(bottomRow: 500) == 42) // grew to capacity
        #expect(pin.bufferScrolled(bottomRow: 500) == 41) // trimmed
        #expect(pin.bufferScrolled(bottomRow: 500) == 40)
        #expect(pin.pinnedRow == 40)
    }

    @Test func trimmingStopsAtTheTopOfTheBuffer() {
        var pin = TerminalScrollPin(scrollbackLines: 2)
        pin.userScrolled(to: 1, atBottom: false)
        #expect(pin.bufferScrolled(bottomRow: 2) == 1)
        #expect(pin.bufferScrolled(bottomRow: 2) == 0)
        #expect(pin.bufferScrolled(bottomRow: 2) == 0)
        #expect(pin.pinnedRow == 0)
    }

    @Test func aFirstScrollAtCapacityIsNotTreatedAsATrim() {
        // Nothing to compare the bottom against yet — assume it grew, or the
        // viewport would slide a row on the first line of output.
        var pin = TerminalScrollPin(scrollbackLines: 500)
        pin.userScrolled(to: 42, atBottom: false)
        #expect(pin.bufferScrolled(bottomRow: 500) == 42)
    }

    // MARK: - Pinning input

    @Test func aNegativeRowPinsToTheTop() {
        var pin = TerminalScrollPin(scrollbackLines: 500)
        pin.userScrolled(to: -3, atBottom: false)
        #expect(pin.pinnedRow == 0)
    }

    @Test func aScrollbackFreeTerminalNeverHoldsAPosition() {
        // No scrollback: every scroll is a trim, so the pin decays to the top
        // immediately instead of freezing the view on stale rows.
        var pin = TerminalScrollPin(scrollbackLines: 0)
        pin.userScrolled(to: 3, atBottom: false)
        #expect(pin.bufferScrolled(bottomRow: 0) == 3)
        #expect(pin.bufferScrolled(bottomRow: 0) == 2)
        #expect(pin.bufferScrolled(bottomRow: 0) == 1)
        #expect(pin.bufferScrolled(bottomRow: 0) == 0)
    }

    // MARK: - Wheel velocity

    @Test func wheelReportsStayOnePerLineForTheProgram() {
        // A trackpad's sub-line deltas still report once — its many small
        // events are what make the scroll smooth.
        #expect(TerminalWheel.reports(delta: 0.2, rows: 40) == 1)
        #expect(TerminalWheel.reports(delta: -1.0, rows: 40) == 1)
        #expect(TerminalWheel.reports(delta: 3.0, rows: 40) == 3)
        // Never more than a screenful from one event.
        #expect(TerminalWheel.reports(delta: 400.0, rows: 40) == 40)
    }

    @Test func wheelVelocityMatchesTheTerminalsOwnCurve() {
        #expect(TerminalWheel.lines(delta: 0.4, rows: 40) == 1)
        #expect(TerminalWheel.lines(delta: -1.0, rows: 40) == 1)
        #expect(TerminalWheel.lines(delta: 3.0, rows: 40) == 3)
        #expect(TerminalWheel.lines(delta: -7.0, rows: 40) == 10)
        #expect(TerminalWheel.lines(delta: 30.0, rows: 40) == 40)
        #expect(TerminalWheel.lines(delta: 30.0, rows: 10) == 20)
    }
}
