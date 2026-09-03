import Testing
@testable import ADBKit

/// The pacing shared by the three streaming feeds. Each flush re-diffs a whole
/// visible feed and every open tab stays mounted, so this interval is a direct
/// multiplier on main-thread layout across all of them.
@Suite struct FeedFlushCadenceTests {
    @Test func inactiveIsSlowerThanActive() {
        #expect(FeedFlushCadence.interval(appActive: false) > FeedFlushCadence.interval(appActive: true))
    }

    @Test func picksTheIntervalForEachState() {
        #expect(FeedFlushCadence.interval(appActive: true) == FeedFlushCadence.active)
        #expect(FeedFlushCadence.interval(appActive: false) == FeedFlushCadence.inactive)
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
        // A cap, so "slower while inactive" can't drift into "effectively off"
        // — a feed that only flushes every few seconds reads as broken when
        // the user comes back to it.
        #expect(FeedFlushCadence.inactive <= .seconds(2))
    }
}
