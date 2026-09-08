import Foundation
import Testing
@testable import ADBKit

@Suite struct TabPinningTests {
    // MARK: - normalized

    @Test func normalizedMovesPinnedTabsToTheFrontKeepingRelativeOrder() {
        let result = TabPinning.normalized(["a", "b", "c", "d"], pinned: ["d", "b"])
        #expect(result.tabs == ["b", "d", "a", "c"])
        #expect(result.pinnedCount == 2)
    }

    @Test func normalizedIgnoresPinnedIDsThatAreNotOpen() {
        // A restore drops tabs whose feature is gone; their pin goes with them.
        let result = TabPinning.normalized(["a", "b"], pinned: ["b", "retired-feature"])
        #expect(result.tabs == ["b", "a"])
        #expect(result.pinnedCount == 1)
    }

    @Test func normalizedWithNothingPinnedKeepsTheOrderExactly() {
        let result = TabPinning.normalized(["a", "b", "c"], pinned: [])
        #expect(result.tabs == ["a", "b", "c"])
        #expect(result.pinnedCount == 0)
    }

    // MARK: - clampedTarget

    @Test func unpinnedTabCannotBeDroppedInsideThePinnedPrefix() {
        // Aiming U1 before P1 lands it at index 1 — inside the prefix — so it
        // is pulled back to the boundary, the first unpinned tab.
        let target = TabPinning.clampedTarget(
            "U1", before: "P1", in: ["P0", "P1", "U0", "U1"], pinnedCount: 2)
        #expect(target == "U0")
    }

    @Test func pinnedTabCannotBeDroppedPastThePinnedPrefix() {
        let target = TabPinning.clampedTarget(
            "P0", before: "U1", in: ["P0", "P1", "U0", "U1"], pinnedCount: 2)
        #expect(target == "U0")
    }

    @Test func pinnedTabDroppedOnTheStripsDeadSpaceStopsAtTheBoundary() {
        // nil = the end of the strip, which is past the prefix.
        let target = TabPinning.clampedTarget(
            "P0", before: nil, in: ["P0", "P1", "U0"], pinnedCount: 2)
        #expect(target == "U0")
    }

    @Test func withEverythingPinnedTheEndOfTheStripIsThePrefix() {
        let target = TabPinning.clampedTarget(
            "P0", before: nil, in: ["P0", "P1"], pinnedCount: 2)
        #expect(target == nil)
    }

    @Test func aDropWithinTheSameRegionIsLeftAlone() {
        let tabs = ["P0", "P1", "U0", "U1"]
        #expect(TabPinning.clampedTarget("P1", before: "P0", in: tabs, pinnedCount: 2) == "P0")
        #expect(TabPinning.clampedTarget("U0", before: nil, in: tabs, pinnedCount: 2) == nil)
        #expect(TabPinning.clampedTarget("U1", before: "U0", in: tabs, pinnedCount: 2) == "U0")
    }

    @Test func theFirstUnpinnedTabAimedAtThePrefixClampsToItselfAndSoStaysPut() {
        let target = TabPinning.clampedTarget(
            "U0", before: "P0", in: ["P0", "P1", "U0"], pinnedCount: 2)
        // `SidebarOrdering.move` no-ops on item == target, which is exactly
        // right: U0 already sits at the boundary.
        #expect(target == "U0")
    }

    @Test func aTabFromAnotherWindowKeepsItsTargetHavingNoRegionHereYet() {
        let target = TabPinning.clampedTarget(
            "incoming", before: "P0", in: ["P0", "U0"], pinnedCount: 1)
        #expect(target == "P0")
    }

    @Test func clampedTargetAgreesWithWhereTheReorderActuallyLands() {
        // The guideline the strip paints and the move the model performs read
        // the same function, so pin the two together: every (tab, target) pair
        // must leave the pinned prefix intact.
        let tabs = ["P0", "P1", "U0", "U1"]
        let pinnedCount = 2
        for id in tabs {
            for target in tabs.map(Optional.init) + [nil] {
                var state = TabState(openTabs: tabs, activeTab: "U0", pinnedCount: pinnedCount)
                state.reorder(id, before: target)
                #expect(
                    Set(state.pinnedTabs) == Set(["P0", "P1"]),
                    "moving \(id) before \(target ?? "end") broke the prefix: \(state.openTabs)")
                #expect(state.pinnedCount == pinnedCount)
                #expect(Set(state.openTabs) == Set(tabs))
            }
        }
    }
}
