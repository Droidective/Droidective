import Foundation
import Testing
@testable import ADBKit

@Suite struct TabStateTests {
    @Test func opensAndActivatesNewTabs() {
        var tabs = TabState()
        tabs.open("a")
        tabs.open("b")
        #expect(tabs.openTabs == ["a", "b"])
        #expect(tabs.activeTab == "b")
    }

    @Test func openingAnOpenTabRefocusesWithoutDuplicating() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "c")
        tabs.open("a")
        #expect(tabs.openTabs == ["a", "b", "c"]) // no duplicate
        #expect(tabs.activeTab == "a")
    }

    @Test func openHasNoTabCap() {
        var tabs = TabState()
        let ids = (0..<40).map { "f\($0)" }
        for id in ids { tabs.open(id) }
        #expect(tabs.openTabs == ids)
        #expect(tabs.activeTab == "f39")
    }

    @Test func closingActiveTabFocusesTheRightNeighbor() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "b")
        tabs.close("b")
        #expect(tabs.openTabs == ["a", "c"])
        #expect(tabs.activeTab == "c") // the tab that slid into b's slot
    }

    @Test func closingTheRightmostActiveTabFocusesTheNewLast() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "c")
        tabs.close("c")
        #expect(tabs.openTabs == ["a", "b"])
        #expect(tabs.activeTab == "b")
    }

    @Test func closingAnInactiveTabKeepsTheActiveOne() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "c")
        tabs.close("a")
        #expect(tabs.openTabs == ["b", "c"])
        #expect(tabs.activeTab == "c")
    }

    @Test func closingTheLastTabClearsTheActiveTab() {
        var tabs = TabState(openTabs: ["a"], activeTab: "a")
        tabs.close("a")
        #expect(tabs.openTabs.isEmpty)
        #expect(tabs.activeTab == nil)
    }

    @Test func closingAnAbsentTabIsANoOp() {
        var tabs = TabState(openTabs: ["a", "b"], activeTab: "a")
        tabs.close("zzz")
        #expect(tabs.openTabs == ["a", "b"])
        #expect(tabs.activeTab == "a")
    }

    @Test func cyclingWrapsAround() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "c")
        tabs.activateNext()
        #expect(tabs.activeTab == "a") // wrap to first
        tabs.activatePrevious()
        #expect(tabs.activeTab == "c") // wrap back to last
        tabs.activatePrevious()
        #expect(tabs.activeTab == "b")
    }

    @Test func cyclingWithNoTabsIsANoOp() {
        var tabs = TabState()
        tabs.activateNext()
        #expect(tabs.activeTab == nil)
    }

    @Test func reorderMovesATabBeforeItsTargetAndKeepsActive() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "b")
        tabs.reorder("c", before: "a")
        #expect(tabs.openTabs == ["c", "a", "b"])
        #expect(tabs.activeTab == "b") // active unchanged by reordering
    }

    @Test func reorderWithNoTargetMovesToTheEnd() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "a")
        tabs.reorder("a", before: nil)
        #expect(tabs.openTabs == ["b", "c", "a"])
        #expect(tabs.activeTab == "a")
    }

    @Test func reorderIgnoresATabThatIsNotOpen() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "a")
        tabs.reorder("x", before: "a")
        #expect(tabs.openTabs == ["a", "b", "c"]) // unchanged
    }

    // MARK: - Pinning

    @Test func pinMovesATabToTheEndOfThePinnedPrefix() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "a")
        tabs.pin("c")
        #expect(tabs.openTabs == ["c", "a", "b"])
        #expect(tabs.pinnedTabs == ["c"])
        tabs.pin("b")
        #expect(tabs.openTabs == ["c", "b", "a"])
        #expect(tabs.pinnedTabs == ["c", "b"])
        #expect(tabs.activeTab == "a") // pinning never changes focus
    }

    @Test func pinningAnAlreadyPinnedOrAbsentTabIsANoOp() {
        var tabs = TabState(openTabs: ["a", "b"], activeTab: "a", pinnedCount: 1)
        tabs.pin("a")
        tabs.pin("gone")
        #expect(tabs.openTabs == ["a", "b"])
        #expect(tabs.pinnedCount == 1)
    }

    @Test func unpinDropsToTheFrontOfTheUnpinnedTabs() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "c", pinnedCount: 2)
        tabs.unpin("a")
        // Back where pinning took it from, not off to the end of the strip.
        #expect(tabs.openTabs == ["b", "a", "c"])
        #expect(tabs.pinnedTabs == ["b"])
    }

    @Test func unpinLandsAtTheFrontOfTheUnpinnedTabsNotBackWhereItStarted() {
        // Pinning doesn't record where the tab came from, so unpinning can't
        // put it back there — it lands at the boundary, which is where the eye
        // last saw it.
        var tabs = TabState(openTabs: ["a", "b", "c", "d"], activeTab: "b")
        tabs.pin("c")
        #expect(tabs.openTabs == ["c", "a", "b", "d"])
        tabs.unpin("c")
        #expect(tabs.openTabs == ["c", "a", "b", "d"])
        #expect(tabs.pinnedCount == 0)
    }

    @Test func closingAPinnedTabShrinksThePrefix() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "c", pinnedCount: 2)
        tabs.close("a")
        #expect(tabs.openTabs == ["b", "c"])
        #expect(tabs.pinnedTabs == ["b"]) // not ["b", "c"] — c was never pinned
    }

    @Test func closingAnUnpinnedTabLeavesThePrefixAlone() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "c", pinnedCount: 2)
        tabs.close("c")
        #expect(tabs.pinnedTabs == ["a", "b"])
    }

    @Test func openingANewTabLandsItUnpinned() {
        var tabs = TabState(openTabs: ["a"], activeTab: "a", pinnedCount: 1)
        tabs.open("b")
        #expect(tabs.openTabs == ["a", "b"])
        #expect(tabs.pinnedTabs == ["a"])
    }

    @Test func initClampsAPinnedCountLargerThanTheStrip() {
        // A persisted count can't outlive the tabs it counted.
        let tabs = TabState(openTabs: ["a"], activeTab: "a", pinnedCount: 4)
        #expect(tabs.pinnedCount == 1)
    }

    @Test func activateByIndexJumpsToThatTab() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "a")
        tabs.activate(index: 2)
        #expect(tabs.activeTab == "c")
        tabs.activate(index: 9) // out of range
        #expect(tabs.activeTab == "c")
    }

    @Test func initNormalizesAStaleActiveTab() {
        // A persisted activeTab pointing at a tab that's no longer open falls
        // back to the first open tab.
        let tabs = TabState(openTabs: ["a", "b"], activeTab: "gone")
        #expect(tabs.activeTab == "a")
    }

    @Test func initWithNoActiveTabPicksTheFirst() {
        let tabs = TabState(openTabs: ["a", "b"], activeTab: nil)
        #expect(tabs.activeTab == "a")
    }
}
