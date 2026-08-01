import CoreGraphics

/// Layout policy for what a workspace pane's mounted content lays out at
/// during a continuous resize (a seam drag or the window's live resize).
///
/// Every open tab stays mounted (`TabHostView`'s keep-alive ZStack), so a
/// resize re-lays-out all of them on every drag tick. A hidden tab holding a
/// heavyweight layout — Crash Catcher's trace is one multi-thousand-line
/// `Text` — turns that into a multi-second main-thread stall (Sentry
/// DROIDECTIVE-MAC-54/-27: a 2k-line trace costs ~30 ms per tick, 8k lines
/// ~240 ms, superlinear). Pinning such content to its last resting size keeps
/// its layout proposal constant, so SwiftUI reuses the cached subtree layout
/// and a drag only pays for what's actually on screen; everything re-lays out
/// once when the resize rests.
enum PaneFreezePolicy {
    /// The fixed size a mounted tab pins to mid-resize, or nil to track the
    /// pane live. The active tab always tracks (the user is watching it), and
    /// hidden tabs track too until a resting size has been measured.
    static func pinnedSize(isActive: Bool, isResizing: Bool, resting: CGSize?) -> CGSize? {
        guard !isActive, isResizing, let resting, resting.width > 0, resting.height > 0 else {
            return nil
        }
        return resting
    }

    /// The fixed width a heavyweight text block pins to mid-resize *even
    /// while visible* (re-wrapping it per tick stalls the drag it's part of),
    /// or nil to track the pane live.
    static func pinnedWidth(isResizing: Bool, resting: CGFloat?) -> CGFloat? {
        guard isResizing, let resting, resting > 0 else { return nil }
        return resting
    }
}
