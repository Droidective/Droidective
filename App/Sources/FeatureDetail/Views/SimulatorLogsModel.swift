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

    /// What this buffer costs, for `AppMemory`'s ledger. Walked on demand
    /// rather than tracked per line, for the reason `LogcatModel.retainedBytes`
    /// gives — the report is built every five minutes, not every flush.
    ///
    /// `searchKey` is a whole second copy of every filterable field, lowercased
    /// at ingest, so it is counted rather than assumed away.
    var retainedBytes: Int {
        lines.reduce(0) { total, line in
            total + line.message.utf8.count + line.searchKey.utf8.count
                + line.process.utf8.count + line.subsystem.utf8.count + line.category.utf8.count
        } * 2
    }
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
