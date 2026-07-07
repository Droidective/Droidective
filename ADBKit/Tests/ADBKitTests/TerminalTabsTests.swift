import Foundation
import Testing
@testable import ADBKit

@Suite("TerminalTabs")
struct TerminalTabsTests {
    // MARK: - Loose tabs by default

    @Test func tabsAreLooseByDefault() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        #expect(tabs.groups.isEmpty)
        #expect(tabs.allTabIDs == [a, b])
        #expect(tabs.groupID(ofTab: a) == nil)
    }

    @Test func addingToAGroupLandsThere() {
        var tabs = TerminalTabs()
        let a = UUID()
        tabs.add(tab: a)
        let group = tabs.newGroup(named: "Build", containing: a)!
        let b = UUID()
        tabs.add(tab: b, toGroup: group)
        #expect(tabs.group(group)?.tabIDs == [a, b])
        #expect(tabs.groupID(ofTab: b) == group)
    }

    // MARK: - Creating groups

    @Test func newGroupWrapsALooseTabInPlace() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID(), c = UUID()
        for tab in [a, b, c] { tabs.add(tab: tab) }
        let group = tabs.newGroup(named: "Mid", containing: b)!
        // b's slot is now a group; a and c stay loose around it.
        #expect(tabs.allTabIDs == [a, b, c])
        #expect(tabs.groupID(ofTab: b) == group)
        #expect(tabs.groupID(ofTab: a) == nil)
        #expect(tabs.groupID(ofTab: c) == nil)
    }

    @Test func newGroupNameFallsBackWhenBlank() {
        var tabs = TerminalTabs()
        let a = UUID()
        tabs.add(tab: a)
        let group = tabs.newGroup(named: "   ", containing: a)!
        #expect(tabs.group(group)?.name == TerminalTabs.defaultGroupName)
    }

    @Test func newGroupOnAnUnknownTabIsNil() {
        var tabs = TerminalTabs()
        #expect(tabs.newGroup(named: "X", containing: UUID()) == nil)
    }

    @Test func newGroupFromAGroupedTabMovesItOut() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        let first = tabs.newGroup(named: "First", containing: a)!
        tabs.move(tab: b, toEndOfGroup: first)
        // Now re-group b into its own group; First keeps a and survives.
        let second = tabs.newGroup(named: "Second", containing: b)!
        #expect(tabs.group(first)?.tabIDs == [a])
        #expect(tabs.group(second)?.tabIDs == [b])
    }

    // MARK: - Auto-deleting empty groups

    @Test func removingTheLastTabDeletesItsGroup() {
        var tabs = TerminalTabs()
        let a = UUID()
        tabs.add(tab: a)
        tabs.newGroup(named: "Solo", containing: a)
        let removed = tabs.remove(tab: a)
        #expect(removed)
        #expect(tabs.groups.isEmpty)
        #expect(tabs.tabCount == 0)
    }

    @Test func removingANonLastTabKeepsTheGroup() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        let group = tabs.newGroup(named: "Pair", containing: a)!
        tabs.move(tab: b, toEndOfGroup: group)   // b is loose after add? add first
        tabs.add(tab: b)
        tabs.move(tab: b, toEndOfGroup: group)
        let removed = tabs.remove(tab: a)
        #expect(removed)
        #expect(tabs.group(group)?.tabIDs == [b])
    }

    @Test func draggingTheLastTabOutDeletesTheGroup() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        let group = tabs.newGroup(named: "G", containing: b)!
        // Drag b out to become loose — its group empties and vanishes.
        tabs.moveToLooseEnd(tab: b)
        #expect(tabs.group(group) == nil)
        #expect(tabs.groups.isEmpty)
        #expect(tabs.allTabIDs == [a, b])
        #expect(tabs.groupID(ofTab: b) == nil)
    }

    // MARK: - Removing

    @Test func removingAnUnknownTabReportsFalse() {
        var tabs = TerminalTabs()
        tabs.add(tab: UUID())
        let removed = tabs.remove(tab: UUID())
        #expect(!removed)
        #expect(tabs.tabCount == 1)
    }

    @Test func removeGroupReturnsItsTabsInOrder() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        let group = tabs.newGroup(named: "G", containing: a)!
        tabs.add(tab: b, toGroup: group)
        let evicted = tabs.removeGroup(group)
        #expect(evicted == [a, b])
        #expect(tabs.groups.isEmpty)
    }

    // MARK: - Renaming / collapsing

    @Test func renameTrimsAndIgnoresEmpty() {
        var tabs = TerminalTabs()
        let a = UUID()
        tabs.add(tab: a)
        let group = tabs.newGroup(named: "Build", containing: a)!
        tabs.renameGroup(group, to: "  Deploy  ")
        #expect(tabs.group(group)?.name == "Deploy")
        tabs.renameGroup(group, to: "   ")
        #expect(tabs.group(group)?.name == "Deploy")
    }

    @Test func collapseIsPerGroup() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        let first = tabs.newGroup(named: "A", containing: a)!
        let second = tabs.newGroup(named: "B", containing: b)!
        tabs.setCollapsed(first, true)
        #expect(tabs.group(first)?.isCollapsed == true)
        #expect(tabs.group(second)?.isCollapsed == false)
    }

    // MARK: - Moving tabs

    @Test func moveBeforeReordersLooseTabs() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID(), c = UUID()
        for tab in [a, b, c] { tabs.add(tab: tab) }
        tabs.move(tab: c, before: a)
        #expect(tabs.allTabIDs == [c, a, b])
        #expect(tabs.groups.isEmpty)
    }

    @Test func moveBeforeAGroupedTabJoinsThatGroup() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        let group = tabs.newGroup(named: "G", containing: b)!
        tabs.move(tab: a, before: b)
        #expect(tabs.group(group)?.tabIDs == [a, b])
        #expect(tabs.groupID(ofTab: a) == group)
    }

    @Test func moveBeforeALooseTabLeavesTheGroup() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID(), c = UUID()
        tabs.add(tab: a)   // loose
        tabs.add(tab: b)
        tabs.add(tab: c)
        let group = tabs.newGroup(named: "G", containing: b)!
        tabs.move(tab: c, toEndOfGroup: group)   // group holds b, c
        tabs.move(tab: c, before: a)             // pull c out, before loose a
        #expect(tabs.groupID(ofTab: c) == nil)
        #expect(tabs.group(group)?.tabIDs == [b])
        #expect(tabs.allTabIDs == [c, a, b])
    }

    @Test func moveBeforeItselfOrUnknownIsANoOp() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        let before = tabs
        tabs.move(tab: a, before: a)
        tabs.move(tab: UUID(), before: a)
        tabs.move(tab: a, before: UUID())
        #expect(tabs == before)
    }

    @Test func moveToEndOfGroupCrossesFromLoose() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        let group = tabs.newGroup(named: "G", containing: a)!
        tabs.move(tab: b, toEndOfGroup: group)
        #expect(tabs.group(group)?.tabIDs == [a, b])
    }

    @Test func moveToEndOfGroupOfTheSoleTabIsANoOp() {
        var tabs = TerminalTabs()
        let a = UUID()
        tabs.add(tab: a)
        let group = tabs.newGroup(named: "G", containing: a)!
        let before = tabs
        tabs.move(tab: a, toEndOfGroup: group)
        #expect(tabs == before)
    }

    @Test func moveToEndOfGroupWithUnknownIDsIsANoOp() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        let group = tabs.newGroup(named: "G", containing: a)!
        let before = tabs
        tabs.move(tab: b, toEndOfGroup: UUID())       // unknown group
        tabs.move(tab: UUID(), toEndOfGroup: group)   // unknown tab
        #expect(tabs == before)
    }

    // MARK: - Moving groups

    @Test func moveGroupBeforeAndToEnd() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID(), c = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        tabs.add(tab: c)
        let first = tabs.newGroup(named: "A", containing: a)!
        let second = tabs.newGroup(named: "B", containing: b)!
        let third = tabs.newGroup(named: "C", containing: c)!
        tabs.moveGroup(third, before: first)
        #expect(tabs.groups.map(\.id) == [third, first, second])
        tabs.moveGroupToEnd(third)
        #expect(tabs.groups.map(\.id) == [first, second, third])
    }

    @Test func moveGroupBeforeALooseTabInterleaves() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)   // loose, first
        tabs.add(tab: b)
        let group = tabs.newGroup(named: "G", containing: b)!   // group, second
        tabs.moveGroup(group, before: a)
        #expect(tabs.allTabIDs == [b, a])
    }

    @Test func moveGroupForwardAccountsForTheRemovalShift() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID(), c = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        tabs.add(tab: c)
        let first = tabs.newGroup(named: "A", containing: a)!
        let second = tabs.newGroup(named: "B", containing: b)!
        let third = tabs.newGroup(named: "C", containing: c)!
        // Forward move: the target is re-found after the group is removed.
        tabs.moveGroup(first, before: third)
        #expect(tabs.groups.map(\.id) == [second, first, third])
    }

    @Test func moveGroupBeforeUnknownTargetKeepsItsPlace() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        let first = tabs.newGroup(named: "A", containing: a)!
        let second = tabs.newGroup(named: "B", containing: b)!
        tabs.moveGroup(first, before: UUID())
        #expect(tabs.groups.map(\.id) == [first, second])
    }

    // MARK: - Focus math

    @Test func neighborCrossesLooseAndGroupedTabs() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID(), c = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        tabs.add(tab: c)
        tabs.newGroup(named: "G", containing: b)
        #expect(tabs.neighbor(of: b) == c)
        #expect(tabs.neighbor(of: c) == b)
    }

    @Test func neighborOfTheOnlyTabIsNil() {
        var tabs = TerminalTabs()
        let tab = UUID()
        tabs.add(tab: tab)
        #expect(tabs.neighbor(of: tab) == nil)
    }

    @Test func cycleWrapsAcrossGroupsInBothDirections() {
        var tabs = TerminalTabs()
        let a = UUID(), b = UUID(), c = UUID()
        tabs.add(tab: a)
        tabs.add(tab: b)
        tabs.add(tab: c)
        let group = tabs.newGroup(named: "G", containing: a)!
        tabs.move(tab: b, toEndOfGroup: group)   // group: a, b ; loose: c
        #expect(tabs.tab(offset: 1, from: c) == a)
        #expect(tabs.tab(offset: -1, from: a) == c)
        #expect(tabs.tab(offset: 1, from: b) == c)
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
