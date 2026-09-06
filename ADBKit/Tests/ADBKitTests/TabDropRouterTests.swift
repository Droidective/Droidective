import Foundation
import Testing
@testable import ADBKit

/// What a dropped tab does, by where it came from and where it landed.
@Suite struct TabDropRouterTests {
    private let here = WorkspaceID("here")
    private let there = WorkspaceID("there")

    private func drag(_ featureID: String = "logcat", from source: WorkspaceID) -> TabDropRouter.Drag {
        TabDropRouter.Drag(featureID: featureID, source: source)
    }

    private func outcome(
        _ drag: TabDropRouter.Drag,
        _ target: TabDropRouter.Target,
        isSplit: Bool = false,
        paneTabCount: Int = 3
    ) -> TabDropRouter.Outcome {
        TabDropRouter.outcome(
            drag: drag,
            window: here,
            target: target,
            shape: TabDropRouter.Shape(isSplit: isSplit, paneTabCount: paneTabCount))
    }

    // MARK: - Within the window that owns the tab

    @Test func aDropOnItsOwnStripPlacesTheTab() {
        #expect(outcome(drag(from: here), .strip(group: 0, before: "wifi"))
            == .place(group: 0, before: "wifi"))
    }

    @Test func aDropOnTheStripsDeadSpacePlacesItAtTheEnd() {
        #expect(outcome(drag(from: here), .strip(group: 1, before: nil))
            == .place(group: 1, before: nil))
    }

    @Test func aDropOnTheTabItselfIsIgnored() {
        #expect(outcome(drag("logcat", from: here), .strip(group: 0, before: "logcat")) == .ignore)
    }

    @Test func aDropOnAPaneOfASplitWindowMovesItIntoThatPane() {
        #expect(outcome(drag(from: here), .pane(group: 1), isSplit: true)
            == .place(group: 1, before: nil))
    }

    @Test func aDropOnTheOnlyPanesContentSplitsIt() {
        #expect(outcome(drag(from: here), .pane(group: 0), isSplit: false, paneTabCount: 2) == .split)
    }

    /// The preview and the action have to agree: `Workspace.split` refuses when
    /// nothing would stay behind, so this must not offer a split either.
    @Test func aLoneTabDroppedOnItsOwnPaneDoesNothing() {
        #expect(outcome(drag(from: here), .pane(group: 0), isSplit: false, paneTabCount: 1) == .ignore)
    }

    // MARK: - From another window

    @Test func aTabFromAnotherWindowLandingOnTheStripIsAHandoffAtThatSlot() {
        #expect(outcome(drag(from: there), .strip(group: 1, before: "wifi"))
            == .handoff(source: there, group: 1, before: "wifi"))
    }

    /// The rule worth having a test for: consolidating into a window must not
    /// silently split it.
    @Test func aTabFromAnotherWindowNeverSplitsTheReceiver() {
        #expect(outcome(drag(from: there), .pane(group: 0), isSplit: false, paneTabCount: 5)
            == .handoff(source: there, group: 0, before: nil))
    }

    @Test func aTabFromAnotherWindowLandingOnASplitPaneGoesToThatPane() {
        #expect(outcome(drag(from: there), .pane(group: 1), isSplit: true)
            == .handoff(source: there, group: 1, before: nil))
    }

    /// Two windows can each hold a tab with the same id, so "the id matches the
    /// drop target" is not the same question as "it was dropped on itself".
    /// Only the second is a no-op; the first is a merge.
    @Test func aSameIdTabFromAnotherWindowIsAHandoffNotAnIgnore() {
        #expect(outcome(drag("logcat", from: there), .strip(group: 0, before: "logcat"))
            == .handoff(source: there, group: 0, before: "logcat"))
    }

    @Test func aLoneTabFromAnotherWindowStillMovesIn() {
        // `paneTabCount` describes the *receiver*; whether the source has
        // anything left is `Workspace.canDetach`'s question, asked earlier.
        #expect(outcome(drag(from: there), .pane(group: 0), isSplit: false, paneTabCount: 1)
            == .handoff(source: there, group: 0, before: nil))
    }
}
