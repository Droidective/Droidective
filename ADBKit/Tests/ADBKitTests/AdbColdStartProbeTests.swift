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
///   rather than guessed. The first run of this probe **hung** — thirty
///   minutes in CI against ten for the whole suite beside it — where the app's
///   own symptom ("0 features" in a launch screenshot taken at 30 s) was
///   equally explained by a hang and by a slow answer. Fixed by `ExitWatcher`'s
///   Windows half, which waits on the process handle.
///
/// A screenshot cannot tell those apart. A stopwatch on the actual call can,
/// which is all this does: kill the server, time `adb devices`, print it, and
/// fail if it is not prompt.
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

    /// The bound. A healthy cold call is ~0.2 s on macOS and on Linux since the
    /// reaper landed; ten seconds is far enough above that to survive a loaded
    /// runner and far enough below the 30 s the synthetic child produced on
    /// Windows to tell the two apart.
    static let promptEnough: Duration = .seconds(10)

    /// The time limit is not decoration. The first run of this probe hung — on
    /// Windows, exactly as Linux used to — and with no limit it sat in CI for
    /// thirty minutes against ten for the whole suite beside it, until it was
    /// cancelled by hand. A probe that can hang has to fail instead.
    @Test(.enabled(if: enabled), .timeLimit(.minutes(2)))
    func theFirstAdbDevicesReturnsPromptly() async throws {
        let adb = try #require(Self.adbPath(), "no adb on this host — set ANDROID_HOME or PATH")
        print("=== probing \(adb) ===")
        let runner = SystemProcessRunner()

        // Cold means cold: with a server already up, `adb devices` is a socket
        // round-trip and measures nothing. This is why the suite is serialized
        // and opt-in — it takes the host's adb server down.
        let killed = await runner.run(executable: adb, arguments: ["kill-server"], timeout: .seconds(30))
        print("=== kill-server exit \(String(describing: killed.exitCode)) ===")

        let clock = ContinuousClock()
        let started = clock.now
        let output = await runner.run(executable: adb, arguments: ["devices"], timeout: .seconds(120))
        let elapsed = clock.now - started

        print("=== cold `adb devices` took \(elapsed) ===")
        print("=== exit \(String(describing: output.exitCode)), timedOut \(output.timedOut) ===")
        print("=== stdout: \(output.stdoutText.replacingOccurrences(of: "\n", with: "\\n")) ===")
        print("=== stderr: \(output.stderrText.replacingOccurrences(of: "\n", with: "\\n")) ===")

        #expect(!output.timedOut, "the first adb devices never returned — this is the Linux hang's shape")
        #expect(output.stdoutText.contains("List of devices"))
        #expect(
            elapsed < Self.promptEnough,
            "the first adb devices took \(elapsed): the app is unusable for that long at every launch")
    }

    /// The same measurement for a *warm* server, as the control.
    ///
    /// Without it a slow cold call is ambiguous: adb itself may simply be slow
    /// to start a server on this host, which is nothing the runner can fix. A
    /// warm call is a socket round-trip through the identical code path, so the
    /// difference between the two is the cost of the fork-and-exit shape.
    @Test(.enabled(if: enabled), .timeLimit(.minutes(2)))
    func aWarmAdbDevicesIsTheControl() async throws {
        let adb = try #require(Self.adbPath(), "no adb on this host — set ANDROID_HOME or PATH")
        let runner = SystemProcessRunner()
        _ = await runner.run(executable: adb, arguments: ["start-server"], timeout: .seconds(120))

        let clock = ContinuousClock()
        let started = clock.now
        let output = await runner.run(executable: adb, arguments: ["devices"], timeout: .seconds(60))
        let elapsed = clock.now - started

        print("=== warm `adb devices` took \(elapsed) ===")
        #expect(!output.timedOut)
        #expect(elapsed < Self.promptEnough)
    }
}
