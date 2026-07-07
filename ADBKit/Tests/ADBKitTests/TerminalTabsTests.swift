import Foundation
import Testing
@testable import ADBKit

@Suite("TerminalTabs")
struct TerminalTabsTests {
    // MARK: - Adding

    @Test func addingATabWithNoGroupsCreatesTheDefaultGroup() {
        var tabs = TerminalTabs()
        let tab = UUID()
        tabs.add(tab: tab)
        #expect(tabs.groups.count == 1)
        #expect(tabs.groups[0].name == TerminalTabs.defaultGroupName)
        #expect(tabs.allTabIDs == [tab])
    }

    @Test func addingWithoutAGroupAppendsToTheLastGroup() {
        var tabs = TerminalTabs()
        tabs.addGroup(named: "Build")
        let device = tabs.addGroup(named: "Device")
        let tab = UUID()
        tabs.add(tab: tab)
        #expect(tabs.group(device)?.tabIDs == [tab])
    }

    @Test func addingToASpecificGroupLandsThere() {
        var tabs = TerminalTabs()
        let build = tabs.addGroup(named: "Build")
        tabs.addGroup(named: "Device")
        let tab = UUID()
        tabs.add(tab: tab, toGroup: build)
        #expect(tabs.group(build)?.tabIDs == [tab])
        #expect(tabs.groupID(ofTab: tab) == build)
    }

    @Test func addGroupFallsBackToDefaultNameWhenBlank() {
        var tabs = TerminalTabs()
        let id = tabs.addGroup(named: "   ")
        #expect(tabs.group(id)?.name == TerminalTabs.defaultGroupName)
    }

    // MARK: - Removing

    @Test func removingATabLeavesItsEmptyGroupInPlace() {
        var tabs = TerminalTabs()
        let tab = UUID()
        tabs.add(tab: tab)
        let removed = tabs.remove(tab: tab)
        #expect(removed)
        #expect(tabs.groups.count == 1)
        #expect(tabs.tabCount == 0)
    }

    @Test func removingAnUnknownTabReportsFalse() {
        var tabs = TerminalTabs()
        tabs.add(tab: UUID())
        let removed = tabs.remove(tab: UUID())
        #expect(!removed)
        #expect(tabs.tabCount == 1)
    }

    @Test func removingAGroupReturnsItsTabsInOrder() {
        var tabs = TerminalTabs()
        let group = tabs.addGroup(named: "Build")
        let a = UUID(), b = UUID()
        tabs.add(tab: a, toGroup: group)
        tabs.add(tab: b, toGroup: group)
        let evicted = tabs.removeGroup(group)
        #expect(evicted == [a, b])
        #expect(tabs.groups.isEmpty)
    }

    // MARK: - Renaming / collapsing

    @Test func renameTrimsAndIgnoresEmpty() {
        var tabs = TerminalTabs()
        let group = tabs.addGroup(named: "Build")
        tabs.renameGroup(group, to: "  Deploy  ")
        #expect(tabs.group(group)?.name == "Deploy")
        tabs.renameGroup(group, to: "   ")
        #expect(tabs.group(group)?.name == "Deploy")
    }

    @Test func collapseIsPerGroup() {
        var tabs = TerminalTabs()
        let a = tabs.addGroup(named: "A")
        let b = tabs.addGroup(named: "B")
        tabs.setCollapsed(a, true)
        #expect(tabs.group(a)?.isCollapsed == true)
        #expect(tabs.group(b)?.isCollapsed == false)
    }

    // MARK: - Moving tabs

    @Test func moveBeforeReordersWithinAGroup() {
        var tabs = TerminalTabs()
        let group = tabs.addGroup(named: "G")
        let a = UUID(), b = UUID(), c = UUID()
        for tab in [a, b, c] { tabs.add(tab: tab, toGroup: group) }
        tabs.move(tab: c, before: a)
        #expect(tabs.group(group)?.tabIDs == [c, a, b])
    }

    @Test func moveBeforeCrossesGroups() {
        var tabs = TerminalTabs()
        let build = tabs.addGroup(named: "Build")
        let device = tabs.addGroup(named: "Device")
        let a = UUID(), b = UUID()
        tabs.add(tab: a, toGroup: build)
        tabs.add(tab: b, toGroup: device)
        tabs.move(tab: a, before: b)
        #expect(tabs.group(build)?.tabIDs == [])
        #expect(tabs.group(device)?.tabIDs == [a, b])
        #expect(tabs.groupID(ofTab: a) == device)
    }

