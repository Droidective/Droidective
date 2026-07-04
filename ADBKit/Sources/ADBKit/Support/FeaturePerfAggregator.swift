import Foundation

/// One flushed window of per-feature resource use — the average and peak CPU
/// and memory observed while a given feature was the active (foreground) one.
/// Emitted to analytics so each feature gets a resource *baseline*, not just the
/// threshold spikes the `ResourceWatchdog` reports.
public struct FeaturePerfRecord: Sendable, Equatable {
    public let feature: String
    public let seconds: Double
    public let samples: Int
    public let averageCPUPercent: Double
    public let peakCPUPercent: Double
    public let averageMemoryBytes: Double
    public let peakMemoryBytes: UInt64

    public init(
        feature: String, seconds: Double, samples: Int,
        averageCPUPercent: Double, peakCPUPercent: Double,
        averageMemoryBytes: Double, peakMemoryBytes: UInt64
    ) {
        self.feature = feature
        self.seconds = seconds
        self.samples = samples
        self.averageCPUPercent = averageCPUPercent
        self.peakCPUPercent = peakCPUPercent
        self.averageMemoryBytes = averageMemoryBytes
        self.peakMemoryBytes = peakMemoryBytes
    }
}

/// Pure state machine that turns a stream of `(ResourceSample, active feature)`
/// readings into per-feature `FeaturePerfRecord`s. It accumulates CPU% (from the
/// cumulative-time delta between consecutive samples) and memory for the current
/// feature, and flushes a record when the active feature changes or a rolling
/// window elapses — so a feature that stays open forever still reports
/// periodically. No I/O; the App layer samples on a timer and forwards records
/// to telemetry.
public struct FeaturePerfAggregator: Sendable {
    /// Flush the running window at least this often, even if the feature never
    /// changes, so a long-lived feature still reports a baseline.
    public let maxWindowSeconds: Double

    private struct Window {
        let feature: String
        let start: TimeInterval
        var lastUptime: TimeInterval
        var samples = 0
        var cpuSamples = 0
        var cpuSum = 0.0
        var cpuPeak = 0.0
        var memSum = 0.0
        var memPeak: UInt64 = 0
    }

    private var previous: ResourceSample?
    private var window: Window?

    public init(maxWindowSeconds: Double = 300) {
        self.maxWindowSeconds = maxWindowSeconds
    }

    /// Feed the next reading. Returns a record when a window closes — because the
    /// feature changed, or the rolling window elapsed — otherwise nil.
    public mutating func ingest(_ sample: ResourceSample, feature: String) -> FeaturePerfRecord? {
        defer { previous = sample }

        // Feature change closes the current window before opening the next.
        if let current = window, current.feature != feature {
            let record = Self.record(from: current)
            window = Window(feature: feature, start: sample.uptime, lastUptime: sample.uptime)
            accumulate(sample)
            return record
        }

        if window == nil {
            window = Window(feature: feature, start: sample.uptime, lastUptime: sample.uptime)
        }
        accumulate(sample)

        // Roll the window over if it has run long enough, keeping the same feature.
        if let current = window, current.lastUptime - current.start >= maxWindowSeconds {
            let record = Self.record(from: current)
            window = Window(feature: feature, start: sample.uptime, lastUptime: sample.uptime)
            return record
        }
        return nil
    }

    /// Close the current window and return its record (e.g. on feature close or
    /// app quit), so the final window isn't silently dropped.
    public mutating func flush() -> FeaturePerfRecord? {
        defer { window = nil }
        guard let current = window else { return nil }
        return Self.record(from: current)
    }

    private mutating func accumulate(_ sample: ResourceSample) {
        guard window != nil else { return }
        window?.lastUptime = sample.uptime
        window?.samples += 1
        window?.memSum += Double(sample.footprintBytes)
        if sample.footprintBytes > (window?.memPeak ?? 0) { window?.memPeak = sample.footprintBytes }
        if let previous, let cpu = sample.cpuPercent(since: previous) {
            window?.cpuSamples += 1
            window?.cpuSum += cpu
            if cpu > (window?.cpuPeak ?? 0) { window?.cpuPeak = cpu }
        }
    }

    private static func record(from window: Window) -> FeaturePerfRecord {
        FeaturePerfRecord(
            feature: window.feature,
            seconds: window.lastUptime - window.start,
            samples: window.samples,
            averageCPUPercent: window.cpuSamples > 0 ? window.cpuSum / Double(window.cpuSamples) : 0,
            peakCPUPercent: window.cpuPeak,
            averageMemoryBytes: window.samples > 0 ? window.memSum / Double(window.samples) : 0,
            peakMemoryBytes: window.memPeak
        )
    }
}
