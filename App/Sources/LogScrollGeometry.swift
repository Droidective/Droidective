import SwiftUI

/// Spatial edge state of a scrollable log pane: which ends the viewport is
/// touching and whether there is anywhere to scroll at all. Produced by the
/// pane (`LogTailViewV2`, `SelectableLogView`), consumed by `LogJumpControls`.
struct LogScrollEdges: Equatable {
    var atTop = true
    var atBottom = true
    var isScrollable = false
}

/// A one-shot scroll command for AppKit-backed panes: bump `token` with the
/// target `edge` and the pane snaps there once.
struct LogJumpRequest: Equatable {
    var token = 0
    var edge: VerticalEdge = .bottom
}

/// Pure scroll-state derivation for `LogTailViewV2` — measured heights and the
/// content's leading-edge offset in, edge/scrollability answers out. Kept free
/// of view code so the tolerance and boundary rules are unit-tested directly.
struct TailGeometry: Equatable {
    /// Signed offset of the content's leading (newest-first) edge in the
    /// scroll's coordinate space: ~0 while parked at the newest edge, growing
    /// in magnitude as the user scrolls into history. The sign flips with the
    /// layout flip, so every rule below compares the magnitude.
    var contentLeadingOffset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    /// How far (points) the content may sit from an edge and still count as
    /// touching it, covering sub-pixel rounding and a tail auto-scroll.
    static let edgeTolerance: CGFloat = 24

    var distanceFromNewest: CGFloat { abs(contentLeadingOffset) }
    /// The full scrollable span; 0 when the content fits the viewport.
    var scrollRange: CGFloat { max(0, contentHeight - viewportHeight) }
    var isScrollable: Bool { scrollRange > 1 }
    var atNewestEdge: Bool { distanceFromNewest <= Self.edgeTolerance }
    var atOldestEdge: Bool { distanceFromNewest >= scrollRange - Self.edgeTolerance }

    /// The spatial reading of the two logical edges for a feed whose newest
    /// line lands on `newestEdge` — what the shared jump controls consume.
    func edges(newestEdge: VerticalEdge) -> LogScrollEdges {
        LogScrollEdges(
            atTop: newestEdge == .top ? atNewestEdge : atOldestEdge,
            atBottom: newestEdge == .bottom ? atNewestEdge : atOldestEdge,
            isScrollable: isScrollable
        )
    }
}
