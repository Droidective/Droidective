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

    /// Lateness past which a sample cannot be a main-thread stall at all.
    ///
    /// The sampler measures how late its own turn arrives, and that conflates
    /// two unrelated things: a main thread that is *busy*, and a process that
    /// is not being scheduled at all — a sleeping Mac, App Nap, a debugger's
    /// SIGSTOP. Only the first is a hang, and the second is unbounded. The
    /// field reported single samples of 164 s, 298 s, 407 s and 577 s in three
    /// days, every one of them with the app in the background, and each was
    /// shipped as `stall_worst_ms` — the very field this type exists to
    /// supply, because Sentry fills a hang's duration in from the configured
    /// threshold. A suspension reported as a stall made the replacement
    /// instrument exactly as untrustworthy as the number it replaced.
    ///
    /// `MainThreadLoad` measures on a `SuspendingClock`, which excludes system
    /// sleep by construction, so this is the second line rather than the
    /// first: App Nap and timer coalescing throttle a backgrounded app without
    /// the machine ever sleeping, and no clock distinguishes those from work.
    ///
    /// A minute is where the line sits. The longest main-thread block this app
    /// can produce is a synchronous adb call at `AdbClient`'s 30 s timeout;
    /// past a minute macOS has long since drawn the beachball, and a process
    /// still alive to report the sample was suspended, not working.
    public static let implausibleLateness: Duration = .seconds(60)

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

        /// Samples thrown out as suspensions rather than stalls
        /// (`implausibleLateness`). Reported rather than dropped silently: a
        /// window with discards is one where the process stopped being
        /// scheduled, which explains an idle gap in every *other* number here
        /// — and a discard count that starts climbing is how a wrong ceiling
        /// would announce itself instead of quietly eating real hangs.
        public let discarded: Int

        /// Share of sampled turns that stalled, 0…100. A single 8 s stall in
        /// ten minutes and a thread late a third of the time are different
        /// problems, and this is what separates them.
        public var stalledPercent: Int {
            samples > 0 ? Int((Double(stalls) / Double(samples) * 100).rounded()) : 0
        }

        /// Nothing to report: the thread kept up for the whole window.
        ///
        /// Deliberately blind to `discarded`. A window that discarded samples
        /// is one where the Mac slept or the app was throttled, and a sleeping
        /// Mac must not become a reason to send an event — the discard count
        /// rides out on the reports that ship anyway.
        public var isQuiet: Bool { stalls == 0 }
    }

    private var latenessMilliseconds: [Int] = []
    private var discarded = 0

    public init() {}

    public mutating func ingest(_ lateness: Duration) {
        let millis = Self.milliseconds(lateness)
        // A suspension is not a stall. Counted, never summarised — one such
        // sample in a window would otherwise *be* the worst and, when it is
        // the only stalled sample, the median too.
        guard millis <= Self.milliseconds(Self.implausibleLateness) else {
            discarded += 1
            return
        }
        latenessMilliseconds.append(millis)
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
        guard !latenessMilliseconds.isEmpty || discarded > 0 else { return nil }
        let stalled = latenessMilliseconds
            .filter { $0 >= Self.milliseconds(Self.threshold) }
            .sorted()
        return Window(
            samples: latenessMilliseconds.count,
            stalls: stalled.count,
            worstMilliseconds: latenessMilliseconds.max() ?? 0,
            medianStallMilliseconds: stalled.isEmpty ? 0 : stalled[stalled.count / 2],
            discarded: discarded)
    }

    /// Summarise and start a fresh window. Exactly one reporter may do this.
    public mutating func takeWindow() -> Window? {
        defer {
            latenessMilliseconds.removeAll(keepingCapacity: true)
            discarded = 0
        }
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
