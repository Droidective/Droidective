import CoreGraphics
import Foundation

/// When a finished tab drag should tear a window off.
///
/// Pure, and separate from the AppKit drag source, because the decision has
/// three inputs that are each easy to get wrong and impossible to unit-test
/// through a real drag: whether anything accepted the drop, whether the drag
/// was cancelled, and whether the cursor was over one of our own windows.
enum TabDetachPolicy {
    /// Whether a screen point lies inside any of the app's own windows.
    ///
    /// A drop the app itself refused — the dead chrome beside the tabs, a pane
    /// with no target under the cursor — is a *miss*, not a request for a new
    /// window: it should snap back. Only a release genuinely away from the app
    /// means "put this somewhere else".
    static func isInsideApp(point: CGPoint, windowFrames: [CGRect]) -> Bool {
        windowFrames.contains { $0.contains(point) }
    }

    /// Whether a drag that has just ended should become a new window.
    ///
    /// - Parameters:
    ///   - accepted: whether any drop target took the tab. A drop that landed
    ///     on a tab strip or pane — in this window or another — is already
    ///     handled, and must not also spawn a window.
    ///   - cancelled: whether the user backed out with Escape. AppKit reports a
    ///     cancel exactly like a refused drop, at whatever point the cursor
    ///     happens to sit, so without this an Esc over the desktop would open a
    ///     window the user was in the middle of *not* asking for.
    ///   - point: where the drag ended, in screen coordinates.
    ///   - windowFrames: the app's own visible windows.
    static func shouldTearOff(
        accepted: Bool,
        cancelled: Bool,
        point: CGPoint,
        windowFrames: [CGRect]
    ) -> Bool {
        guard !accepted, !cancelled else { return false }
        return !isInsideApp(point: point, windowFrames: windowFrames)
    }
}
