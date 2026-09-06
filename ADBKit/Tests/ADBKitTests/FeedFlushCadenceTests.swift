import Testing
@testable import ADBKit

/// The pacing shared by the three streaming feeds. Each flush re-diffs a whole
/// visible feed and every open tab stays mounted, so this interval is a direct
/// multiplier on main-thread layout across all of them.
@Suite struct FeedFlushCadenceTests {
    @Test func inactiveIsSlowerThanActive() {
        #expect(
            FeedFlushCadence.interval(appActive: false, watched: true, lateness: .zero)
                > FeedFlushCadence.interval(appActive: true, watched: true, lateness: .zero))
    }

    @Test func picksTheIntervalForEachState() {
        #expect(
            FeedFlushCadence.interval(appActive: true, watched: true, lateness: .zero)
                == FeedFlushCadence.active)
        #expect(
            FeedFlushCadence.interval(appActive: false, watched: true, lateness: .zero)
                == FeedFlushCadence.inactive)
    }

    /// The regression this exists for. Reactotron sat at 16 ms — up to 62 full
    /// re-diffs a second, paid across every mounted tab — while being the
    /// largest of the three feeds (DROIDECTIVE-MAC-B). Anything at or below a
    /// frame is that bug back.
    @Test func activeIsNotPerFrame() {
        #expect(FeedFlushCadence.active >= .milliseconds(100))
    }

    /// Never zero and never stopped: pausing a feed outright grows the buffer
    /// unbounded and hands SwiftUI one enormous flush on reactivation, which
    /// is the same mass-mutation stall the pacing avoids.
    @Test func neitherStateStopsTheFeed() {
        #expect(FeedFlushCadence.active > .zero)
        #expect(FeedFlushCadence.inactive > .zero)
        #expect(FeedFlushCadence.hidden > .zero)
        // A cap, so "slower while inactive" can't drift into "effectively off"
        // — a feed that only flushes every few seconds reads as broken when
        // the user comes back to it.
        #expect(FeedFlushCadence.inactive <= .seconds(2))
    }

    // MARK: Visibility

    /// A mounted-but-hidden tab lays its rows out exactly like a visible one,
    /// so the feed nobody can see must be the cheapest of the three states —
    /// including when the app itself is frontmost, which says nothing about
    /// whether *this* tab is the one on screen.
    @Test func hiddenIsTheSlowestState() {
        let hidden = FeedFlushCadence.interval(appActive: true, watched: false, lateness: .zero)
        #expect(hidden == FeedFlushCadence.hidden)
        #expect(hidden > FeedFlushCadence.inactive)
        #expect(hidden > FeedFlushCadence.active)
    }

    /// App activation is irrelevant while nothing can see the feed: the cost
    /// being paced away is this tab's layout, and a hidden tab is hidden
    /// whether or not the window is frontmost.
    @Test func activationDoesNotChangeAHiddenFeed() {
        #expect(
            FeedFlushCadence.interval(appActive: true, watched: false, lateness: .zero)
                == FeedFlushCadence.interval(appActive: false, watched: false, lateness: .zero))
    }

    /// Hidden is a pace, not a pause — but it must stay short enough that the
    /// buffer keeps draining into the feed's own ring between reveals.
    @Test func hiddenStaysBounded() {
        #expect(FeedFlushCadence.hidden <= .seconds(10))
    }

    // MARK: Backpressure

    @Test func aMainThreadThatKeptUpDoesNotWiden() {
        #expect(
            FeedFlushCadence.interval(appActive: true, watched: true, lateness: .zero)
                == FeedFlushCadence.active)
    }

    /// The wedge this exists for: a fixed interval asks for the main thread as
    /// often when a flush costs 900 ms as when it costs 5 ms, so a big enough
    /// feed saturates the thread and never catches up. Lateness has to widen
    /// the next wait by at least what the thread was already behind.
    @Test func latenessWidensTheNextInterval() {
        let late = FeedFlushCadence.interval(
            appActive: true, watched: true, lateness: .milliseconds(900))
        #expect(late >= FeedFlushCadence.active + .milliseconds(900))
        #expect(late > FeedFlushCadence.active)
    }

    @Test func wideningIsMonotonicInLateness() {
        var previous = FeedFlushCadence.interval(appActive: true, watched: true, lateness: .zero)
        for milliseconds in [50, 200, 800, 1500, 3000] {
            let next = FeedFlushCadence.interval(
                appActive: true, watched: true, lateness: .milliseconds(milliseconds))
            #expect(next >= previous)
            previous = next
        }
    }

    /// A system sleep makes lateness the length of the sleep, which says
    /// nothing about load — the ceiling is what keeps that from parking the
    /// feed for an hour. It also bounds how long recovery takes once a real
    /// overload clears.
    @Test func hugeLatenessClampsToTheCeiling() {
        let slept = FeedFlushCadence.interval(
            appActive: true, watched: true, lateness: .seconds(3600))
        #expect(slept == FeedFlushCadence.maxInterval)
    }

    /// Backing off must never overtake the ceiling from any starting state,
    /// hidden included — the ceiling is the promise that a feed always comes
    /// back.
    @Test func noStateExceedsTheCeiling() {
        for appActive in [true, false] {
            for watched in [true, false] {
                for seconds in [0, 1, 10, 600] {
                    let interval = FeedFlushCadence.interval(
                        appActive: appActive, watched: watched, lateness: .seconds(seconds))
                    #expect(interval <= FeedFlushCadence.maxInterval)
                }
            }
        }
    }

    /// A clock that reads early must not shorten the interval below its base —
    /// that would be the per-frame flush back under another name.
    @Test func negativeLatenessIsIgnored() {
        #expect(
            FeedFlushCadence.interval(appActive: true, watched: true, lateness: .milliseconds(-500))
                == FeedFlushCadence.active)
    }

    /// The ceiling has to leave room above the slowest base, or the widening
    /// it bounds could never happen for a hidden feed.
    @Test func theCeilingLeavesRoomAboveEveryBase() {
        #expect(FeedFlushCadence.maxInterval > FeedFlushCadence.hidden)
    }

    @Test func baseIgnoresLatenessEntirely() {
        #expect(FeedFlushCadence.base(appActive: true, watched: true) == FeedFlushCadence.active)
        #expect(FeedFlushCadence.base(appActive: false, watched: true) == FeedFlushCadence.inactive)
        #expect(FeedFlushCadence.base(appActive: false, watched: false) == FeedFlushCadence.hidden)
    }

    // MARK: Lateness readings

    @Test func latenessIsHowFarPastTheRequestedWait() {
        #expect(
            FeedFlushCadence.lateness(elapsed: .milliseconds(1200), requested: .seconds(1))
                == .milliseconds(200))
    }

    /// A wake-up that beat its deadline, or a clock reading early, is not
    /// evidence of load — and a negative lateness would *shorten* the next
    /// interval, which is the per-frame flush back under another name.
    @Test func aWaitThatFinishedEarlyReadsAsNoLoad() {
        #expect(FeedFlushCadence.lateness(elapsed: .milliseconds(900), requested: .seconds(1)) == .zero)
        #expect(FeedFlushCadence.lateness(elapsed: .zero, requested: .seconds(1)) == .zero)
    }

    @Test func anExactWaitReadsAsNoLoad() {
        #expect(FeedFlushCadence.lateness(elapsed: .seconds(1), requested: .seconds(1)) == .zero)
    }

    /// The sampler's reading feeds straight back into the interval, so the
    /// round trip has to hold: a thread half a second behind buys the feed at
    /// least that much more room.
    @Test func aSamplersReadingWidensTheNextInterval() {
        let observed = FeedFlushCadence.lateness(
            elapsed: .milliseconds(1500), requested: .seconds(1))
        let widened = FeedFlushCadence.interval(appActive: true, watched: true, lateness: observed)
        #expect(observed == .milliseconds(500))
        #expect(widened == FeedFlushCadence.active + .milliseconds(500))
    }
}
