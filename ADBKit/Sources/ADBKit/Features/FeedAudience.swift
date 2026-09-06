import Foundation

/// Who can currently see a streaming feed.
///
/// Visibility decides a feed's flush pacing (`FeedFlushCadence.hidden`), and it
/// cannot be a flag: one feed can be on screen in several places at once. The
/// Reactotron timeline is app-wide (`AppCore.reactotronSession`), so two
/// windows can show it side by side; the JS Console is per window but a split
/// puts it in both panes. A flag written by whichever view reported last would
/// let a hidden tab in one window pace the feed someone is reading in another.
///
/// Membership is keyed by view identity rather than counted, because the
/// reports come from SwiftUI lifecycle hooks: an `onAppear` without its
/// matching `onDisappear` (a pane move, a window closing mid-update) would
/// leak a count that never comes back down, and the same view reporting twice
/// would double it. Re-reporting the same identity is idempotent here.
///
/// A leaked identity — a view torn down without its `onDisappear` — prices the
/// feed as *watched*, which is the safe direction: it pays for layout nobody
/// is reading rather than pausing a feed someone is looking at.
public struct FeedAudience: Sendable, Equatable {
    private var watching: Set<UUID> = []

    public init() {}

    /// Whether any mounted view can see the feed right now.
    public var isWatched: Bool { !watching.isEmpty }

    /// Record one view's visibility.
    ///
    /// - Returns: whether `isWatched` changed, so a caller can skip the work a
    ///   transition triggers (the eager flush on becoming visible) when
    ///   nothing actually changed. Views report on every appearance and tab
    ///   switch, so most calls change nothing.
    @discardableResult
    public mutating func update(view id: UUID, visible: Bool) -> Bool {
        let was = isWatched
        if visible {
            watching.insert(id)
        } else {
            watching.remove(id)
        }
        return was != isWatched
    }

    /// Forget every viewer — teardown, where the views are going away without
    /// necessarily reporting it (a window close, a role reset).
    @discardableResult
    public mutating func removeAll() -> Bool {
        let was = isWatched
        watching.removeAll()
        return was != isWatched
    }
}
