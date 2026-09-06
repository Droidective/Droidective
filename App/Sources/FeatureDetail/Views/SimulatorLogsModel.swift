import ADBKit
import Foundation

/// iOS Logs' collected lines and filters — Logcat's twin, kept per window by
/// `FeatureStateStore` for the same reason: a tab moving to another window
/// rebuilds its view, and a unified-log feed that starts empty every time it
/// changes places is a restart, not a move.
///
/// As with Logcat, the `simctl spawn … log stream` process itself stays with
/// the view and reattaches. Only what it accumulated is worth carrying.
@MainActor
@Observable
final class SimulatorLogsModel {
    var lines: [SimLogLine] = []
    var paused = false
    var shownLevels: Set<SimLogLevel> = [.notice, .error, .fault]
    var processFilter: String?
    /// What the user is typing, debounced into `search`.
    var searchInput = ""
    var search = ""
    /// The stream query (`SimulatorLogsView.taskKey`) the buffer was collected
    /// under. A restart with the same query is a remount — the tab moved — and
    /// keeps what it had; a different one is a different question and clears.
    var bufferKey: String?
}
