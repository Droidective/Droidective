import Foundation
import Testing

@testable import ADBKit

@Suite struct TabOverflowTests {

    /// Seven tabs of 100pt, 4pt apart: 7 tabs need 724, 6 need 620, and so on.
    private let widths = Array(repeating: 100.0, count: 7)

    private func layout(available: Double, selected: Int? = 0) -> TabOverflow.Layout {
        TabOverflow.layout(
            widths: widths, available: available, spacing: 4, overflowWidth: 30, selected: selected
        )
    }

    @Test func everythingFitsWhenThereIsRoom() {
        let result = layout(available: 1000)
        #expect(result.visible == [0, 1, 2, 3, 4, 5, 6])
        #expect(result.overflow.isEmpty)
    }

    @Test func anExactFitDoesNotSpill() {
        // 7 * 100 + 6 * 4 = 724.
        let result = layout(available: 724)
        #expect(result.overflow.isEmpty)
    }

    @Test func oneShortOfAnExactFitSpillsTheLastTab() {
        let result = layout(available: 723)
        #expect(result.visible == [0, 1, 2, 3, 4, 5])
        #expect(result.overflow == [6])
    }

    @Test func laterTabsGiveWayFirst() {
        let result = layout(available: 400)
        #expect(result.visible == [0, 1, 2])
        #expect(result.overflow == [3, 4, 5, 6])
    }

    @Test func theOverflowButtonIsPaidForOutOfTheSameBudget() {
        // 3 tabs + gaps = 308; plus the 30pt button and its gap = 342.
        #expect(layout(available: 342).visible == [0, 1, 2])
        #expect(layout(available: 341).visible == [0, 1])
    }

    /// The whole point of the change: whatever is drawn must actually fit, so
    /// nothing is ever shown clipped in half.
    @Test func aDrawnRowAlwaysFits() {
        for available in stride(from: 0.0, through: 800.0, by: 7.0) {
            for selected in 0..<widths.count {
                let result = layout(available: available, selected: selected)
                guard !result.visible.isEmpty else { continue }
                let tabs = result.visible.reduce(0.0) { $0 + widths[$1] }
                    + 4 * Double(result.visible.count - 1)
                let demand = tabs + (result.overflow.isEmpty ? 0 : 4 + 30)
                #expect(demand <= available)
            }
        }
    }

    @Test func aRowThatCanTakeATabButNotTheButtonShowsOnlyTheButton() {
        // 100pt tab + 4 + 30 = 134; at 120 the tab alone would fit but the
        // pair does not, and half an overflow button is not an option.
        let result = layout(available: 120, selected: 4)
        #expect(result.visible.isEmpty)
        #expect(result.overflow == Array(0..<7))
    }

    @Test func everyTabAppearsExactlyOnce() {
        for available in stride(from: 0.0, through: 800.0, by: 11.0) {
            for selected in 0..<widths.count {
                let result = layout(available: available, selected: selected)
                let all = (result.visible + result.overflow).sorted()
                #expect(all == Array(0..<widths.count))
            }
        }
    }

    @Test func theSelectedTabStaysVisible() {
        // Selecting Code (6) on a narrow row pulls it out of the menu.
        let result = layout(available: 400, selected: 6)
        #expect(result.visible.contains(6))
        #expect(!result.overflow.contains(6))
    }

    @Test func thePulledSelectionTakesTheLastSlotAndDisplacesThatTab() {
        let result = layout(available: 400, selected: 6)
        #expect(result.visible == [0, 1, 6])
        #expect(result.overflow == [2, 3, 4, 5])
    }

    @Test func theOverflowMenuStaysInDisplayOrder() {
        let result = layout(available: 400, selected: 5)
        #expect(result.overflow == result.overflow.sorted())
    }

    @Test func aSelectionThatAlreadyFitsIsNotMoved() {
        let result = layout(available: 400, selected: 1)
        #expect(result.visible == [0, 1, 2])
        #expect(result.overflow == [3, 4, 5, 6])
    }

    @Test func aRowTooNarrowForAnyTabStillShowsTheSelection() {
        // 100pt tab + 4 + 30 = 134 exactly.
        let result = layout(available: 134, selected: 4)
        #expect(result.visible == [4])
        #expect(result.overflow == [0, 1, 2, 3, 5, 6])
    }

    @Test func aRowNarrowerThanOneTabHidesEverything() {
        let result = layout(available: 40, selected: 3)
        #expect(result.visible.isEmpty)
        #expect(result.overflow == Array(0..<7))
    }

    @Test func noSelectionIsHandled() {
        let result = TabOverflow.layout(
            widths: widths, available: 400, spacing: 4, overflowWidth: 30, selected: nil
        )
        #expect(result.visible == [0, 1, 2])
        #expect(result.overflow == [3, 4, 5, 6])
    }

    @Test func anEmptyTabListProducesNothing() {
        let result = TabOverflow.layout(
            widths: [], available: 400, spacing: 4, overflowWidth: 30, selected: nil
        )
        #expect(result.visible.isEmpty)
        #expect(result.overflow.isEmpty)
    }

    @Test func unevenWidthsAreRespected() {
        let uneven = [60.0, 200.0, 50.0, 50.0]
        let result = TabOverflow.layout(
            widths: uneven, available: 300, spacing: 4, overflowWidth: 30, selected: 0
        )
        // 60 + 4 + 200 = 264, plus the button and its gap = 298 — the third
        // tab would need another 54.
        #expect(result.visible == [0, 1])
        #expect(result.overflow == [2, 3])
    }

    @Test func aZeroWidthRowDoesNotTrap() {
        let result = layout(available: 0, selected: 0)
        #expect(result.visible.isEmpty)
        #expect(result.overflow.count == 7)
    }
}
