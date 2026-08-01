import Foundation

@testable import ADBKit

/// Wraps a real runner, passes every call through, and records the result.
///
/// Used once against a live emulator to capture genuine device output, then the
/// recording is committed and `FixtureProcessRunner` replays it offline. Nothing
/// in the shipping library depends on this — it lives in the test target so the
/// app carries no recording machinery.
final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    /// Above this, stdout is recorded as metadata only. Screenshots and
    /// bugreports are parser-irrelevant and would bloat the repo.
    static let maxRecordedBytes = 256 * 1024

    private let underlying: any ProcessRunning
    private let serial: String?
    private let lock = NSLock()
    private var entries: [ProcessFixture.Entry] = []

    init(wrapping underlying: any ProcessRunning, serial: String? = nil) {
        self.underlying = underlying
        self.serial = serial
    }

    var recorded: [ProcessFixture.Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func fixture(deviceModel: String? = nil, androidSdk: String? = nil) -> ProcessFixture {
        ProcessFixture(deviceModel: deviceModel, androidSdk: androidSdk, entries: recorded)
    }

    func run(
        executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int
    ) async -> ProcessOutput {
        let output = await underlying.run(
            executable: executable, arguments: arguments,
            timeout: timeout, maxOutputBytes: maxOutputBytes)

        // Denied commands are still executed — the caller needs the real result —
        // but nothing about them reaches disk.
        guard !FixtureRedaction.isDenied(arguments: arguments) else { return output }

        // Locking happens in a synchronous helper: NSLock is unavailable from an
        // async context under strict concurrency (same shape as MockProcessRunner).
        append(
            ProcessFixture.Entry(
                // Basename only: the resolved adb path contains the recording
                // host's home directory, and replay matches on arguments anyway.
                executable: URL(fileURLWithPath: executable).lastPathComponent,
                // Normalized so the fixture does not bake in this run's serial.
                arguments: FixtureRedaction.normalizeArguments(arguments, serial: serial),
                stdout: captured(output.stdout),
                stderr: captured(output.stderr),
                exitCode: output.exitCode,
                timedOut: output.timedOut,
                omittedReason: omissionReason(output.stdout)
            ))
        return output
    }

    private func append(_ entry: ProcessFixture.Entry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    /// UTF-8 text, scrubbed — or nil when the payload is binary or oversized.
    private func captured(_ data: Data) -> String? {
        guard data.count <= Self.maxRecordedBytes else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return FixtureRedaction.scrub(text, serial: serial)
    }

    private func omissionReason(_ data: Data) -> String? {
        if data.count > Self.maxRecordedBytes { return "over cap, \(data.count) bytes" }
        if String(data: data, encoding: .utf8) == nil { return "binary, \(data.count) bytes" }
        return nil
    }
}

/// Replays a recorded fixture: matches an invocation against the recording and
/// returns what the device actually said.
///
/// Matching is by exact argument vector, falling back to a longest-prefix match
/// so a fixture stays usable when a caller gains a trailing flag. An
/// unmatched invocation fails loudly rather than returning empty output — a
/// silent empty string is exactly how a parser test passes for the wrong reason.
final class FixtureProcessRunner: ProcessRunning, @unchecked Sendable {
    private let entries: [ProcessFixture.Entry]
    private let lock = NSLock()
    private var unmatched: [[String]] = []

    init(_ fixture: ProcessFixture) {
        self.entries = fixture.entries
    }

    convenience init(named name: String) throws {
        self.init(try ProcessFixture.load(named: name))
    }

    /// Argument vectors the fixture had no answer for. A test that cares should
    /// assert this is empty.
    var unmatchedInvocations: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return unmatched
    }

    func run(
        executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int
    ) async -> ProcessOutput {
        // Normalized the same way the recorder did, so a fixture captured against
        // emulator-5554 still matches a caller targeting emulator-5556.
        let normalized = FixtureRedaction.normalizeArguments(arguments)
        return match(normalized) ?? missing(normalized)
    }

    /// Synchronous so the lock stays out of an async context (NSLock is
    /// unavailable there under strict concurrency).
    private func match(_ arguments: [String]) -> ProcessOutput? {
        if let exact = entries.first(where: { $0.arguments == arguments }) {
            return exact.output
        }
        // Longest prefix wins, so a more specific recording beats a generic one.
        return entries
            .filter { arguments.starts(with: $0.arguments) && !$0.arguments.isEmpty }
            .max { $0.arguments.count < $1.arguments.count }?
            .output
    }

    private func missing(_ arguments: [String]) -> ProcessOutput {
        lock.lock()
        unmatched.append(arguments)
        lock.unlock()
        return ProcessOutput(
            stdout: Data(),
            stderr: Data("no fixture entry for: \(arguments.joined(separator: " "))".utf8),
            exitCode: 1,
            timedOut: false
        )
    }
}
