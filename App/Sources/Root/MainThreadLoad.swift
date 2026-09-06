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

    private var sampler: Task<Void, Never>?

    private init() {}

    /// Begin sampling. Idempotent — every window's launch setup may call it.
    func start() {
        guard sampler == nil else { return }
        sampler = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let started = ContinuousClock.now
                try? await Task.sleep(for: Self.period)
                guard let self, !Task.isCancelled else { return }
                // A system sleep lands here as an enormous reading; it means
                // nothing about load, and `FeedFlushCadence.maxInterval` is
                // what keeps it from parking the feeds. Clamping it here
                // instead would need a "was the Mac asleep?" guess.
                self.lateness = FeedFlushCadence.lateness(
                    elapsed: ContinuousClock.now - started, requested: Self.period)
            }
        }
    }
}
