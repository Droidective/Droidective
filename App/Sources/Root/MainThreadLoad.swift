import ADBKit
import Foundation

/// How far behind the main thread is, sampled by asking it for a turn on a
/// fixed schedule and measuring how late that turn arrives.
///
/// The streaming feeds pace themselves against this (`FeedFlushCadence`).
/// One app-wide sampler rather than a measurement per feed, for two reasons:
///
/// - **Load is a property of the thread, not of a feed.** A user with nine
///   mounted tabs has three feeds, a mirror session and every hidden tab's
///   layout sharing one thread. A feed that measured only its own flushes
///   would under-observe precisely when it matters — the starved feed is the
///   one that isn't getting turns, so it has nothing to measure.
/// - **Timing a flush measures the wrong thing.** The expensive part is the
///   SwiftUI layout the flush *causes*, which happens after the mutation
///   returns, in a later runloop pass. Waiting for a turn on this thread
///   prices that in; a stopwatch around the mutation does not.
///
/// Deliberately not `@Observable`: this changes twice a second for the life of
/// the app, and anything observing it would re-render on every sample — the
/// exact cost it exists to bound. Feeds read it when they schedule a flush.
@MainActor
final class MainThreadLoad {
    static let shared = MainThreadLoad()

    /// Sampling period. Frequent enough that a feed scheduling a flush reads a
    /// current number, rare enough to be free (two wake-ups a second, no
    /// allocation, no observation).
    private static let period: Duration = .milliseconds(500)

    /// How late the last sample's turn arrived — zero when the thread kept up.
    /// Self-clearing: a saturated thread reports a large value, and the next
    /// sample after it clears reports zero again, so no decay is needed.
    private(set) var lateness: Duration = .zero

    /// The same samples, kept rather than overwritten (`MainThreadStall`).
    ///
    /// Pacing only ever needs the latest reading, so that is all this used to
    /// keep — and the app therefore measured its own stalls twice a second for
    /// the life of the process and remembered none of them. The hang reports it
    /// sends cannot supply a duration (Sentry fills that in from the
    /// configured threshold), so these samples are the only record of how long
    /// the thread actually went away for.
    private var stall = MainThreadStall()

    private var sampler: Task<Void, Never>?

    private init() {}

    /// The stalls in the current window, left in place. What a hang report
    /// reads — it fires on its own schedule and must not consume the window
    /// the health report is accumulating.
    func stallSummary() -> MainThreadStall.Window? {
        stall.summary()
    }

    /// Summarise the stalls since the last call and start a fresh window. The
    /// health report is the only caller; a second drainer would leave each of
    /// them an arbitrary half of the samples.
    func takeStallWindow() -> MainThreadStall.Window? {
        stall.takeWindow()
    }

    /// Begin sampling. Idempotent — every window's launch setup may call it.
    func start() {
        guard sampler == nil else { return }
        sampler = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // `SuspendingClock`, not `ContinuousClock`: the two differ by
                // exactly the thing being measured wrongly here. A continuous
                // clock keeps counting while the Mac sleeps, so a lid closed
                // for ten minutes read as a ten-minute main-thread stall —
                // and once `MainThreadStall` started *keeping* these samples
                // instead of only pacing feeds with them, that reading shipped
                // as `stall_worst_ms`. Suspending stops for system sleep by
                // construction, which is the "was the Mac asleep?" question
                // the old comment here said could not be answered. App Nap
                // still throttles a backgrounded app without the machine
                // sleeping, and no clock separates that from work, so
                // `MainThreadStall.implausibleLateness` is the second line.
                let started = SuspendingClock.now
                try? await Task.sleep(for: Self.period)
                guard let self, !Task.isCancelled else { return }
                self.lateness = FeedFlushCadence.lateness(
                    elapsed: SuspendingClock.now - started, requested: Self.period)
                self.stall.ingest(self.lateness)
            }
        }
    }
}
