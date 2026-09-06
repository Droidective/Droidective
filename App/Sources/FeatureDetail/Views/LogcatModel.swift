import ADBKit
import Foundation

/// Logcat's state that should outlive its view.
///
/// Held per window by `FeatureStateStore`, not as view `@State`, so the buffer
/// and the filters that make sense of it survive the tab being rebuilt —
/// moving to the other split pane, or to another window. Losing a few thousand
/// collected lines because a tab changed places is the kind of thing that makes
/// a move feel like a restart.
///
/// The live `adb logcat` process deliberately does *not* live here: it is
/// owned by the view's `.task` and reattaches in milliseconds, so keeping the
/// stream itself continuous across a move would be invasive for no visible
/// gain. The buffer is what is expensive to rebuild — it cannot be, it is gone.
@MainActor
@Observable
final class LogcatModel {
    /// Everything collected so far, capped by `LogcatView.maxLines`.
    var lines: [LogLine] = []
    /// Streaming is held; new lines are dropped rather than buffered.
    var paused = false
    /// The level filter ("All", "Error", …) — part of the stream's arguments,
    /// so changing it restarts the stream and clears the buffer.
    var level = "All"
    /// Restrict to one app's pid, and to one tag.
    var packageFilter: String?
    var tagFilter: String?
    /// What the user is typing, debounced into `search`, which is what the
    /// filtering actually reads (one rebuild per pause, not per keystroke).
    var searchInput = ""
    var search = ""
    /// pid → process name, from a periodic `ps` snapshot. Carried across a
    /// move so the process column does not blank out and re-probe.
    var processNames: [String: String] = [:]
    /// The stream query (`LogcatView.taskKey`) the buffer was collected under.
    ///
    /// A restart with the *same* query is a remount — the tab moved to another
    /// window or pane — and must keep what it had. A different query is a
    /// different question (another device, level or app), whose answers must
    /// not be mixed in with the old ones, so that clears.
    var bufferKey: String?
    /// One-shot: the App filter is seeded from the device bar's chosen bundle
    /// the first time the view appears, then left alone. Kept here so a move
    /// does not re-seed over a filter the user has since changed.
    var seededPackageFilter = false
}
