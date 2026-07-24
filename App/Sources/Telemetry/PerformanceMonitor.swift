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
    /// plus every open tab across both panes.
    struct FeatureContext {
        let activeFeature: String?
        let openFeatures: [String]
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

    private var poller: Task<Void, Never>?
    private var watchdog = ResourceWatchdog()
    private var perFeature = FeaturePerfAggregator()

    /// Begin sampling every `interval`. `context` is read on the main actor each
    /// tick, so it can reach into AppState safely. Each sample feeds two things:
    /// the watchdog (threshold spikes → incident events) and the per-feature
    /// aggregator (resource baselines attributed to the active feature).
    func start(interval: Duration = .seconds(5), context: @escaping @MainActor () -> FeatureContext) {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                guard let sample = ProcessStats.sample() else { continue }
                let context = context()
                let cpuLimitOverride = Self.cpuExpectedHigh(context) ? Self.mirrorCPULimitPercent : nil
                for event in self.watchdog.ingest(sample, cpuLimitOverride: cpuLimitOverride) {
                    Telemetry.shared.reportResourceEvent(event, context: context)
                }
                if let record = self.perFeature.ingest(sample, feature: context.activeFeature ?? "none") {
                    Telemetry.shared.reportFeaturePerf(record)
                }
            }
        }
    }
}