    @Test func moveBeforeItselfOrUnknownIsANoOp() {
        var tabs = TerminalTabs()
        let group = tabs.addGroup(named: "G")
        let a = UUID(), b = UUID()
        tabs.add(tab: a, toGroup: group)
        tabs.add(tab: b, toGroup: group)
        let before = tabs
        tabs.move(tab: a, before: a)
        tabs.move(tab: UUID(), before: a)
        tabs.move(tab: a, before: UUID())
        #expect(tabs == before)
    }

    @Test func moveDownWithinAGroupAccountsForTheRemovalShift() {
        var tabs = TerminalTabs()
        let group = tabs.addGroup(named: "G")
        let a = UUID(), b = UUID(), c = UUID()
        for tab in [a, b, c] { tabs.add(tab: tab, toGroup: group) }
        tabs.move(tab: a, before: c)
        #expect(tabs.group(group)?.tabIDs == [b, a, c])
    }

    @Test func moveToEndOfGroupAppends() {
        var tabs = TerminalTabs()
        let build = tabs.addGroup(named: "Build")
        let device = tabs.addGroup(named: "Device")
        let a = UUID(), b = UUID()
        tabs.add(tab: a, toGroup: build)
        tabs.add(tab: b, toGroup: device)
        tabs.move(tab: a, toEndOfGroup: device)
        #expect(tabs.group(device)?.tabIDs == [b, a])
        tabs.move(tab: b, toEndOfGroup: device)
        #expect(tabs.group(device)?.tabIDs == [a, b])
    }

    // MARK: - Moving groups

    @Test func moveGroupBeforeAndToEnd() {
        var tabs = TerminalTabs()
        let a = tabs.addGroup(named: "A")
        let b = tabs.addGroup(named: "B")
        let c = tabs.addGroup(named: "C")
        tabs.moveGroup(c, before: a)
        #expect(tabs.groups.map(\.id) == [c, a, b])
        tabs.moveGroupToEnd(c)
        #expect(tabs.groups.map(\.id) == [a, b, c])
    }

    @Test func moveGroupBeforeUnknownTargetKeepsItsPlace() {
        var tabs = TerminalTabs()
        let a = tabs.addGroup(named: "A")
        let b = tabs.addGroup(named: "B")
        tabs.moveGroup(a, before: UUID())
        #expect(tabs.groups.map(\.id) == [a, b])
    }

    // MARK: - Focus math

    @Test func neighborIsTheTabSlidingIntoTheSlot() {
        var tabs = TerminalTabs()
        let group = tabs.addGroup(named: "G")
        let a = UUID(), b = UUID(), c = UUID()
        for tab in [a, b, c] { tabs.add(tab: tab, toGroup: group) }
        #expect(tabs.neighbor(of: b) == c)
        #expect(tabs.neighbor(of: c) == b)   // last: falls back to previous
    }

    @Test func neighborCrossesGroupBoundaries() {
        var tabs = TerminalTabs()
        let build = tabs.addGroup(named: "Build")
        let device = tabs.addGroup(named: "Device")
        let a = UUID(), b = UUID()
        tabs.add(tab: a, toGroup: build)
        tabs.add(tab: b, toGroup: device)
        #expect(tabs.neighbor(of: a) == b)
        #expect(tabs.neighbor(of: b) == a)
    }

    @Test func neighborOfTheOnlyTabIsNil() {
        var tabs = TerminalTabs()
        let tab = UUID()
        tabs.add(tab: tab)
        #expect(tabs.neighbor(of: tab) == nil)
    }

    @Test func cycleWrapsAcrossGroupsInBothDirections() {
        var tabs = TerminalTabs()
        let build = tabs.addGroup(named: "Build")
        let device = tabs.addGroup(named: "Device")
        let a = UUID(), b = UUID(), c = UUID()
        tabs.add(tab: a, toGroup: build)
        tabs.add(tab: b, toGroup: build)
        tabs.add(tab: c, toGroup: device)
        #expect(tabs.tab(offset: 1, from: c) == a)    // wraps forward
        #expect(tabs.tab(offset: -1, from: a) == c)   // wraps backward
        #expect(tabs.tab(offset: 1, from: b) == c)    // crosses the boundary
    }

    @Test func cycleFromAnUnknownTabFallsToTheFirst() {
        var tabs = TerminalTabs()
        let a = UUID()
        tabs.add(tab: a)
        #expect(tabs.tab(offset: 1, from: UUID()) == a)
    }

    @Test func cycleWithNoTabsIsNil() {
        let tabs = TerminalTabs()
        #expect(tabs.tab(offset: 1, from: UUID()) == nil)
    }
}
