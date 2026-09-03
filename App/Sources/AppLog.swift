import ADBKit
import Foundation
import os

/// The app's logging front door: one call writes to the local unified log and,
/// when it is worth the quota, to the backend as a structured log line.
///
/// Watch the local half live while exercising the app:
///
///     /usr/bin/log stream --info --predicate 'subsystem BEGINSWITH "com.rohindh.droidective"'
///
/// Two sinks, two very different budgets. `os_log` costs nothing when nothing
/// is attached, so it takes everything. The backend gets only what would help
/// diagnose a report from someone else's machine, rate-limited per area by
/// `LogBudget` — the events worth logging are the ones that repeat, and one
/// session here has produced 1931 of them.
///
/// Everything is `.public` and every attribute is a number, a feature id, or a
/// fixed label. No paths, URLs, device serials, package ids or command
/// contents, matching Settings ▸ Privacy and the privacy policy. That is a
/// property of the call sites, so keep it that way: the type accepts a fixed
/// `Area` and `[String: Int]` rather than free-form strings for exactly this
/// reason.
@MainActor
enum AppLog {
    enum Level: String, Sendable {
        case debug, info, warn, error
    }

    /// The subsystem's areas. Fixed, so a log line can never carry an
    /// identifier in the place a category goes, and so the backend's rate
    /// limit has a stable key to count against.
    enum Area: String, CaseIterable, Sendable {
        case feed          // the streaming log/console feeds
        case reactotron
        case jsConsole = "js-console"
        case mirror
        case device
        case tools
        case updater
        case window

        var logger: Logger {
            Logger(subsystem: "com.rohindh.droidective", category: rawValue)
        }
    }

    /// At most five lines per area per minute reach the backend. Five is
    /// enough to see a pattern and small enough that a pathological session
    /// can't spend the project's quota; the count of what it swallowed rides
    /// out on the next line that fits, so the magnitude survives the limit.
    private static var budget = LogBudget(limit: 5, windowSeconds: 60)

    private static let started = ContinuousClock.now

    private static var nowSeconds: Double {
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
    }

    /// Record something worth knowing. Always logged locally; forwarded to the
    /// backend when `toBackend` is set and the area's budget allows.
    static func write(
        _ level: Level,
        _ area: Area,
        _ message: String,
        _ attributes: [String: Int] = [:],
        toBackend: Bool = false
    ) {
        let rendered = attributes.isEmpty
            ? message
            : "\(message) " + attributes.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
        local(level, area, rendered)

        guard toBackend else { return }
        let decision = budget.admit(area.rawValue, at: nowSeconds)
        guard decision.allowed else { return }
        var payload: [String: Any] = attributes
        payload["area"] = area.rawValue
        // Zero would read as "nothing was dropped" rather than "not
        // applicable", so the key is simply absent when there is no burst.
        if decision.suppressed > 0 { payload["suppressed"] = decision.suppressed }
        Telemetry.shared.log(level, message, payload)
    }

    private static func local(_ level: Level, _ area: Area, _ rendered: String) {
        let logger = area.logger
        switch level {
        case .debug: logger.debug("\(rendered, privacy: .public)")
        case .info: logger.info("\(rendered, privacy: .public)")
        case .warn: logger.warning("\(rendered, privacy: .public)")
        case .error: logger.error("\(rendered, privacy: .public)")
        }
    }
}
