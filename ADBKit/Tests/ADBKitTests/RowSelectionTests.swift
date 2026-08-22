import Testing
@testable import ADBKit

/// The log feeds' multi-selection: ⌘-click, ⇧-click, drag, and what happens when
/// the feed changes underneath a selection.
@Suite struct RowSelectionTests {
    private let order = ["a", "b", "c", "d", "e"]

    @Test func plainClickSelectsOneAndAnchorsIt() {
        var selection = RowSelection<String>()
        selection.replace(with: "c")
        #expect(selection.ids == ["c"])
        #expect(selection.anchor == "c")
    }

    @Test func commandClickAddsThenRemoves() {
        var selection = RowSelection<String>()
        selection.toggle("b")
        selection.toggle("d")
        #expect(selection.ids == ["b", "d"])
        selection.toggle("b")
        #expect(selection.ids == ["d"])
        // The row touched last anchors the next range, selected or not.
        #expect(selection.anchor == "b")
    }

    @Test func shiftClickSpansFromTheAnchorInBothDirections() {
        var selection = RowSelection<String>()
        selection.replace(with: "b")
        selection.extend(to: "d", in: order)
        #expect(selection.ids == ["b", "c", "d"])

        var upward = RowSelection<String>()
        upward.replace(with: "d")
        upward.extend(to: "b", in: order)
        #expect(upward.ids == ["b", "c", "d"])
    }

    @Test func aSecondShiftClickRespansFromTheSameAnchor() {
        var selection = RowSelection<String>()
        selection.replace(with: "b")
        selection.extend(to: "e", in: order)
        selection.extend(to: "c", in: order)
        // Shrunk, not ratcheted — the anchor never moved to "e".
        #expect(selection.ids == ["b", "c"])
        #expect(selection.anchor == "b")
    }

    @Test func shiftClickWithoutAnAnchorActsLikeAPlainClick() {
        var selection = RowSelection<String>()
        selection.extend(to: "c", in: order)
        #expect(selection.ids == ["c"])
        #expect(selection.anchor == "c")
    }

    @Test func anAdditiveRangeKeepsWhatWasAlreadyPicked() {
        var selection = RowSelection<String>()
        selection.toggle("a")
        selection.toggle("c")
        selection.extend(to: "d", in: order, additive: true)
        #expect(selection.ids == ["a", "c", "d"])
    }

    @Test func dragSelectsTheSpanAndRecomputesAsItMoves() {
        var selection = RowSelection<String>()
        selection.select(from: "d", to: "b", in: order)
        #expect(selection.ids == ["b", "c", "d"])
        // The pointer comes back up: the span shrinks rather than accumulating.
        selection.select(from: "d", to: "c", in: order)
        #expect(selection.ids == ["c", "d"])
        #expect(selection.anchor == "d")
    }

    @Test func aRowThatIsNotInTheFeedIsIgnored() {
        var selection = RowSelection<String>()
        selection.replace(with: "b")
        selection.extend(to: "zzz", in: order)
        // No crash, and no pretend range: the click landed on nothing.
        #expect(selection.ids == ["b"])
        selection.select(from: "zzz", to: "c", in: order)
        #expect(selection.ids == ["b"])
    }

    @Test func retainDropsRowsTheFeedNoLongerHas() {
        var selection = RowSelection<String>()
        selection.replace(with: "a")
        selection.extend(to: "c", in: order)
        // The ring buffer trimmed the oldest two.
        selection.retain(in: ["c", "d", "e"])
        #expect(selection.ids == ["c"])
        // The anchor went with them, so the next ⇧-click starts fresh.
        #expect(selection.anchor == nil)
    }

    @Test func retainKeepsAnIntactSelectionUntouched() {
        var selection = RowSelection<String>()
        selection.replace(with: "b")
        selection.extend(to: "c", in: order)
        let before = selection
        selection.retain(in: order)
        #expect(selection == before)
    }

    @Test func orderedReturnsTheSelectionInDisplayOrder() {
        var selection = RowSelection<String>()
        selection.toggle("d")
        selection.toggle("a")
        selection.toggle("c")
        #expect(selection.ordered(in: order) == ["a", "c", "d"])
    }
}
