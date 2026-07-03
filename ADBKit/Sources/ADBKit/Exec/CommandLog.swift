import Foundation

public struct CommandLogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let command: String
    public let exitCode: Int32?
    public let duration: Duration
    public let stdout: String
    public let stderr: String

    public init(
        id: UUID,
        timestamp: Date,
        command: String,
        exitCode: Int32?,
        duration: Duration,
        stdout: String,
        stderr: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.command = command
        self.exitCode = exitCode
        self.duration = duration
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Recent adb invocations, surfaced in the Settings ▸ Command Log sheet.
///
/// Only commands run inside a `CommandLog.$isUserInitiated.withValue(true)`
/// scope are recorded — so the log shows the user's actions, not background
/// polling (device list, override reconciliation, logcat pid lookups).
public actor CommandLog {
    @TaskLocal public static var isUserInitiated = false

    public static let maxEntries = 200
    public static let maxCapture = 8000

    private var entries: [CommandLogEntry] = []

    public init() {}

    public func record(command: String, exitCode: Int32?, duration: Duration, stdout: String, stderr: String) {
        guard CommandLog.isUserInitiated else { return }
        entries.append(
            CommandLogEntry(
                id: UUID(),
                timestamp: Date(),
                command: command,
                exitCode: exitCode,
                duration: duration,
                stdout: String(stdout.prefix(CommandLog.maxCapture)),
                stderr: String(stderr.prefix(CommandLog.maxCapture))
            )
        )
        if entries.count > CommandLog.maxEntries {
            entries.removeFirst(entries.count - CommandLog.maxEntries)
        }
    }

    /// Most-recent-first snapshot.
    public func snapshot() -> [CommandLogEntry] {
        entries.reversed()
    }

    public func clear() {
        entries.removeAll()
    }
}

extension CommandLog {
    /// Run `body` as a user-initiated action, so the adb commands it triggers
    /// are recorded on the command log. Wraps the `isUserInitiated` task-local.
    public static func userInitiated<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        try await CommandLog.$isUserInitiated.withValue(true, operation: body)
    }
}
