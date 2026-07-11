import os

/// Performance instrumentation for the streaming log feeds (JS Console,
/// Reactotron, the shared scroller). Watch it live while exercising the app:
///
///     log stream --info --predicate 'subsystem == "com.rohindh.droidective.perf"'
///
/// Everything logs `.public` — the payload is sizes and durations, never
/// content. Cheap when Console isn't attached (os.Logger no-ops early).
enum PerfLog {
    static let console = Logger(subsystem: "com.rohindh.droidective.perf", category: "js-console")
    static let feed = Logger(subsystem: "com.rohindh.droidective.perf", category: "log-feed")

    /// Run `body`, logging a warning when it exceeds `thresholdMs`.
    @discardableResult
    static func measure<T>(
        _ logger: Logger, _ label: String, thresholdMs: Double = 4, _ body: () -> T
    ) -> T {
        let start = ContinuousClock.now
        let result = body()
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        if ms >= thresholdMs {
            logger.warning("\(label, privacy: .public) took \(ms, format: .fixed(precision: 1), privacy: .public)ms")
        }
        return result
    }
}
