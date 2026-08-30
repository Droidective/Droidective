import Foundation
import Testing

@testable import ADBKit

/// How long the *first* `adb devices` on a machine takes — the real command,
/// on the real host, with no adb server running yet.
///
/// This is not a unit test and does not run by default. It exists because that
/// one call is where both ports fell over, and the two failures looked nothing
/// alike from a log:
///
/// - **Linux**: it never returned. `adb devices` forks the adb *server*, prints
///   two lines and exits; corelibs left the child a zombie it never reaped, so
///   `terminationHandler` never fired and the continuation waiting on it was
///   suspended for the life of the process. The app came up with "0 features".
///   Fixed by `ExitWatcher`'s POSIX half.
/// - **Windows**: the same picture, and this file is how that was established
///   rather than guessed. The first run of this probe **hung** — thirty minutes
///   in CI against ten for the whole suite beside it — where the app's own
///   symptom ("0 features" in a launch screenshot taken at 30 s) was equally
///   explained by a hang and by a slow answer.
///
/// A screenshot cannot tell those apart. A stopwatch on the actual call can,
/// which is all this does: kill the server, time `adb devices`, print it, and
/// fail if it is not prompt.
///
/// **It bounds itself**, and that is not belt and braces. The call under
/// measurement is exactly the one that can fail to return at all, and neither
/// the runner's own watchdog nor swift-testing's `.timeLimit` can rescue a
/// continuation nobody will resume — the first one recovers by terminating a
/// process that is *still running*, and this one is already gone. So the wait
/// is raced against a sleep and a probe that would hang fails instead, with
/// every stage timestamped so the log says which one it stopped in.
///
/// Gated on `ADB_COLD_START_PROBE=1` and skipped otherwise, like the emulator
/// suites: it needs a real adb, and it kills the machine's adb server, which no
/// other test may have running under it.
@Suite(.serialized) struct AdbColdStartProbeTests {
    static var enabled: Bool { ProcessInfo.processInfo.environment["ADB_COLD_START_PROBE"] == "1" }

    /// adb from the SDK the host advertises, or from PATH.
    ///
    /// Deliberately not `ToolLocator`: its login-shell fallback is a *second*
    /// child process with the same shape as the one under measurement, and a
    /// probe whose own setup can hang is not a probe.
    static func adbPath() -> String? {
        let manager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        #if os(Windows)
        let executable = "adb.exe"
        let separator: Character = ";"
        #else
        let executable = "adb"
        let separator: Character = ":"
        #endif

        var candidates: [String] = []
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            guard let root = environment[key], !root.isEmpty else { continue }
            candidates.append(
                URL(fileURLWithPath: root)
                    .appendingPathComponent("platform-tools")
                    .appendingPathComponent(executable).path)
        }
        for directory in (environment["PATH"] ?? "").split(separator: separator) {
            candidates.append(
                URL(fileURLWithPath: String(directory)).appendingPathComponent(executable).path)
        }
        return candidates.first { manager.isExecutableFile(atPath: $0) }
    }

    /// The bound. A healthy cold call is ~3 s on macOS (adb's own wait for the
    /// server it just started) and ~0.2 s on Linux; ten seconds is far enough
    /// above both to survive a loaded runner and far below the point where
    /// someone would call the app broken.
    static let promptEnough: Duration = .seconds(10)

    /// How long the probe itself waits before calling it a hang. Well past
    /// `promptEnough`, so a slow answer is reported as slow rather than as a
    /// hang, and well under any CI job's patience.
    static let giveUpAfter: Duration = .seconds(45)

    /// Runs a command, or answers nil if it never came back.
    ///
    /// **Deliberately not a task group.** A group awaits every child before it
    /// returns, and cancelling one that is suspended on a continuation nobody
    /// will resume does not wake it — so the obvious spelling of this
    /// *inherits* the hang it exists to bound, which is how the first two
    /// attempts each parked a Windows job for a quarter of an hour. Two
    /// unstructured tasks racing one continuation is the shape that can walk
    /// away, and walking away from a wedged call is the whole point.
    ///
    /// The abandoned task is cancelled on the way past, which is what tears the
    /// child down (`SystemProcessRunner.run` kills it from its cancellation
    /// handler) for every case where cancellation *can* be observed.
    static func bounded(
        _ label: String, _ work: @escaping @Sendable () async -> ProcessOutput
    ) async -> (output: ProcessOutput?, elapsed: Duration) {
        let clock = ContinuousClock()
        let started = clock.now
        let answered = LockedBox(false)
        let output: ProcessOutput? = await withCheckedContinuation { continuation in
            let running = Task {
                let result = await work()
                if !answered.swap(true) { continuation.resume(returning: result) }
            }
            Task {
                try? await Task.sleep(for: giveUpAfter)
                guard !answered.swap(true) else { return }
                running.cancel()
                continuation.resume(returning: nil)
            }
        }
        let elapsed = clock.now - started
        print("=== \(label) took \(elapsed)\(output == nil ? " AND NEVER RETURNED" : "") ===")
        return (output, elapsed)
    }

    @Test(.enabled(if: enabled))
    func theFirstAdbDevicesReturnsPromptly() async throws {
        let adb = try #require(Self.adbPath(), "no adb on this host — set ANDROID_HOME or PATH")
        print("=== probing \(adb) ===")
        let runner = SystemProcessRunner()

        // Cold means cold: with a server already up, `adb devices` is a socket
        // round-trip and measures nothing. This is why the suite is serialized
        // and opt-in — it takes the host's adb server down.
        let killed = await Self.bounded("kill-server") {
            await runner.run(executable: adb, arguments: ["kill-server"], timeout: .seconds(30))
        }
        print("=== kill-server exit \(String(describing: killed.output?.exitCode)) ===")

        let cold = await Self.bounded("cold `adb devices`") {
            await runner.run(executable: adb, arguments: ["devices"], timeout: .seconds(30))
        }
        let output = try #require(
            cold.output,
            "the first adb devices never returned — this is the hang the ports fell over on")
        print("=== exit \(String(describing: output.exitCode)), timedOut \(output.timedOut) ===")
        print("=== stdout: \(output.stdoutText.replacingOccurrences(of: "\n", with: "\\n")) ===")
        print("=== stderr: \(output.stderrText.replacingOccurrences(of: "\n", with: "\\n")) ===")

        #expect(!output.timedOut, "the runner had to kill it, which is a hang by another name")
        #expect(output.stdoutText.contains("List of devices"))
        #expect(
            cold.elapsed < Self.promptEnough,
            "the first adb devices took \(cold.elapsed): the app is unusable for that long at every launch")
    }

    /// The same measurement for a *warm* server, as the control.
    ///
    /// Without it a slow cold call is ambiguous: adb itself may simply be slow
    /// to start a server on this host, which is nothing the runner can fix. A
    /// warm call is a socket round-trip through the identical code path, so the
    /// difference between the two is the cost of the fork-and-exit shape.
    @Test(.enabled(if: enabled))
    func aWarmAdbDevicesIsTheControl() async throws {
        let adb = try #require(Self.adbPath(), "no adb on this host — set ANDROID_HOME or PATH")
        let runner = SystemProcessRunner()
        _ = await Self.bounded("start-server") {
            await runner.run(executable: adb, arguments: ["start-server"], timeout: .seconds(30))
        }

        let warm = await Self.bounded("warm `adb devices`") {
            await runner.run(executable: adb, arguments: ["devices"], timeout: .seconds(30))
        }
        let output = try #require(warm.output, "even a warm adb devices never returned")
        #expect(!output.timedOut)
        #expect(warm.elapsed < Self.promptEnough)
    }
}
