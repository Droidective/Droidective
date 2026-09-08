import Testing
@testable import ADBKit

/// The pacing shared by the three streaming feeds. Each flush re-diffs a whole
/// visible feed and every open tab stays mounted, so this interval is a direct
/// multiplier on main-thread layout across all of them.
@Suite struct FeedFlushCadenceTests {
    @Test func inactiveIsSlowerThanActive() throws {
        let inactive = try #require(
            FeedFlushCadence.interval(appActive: false, watched: true, lateness: .zero))
        let active = try #require(
            FeedFlushCadence.interval(appActive: true, watched: true, lateness: .zero))
        #expect(inactive > active)
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

    /// A feed someone can see is never stopped, whether or not the app is
    /// frontmost: it is being read, and a feed that only flushes every few
    /// seconds reads as broken when the user looks back at it.
    @Test func aWatchedFeedIsNeverStopped() {
        #expect(FeedFlushCadence.active > .zero)
        #expect(FeedFlushCadence.inactive > .zero)
        #expect(FeedFlushCadence.interval(appActive: true, watched: true, lateness: .zero) != nil)
        #expect(FeedFlushCadence.interval(appActive: false, watched: true, lateness: .zero) != nil)
        // A cap, so "slower while inactive" can't drift into "effectively off".
        #expect(FeedFlushCadence.inactive <= .seconds(2))
    }

    // MARK: Visibility

    /// A feed nobody can see schedules nothing at all. A mounted hidden tab
    /// lays its rows out exactly like a visible one, so publishing to it buys
    /// a SwiftUI diff no one reads — the twenty-four minutes of once-a-second
    /// re-diffing behind DROIDECTIVE-MAC-B. Rows keep arriving into the feed's
    /// byte-bounded pending buffer, which is what makes stopping safe.
    @Test func anUnwatchedFeedSchedulesNothing() {
        #expect(FeedFlushCadence.interval(appActive: true, watched: false, lateness: .zero) == nil)
        #expect(FeedFlushCadence.interval(appActive: false, watched: false, lateness: .zero) == nil)
    }

    /// App activation is irrelevant while nothing can see the feed: the cost
    /// being skipped is this tab's layout, and a hidden tab is hidden whether
    /// or not the window is frontmost.
    @Test func activationDoesNotChangeAnUnwatchedFeed() {
        #expect(
            FeedFlushCadence.interval(appActive: true, watched: false, lateness: .zero)
                == FeedFlushCadence.interval(appActive: false, watched: false, lateness: .zero))
    }

    /// No amount of lateness turns an unwatched feed back on: the widening is
    /// a pace, and there is no pace to widen.
    @Test func latenessCannotReviveAnUnwatchedFeed() {
        for seconds in [0, 1, 10, 600] {
            #expect(
                FeedFlushCadence.interval(
                    appActive: true, watched: false, lateness: .seconds(seconds)) == nil)
        }
    }

    /// A feed that cannot pause — one whose flush yields into an
    /// `AsyncStream` rather than publishing observable state, so pausing would
    /// stall the stream — backs off to the ceiling instead of stopping.
    @Test func aDrainingFeedBacksOffInsteadOfStopping() {
        let unwatched = FeedFlushCadence.drainingInterval(
            appActive: true, watched: false, lateness: .zero)
        #expect(unwatched == FeedFlushCadence.maxInterval)
        // Watched, it paces exactly like every other feed.
        #expect(
            FeedFlushCadence.drainingInterval(appActive: true, watched: true, lateness: .zero)
                == FeedFlushCadence.active)
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
    @Test func latenessWidensTheNextInterval() throws {
        let late = try #require(FeedFlushCadence.interval(
            appActive: true, watched: true, lateness: .milliseconds(900)))
        #expect(late >= FeedFlushCadence.active + .milliseconds(900))
        #expect(late > FeedFlushCadence.active)
    }

    @Test func wideningIsMonotonicInLateness() throws {
        var previous = try #require(
            FeedFlushCadence.interval(appActive: true, watched: true, lateness: .zero))
        for milliseconds in [50, 200, 800, 1500, 3000] {
            let next = try #require(FeedFlushCadence.interval(
                appActive: true, watched: true, lateness: .milliseconds(milliseconds)))
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

    /// Backing off must never overtake the ceiling from any starting state —
    /// the ceiling is the promise that a feed someone is watching always comes
    /// back. The draining form is included, since it is the one that answers
    /// with the ceiling itself.
    @Test func noStateExceedsTheCeiling() {
        for appActive in [true, false] {
            for watched in [true, false] {
                for seconds in [0, 1, 10, 600] {
                    let interval = FeedFlushCadence.interval(
                        appActive: appActive, watched: watched, lateness: .seconds(seconds))
                    #expect(interval ?? .zero <= FeedFlushCadence.maxInterval)
                    #expect(FeedFlushCadence.drainingInterval(
                        appActive: appActive, watched: watched,
                        lateness: .seconds(seconds)) <= FeedFlushCadence.maxInterval)
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
    /// it bounds could never happen at all.
    @Test func theCeilingLeavesRoomAboveEveryBase() {
        #expect(FeedFlushCadence.maxInterval > FeedFlushCadence.inactive)
        #expect(FeedFlushCadence.maxInterval > FeedFlushCadence.active)
    }

    @Test func baseIgnoresLatenessEntirely() {
        #expect(FeedFlushCadence.base(appActive: true, watched: true) == FeedFlushCadence.active)
        #expect(FeedFlushCadence.base(appActive: false, watched: true) == FeedFlushCadence.inactive)
        #expect(FeedFlushCadence.base(appActive: false, watched: false) == nil)
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
