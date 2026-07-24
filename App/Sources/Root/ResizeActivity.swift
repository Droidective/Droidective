import AppKit
import SwiftUI

/// Whether the user is mid-continuous-resize: a seam drag (the sidebar handle
/// or the split divider) or the main window's live resize. Panes observe it to
/// pin heavyweight content at its resting size (`PaneFreezePolicy`) so a drag
/// doesn't re-lay-out offscreen tabs on every tick.
///
/// A main-actor singleton, like `WindowMinSizeGuard` — the notification
/// closures re-enter through `shared`, which keeps them Swift-6 clean without
/// capturing a non-Sendable instance.
@MainActor
@Observable
final class ResizeActivity {
    static let shared = ResizeActivity()

    /// A seam drag is in flight — mirrored from RootView's transient drag
    /// state by `ResizeActivityBridge`.
    var seamDragging = false
    /// The tracked window is inside a live user resize.
    private(set) var windowResizing = false

    var isActive: Bool { seamDragging || windowResizing }

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Follow `window`'s live-resize lifecycle. Re-entrant: tracking a new
    /// window (the main window was closed and reopened) drops the previous
    /// observers first.
    func track(_ window: NSWindow) {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = [
            center.addObserver(
                forName: NSWindow.willStartLiveResizeNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { ResizeActivity.shared.windowResizing = true }
            },
            center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { ResizeActivity.shared.windowResizing = false }
            },
        ]
    }
}

/// RootView's single chain link for resize activity: injects the shared
/// instance into the environment and mirrors the seam-drag state into it
/// (drag transitions only — never per tick).
struct ResizeActivityBridge: ViewModifier {
    let seamDragging: Bool

    func body(content: Content) -> some View {
        content
            .environment(ResizeActivity.shared)
            .onChange(of: seamDragging) { _, dragging in
                ResizeActivity.shared.seamDragging = dragging
            }
    }
}
