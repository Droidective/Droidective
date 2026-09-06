import SwiftUI

/// Per-tab context handed down by the tab host (`TabHostView`). Open tabs all
/// stay mounted at once, so a view can't assume it's the one on screen — these
/// tell it which tab it lives in and whether that tab is currently visible.

private struct TabIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

private struct TabFeatureIDKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    /// True when this view's tab is the foreground (visible) one. Backgrounded
    /// tabs stay mounted, so device-heavy *live* views (network/CPU polling, the
    /// screen mirror) read this to pause while hidden. Recordings and log streams
    /// deliberately ignore it and keep *running* — but they pace their flushing
    /// by it (`reportsFeedVisibility`, `FeedFlushCadence.hidden`), because a
    /// mounted hidden tab lays its rows out exactly like a visible one.
    /// Defaults to true for views shown outside the tab host (Settings,
    /// sheets), which must never pause.
    var tabIsActive: Bool {
        get { self[TabIsActiveKey.self] }
        set { self[TabIsActiveKey.self] = newValue }
    }

    /// The feature id of the tab this view belongs to. A view registering a
    /// leave guard tags it with this so closing the right tab is what prompts —
    /// needed because the screenshot/video editors embed inside several
    /// different tabs (screen-record, scrcpy, their own).
    var tabFeatureID: String {
        get { self[TabFeatureIDKey.self] }
        set { self[TabFeatureIDKey.self] = newValue }
    }
}

/// Reports to a streaming feed whether this view can currently see it, so the
/// feed can pace its flushes (`FeedFlushCadence`, `FeedAudience`).
///
/// One modifier rather than three hooks per feed: all three feeds — the
/// Reactotron timeline, the JS Console and logcat — need the identical
/// appear/switch/disappear triple, and the pacing rule is only as good as its
/// least careful call site.
///
/// The report is keyed by a per-view `UUID` because one feed can be on screen
/// in several places at once (an app-wide feed in two windows, a per-window
/// feed in both panes of a split), and because SwiftUI lifecycle hooks are not
/// reliably balanced — see `FeedAudience`.
private struct FeedVisibilityReporter: ViewModifier {
    @Environment(\.tabIsActive) private var tabIsActive
    /// Identity for this view instance, stable for as long as it is mounted.
    @State private var viewID = UUID()
    let report: (UUID, Bool) -> Void

    func body(content: Content) -> some View {
        content
            // Reported from lifecycle hooks, never from `body`: these writes
            // land on state a feed view reads, and writing observable state
            // during an update is an endless update loop, not a wasted pass.
            .onAppear { report(viewID, tabIsActive) }
            .onChange(of: tabIsActive) { _, visible in report(viewID, visible) }
            .onDisappear { report(viewID, false) }
    }
}

extension View {
    /// Tell a feed when this view can see it. `report` takes the view's
    /// identity and whether it is visible — pass it straight to the session's
    /// `noteVisibility(view:visible:)`.
    func reportsFeedVisibility(to report: @escaping (UUID, Bool) -> Void) -> some View {
        modifier(FeedVisibilityReporter(report: report))
    }
}
