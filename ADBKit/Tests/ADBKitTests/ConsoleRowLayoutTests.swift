@testable import ADBKit
import Testing

/// `ConsoleRowLayout` — the wrapping geometry of a JS console row.
struct ConsoleRowLayoutTests {
    private func segment(_ width: Double, _ height: Double, baseline: Double) -> ConsoleRowSegment {
        ConsoleRowSegment(width: width, height: height, baseline: baseline)
    }

    /// Every segment has to end up inside the height the row reports. This is
    /// the regression: the height used to grow as segments arrived, against the
    /// baseline known at that moment — so a tall segment that a later,
    /// lower-baselined one pushed down drew past the reported height, and a
    /// feed of under-reporting rows left gaps that moved on every resize.
    @Test func everySegmentFitsInsideTheReportedHeight() {
        // A message wrapped to three lines (tall, baseline near its top) next to
        // a single-line object chip whose baseline sits lower.
        let segments = [segment(200, 48, baseline: 11), segment(80, 18, baseline: 30)]
        let arranged = ConsoleRowLayout.arrange(segments, maxWidth: 400)
        for (index, slot) in arranged.slots.enumerated() {
            let bottom = slot.y + segments[index].height
            #expect(bottom <= arranged.height + 0.001, "segment \(index) draws past the row's height")
        }
        // The tall segment is pushed down onto the shared baseline, and the
        // height covers where it lands.
        #expect(arranged.slots[0].y == 19)
        #expect(arranged.height == 67)
    }

    @Test func segmentsShareOneBaselineAcrossALine() {
        let segments = [segment(50, 20, baseline: 15), segment(50, 30, baseline: 22)]
        let arranged = ConsoleRowLayout.arrange(segments, maxWidth: 400, spacing: 5)
        // Both sit so their baselines line up at the larger of the two.
        #expect(arranged.slots[0].y + 15 == arranged.slots[1].y + 22)
        #expect(arranged.slots[0].x == 0)
        #expect(arranged.slots[1].x == 55)
    }

    @Test func aSegmentThatWouldOverflowStartsANewLine() {
        let segments = [segment(60, 20, baseline: 15), segment(60, 20, baseline: 15), segment(60, 20, baseline: 15)]
        let arranged = ConsoleRowLayout.arrange(segments, maxWidth: 130, spacing: 5, lineSpacing: 3)
        // 60 + 5 + 60 = 125 fits; the third would reach 190.
        #expect(arranged.slots[0].y == 0)
        #expect(arranged.slots[1].y == 0)
        #expect(arranged.slots[2].y == 23)
        #expect(arranged.slots[2].x == 0)
        #expect(arranged.height == 43)
    }

    /// A row that advertises more width than it was offered makes the pane lay
    /// it out past its own edge.
    @Test func theReportedWidthNeverExceedsWhatWasOffered() {
        let wide = [segment(900, 20, baseline: 15)]
        #expect(ConsoleRowLayout.arrange(wide, maxWidth: 300).width == 300)
        let narrow = [segment(80, 20, baseline: 15)]
        #expect(ConsoleRowLayout.arrange(narrow, maxWidth: 300).width == 80)
    }

    /// A single segment wider than the row still gets placed rather than
    /// looping or vanishing — a long unbreakable token has to go somewhere.
    @Test func aSegmentWiderThanTheRowIsStillPlaced() {
        let segments = [segment(500, 20, baseline: 15), segment(40, 20, baseline: 15)]
        let arranged = ConsoleRowLayout.arrange(segments, maxWidth: 100)
        #expect(arranged.slots.count == 2)
        #expect(arranged.slots[0] == ConsoleRowSlot(x: 0, y: 0))
        #expect(arranged.slots[1].y > 0)
    }

    /// Asked for its minimum, the layout answers one segment per line rather
    /// than dividing by zero or reporting nothing.
    @Test func aZeroWidthProposalPutsEverySegmentOnItsOwnLine() {
        let segments = [segment(40, 20, baseline: 15), segment(40, 20, baseline: 15)]
        let arranged = ConsoleRowLayout.arrange(segments, maxWidth: 0)
        #expect(arranged.slots[0].y == 0)
        #expect(arranged.slots[1].y == 23)
        #expect(arranged.width == 0)
    }

    @Test func anEmptyRowHasNoSizeAndNoSlots() {
        let arranged = ConsoleRowLayout.arrange([], maxWidth: 300)
        #expect(arranged.slots.isEmpty)
        #expect(arranged.width == 0)
        #expect(arranged.height == 0)
    }

    /// One segment is the common case (a log with no object) — no trailing
    /// line spacing should leak into its height.
    @Test func aSingleSegmentIsExactlyItsOwnSize() {
        let arranged = ConsoleRowLayout.arrange([segment(120, 22, baseline: 16)], maxWidth: 300)
        #expect(arranged.slots == [ConsoleRowSlot(x: 0, y: 0)])
        #expect(arranged.width == 120)
        #expect(arranged.height == 22)
    }
}
