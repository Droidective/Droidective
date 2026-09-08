import Foundation
import Testing
@testable import ADBKit

/// The app's own stall record. It exists because the hang events cannot say how
/// long a hang lasted — Sentry fills the duration in from the configured
/// threshold — so these summaries are the only answer to "how bad was it".
@Suite struct MainThreadStallTests {
    private func stall(_ latenessMs: [Int]) -> MainThreadStall {
        var stall = MainThreadStall()
        for ms in latenessMs { stall.ingest(.milliseconds(ms)) }
        return stall
    }

    // MARK: - Summarising

    @Test func aHealthyThreadReportsQuietRatherThanNothing() throws {
        // Every turn arrived on time. That is a fact worth recording as a
        // baseline, not an absence of data.
        let subject = stall([0, 0, 0, 0])
        let window = try #require(subject.summary())
        #expect(window.samples == 4)
        #expect(window.stalls == 0)
        #expect(window.isQuiet)
        #expect(window.stalledPercent == 0)
        #expect(window.worstMilliseconds == 0)
    }

    @Test func nothingSampledIsNil() {
        let untouched = MainThreadStall()
        #expect(untouched.summary() == nil)
        var empty = MainThreadStall()
        let taken = empty.takeWindow()
        #expect(taken == nil)
    }

    /// The number the hang events never carried: one turn that arrived eight
    /// seconds late is an eight-second hang, however "at least 2000 ms" it was
    /// reported as.
    @Test func theWorstSampleIsTheHangDuration() throws {
        let subject = stall([0, 0, 8_000, 0])
        let window = try #require(subject.summary())
        #expect(window.worstMilliseconds == 8_000)
        #expect(window.stalls == 1)
    }

    /// One long stall and a thread late a third of the time are different
    /// problems; the share is what separates them.
    @Test func theStalledShareSeparatesASpikeFromSaturation() throws {
        let spiky = stall(Array(repeating: 0, count: 99) + [4_000])
        let spike = try #require(spiky.summary())
        #expect(spike.stalledPercent == 1)

        let busy = stall(Array(repeating: 400, count: 100))
        let saturated = try #require(busy.summary())
        #expect(saturated.stalledPercent == 100)
        #expect(saturated.worstMilliseconds == 400)
    }

    /// The median is taken over stalled samples only. Over *all* samples it
    /// would read zero on any app that mostly keeps up, which is every app
    /// worth diagnosing.
    @Test func theMedianIgnoresTheHealthySamples() throws {
        let subject = stall(Array(repeating: 0, count: 50) + [300, 900, 1_500])
        let window = try #require(subject.summary())
        #expect(window.medianStallMilliseconds == 900)
        #expect(window.stalls == 3)
    }

    @Test func latenessAtTheThresholdCounts() throws {
        let subject = stall([249, 250])
        let window = try #require(subject.summary())
        #expect(window.stalls == 1) // 250 is a stall, 249 is not
    }

    // MARK: - Peek vs drain

    /// Two reporters read this — a hang whenever one happens, and the health
    /// report on a fixed cadence. Only the second may consume, or each would
    /// see an arbitrary half of the samples.
    @Test func summaryLeavesTheWindowInPlace() throws {
        let subject = stall([0, 500, 0])
        let first = try #require(subject.summary())
        let second = try #require(subject.summary())
        #expect(first == second)
        #expect(second.samples == 3)
    }

    @Test func takeWindowStartsAFreshOne() throws {
        var subject = stall([0, 500])
        // Outside the macro: `#require` captures its argument immutably, and
        // this is the mutating half of the pair.
        let drained = subject.takeWindow()
        let taken = try #require(drained)
        #expect(taken.stalls == 1)
        #expect(subject.summary() == nil)
        subject.ingest(.milliseconds(0))
        let reopened = try #require(subject.summary())
        #expect(reopened.samples == 1)
    }

    // MARK: - Bounds

    /// This type is instrumentation for memory problems, so it must not be one:
    /// a long session samples twice a second for hours.
    @Test func theSampleWindowIsBounded() throws {
        var subject = MainThreadStall()
        for _ in 0..<(MainThreadStall.capacity * 3) { subject.ingest(.milliseconds(1)) }
        let window = try #require(subject.summary())
        #expect(window.samples == MainThreadStall.capacity)
    }

    /// The oldest samples are the ones dropped, so a stall stays visible for
    /// the whole window it happened in rather than being evicted by the newest
    /// healthy readings.
    @Test func theOldestSamplesAreTheOnesDropped() throws {
        var subject = MainThreadStall()
        subject.ingest(.milliseconds(9_000)) // the oldest
        for _ in 0..<MainThreadStall.capacity { subject.ingest(.milliseconds(0)) }
        let window = try #require(subject.summary())
        #expect(window.worstMilliseconds == 0, "the 9 s sample should have aged out")
        #expect(window.samples == MainThreadStall.capacity)
    }

    @Test func aNegativeDurationIsFlooredAtZero() throws {
        var subject = MainThreadStall()
        subject.ingest(.milliseconds(-500))
        let window = try #require(subject.summary())
        #expect(window.worstMilliseconds == 0)
    }

    @Test func subSecondDurationsConvertExactly() {
        #expect(MainThreadStall.milliseconds(.milliseconds(1)) == 1)
        #expect(MainThreadStall.milliseconds(.seconds(3)) == 3_000)
        #expect(MainThreadStall.milliseconds(.microseconds(999)) == 0)
    }
}
