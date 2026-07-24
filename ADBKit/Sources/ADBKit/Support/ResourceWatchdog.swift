import Foundation

/// One reading of the app's own resource usage. `cpuTimeSeconds` is the
/// process's *cumulative* CPU time, so the watchdog derives a CPU percentage
/// from the delta between consecutive samples.
public struct ResourceSample: Sendable, Equatable {
    /// Monotonic timestamp in seconds (e.g. `ProcessInfo.systemUptime`).
    public let uptime: TimeInterval
    /// Cumulative user + system CPU time consumed by the process, in seconds.
    public let cpuTimeSeconds: Double
    /// Physical memory footprint in bytes (the Activity Monitor "Memory" number).
    public let footprintBytes: UInt64

    public init(uptime: TimeInterval, cpuTimeSeconds: Double, footprintBytes: UInt64) {
        self.uptime = uptime
        self.cpuTimeSeconds = cpuTimeSeconds
        self.footprintBytes = footprintBytes
    }

    /// CPU percentage (100 = one fully busy core) consumed since an earlier
    /// sample, from the cumulative-time delta. `nil` for a non-advancing clock
    /// (the first reading, or two samples at the same instant).
    public func cpuPercent(since previous: ResourceSample) -> Double? {
        guard uptime > previous.uptime else { return nil }
        let used = max(0, cpuTimeSeconds - previous.cpuTimeSeconds)
        return used / (uptime - previous.uptime) * 100
    }
}

public enum ResourceMetric: String, Sendable {
    case cpu
    case memory
}

/// Emitted by `ResourceWatchdog` when usage crosses, or recovers from, a limit.
/// Values are CPU percent (100 = one core) for `.cpu` and bytes for `.memory`.
public enum ResourceEvent: Sendable, Equatable {
    /// Usage stayed over the limit for the sustained window; `value` is the
    /// reading that confirmed it.
    case began(metric: ResourceMetric, value: Double, limit: Double)
    /// The episode ended: usage dropped back below the reset level.
    case ended(metric: ResourceMetric, peak: Double, seconds: Double)
}

/// Pure state machine turning a stream of `ResourceSample`s into begin/end
/// events for sustained CPU and memory overuse. Debounces with a consecutive-
/// sample count, tracks the episode peak, and rate-limits repeat alerts per
/// metric with a cooldown. No I/O — the App layer samples on a timer and
/// forwards events to telemetry.
public struct ResourceWatchdog: Sendable {
    public struct Limits: Sendable {
        /// CPU percentage (100 = one fully busy core) that counts as overuse.
        public var cpuPercent: Double
        /// Memory footprint in bytes that counts as overuse.
        public var memoryBytes: Double
        /// Consecutive over-limit samples required before an episode begins.
        public var sustainedSamples: Int
        /// An episode ends once usage falls below `limit * resetFraction`.
        public var resetFraction: Double
        /// Minimum seconds between `began` events for the same metric.
        public var cooldownSeconds: Double

        public init(
            cpuPercent: Double = 200,
            memoryBytes: Double = 1_500 * 1_048_576,
            sustainedSamples: Int = 3,
            resetFraction: Double = 0.8,
            cooldownSeconds: Double = 1_800
        ) {
            self.cpuPercent = cpuPercent
            self.memoryBytes = memoryBytes
            self.sustainedSamples = sustainedSamples
            self.resetFraction = resetFraction
            self.cooldownSeconds = cooldownSeconds
        }
    }

    private struct MetricState {
        var strikes = 0
        var episodeStart: TimeInterval?
        var peak: Double = 0
        var lastBegan: TimeInterval?
    }

    public let limits: Limits
    private var previous: ResourceSample?
    private var cpu = MetricState()
    private var memory = MetricState()

    public init(limits: Limits = Limits()) {
        self.limits = limits
    }

    /// Feed the next sample; returns the threshold events it triggered.
    ///
    /// `cpuLimitOverride` replaces the configured CPU limit for this sample only.
    /// The App layer raises it while a feature that legitimately pegs the CPU is
    /// on screen — live screen mirroring and recording decode H.264 in-process,
    /// so ~two busy cores is expected there, not an incident. Raised, never
    /// waived: an unbounded override hid a real mirror-session leak from
    /// telemetry for hours. Memory is always judged against the configured
    /// limit.
    public mutating func ingest(
        _ sample: ResourceSample, cpuLimitOverride: Double? = nil
    ) -> [ResourceEvent] {
        var events: [ResourceEvent] = []
        if let percent = cpuPercent(for: sample) {
            Self.step(.cpu, state: &cpu, value: percent, limit: cpuLimitOverride ?? limits.cpuPercent,
                      limits: limits, at: sample.uptime, into: &events)
        }
        Self.step(.memory, state: &memory, value: Double(sample.footprintBytes),
                  limit: limits.memoryBytes, limits: limits, at: sample.uptime, into: &events)
        previous = sample
        return events
    }

    /// CPU% from the cumulative-time delta; nil for the first sample or a
    /// non-advancing clock.
    private func cpuPercent(for sample: ResourceSample) -> Double? {
        guard let previous else { return nil }
        return sample.cpuPercent(since: previous)
    }

    private static func step(
        _ metric: ResourceMetric,
        state: inout MetricState,
        value: Double,
        limit: Double,
        limits: Limits,
        at time: TimeInterval,
        into events: inout [ResourceEvent]
    ) {
        if let start = state.episodeStart {
            state.peak = max(state.peak, value)
            if value < limit * limits.resetFraction {
                events.append(.ended(metric: metric, peak: state.peak, seconds: time - start))
                state.episodeStart = nil
                state.strikes = 0
            }
            return
        }
        guard value >= limit else {
            state.strikes = 0
            return
        }
        state.strikes += 1
        guard state.strikes >= limits.sustainedSamples else { return }
        if let last = state.lastBegan, time - last < limits.cooldownSeconds { return }
        state.episodeStart = time
        state.peak = value
        state.lastBegan = time
        events.append(.began(metric: metric, value: value, limit: limit))
    }
}
