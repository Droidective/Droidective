import Foundation
import Testing

@testable import ADBKit

/// The ledger exists for one number — the footprint nobody can account for —
/// so most of these are about that subtraction staying honest.
@Suite struct MemoryLedgerTests {
    private let mb = 1_048_576

    private func ledger(_ pairs: [(MemoryLedger.Owner, Int)]) -> MemoryLedger {
        var ledger = MemoryLedger()
        for (owner, megabytes) in pairs {
            ledger.report(owner, MemoryLedger.Entry(residentBytes: megabytes * mb))
        }
        return ledger
    }

    // MARK: - The subtraction

    @Test func whatIsNotAccountedForIsTheAnswer() {
        // The shape of the real report: feeds capped and honest, footprint
        // still 1.6 GB. 232 MB explained, 1404 MB not — which says the next
        // place to look is not the feeds.
        let subject = ledger([(.reactotron, 160), (.jsConsole, 72)])
        let footprint = UInt64(1_636 * mb)
        #expect(subject.attributedBytes == 232 * mb)
        #expect(subject.unattributedBytes(footprintBytes: footprint) == 1_404 * mb)
        #expect(subject.attributedPercent(footprintBytes: footprint) == 14)
    }

    /// These are estimates. One that overshoots must not report a negative —
    /// that reads as a broken pipeline rather than as a too-generous
    /// multiplier, which is what it is.
    @Test func anOverEstimateFloorsAtZeroRatherThanGoingNegative() {
        let subject = ledger([(.reactotron, 900)])
        let footprint = UInt64(400 * mb)
        #expect(subject.unattributedBytes(footprintBytes: footprint) == 0)
        #expect(subject.attributedPercent(footprintBytes: footprint) == 100, "clamped, never 225")
    }

    @Test func anEmptyLedgerAttributesNothingRatherThanEverything() {
        let subject = MemoryLedger()
        let footprint = UInt64(500 * mb)
        #expect(subject.attributedBytes == 0)
        #expect(subject.unattributedBytes(footprintBytes: footprint) == 500 * mb)
        #expect(subject.attributedPercent(footprintBytes: footprint) == 0)
    }

    @Test func aZeroFootprintCannotDivideByZero() {
        #expect(ledger([(.logcat, 5)]).attributedPercent(footprintBytes: 0) == 0)
    }

    // MARK: - Bookkeeping

    @Test func reportingTwiceReplacesRatherThanAccumulates() {
        var subject = MemoryLedger()
        subject.report(.reactotron, MemoryLedger.Entry(residentBytes: 100 * mb, items: 900))
        subject.report(.reactotron, MemoryLedger.Entry(residentBytes: 40 * mb, items: 300))
        #expect(subject.attributedBytes == 40 * mb, "a ring that evicted must shrink the total")
        #expect(subject.entry(.reactotron)?.items == 300)
        #expect(subject.retainerCount == 1)
    }

    /// The failure this guards is the one the feed reporter it replaces called
    /// out: a torn-down retainer whose last reading keeps counting turns the
    /// unattributed figure — the whole point of the type — into nonsense.
    @Test func aForgottenRetainerStopsCounting() {
        var subject = ledger([(.reactotron, 160), (.screenshot, 80)])
        subject.forget(.screenshot)
        #expect(subject.attributedBytes == 160 * mb)
        #expect(subject.entry(.screenshot) == nil)
        #expect(subject.retainerCount == 1)
    }

    @Test func forgettingSomethingNeverReportedIsHarmless() {
        var subject = ledger([(.logcat, 12)])
        subject.forget(.decompile)
        #expect(subject.attributedBytes == 12 * mb)
    }

    @Test func watchedCountsOnlyWhatSomeoneCanSee() {
        var subject = MemoryLedger()
        subject.report(.reactotron, MemoryLedger.Entry(residentBytes: mb, watched: true))
        subject.report(.jsConsole, MemoryLedger.Entry(residentBytes: mb, watched: false))
        subject.report(.logcat, MemoryLedger.Entry(residentBytes: mb, watched: false))
        #expect(subject.retainerCount == 3)
        #expect(subject.watchedCount == 1, "two of the three are held for nobody")
    }

    // MARK: - Telemetry shape

    @Test func propertiesCarryTheHeadlineAndThePerOwnerBreakdown() {
        var subject = MemoryLedger()
        subject.report(.reactotron, MemoryLedger.Entry(residentBytes: 160 * mb, items: 2_500, watched: true))
        subject.report(.jsConsole, MemoryLedger.Entry(residentBytes: 72 * mb, items: 3_300))
        let properties = subject.properties(footprintBytes: UInt64(1_636 * mb))

        #expect(properties["mem_known_mb"] == 232)
        #expect(properties["mem_unknown_mb"] == 1_404)
        #expect(properties["mem_known_pct"] == 14)
        #expect(properties["mem_retainers"] == 2)
        #expect(properties["mem_retainers_watched"] == 1)
        #expect(properties["mem_rt_mb"] == 160)
        #expect(properties["mem_rt_items"] == 2_500)
        #expect(properties["mem_js_mb"] == 72)
        #expect(properties["mem_js_items"] == 3_300)
    }

    /// Every key is `mem_` + a case of a closed enum, so a renamed feature can
    /// never start a new column and a dashboard can never quietly lose one.
    @Test func everyEmittedKeyComesFromTheFixedOwnerSet() {
        var subject = MemoryLedger()
        for owner in MemoryLedger.Owner.allCases {
            subject.report(owner, MemoryLedger.Entry(residentBytes: mb, items: 1))
        }
        let keys = Set(subject.properties(footprintBytes: UInt64(mb)).keys)
        let expected = Set(
            MemoryLedger.Owner.allCases.flatMap { ["mem_\($0.rawValue)_mb", "mem_\($0.rawValue)_items"] }
                + ["mem_known_mb", "mem_unknown_mb", "mem_known_pct", "mem_retainers", "mem_retainers_watched"])
        #expect(keys == expected)
    }

    @Test func ownerKeysAreDistinct() {
        let raw = MemoryLedger.Owner.allCases.map(\.rawValue)
        #expect(Set(raw).count == raw.count, "two owners sharing a key would silently overwrite")
    }

    /// An items count of zero is a retainer with no meaningful unit (an image,
    /// a tree), not a retainer holding nothing — so the key is absent rather
    /// than reading as an empty buffer.
    @Test func anItemlessRetainerOmitsTheCountRatherThanSendingZero() {
        var subject = MemoryLedger()
        subject.report(.screenshot, MemoryLedger.Entry(residentBytes: 80 * mb))
        let properties = subject.properties(footprintBytes: UInt64(500 * mb))
        #expect(properties["mem_shot_mb"] == 80)
        #expect(properties["mem_shot_items"] == nil)
    }

    /// Sub-megabyte holdings round rather than vanishing: a retainer reported
    /// as 0 MB looks like a bug in the reporter.
    @Test func aSmallHoldingRoundsRatherThanDisappearing() {
        #expect(MemoryLedger.megabytes(700_000) == 1)
        #expect(MemoryLedger.megabytes(0) == 0)
        #expect(MemoryLedger.megabytes(1_572_864) == 2)  // 1.5 MB rounds up
    }
}
