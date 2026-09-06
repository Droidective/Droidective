import Foundation

/// How often a streaming feed drains its buffered rows into observable state.
///
/// This is the pacing that decides how much SwiftUI work a chatty stream
/// costs, because each flush re-diffs the whole visible feed: the interval is
/// a direct multiplier on main-thread layout. A 16 ms cadence is up to 62 full
/// diffs a second, and every open tab stays mounted (`TabHostView`'s
/// keep-alive ZStack), so those diffs are paid across *every* mounted feed
/// rather than only the one on screen.
///
/// The JS Console found this first and shipped 250 ms/1 s
/// (DROIDECTIVE-MAC-2N); logcat shipped a flat 300 ms in v3.6.1, which is the
/// value the shared rule settled on. The rule
/// lives here so the third feed can't miss it — the Reactotron timeline did,
/// and stayed at 16 ms while being the largest feed of the three
/// (DROIDECTIVE-MAC-B: 5087 hangs, and its top `open_features` rows are
/// single users with 9 to 18 tabs mounted at once).
///
/// **Inactive is slower, never stopped.** Nobody is reading in real time and a
/// feed streaming behind an unfocused window used to burn CPU for hours — but
/// pausing outright is worse than pacing: the buffer grows unbounded, and
/// reactivation hands SwiftUI one enormous flush, which is the same
/// mass-mutation stall the pacing exists to avoid.
///
/// Two things the fixed active/inactive pair could not express, both of which
/// the hang data asked for (5261 hangs in 30 days, 75:1 of them with the app
/// not frontmost, every culprit a feed row — `coloredTokenText`,
/// `ResolvedTextFilter`, `ConsoleFlowLayout`, `JSEntryRow.body`, `RtItem`):
///
/// - **A feed nobody can see costs the same as one on screen.** Hidden tabs
///   stay mounted, so a hidden feed's flush lays its rows out exactly like a
///   visible one. `hidden` prices that in — but it stays a *pace*, not a
///   pause, for the reason above, and a feed becoming visible must flush
///   eagerly rather than wait out the long interval.
/// - **Cost was never in the loop.** A fixed interval asks for the main thread
///   just as often when a flush costs 5 ms as when it costs 900 ms, so a big
///   enough feed can saturate the thread and never catch up — the app is then
///   alive but permanently behind, which is what "it went unresponsive and
///   clicking the Dock did nothing" is. `lateness` closes the loop: a flush
///   that had to wait for a busy main thread reports how late it ran, and the
///   next interval widens by that much, so the feed's share of the thread
///   falls as the thread gets busier and snaps back when it clears.
public enum FeedFlushCadence {
    /// The app is frontmost and the feed is on screen — fast enough to read as
    /// live, slow enough that a burst becomes one mutation per ~third of a
    /// second instead of per frame.
    ///
    /// 300 ms rather than the JS Console's original 250 ms because logcat has
    /// shipped 300 since v3.6.1, and unifying downward measurably cost the one
    /// state the user is actually watching: a logcat streaming ~300 lines/s
    /// went 14.2% CPU to 15.3% purely from the extra flushes. Every feed is
    /// cheaper at 300 and none of them reads differently — the fix that
    /// mattered was leaving 16 ms, not the 50 ms between these two.
    public static let active: Duration = .milliseconds(300)

    /// On screen, but another app is frontmost. Four flushes a second down to
    /// one.
    public static let inactive: Duration = .seconds(1)

    /// Mounted but not on screen — a tab behind another tab, in either pane of
    /// any window. Nothing is being read, so this only has to keep the buffer
    /// draining into the feed's own ring; the eager flush on becoming visible
    /// is what the user actually sees.
    public static let hidden: Duration = .seconds(5)

    /// Ceiling for the `lateness` widening. Past this the feed has backed off
    /// as far as it usefully can, and a longer wait only delays recovery —
    /// including after a system sleep, where lateness is the length of the
    /// sleep and means nothing about load.
    public static let maxInterval: Duration = .seconds(8)

    /// The unloaded interval for a feed in this state, before any widening.
    public static func base(appActive: Bool, watched: Bool) -> Duration {
        guard watched else { return hidden }
        return appActive ? active : inactive
    }

    /// How late a wait of `requested` actually was, given it took `elapsed`.
    ///
    /// The reading belongs to the *thread*, not to a feed: it is taken by one
    /// app-wide sampler whose own scheduled wake-ups measure how far behind
    /// the main thread is, and every feed then paces against the same number.
    /// A feed measuring only its own flushes would under-observe exactly when
    /// it matters — the feed that is starved reports nothing, and the load it
    /// is waiting behind belongs to the other eight mounted tabs.
    ///
    /// Never negative: a clock reading early, or a wake-up that beat its
    /// deadline, is not evidence of load.
    public static func lateness(elapsed: Duration, requested: Duration) -> Duration {
        max(.zero, elapsed - requested)
    }

    /// How long to wait before the next flush.
    ///
    /// - Parameters:
    ///   - appActive: whether this app is frontmost.
    ///   - watched: whether any mounted view can currently see this feed
    ///     (`FeedAudience`), which is not the same as the feed having a view —
    ///     a hidden tab keeps its view mounted.
    ///   - lateness: how far past its requested interval the last scheduled
    ///     flush actually ran. Zero when the main thread kept up; negative
    ///     values (a clock reading early) are treated as zero.
    public static func interval(appActive: Bool, watched: Bool, lateness: Duration) -> Duration {
        let base = base(appActive: appActive, watched: watched)
        guard lateness > .zero else { return base }
        return min(maxInterval, max(base, base + lateness))
    }
}
