import Foundation

/// The app's own CPU and memory over a reporting window — averaged, not
/// sampled.
///
/// Every resource number the app sends today is either an instant (the
/// footprint at the moment a hang fired) or attributed to one feature
/// (`feature_perf`, keyed on whatever was on screen). Neither answers the
/// plainest question there is: what does this app normally cost? A peak of
/// 102% CPU means something very different on a process that idles at 3% than
/// on one that sits at 40, and nothing collected could distinguish them.
///
/// So this accumulates across the whole health window, app-wide, with no
/// feature attribution at all — the average is the baseline every spike should
/// be read against.
///
/// Pure and value-typed; the App layer owns the timer and the sampling.
public struct UsageWindow: Sendable, Equatable {
    /// One closed window's summary.
    public struct Summary: Sendable, Equatable {
        public let samples: Int
        public let averageCPUPercent: Double
        public let peakCPUPercent: Double
        public let averageFootprintBytes: Double
        public let peakFootprintBytes: UInt64
        /// Footprint at the window's first sample, so growth *within* the
        /// window is readable without joining to the session baseline. A
        /// window that opened at 400 MB and closed at 1.4 GB is a leak in
        /// progress; one that sat at 1.4 GB throughout is a plateau.
        public let firstFootprintBytes: UInt64
        public let lastFootprintBytes: UInt64

        /// Bytes gained across the window, negative when it fell.
        public var footprintDeltaBytes: Int {
            Int(lastFootprintBytes) - Int(firstFootprintBytes)
        }
    }

    private var samples = 0
    private var cpuTotal: Double = 0
    private var cpuPeak: Double = 0
    private var footprintTotal: Double = 0
    private var footprintPeak: UInt64 = 0
    private var firstFootprint: UInt64?
    private var lastFootprint: UInt64 = 0

    public init() {}

    /// Add a reading. `cpuPercent` is nil for the first sample of a session —
    /// CPU comes from a delta between two cumulative readings, so there is
    /// nothing to compute yet — and the memory half is still recorded.
    public mutating func ingest(cpuPercent: Double?, footprintBytes: UInt64) {
        samples += 1
        if let cpuPercent {
            let clamped = max(0, cpuPercent)
            cpuTotal += clamped
            cpuPeak = max(cpuPeak, clamped)
        }
        footprintTotal += Double(footprintBytes)
        footprintPeak = max(footprintPeak, footprintBytes)
        if firstFootprint == nil { firstFootprint = footprintBytes }
        lastFootprint = footprintBytes
    }

    /// Summarise without resetting — for a reporter that must not disturb the
    /// window another one is accumulating (a resource alert fires whenever it
    /// fires; the health report drains on a fixed cadence).
    public func summary() -> Summary? {
        guard samples > 0, let firstFootprint else { return nil }
        return Summary(
            samples: samples,
            averageCPUPercent: cpuTotal / Double(samples),
            peakCPUPercent: cpuPeak,
            averageFootprintBytes: footprintTotal / Double(samples),
            peakFootprintBytes: footprintPeak,
            firstFootprintBytes: firstFootprint,
            lastFootprintBytes: lastFootprint)
    }

    /// Summarise and start a fresh window. Exactly one reporter may do this,
    /// for the reason `MainThreadStall.takeWindow` gives: two drainers would
    /// each see an arbitrary half of the samples.
    public mutating func takeWindow() -> Summary? {
        defer { self = UsageWindow() }
        return summary()
    }
}
