import Foundation
import Testing
@testable import ADBKit

@Suite("TerminalSplitTree")
struct TerminalSplitTreeTests {
    // MARK: - Single pane

    @Test func startsAsASinglePane() {
        let a = UUID()
        let tree = TerminalSplitTree(pane: a)
        #expect(tree.paneIDs == [a])
        #expect(tree.paneCount == 1)
        #expect(tree.contains(a))
    }

    // MARK: - Splitting

    @Test func splittingAddsThePaneAfterItsSource() {
        let a = UUID(), b = UUID()
        var tree = TerminalSplitTree(pane: a)
        let didSplit = tree.split(pane: a, direction: .vertical, adding: b)
        #expect(didSplit)
        #expect(tree.paneIDs == [a, b])
        #expect(tree.root == .split(.vertical, [.pane(a), .pane(b)]))
    }

    @Test func sameDirectionSplitInsertsAnEqualSibling() {
        let a = UUID(), b = UUID(), c = UUID()
        var tree = TerminalSplitTree(pane: a)
        tree.split(pane: a, direction: .vertical, adding: b)
        tree.split(pane: a, direction: .vertical, adding: c)
        // c slides in right after a — three flat siblings, not a nested split.
        #expect(tree.root == .split(.vertical, [.pane(a), .pane(c), .pane(b)]))
    }

    @Test func crossDirectionSplitNests() {
        let a = UUID(), b = UUID(), c = UUID()
        var tree = TerminalSplitTree(pane: a)
        tree.split(pane: a, direction: .vertical, adding: b)
        tree.split(pane: b, direction: .horizontal, adding: c)
        #expect(tree.root == .split(.vertical, [
            .pane(a),
            .split(.horizontal, [.pane(b), .pane(c)]),
        ]))
        #expect(tree.paneIDs == [a, b, c])
    }

    @Test func splittingAnUnknownPaneIsANoOp() {
        let a = UUID()
        var tree = TerminalSplitTree(pane: a)
        let didSplit = tree.split(pane: UUID(), direction: .vertical, adding: UUID())
        #expect(!didSplit)
        #expect(tree.paneIDs == [a])
    }

    @Test func splittingWithAnExistingPaneIdIsANoOp() {
        let a = UUID(), b = UUID()
        var tree = TerminalSplitTree(pane: a)
        tree.split(pane: a, direction: .vertical, adding: b)
        let didSplit = tree.split(pane: a, direction: .horizontal, adding: b)
        #expect(!didSplit)
    }

    // MARK: - Removing

    @Test func removingAPaneCollapsesTheSplit() {
        let a = UUID(), b = UUID()
        var tree = TerminalSplitTree(pane: a)
        tree.split(pane: a, direction: .vertical, adding: b)
        let didRemove = tree.remove(pane: b)
        #expect(didRemove)
        #expect(tree.root == .pane(a))
    }

    @Test func removingFromThreeSiblingsKeepsTheOthersFlat() {
        let a = UUID(), b = UUID(), c = UUID()
        var tree = TerminalSplitTree(pane: a)
        tree.split(pane: a, direction: .vertical, adding: b)
        tree.split(pane: b, direction: .vertical, adding: c)
        tree.remove(pane: b)
        #expect(tree.root == .split(.vertical, [.pane(a), .pane(c)]))
    }

    @Test func collapsingANestedSplitMergesIntoASameDirectionParent() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var tree = TerminalSplitTree(pane: a)
        tree.split(pane: a, direction: .vertical, adding: b)
        tree.split(pane: b, direction: .horizontal, adding: c)
        tree.split(pane: c, direction: .vertical, adding: d)
        // Removing b collapses the horizontal split to its remaining child —
        // a vertical split — which flattens into the vertical parent.
        tree.remove(pane: b)
        #expect(tree.root == .split(.vertical, [.pane(a), .pane(c), .pane(d)]))
    }

    @Test func removingTheLastPaneEmptiesTheTree() {
        let a = UUID()
        var tree = TerminalSplitTree(pane: a)
        let didRemove = tree.remove(pane: a)
        #expect(didRemove)
        #expect(tree.paneIDs.isEmpty)
        #expect(tree.root == nil)
    }

    @Test func removingAnUnknownPaneIsANoOp() {
        let a = UUID()
        var tree = TerminalSplitTree(pane: a)
        let didRemove = tree.remove(pane: UUID())
        #expect(!didRemove)
        #expect(tree.paneIDs == [a])
    }

    // MARK: - Focus math

    @Test func neighborIsTheNextPaneOrThePreviousWhenLast() {
        let a = UUID(), b = UUID(), c = UUID()
        var tree = TerminalSplitTree(pane: a)
        tree.split(pane: a, direction: .vertical, adding: b)
        tree.split(pane: b, direction: .horizontal, adding: c)
        #expect(tree.neighbor(of: a) == b)
        #expect(tree.neighbor(of: c) == b)
        #expect(tree.neighbor(of: UUID()) == nil)
    }

    @Test func neighborOfTheOnlyPaneIsNil() {
        let a = UUID()
        let tree = TerminalSplitTree(pane: a)
        #expect(tree.neighbor(of: a) == nil)
    }
}
