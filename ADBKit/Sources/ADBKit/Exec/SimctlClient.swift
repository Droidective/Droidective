import Foundation

public enum SimctlError: Error, LocalizedError, Sendable {
    case xcrunNotFound

    public var errorDescription: String? {
        switch self {
        case .xcrunNotFound:
            return "Xcode not found. Install Xcode to control iOS Simulators."
        }
    }
}

/// The `xcrun simctl` exec wrapper — AdbClient's counterpart for iOS
/// Simulators. Throws only `SimctlError.xcrunNotFound`; command failures come
/// back as `AdbResult` data. Unlike adb there is no `-s` flag — device-scoped
/// commands take the UDID inline (`simctl io <udid> screenshot …`), so
/// callers pass full argument vectors.
public struct SimctlClient: Sendable {
    public static let defaultTimeout: Duration = .seconds(30)
    public static let defaultMaxOutput = 10 * 1024 * 1024

    public let log: CommandLog
    let runner: any ProcessRunning
    let xcrunPath: String
    let isExecutableFile: @Sendable (String) -> Bool

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        log: CommandLog = CommandLog(),
        xcrunPath: String = "/usr/bin/xcrun",
        isExecutableFile: @escaping @Sendable (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    ) {
        self.runner = runner
        self.log = log
        self.xcrunPath = xcrunPath
        self.isExecutableFile = isExecutableFile
    }

    /// Whether `simctl` can run at all (Xcode's xcrun is present). Cheap — a
    /// filesystem check (injected in tests, so mock-driven suites don't
    /// depend on the host having an /usr/bin/xcrun), no process spawn.
    public var available: Bool {
        isExecutableFile(xcrunPath)
    }

    public func run(
        _ args: [String],
        timeout: Duration = SimctlClient.defaultTimeout,
        maxOutputBytes: Int = SimctlClient.defaultMaxOutput
    ) async throws(SimctlError) -> AdbResult {
        guard available else { throw .xcrunNotFound }
        let clock = ContinuousClock()
        let started = clock.now
        let output = await runner.run(
            executable: xcrunPath,
            arguments: ["simctl"] + args,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes
        )
        await log.record(
            command: "xcrun simctl \(args.joined(separator: " "))",
            exitCode: output.exitCode,
            duration: clock.now - started,
            stdout: output.stdoutText,
            stderr: output.stderrText
        )
        var stderr = output.stderrText
        if stderr.isEmpty && output.exitCode != 0 {
            stderr = "simctl command failed"
        }
        return AdbResult(
            stdout: output.stdoutText,
            stderr: stderr,
            exitCode: output.exitCode,
            timedOut: output.timedOut
        )
    }
}

/// Map common simctl stderr to a short, human message.
public func friendlySimctlError(_ result: AdbResult, fallback: String) -> String {
    if result.timedOut { return "The command timed out." }
    let text = result.stderr.lowercased()
    if text.contains("current state: booted") { return "Simulator is already booted." }
    if text.contains("current state: shutdown") { return "Simulator is already shut down." }
    if text.contains("invalid device") {
        return "Simulator not found — it may have been deleted."
    }
    if text.contains("unable to lookup in current state") {
        return "Simulator isn't booted — boot it first."
    }
    let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}
