import os

/// Performance instrumentation for the streaming log feeds (JS Console,
/// Reactotron, the shared scroller). Watch it live while exercising the app:
///
///     /usr/bin/log stream --info --predicate 'subsystem == "com.rohindh.droidective.perf"'
///
/// Everything logs `.public` — the payload is sizes and durations, never
/// content. Cheap when Console isn't attached (os.Logger no-ops early).
///
/// A breach past `backendThresholdMs` also reaches the backend through
/// `AppLog`, because a main-thread operation that long is what a user
/// experiences as a hang, and until now these warnings existed only on the
/// developer's own machine: the app's largest hang issue had to be diagnosed
/// from tag aggregates because nothing said *what* was slow.
enum PerfLog {
    static let console = Logger(subsystem: "com.rohindh.droidective.perf", category: "js-console")
    static let feed = Logger(subsystem: "com.rohindh.droidective.perf", category: "log-feed")

    /// Local warnings start here — frequent, cheap, useful with Console open.
    static let localThresholdMs: Double = 4

    /// Backend reports start here. Well past a frame: at 250 ms the user is
    /// watching the app not repaint, and Sentry's own hang detector fires at
    /// 2000 ms, so this is the band that explains a hang before it is one.
    static let backendThresholdMs: Double = 250

    /// Run `body`, logging a warning when it exceeds `thresholdMs`.
    @discardableResult
    static func measure<T>(
        _ logger: Logger, _ label: String, thresholdMs: Double = localThresholdMs, _ body: () -> T
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

    /// `measure` for work on the main actor that is worth reporting from the
    /// field. `area` keys the backend's rate limit; `label` stays a fixed
    /// string so no identifier can ride out inside it.
    @discardableResult
    @MainActor
    static func measureReported<T>(
        _ area: AppLog.Area, _ label: String, _ body: () -> T
    ) -> T {
        let start = ContinuousClock.now
        let result = body()
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        guard ms >= localThresholdMs else { return result }
        AppLog.write(
            ms >= backendThresholdMs ? .warn : .debug,
            area,
            "\(label) was slow",
            ["ms": Int(ms.rounded())],
            toBackend: ms >= backendThresholdMs
        )
        return result
    }
}
