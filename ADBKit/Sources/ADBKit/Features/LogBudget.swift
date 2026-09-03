import Foundation

/// A per-key rate limit for logs that leave the machine.
///
/// Local `os_log` can take everything — it costs nothing when Console isn't
/// attached. A backend sink cannot: the events worth logging are exactly the
/// ones that repeat, and the app's own numbers say how badly. One user
/// produced 1931 hang reports from a single session (DROIDECTIVE-MAC-B), and
/// the streaming feeds breach their slow-operation threshold many times a
/// second under load. Unbudgeted, the first pathological session would spend
/// the whole project's log quota and the next one would arrive to none.
///
/// Keyed rather than global so a chatty area can't starve a quiet one: the
/// Reactotron feed hitting its limit must not hide the one log the updater
/// emits all day.
///
/// The suppressed count rides on the next admitted log, because the magnitude
/// is the diagnostic. "Flush took 300 ms" is ambiguous; "took 300 ms, 412
/// suppressed since the last one" is the bug.
public struct LogBudget: Sendable {
    public struct Decision: Equatable, Sendable {
        public let allowed: Bool
        /// How many were dropped for this key since the last admitted one.
        /// Always 0 when `allowed` is false — it is reported *to* the log that
        /// gets through, not to the ones that don't.
        public let suppressed: Int

        public init(allowed: Bool, suppressed: Int) {
            self.allowed = allowed
            self.suppressed = suppressed
        }
    }

    private struct Window {
        var openedAt: Double
        var admitted: Int
        var suppressed: Int
    }

    public let limit: Int
    public let windowSeconds: Double
    private var windows: [String: Window] = [:]

    /// - Parameters:
    ///   - limit: admissions allowed per key per window.
    ///   - windowSeconds: how long a window lasts before the count resets.
    public init(limit: Int = 5, windowSeconds: Double = 60) {
        self.limit = max(1, limit)
        self.windowSeconds = max(0, windowSeconds)
    }

    /// Whether a log for `key` may be sent at `seconds` (a monotonic reading).
    public mutating func admit(_ key: String, at seconds: Double) -> Decision {
        guard var window = windows[key] else {
            windows[key] = Window(openedAt: seconds, admitted: 1, suppressed: 0)
            return Decision(allowed: true, suppressed: 0)
        }
        // A window that has run out re-opens and reports what it swallowed.
        if seconds - window.openedAt >= windowSeconds {
            let carried = window.suppressed
            windows[key] = Window(openedAt: seconds, admitted: 1, suppressed: 0)
            return Decision(allowed: true, suppressed: carried)
        }
        guard window.admitted < limit else {
            window.suppressed += 1
            windows[key] = window
            return Decision(allowed: false, suppressed: 0)
        }
        let carried = window.suppressed
        window.admitted += 1
        window.suppressed = 0
        windows[key] = window
        return Decision(allowed: true, suppressed: carried)
    }

    /// Keys currently tracked — bounded in practice by the number of call
    /// sites, which is why this needs no eviction.
    public var trackedKeys: Int { windows.count }
}
