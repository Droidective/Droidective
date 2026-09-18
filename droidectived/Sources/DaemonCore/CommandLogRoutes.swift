import ADBKit
import Foundation

/// Wire shapes for the Command Log — the recent adb calls behind Settings ▸
/// Privacy ▸ Command log.
///
/// The daemon decides nothing about what is in it. `AdbClient` already records
/// every call it makes into the `CommandLog` actor it was handed, gated on the
/// `isUserInitiated` task-local, so the whole feature here is scoping that
/// task-local around a route and reading the actor back out.
public enum CommandLogProtocol {
    /// The header a client sets on a call it makes on a *timer* rather than
    /// because someone pressed something.
    ///
    /// The Mac keeps background polling out of the log by simply not wrapping
    /// it (`MeminfoView`: "the first read is user-initiated so it lands in the
    /// Recent log; the 2s polling that follows stays out"). Only the client
    /// knows which of the two a call is, so it has to say — a route cannot tell
    /// a refresh someone clicked from the poll that follows it.
    ///
    /// **Absent means recorded**, and that direction is deliberate. The log
    /// holds 200 entries, so a poll that forgets this header is visible noise
    /// somebody notices and fixes; an action that forgot the opposite flag
    /// would be silently missing from the log a bug report is pasted out of,
    /// which is the failure mode the Mac's own checklist calls out as silent.
    public static let header = "X-Droidective-Background"

    /// Whether this request is background polling, from the header's value.
    ///
    /// Pure so the rule is testable without a socket: anything other than an
    /// absent header or an explicit "0"/"false" counts as background, because a
    /// client that bothered to send the header meant it.
    public static func isBackground(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespaces).lowercased()
        if normalized.isEmpty || normalized == "0" || normalized == "false" { return false }
        return true
    }

    /// One recorded adb call.
    ///
    /// A DTO rather than `CommandLogEntry`: that type carries a `Duration` and
    /// a `Date`, neither of which has a stable JSON form worth pinning, so the
    /// conversion happens once here instead of in each client.
    public struct Entry: Codable, Equatable, Sendable {
        public let id: String
        /// Milliseconds since the epoch — the row shows a time, and a number
        /// avoids every client agreeing on a date format.
        public let at: Int
        public let command: String
        /// Absent when the process was killed rather than exiting, which the
        /// row renders as "killed" exactly as `CommandLogRow.exitLabel` does.
        public let exitCode: Int?
        public let durationMs: Int
        public let stdout: String
        public let stderr: String

        public init(_ entry: CommandLogEntry) {
            id = entry.id.uuidString
            at = Int(entry.timestamp.timeIntervalSince1970 * 1000)
            command = entry.command
            exitCode = entry.exitCode.map(Int.init)
            durationMs = Self.milliseconds(entry.duration)
            stdout = entry.stdout
            stderr = entry.stderr
        }

        /// `CommandLogRow.exitLabel`'s arithmetic, which is the only place the
        /// Mac converts a `Duration` for display.
        static func milliseconds(_ duration: Duration) -> Int {
            Int(duration.components.seconds * 1000)
                + Int(duration.components.attoseconds / 1_000_000_000_000_000)
        }
    }

    public struct ListResponse: Codable, Equatable, Sendable {
        /// Most-recent-first, as `CommandLog.snapshot()` orders them.
        public let entries: [Entry]
        public init(entries: [Entry]) { self.entries = entries }
    }
}

/// The two Command Log routes.
///
/// Separate from `DaemonServer` for the reason `CrashRoutes` is: its dispatch
/// stays a table of routes, and these are testable without a socket.
enum CommandLogRoutes {
    /// Neither route takes a body — the log is the daemon's, not a device's.
    static func list(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        let entries = await backend.commandLog()
        return (200, DaemonProtocol.encoded(CommandLogProtocol.ListResponse(
            entries: entries.map(CommandLogProtocol.Entry.init))))
    }

    static func clear(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        await backend.clearCommandLog()
        return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(
            FeatureResult(ok: true, message: "Command log cleared"))))
    }
}
