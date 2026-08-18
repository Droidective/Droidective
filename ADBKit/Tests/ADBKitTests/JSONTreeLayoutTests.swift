import Foundation
import Testing
@testable import ADBKit

@Suite struct JSONTreeLayoutTests {
    /// 11pt monospaced — the object tree's row font at the default text scale.
    private let font: Double = 11

    @Test func columnFollowsThePaneWidth() {
        // 6.6pt per glyph: a 660pt pane holds 100 glyphs, less the 30pt gutter
        // and a 4-character key ("data" + ":" + a space = 6 glyphs).
        let wide = JSONTreeLayout.columnCharacters(rowWidth: 660, fontSize: font, depth: 0, keyCharacters: 4)
        let narrow = JSONTreeLayout.columnCharacters(rowWidth: 330, fontSize: font, depth: 0, keyCharacters: 4)
        #expect(wide == 89)
        #expect(narrow == 39)
        // Halving the pane roughly halves the line — the property the split
        // panes depend on.
        #expect(narrow < wide / 2 + 5)
    }

    @Test func nestingAndLongKeysEatIntoTheValueColumn() {
        let shallow = JSONTreeLayout.columnCharacters(rowWidth: 660, fontSize: font, depth: 0, keyCharacters: 4)
        let deep = JSONTreeLayout.columnCharacters(rowWidth: 660, fontSize: font, depth: 5, keyCharacters: 4)
        let longKey = JSONTreeLayout.columnCharacters(rowWidth: 660, fontSize: font, depth: 0, keyCharacters: 30)
        #expect(deep < shallow)
        #expect(longKey == shallow - 26)
        // 5 levels × 12pt of indent ≈ 9 glyphs.
        #expect(shallow - deep == 9)
    }

    @Test func aBiggerTextScaleFitsFewerCharacters() {
        let normal = JSONTreeLayout.columnCharacters(rowWidth: 660, fontSize: 11, depth: 0, keyCharacters: 4)
        let zoomed = JSONTreeLayout.columnCharacters(rowWidth: 660, fontSize: 22, depth: 0, keyCharacters: 4)
        #expect(zoomed < normal / 2 + 5)
    }

    @Test func degenerateWidthsReportALineThatHoldsSomething() {
        // Before the pane reports its width, and at widths the gutter alone
        // exceeds — a zero column would divide every value into infinite lines.
        #expect(JSONTreeLayout.columnCharacters(rowWidth: 0, fontSize: font, depth: 0, keyCharacters: 0) == 1)
        #expect(JSONTreeLayout.columnCharacters(rowWidth: 20, fontSize: font, depth: 0, keyCharacters: 0) == 1)
        #expect(JSONTreeLayout.columnCharacters(rowWidth: 660, fontSize: 0, depth: 0, keyCharacters: 0) == 1)
        #expect(JSONTreeLayout.columnCharacters(rowWidth: 660, fontSize: font, depth: 900, keyCharacters: 0) == 1)
    }

    @Test func nonFiniteWidthClampsInsteadOfTrapping() {
        // A NaN or infinite width reaching the Int conversion is a crash, not a
        // layout glitch — the same trap `PaneSplit` pins for frame widths.
        #expect(JSONTreeLayout.columnCharacters(rowWidth: .nan, fontSize: font, depth: 0, keyCharacters: 0) == 1)
        #expect(JSONTreeLayout.columnCharacters(rowWidth: .infinity, fontSize: font, depth: 0, keyCharacters: 0) == 1)
        #expect(JSONTreeLayout.columnCharacters(rowWidth: 660, fontSize: .nan, depth: 0, keyCharacters: 0) == 1)
        // A finite but absurd width clamps below the Int conversion's ceiling.
        #expect(
            JSONTreeLayout.columnCharacters(rowWidth: 1e9, fontSize: font, depth: 0, keyCharacters: 0) == 100_000
        )
    }

    @Test func budgetKeepsAGlyphPerLineInHand() {
        // 40-character column × 3 lines, less a glyph a line so a hair-optimistic
        // estimate can't spill onto a fourth: 117, not 120.
        #expect(JSONTreeLayout.collapsedBudget(columnCharacters: 40) == 117)
        #expect(JSONTreeLayout.collapsedBudget(columnCharacters: 40, lines: 1) == 39)
        // Degenerate columns and line counts still yield a budget of at least
        // one character — a zero would cut every value to nothing.
        #expect(JSONTreeLayout.collapsedBudget(columnCharacters: 0) == 1)
        #expect(JSONTreeLayout.collapsedBudget(columnCharacters: 1) == 1)
        #expect(JSONTreeLayout.collapsedBudget(columnCharacters: 40, lines: 0) == 39)
    }

    @Test func overflowIsMeasuredAgainstTheBudget() {
        #expect(!JSONTreeLayout.overflows(characters: 117, columnCharacters: 40))
        #expect(JSONTreeLayout.overflows(characters: 118, columnCharacters: 40))
        #expect(!JSONTreeLayout.overflows(characters: 0, columnCharacters: 40))
        // An explicit line count is honoured — one line is the un-wrapped case.
        #expect(JSONTreeLayout.overflows(characters: 40, columnCharacters: 40, lines: 1))
        #expect(!JSONTreeLayout.overflows(characters: 40, columnCharacters: 40, lines: 2))
    }

    @Test func degenerateColumnStillDecides() {
        #expect(JSONTreeLayout.overflows(characters: 10, columnCharacters: 0))
        #expect(!JSONTreeLayout.overflows(characters: 1, columnCharacters: 0))
        #expect(JSONTreeLayout.overflows(characters: 10, columnCharacters: 3, lines: 0))
    }

    @Test func theUnmeasuredBudgetIsAboutThreeLinesOfATypicalPane() {
        // The first frame, before the pane reports its width: enough to look
        // like a collapsed value, far short of a whole payload.
        let typical = JSONTreeLayout.collapsedBudget(
            columnCharacters: JSONTreeLayout.columnCharacters(
                rowWidth: 660, fontSize: font, depth: 0, keyCharacters: 4
            )
        )
        #expect(JSONTreeLayout.unmeasuredBudget < typical)
        #expect(JSONTreeLayout.unmeasuredBudget > 100)
    }

    @Test func aRealisticPayloadKeepsItsDisclosure() {
        // The reported case: a stringified request body in a split pane.
        let body = String(repeating: "a", count: 900)
        let column = JSONTreeLayout.columnCharacters(rowWidth: 420, fontSize: font, depth: 1, keyCharacters: 4)
        #expect(JSONTreeLayout.overflows(characters: body.count, columnCharacters: column))
        // A short value in the same pane doesn't.
        #expect(!JSONTreeLayout.overflows(characters: 24, columnCharacters: column))
    }
}
