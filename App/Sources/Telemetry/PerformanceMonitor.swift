import ADBKit
import Foundation

/// Watches the app's *own* CPU and memory footprint and reports sustained
/// overuse to telemetry — a Sentry warning grouped per metric + feature and a
/// PostHog event — tagged with the features open at the time so spikes are
/// attributable. The threshold logic is ADBKit's `ResourceWatchdog` (pure,
/// tested); this owns only the timer and the feature context.
@MainActor
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    private init() {}

    /// Which features were on screen when an incident fired: the focused tab
    /// plus every open tab across both panes — and what the app was actually
    /// doing, which is rarely the same thing. Every tab stays mounted, so
    /// `activeFeature` names what the user was looking at while three mirrors
    /// streamed behind it.
    struct FeatureContext {
        let activeFeature: String?
        let openFeatures: [String]
        /// Live work, gathered by the caller because only it can reach the
        /// window registry. `sessionSeconds` is filled in here.
        var census: WorkloadCensus = WorkloadCensus()
    }

    /// Features that legitimately peg the CPU while on screen: live screen
    /// mirroring and recording both decode H.264 in-process, so ~two busy cores
    /// is expected, not an incident. CPU overuse gets a raised limit — not a
    /// waiver — while one of these is open; the per-feature baseline
    /// (`feature_perf`) still records it, and memory is watched regardless.
    private static let cpuIntensiveFeatures: Set<String> = ["scrcpy", "screen-record"]

    /// The raised CPU limit while a mirror feature is open. The old waiver
    /// was `.infinity`, which made the v3.1.0 mirror-session leak invisible:
    /// a user burned 250%+ for hours with a scrcpy tab open and telemetry
    /// never fired an incident. Healthy mirroring is ~two busy cores; well
    /// past four sustained is a leak, and it must report.
    private static let mirrorCPULimitPercent: Double = 450

    /// Whether a CPU-intensive feature is on screen (focused or open in either
    /// pane), so this sample is judged against the raised mirror limit
    /// instead of the base one.
    private static func cpuExpectedHigh(_ context: FeatureContext) -> Bool {
        if let active = context.activeFeature, cpuIntensiveFeatures.contains(active) { return true }
        return context.openFeatures.contains { cpuIntensiveFeatures.contains($0) }
    }

    /// Ticks between health reports. The poller runs every 5 s and this is a
    /// windowed summary, not a sample, so a five-minute window is both enough
    /// resolution to see a footprint climbing over an hour and little enough
    /// event volume to sit inside a free plan.
    private static let healthReportTicks = 60

    private var poller: Task<Void, Never>?
    private var watchdog = ResourceWatchdog()
    private var perFeature = FeaturePerfAggregator()
    private var ticksUntilHealthReport = healthReportTicks

    /// App-wide CPU and memory across the health window. `FeaturePerfAggregator`
    /// already keeps this per *feature*, keyed on whatever is in the
    /// foreground; nothing kept the plain app-wide baseline, so no event could
    /// say what this app normally costs — and a 102% peak means one thing on a
    /// process that idles at 3% and another on one that sits at 40.
    private var usage = UsageWindow()

    /// The previous sample, kept here as well as inside the watchdog: CPU is a
    /// delta between two cumulative readings, and `UsageWindow` needs the same
    /// figure the watchdog derives privately.
    private var previousSample: ResourceSample?

    /// When sampling began, which is app launch — `start()` is called once
    /// from the first window's appear. Filled into every census so a footprint
    /// can be read against how long the session has been running; growth
    /// percentage alone cannot separate ten minutes from eleven hours.
    private var startedAt: TimeInterval?

    /// Begin sampling every `interval`. `context` is read on the main actor each
    /// tick, so it can reach into AppState safely. Each sample feeds two things:
    /// the watchdog (threshold spikes → incident events) and the per-feature
    /// aggregator (resource baselines attributed to the active feature).
    func start(interval: Duration = .seconds(5), context: @escaping @MainActor () -> FeatureContext) {
        guard poller == nil else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                guard let sample = ProcessStats.sample() else { continue }
                var context = context()
                context.census.sessionSeconds = self.sessionSeconds(at: sample.uptime)

                // CPU before anything reports, so an alert raised on this very
                // sample already sees it. The watchdog derives the same figure
                // privately; this is the copy the app-wide window keeps.
                let cpuPercent = self.previousSample.flatMap { sample.cpuPercent(since: $0) }
                self.previousSample = sample
                self.usage.ingest(cpuPercent: cpuPercent, footprintBytes: sample.footprintBytes)

                // Published before the watchdog runs: `reportResourceEvent`
                // reads this to answer "what was the app doing", and an alert
                // that fired on the previous tick's census would name the
                // wrong workload.
                Telemetry.shared.noteWorkload(context.census, usage: self.usage.summary())

                let cpuLimitOverride = Self.cpuExpectedHigh(context) ? Self.mirrorCPULimitPercent : nil
                for event in self.watchdog.ingest(sample, cpuLimitOverride: cpuLimitOverride) {
                    Telemetry.shared.reportResourceEvent(event, context: context)
                }
                if let record = self.perFeature.ingest(sample, feature: context.activeFeature ?? "none") {
                    Telemetry.shared.reportFeaturePerf(record)
                }
                self.ticksUntilHealthReport -= 1
                guard self.ticksUntilHealthReport <= 0 else { continue }
                self.ticksUntilHealthReport = Self.healthReportTicks
                // Both windows drain here and nowhere else: a second drainer
                // would leave each of them an arbitrary half of the samples.
                // The drained usage window is republished first so the health
                // report carries the window it summarises rather than the one
                // that just started.
                let closed = self.usage.takeWindow()
                Telemetry.shared.noteWorkload(context.census, usage: closed)
                Telemetry.shared.reportHealth(
                    footprintBytes: sample.footprintBytes,
                    stall: MainThreadLoad.shared.takeStallWindow())
            }
        }
    }

    /// Seconds since sampling began. `ResourceSample.uptime` is
    /// `ProcessInfo.systemUptime`, the same monotonic clock `startedAt` was
    /// taken from, so this is a plain subtraction and no wall-clock change can
    /// make it run backwards.
    private func sessionSeconds(at uptime: TimeInterval) -> Int {
        guard let startedAt else { return 0 }
        return Int(max(0, uptime - startedAt).rounded())
    }
}
