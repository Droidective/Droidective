import Foundation
import Testing

@testable import ADBKit

/// The app-wide baseline. Every other resource number is a peak or a
/// per-feature slice; this is what the app normally costs, which is what a
/// peak has to be read against.
@Suite struct UsageWindowTests {
    private let mb: UInt64 = 1_048_576

    @Test func nothingSampledIsNil() {
        #expect(UsageWindow().summary() == nil)
        var empty = UsageWindow()
        #expect(empty.takeWindow() == nil)
    }

    @Test func theAverageIsAcrossEverySampleAndThePeakIsTheWorst() throws {
        var subject = UsageWindow()
        for cpu in [10.0, 20.0, 102.0, 8.0] {
            subject.ingest(cpuPercent: cpu, footprintBytes: 500 * mb)
        }
        let window = try #require(subject.summary())
        #expect(window.samples == 4)
        #expect(window.averageCPUPercent == 35)
        #expect(window.peakCPUPercent == 102)
    }

    /// A session's first sample has no CPU — the figure is a delta between two
    /// cumulative readings — but its memory is still real and must count.
    @Test func theFirstSampleContributesMemoryWithoutCPU() throws {
        var subject = UsageWindow()
        subject.ingest(cpuPercent: nil, footprintBytes: 300 * mb)
        subject.ingest(cpuPercent: 40, footprintBytes: 500 * mb)
        let window = try #require(subject.summary())
        #expect(window.samples == 2)
        #expect(window.averageFootprintBytes == Double(400 * mb))
        #expect(window.averageCPUPercent == 20, "40 over two samples — the CPU-less one counts as zero")
        #expect(window.peakCPUPercent == 40)
    }

    /// The distinction the incidents needed: a window that climbed is a leak
    /// in progress, one that sat still is a plateau, and the peak alone cannot
    /// tell them apart.
    @Test func theWindowRecordsWhereItStartedAndEnded() throws {
        var subject = UsageWindow()
        subject.ingest(cpuPercent: 5, footprintBytes: 400 * mb)
        subject.ingest(cpuPercent: 5, footprintBytes: 900 * mb)
        subject.ingest(cpuPercent: 5, footprintBytes: 1_400 * mb)
        let climbing = try #require(subject.summary())
        #expect(climbing.firstFootprintBytes == 400 * mb)
        #expect(climbing.lastFootprintBytes == 1_400 * mb)
        #expect(climbing.footprintDeltaBytes == Int(1_000 * mb))
        #expect(climbing.peakFootprintBytes == 1_400 * mb)
    }

    @Test func aFallingWindowReportsANegativeDelta() throws {
        var subject = UsageWindow()
        subject.ingest(cpuPercent: 0, footprintBytes: 1_500 * mb)
        subject.ingest(cpuPercent: 0, footprintBytes: 600 * mb)
        let window = try #require(subject.summary())
        #expect(window.footprintDeltaBytes == -Int(900 * mb))
        #expect(window.peakFootprintBytes == 1_500 * mb, "the peak survives the fall")
    }

    /// CPU is derived from a clock delta, so a non-monotonic reading could in
    /// principle arrive negative; it must not drag the average below zero.
    @Test func aNegativeCPUReadingIsFlooredRatherThanSubtracted() throws {
        var subject = UsageWindow()
        subject.ingest(cpuPercent: -30, footprintBytes: mb)
        subject.ingest(cpuPercent: 30, footprintBytes: mb)
        let window = try #require(subject.summary())
        #expect(window.averageCPUPercent == 15)
        #expect(window.peakCPUPercent == 30)
    }

    @Test func takeWindowStartsAFreshOne() throws {
        var subject = UsageWindow()
        subject.ingest(cpuPercent: 50, footprintBytes: 800 * mb)
        let drained = subject.takeWindow()
        let taken = try #require(drained)
        #expect(taken.peakCPUPercent == 50)
        #expect(subject.summary() == nil)
        subject.ingest(cpuPercent: 1, footprintBytes: 100 * mb)
        let reopened = try #require(subject.summary())
        #expect(reopened.samples == 1)
        #expect(reopened.peakCPUPercent == 1, "the 50% peak did not survive the drain")
        #expect(reopened.firstFootprintBytes == 100 * mb)
    }

    @Test func summaryLeavesTheWindowInPlace() throws {
        var subject = UsageWindow()
        subject.ingest(cpuPercent: 12, footprintBytes: 200 * mb)
        let first = try #require(subject.summary())
        let second = try #require(subject.summary())
        #expect(first == second)
    }
}
