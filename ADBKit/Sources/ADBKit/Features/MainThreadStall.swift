import Foundation

/// The app's own record of how long the main thread went away for.
///
/// This exists because the hang reports the app already sends cannot answer
/// "how bad was it". Sentry's hang integration fills the duration in from the
/// *configured threshold* — `durationMs = appHangTimeoutInterval * 1000` — so
/// every event says "at least 2000 ms" whether the thread was gone for two
/// seconds or forty. Sixty-odd such reports from one install told us a hang
/// happened and nothing about its size.
///
/// The measurement was already being taken and thrown away: `MainThreadLoad`
/// asks the main thread for a turn twice a second and records how late the turn
/// arrives, purely so the feeds can pace against it. A thread that disappeared
/// for eight seconds shows up there as one ~7.5 s sample. Keeping those samples
/// is the whole instrument — no new probe, no stopwatch around a mutation
/// (which the feed convention warns measures the wrong thing, since the
/// expensive part is the layout the mutation causes in a later runloop pass).
///
/// Pure and value-typed, so the summarising is tested without a clock.
public struct MainThreadStall: Sendable, Equatable {
    /// Lateness past which a sample is a stall a person would notice rather
    /// than scheduler noise.
    ///
    /// 250 ms, matching the band `PerfLog.backendThresholdMs` already reports
    /// on: past a few frames the user is watching the app not repaint, and
    /// Sentry's own detector does not fire until 2000 ms — so this is the
    /// range that explains a hang *before* it is one.
    public static let threshold: Duration = .milliseconds(250)

    /// Samples kept before the oldest are dropped. At two samples a second
    /// this is ten minutes of history, comfortably more than the reporting
    /// window, and it bounds the memory of a type that exists to diagnose
    /// memory problems.
    static let capacity = 1200

    /// One reporting window, in whole milliseconds — the shape that goes to
    /// the backend, where a float would only be false precision.
    public struct Window: Sendable, Equatable {
        /// How many turns were sampled.
        public let samples: Int
        /// How many of them were late past `threshold`.
        public let stalls: Int
        /// The worst single lateness — the closest thing to "how long did it
        /// hang for", which is the question the hang events cannot answer.
        public let worstMilliseconds: Int
        /// Median lateness across *stalled* samples only. The median over all
        /// samples is zero on any healthy app and says nothing.
        public let medianStallMilliseconds: Int

        /// Share of sampled turns that stalled, 0…100. A single 8 s stall in
        /// ten minutes and a thread late a third of the time are different
        /// problems, and this is what separates them.
        public var stalledPercent: Int {
            samples > 0 ? Int((Double(stalls) / Double(samples) * 100).rounded()) : 0
        }

        /// Nothing to report: the thread kept up for the whole window.
        public var isQuiet: Bool { stalls == 0 }
    }

    private var latenessMilliseconds: [Int] = []

    public init() {}

    public mutating func ingest(_ lateness: Duration) {
        latenessMilliseconds.append(Self.milliseconds(lateness))
        if latenessMilliseconds.count > Self.capacity {
            latenessMilliseconds.removeFirst(latenessMilliseconds.count - Self.capacity)
        }
    }

    /// Summarise without resetting.
    ///
    /// For a reporter that must not disturb the window another one is
    /// accumulating: the health report drains on a fixed cadence, while a hang
    /// report fires whenever the thread misbehaves. If both consumed the
    /// samples they would each see an arbitrary half of them, and the number
    /// that matters — how late the thread has been *lately* — would be split
    /// between two events at random.
    ///
    /// Returns nil when nothing was sampled at all, which is distinct from a
    /// window that sampled a healthy thread: that reports `isQuiet`, so a
    /// caller can still record the baseline.
    public func summary() -> Window? {
        guard !latenessMilliseconds.isEmpty else { return nil }
        let stalled = latenessMilliseconds
            .filter { $0 >= Self.milliseconds(Self.threshold) }
            .sorted()
        return Window(
            samples: latenessMilliseconds.count,
            stalls: stalled.count,
            worstMilliseconds: latenessMilliseconds.max() ?? 0,
            medianStallMilliseconds: stalled.isEmpty ? 0 : stalled[stalled.count / 2])
    }

    /// Summarise and start a fresh window. Exactly one reporter may do this.
    public mutating func takeWindow() -> Window? {
        defer { latenessMilliseconds.removeAll(keepingCapacity: true) }
        return summary()
    }

    /// Whole milliseconds, rounded down. Negative durations cannot occur —
    /// `FeedFlushCadence.lateness` clamps at zero — but a floor at zero keeps
    /// that a property of this type too rather than an assumption about it.
    static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        let millis = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
        return Int(max(0, millis))
    }
}
