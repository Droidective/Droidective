import Foundation

/// The one table deciding what a dropped tab does — the tab-drag twin of
/// `FileDropRouter`.
///
/// A tab can now be dropped on four kinds of place (its own strip, its own
/// pane, *another window's* strip, another window's pane) and the answer
/// differs in ways that are easy to get subtly wrong: a tab arriving from
/// elsewhere must never split the window it lands in, and a split must only be
/// promised when there is something to leave behind. Keeping the decision here,
/// pure, means the drop targets and the hover previews read the same rule
/// instead of two hand-written approximations of it.
public enum TabDropRouter {
    /// A tab drag in flight: what is moving, and which window it left.
    public struct Drag: Sendable, Equatable {
        public let featureID: String
        public let source: WorkspaceID

        public init(featureID: String, source: WorkspaceID) {
            self.featureID = featureID
            self.source = source
        }
    }

    /// Where the drop landed.
    public enum Target: Sendable, Equatable {
        /// A pane's tab strip — precise placement, and never a split.
        case strip(group: Int, before: String?)
        /// A pane's content. In a split window this means "move into this
        /// pane"; in a single-pane window it is the drop-to-split gesture.
        case pane(group: Int)
    }

    /// What to do about it.
    public enum Outcome: Sendable, Equatable {
        /// Nothing: the tab was dropped where it already is.
        case ignore
        /// Place it within the window that already holds it.
        case place(group: Int, before: String?)
        /// Split this window's single pane, moving the tab into the new one.
        case split
        /// It belongs to another window — move it here, at this slot.
        case handoff(source: WorkspaceID, group: Int, before: String?)
    }

    /// The receiving window's shape, as far as this decision cares.
    public struct Shape: Sendable, Equatable {
        /// Whether the window already has two panes.
        public let isSplit: Bool
        /// How many tabs the dropped-on pane holds.
        public let paneTabCount: Int

        public init(isSplit: Bool, paneTabCount: Int) {
            self.isSplit = isSplit
            self.paneTabCount = paneTabCount
        }
    }

    /// Where a dropped tab should go.
    ///
    /// - Parameters:
    ///   - drag: the tab in flight and the window it came from.
    ///   - window: the window the drop landed in.
    ///   - target: the strip slot or pane under the cursor.
    ///   - shape: the receiving window's panes.
    public static func outcome(
        drag: Drag,
        window: WorkspaceID,
        target: Target,
        shape: Shape
    ) -> Outcome {
        // A tab from another window is being *moved in*, never split off: the
        // user is consolidating, and a split the receiver did not ask for is an
        // extra pane to undo. A cross-window drop on a pane therefore behaves
        // like a drop on that pane's strip.
        guard drag.source == window else {
            switch target {
            case .strip(let group, let before):
                return .handoff(source: drag.source, group: group, before: before)
            case .pane(let group):
                return .handoff(source: drag.source, group: group, before: nil)
            }
        }

        switch target {
        case .strip(let group, let before):
            // Dropped on itself: `SidebarOrdering` would treat it as a no-op
            // anyway, but saying so here keeps the guideline and the action
            // agreeing about when nothing is going to happen.
            guard before != drag.featureID else { return .ignore }
            return .place(group: group, before: before)

        case .pane(let group):
            guard !shape.isSplit else { return .place(group: group, before: nil) }
            // Only promise a split the workspace will honour: `Workspace.split`
            // requires something to stay behind, so a lone tab dropped on its
            // own pane does nothing rather than showing a preview that lies.
            return shape.paneTabCount > 1 ? .split : .ignore
        }
    }
}
