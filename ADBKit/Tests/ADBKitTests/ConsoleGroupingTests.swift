@testable import ADBKit
import Testing

/// `ConsoleGroupTracker` — the JS console's `console.group` nesting.
struct ConsoleGroupingTests {
    @Test func groupHeaderSitsAtTheOuterDepthAndItsRowsIndent() {
        var tracker = ConsoleGroupTracker()
        #expect(tracker.placement(for: "log", id: 1) == .entry(depth: 0, path: []))
        #expect(tracker.placement(for: "startGroup", id: 2) == .groupStart(depth: 0, path: [], collapsed: false))
        #expect(tracker.placement(for: "log", id: 3) == .entry(depth: 1, path: [2]))
        #expect(tracker.placement(for: "startGroupCollapsed", id: 4)
            == .groupStart(depth: 1, path: [2], collapsed: true))
        #expect(tracker.placement(for: "log", id: 5) == .entry(depth: 2, path: [2, 4]))
        #expect(tracker.placement(for: "endGroup", id: 6) == .groupEnd)
        #expect(tracker.placement(for: "log", id: 7) == .entry(depth: 1, path: [2]))
        #expect(tracker.placement(for: "endGroup", id: 8) == .groupEnd)
        #expect(tracker.placement(for: "log", id: 9) == .entry(depth: 0, path: []))
    }

    /// `console.groupEnd` shows no row — rendering it produced the empty rows
    /// that trailed every grouped burst.
    @Test func groupEndNeverProducesARow() {
        var tracker = ConsoleGroupTracker()
        #expect(tracker.placement(for: "endGroup", id: 1) == .groupEnd)
    }

    /// An app that throws between `group` and `groupEnd` never closes it, and a
    /// stray `groupEnd` is just as common — neither may drive the depth negative
    /// or strand the rest of the feed indented.
    @Test func unbalancedGroupsClampAndReset() {
        var tracker = ConsoleGroupTracker()
        _ = tracker.placement(for: "endGroup", id: 1)
        _ = tracker.placement(for: "endGroup", id: 2)
        #expect(tracker.depth == 0)
        #expect(tracker.placement(for: "log", id: 3) == .entry(depth: 0, path: []))

        _ = tracker.placement(for: "startGroup", id: 4)
        _ = tracker.placement(for: "startGroup", id: 5)
        #expect(tracker.depth == 2)
        #expect(tracker.open == [4, 5])
        tracker.reset()
        #expect(tracker.placement(for: "log", id: 6) == .entry(depth: 0, path: []))
    }

    /// The path is what a collapsed header hides by: every row inside it, at
    /// any nesting, names it.
    @Test func everyRowInsideAGroupNamesIt() {
        var tracker = ConsoleGroupTracker()
        _ = tracker.placement(for: "startGroup", id: 10)
        _ = tracker.placement(for: "startGroup", id: 20)
        guard case let .entry(_, path) = tracker.placement(for: "log", id: 30) else {
            Issue.record("expected an ordinary row")
            return
        }
        #expect(path.contains(10))
        #expect(path.contains(20))
    }

    @Test func everyOtherConsoleTypeIsAnOrdinaryRow() {
        var tracker = ConsoleGroupTracker()
        for type in ["log", "warning", "error", "info", "debug", "table", "assert", "dir", "trace"] {
            #expect(tracker.placement(for: type, id: 1) == .entry(depth: 0, path: []),
                    "\(type) should be an ordinary row")
        }
    }
}
