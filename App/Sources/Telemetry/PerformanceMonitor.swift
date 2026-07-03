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

    private var poller: Task<Void, Never>?
    private var watchdog = ResourceWatchdog()

    /// Begin sampling every `interval`. `context` is read on the main actor
    /// only when an event fires, so it can reach into AppState safely.
    func start(interval: Duration = .seconds(5), context: @escaping @MainActor () -> FeatureContext) {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                guard let sample = ProcessStats.sample() else { continue }
                for event in self.watchdog.ingest(sample) {
                    Telemetry.shared.reportResourceEvent(event, context: context())
                }
            }
        }
    }
}
