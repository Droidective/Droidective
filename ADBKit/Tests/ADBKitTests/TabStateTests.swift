import Foundation
import Testing
@testable import ADBKit

@Suite struct TabStateTests {
    @Test func opensAndActivatesNewTabs() {
        var tabs = TabState()
        let a = tabs.open("a")
        let b = tabs.open("b")
        #expect(a)
        #expect(b)
        #expect(tabs.openTabs == ["a", "b"])
        #expect(tabs.activeTab == "b")
    }

    @Test func openingAnOpenTabRefocusesWithoutDuplicating() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "c")
        let reopened = tabs.open("a")
        #expect(reopened)
        #expect(tabs.openTabs == ["a", "b", "c"]) // no duplicate
        #expect(tabs.activeTab == "a")
    }

    @Test func openRefusesANewTabAtTheCapButStillRefocusesOpenOnes() {
        let ids = (0..<TabState.maxTabs).map { "f\($0)" }
        var tabs = TabState(openTabs: ids, activeTab: ids.last)
        let overflow = tabs.open("overflow")            // new tab blocked at cap
        #expect(overflow == false)
        #expect(tabs.openTabs == ids)
        let refocus = tabs.open("f0")                    // already-open still focuses
        #expect(refocus)
        #expect(tabs.activeTab == "f0")
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

    @Test func reorderAdoptsAPermutationAndKeepsActive() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "b")
        tabs.reorder(["c", "a", "b"])
        #expect(tabs.openTabs == ["c", "a", "b"])
        #expect(tabs.activeTab == "b") // active unchanged by reordering
    }

    @Test func reorderIgnoresNonPermutations() {
        var tabs = TabState(openTabs: ["a", "b", "c"], activeTab: "a")
        tabs.reorder(["a", "b"])            // missing c
        tabs.reorder(["a", "b", "c", "d"])  // extra d
        tabs.reorder(["a", "b", "x"])       // swapped id
        #expect(tabs.openTabs == ["a", "b", "c"]) // unchanged
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
