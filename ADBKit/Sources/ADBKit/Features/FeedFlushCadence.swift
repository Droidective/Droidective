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
/// (DROIDECTIVE-MAC-2N); logcat shipped a flat 300 ms in v3.6.1. The rule
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
public enum FeedFlushCadence {
    /// The app is frontmost — fast enough to read as live, slow enough that a
    /// burst becomes one mutation per quarter second instead of per frame.
    public static let active: Duration = .milliseconds(250)

    /// Another app is frontmost. Four flushes a second down to one.
    public static let inactive: Duration = .seconds(1)

    public static func interval(appActive: Bool) -> Duration {
        appActive ? active : inactive
    }
}
