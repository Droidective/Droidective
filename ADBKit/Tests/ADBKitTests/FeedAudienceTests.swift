import Foundation
import Testing
@testable import ADBKit

/// Feed visibility, which decides pacing (`FeedFlushCadence.hidden`). The part
/// that goes wrong is never one view reporting — it is two views disagreeing,
/// or a view that never reports its exit.
///
/// `update` is `mutating`, and the `#expect` macro cannot host a mutating call
/// (it captures the expression to report it), so every result lands in a local
/// first.
@Suite struct FeedAudienceTests {
    @Test func startsUnwatched() {
        let audience = FeedAudience()
        #expect(!audience.isWatched)
    }

    @Test func oneVisibleViewIsWatched() {
        var audience = FeedAudience()
        let changed = audience.update(view: UUID(), visible: true)
        #expect(changed)
        #expect(audience.isWatched)
    }

    /// The reason this isn't a flag: an app-wide feed shown in two windows,
    /// where one of them switches to another tab. The window still reading it
    /// must keep the visible pace.
    @Test func aHiddenViewDoesNotUnwatchAFeedAnotherViewIsShowing() {
        var audience = FeedAudience()
        let reading = UUID()
        let switchedAway = UUID()
        audience.update(view: reading, visible: true)
        audience.update(view: switchedAway, visible: true)
        audience.update(view: switchedAway, visible: false)
        #expect(audience.isWatched)
        audience.update(view: reading, visible: false)
        #expect(!audience.isWatched)
    }

    /// The reason this isn't a count: views report on every appearance and tab
    /// switch, so the same identity arrives repeatedly.
    @Test func repeatedReportsFromOneViewAreIdempotent() {
        var audience = FeedAudience()
        let view = UUID()
        audience.update(view: view, visible: true)
        audience.update(view: view, visible: true)
        audience.update(view: view, visible: true)
        // One `false` from that same view must be enough to end it: a counted
        // audience would still be at three and stay "watched" forever.
        audience.update(view: view, visible: false)
        #expect(!audience.isWatched)
    }

    @Test func leavingTwiceDoesNotGoNegative() {
        var audience = FeedAudience()
        let view = UUID()
        audience.update(view: view, visible: true)
        audience.update(view: view, visible: false)
        audience.update(view: view, visible: false)
        #expect(!audience.isWatched)
        // ...and the view coming back is still enough to be watched again — a
        // count driven negative would need two arrivals to recover.
        audience.update(view: view, visible: true)
        #expect(audience.isWatched)
    }

    @Test func leavingAViewThatNeverArrivedChangesNothing() {
        var audience = FeedAudience()
        let changed = audience.update(view: UUID(), visible: false)
        #expect(!changed)
        #expect(!audience.isWatched)
    }

    /// Only the transitions report `true`, so a caller can hang the eager
    /// reveal flush off this without flushing on every tab switch elsewhere.
    @Test func onlyTheWatchedTransitionsReportAChange() {
        var audience = FeedAudience()
        let first = UUID()
        let second = UUID()
        let becameWatched = audience.update(view: first, visible: true)
        let secondArrived = audience.update(view: second, visible: true)
        let firstLeft = audience.update(view: first, visible: false)
        let becameUnwatched = audience.update(view: second, visible: false)
        #expect(becameWatched)      // unwatched -> watched
        #expect(!secondArrived)     // still watched
        #expect(!firstLeft)         // still watched
        #expect(becameUnwatched)    // watched -> unwatched
    }

    @Test func removeAllForgetsEveryViewer() {
        var audience = FeedAudience()
        audience.update(view: UUID(), visible: true)
        audience.update(view: UUID(), visible: true)
        let cleared = audience.removeAll()
        #expect(cleared)
        #expect(!audience.isWatched)
        // Idempotent: a second teardown reports no change.
        let again = audience.removeAll()
        #expect(!again)
    }
}
