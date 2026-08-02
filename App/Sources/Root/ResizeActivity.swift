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
    /// Windows currently inside a live resize. A set, not a flag: with several
    /// windows open, one finishing its resize must not clear the state for
    /// another that is still being dragged.
    @ObservationIgnored private var resizing: Set<ObjectIdentifier> = []

    private init() {
        // Observed app-wide (`object: nil`) rather than per window — windows
        // come and go, and every one of them should freeze heavyweight panes
        // while it's being dragged.
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.willStartLiveResizeNotification, object: nil, queue: .main
            ) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated { ResizeActivity.shared.setResizing(true, window) }
            },
            center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification, object: nil, queue: .main
            ) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated { ResizeActivity.shared.setResizing(false, window) }
            },
        ]
    }

    private func setResizing(_ active: Bool, _ window: NSWindow?) {
        guard let window else { return }
        let key = ObjectIdentifier(window)
        if active {
            resizing.insert(key)
        } else {
            resizing.remove(key)
        }
        windowResizing = !resizing.isEmpty
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
