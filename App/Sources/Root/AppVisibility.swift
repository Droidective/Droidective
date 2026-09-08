import AppKit
import Foundation

/// Whether any of the app's windows is actually on screen, as the window
/// server sees it.
///
/// The streaming feeds need this because "watched" was inferred from two things
/// that both lie about it. `NSApp.isActive` says whether we are frontmost, not
/// whether we are *visible* — an app behind another window is inactive but may
/// be fully readable beside it. And a tab being the front tab of its pane
/// (`tabIsActive`) says nothing about the window that pane is in.
///
/// Between them they produced the shape of DROIDECTIVE-MAC-B: a user with the
/// app behind another window and a Reactotron tab in front, so the feed scored
/// as watched-but-inactive and re-published every second for twenty-four
/// minutes while nobody could see a thing. `occlusionState` is the window
/// server's own answer to the question, so it is the one worth asking.
///
/// `@Observable` on purpose, unlike `MainThreadLoad`: this changes when the
/// user switches app or covers a window — a few times an hour, not twice a
/// second — so the feed views can simply read it and re-report their
/// visibility through the path they already use.
@MainActor
@Observable
final class AppVisibility {
    static let shared = AppVisibility()

    /// True while at least one window that can front the app is unoccluded.
    ///
    /// Starts true so a feed mounted before the first notification behaves as
    /// it always did, and errs that way in general: over-reporting visibility
    /// pays for layout nobody reads, while under-reporting would stall a feed
    /// somebody is watching. `FeedAudience` leans the same way, for the same
    /// reason.
    private(set) var hasVisibleWindow = true

    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Begin observing. Idempotent — every window's launch setup may call it.
    func start() {
        guard observers.isEmpty else { return }
        // `object: nil`, and recomputed from `NSApp.windows` rather than
        // tracked per window: an app-wide singleton that re-points at the
        // newest window silently drops the others (see the multi-window
        // convention in CLAUDE.md), and the answer here is a fold over every
        // window anyway.
        let center = NotificationCenter.default
        for name: NSNotification.Name in [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
            // Activation is part of the answer (see `recompute`), so a change
            // in it has to re-ask the question.
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppVisibility.shared.recompute() }
            })
        }
        recompute()
    }

    private func recompute() {
        // Frontmost counts as visible without consulting occlusion at all.
        // `occlusionState` is the window server's answer and it is the right
        // one, but a wrong answer in the stalling direction would freeze a
        // feed somebody is reading — the one failure worse than the cost this
        // saves. If we are the app in front, someone is looking at us.
        let visible = NSApp.isActive || NSApp.windows.contains { window in
            // `canBecomeMain` narrows this to the windows that show features —
            // the workspace windows and the pop-out mirrors — so the Quick
            // Actions panel being on screen does not make a covered timeline
            // count as watched.
            window.canBecomeMain
                && window.isVisible
                && !window.isMiniaturized
                && window.occlusionState.contains(.visible)
        }
        // Guarded: this is `@Observable` and the feed views read it, so an
        // unconditional write would invalidate them on every occlusion
        // notification — including the ones that changed nothing.
        guard visible != hasVisibleWindow else { return }
        hasVisibleWindow = visible
    }
}
