import Foundation
import Testing
@testable import ADBKit

/// Real-process tests: the runner must never park cooperative threads, so
/// heavy concurrency here both validates behavior and acts as a starvation
/// regression net (the v1 runner deadlocked the async runtime under ~4
/// concurrent invocations).
@Suite struct SystemProcessRunnerTests {
    let runner = SystemProcessRunner()

    /// Timeout for the cases that assert a child *completed*, where the value
    /// is only a safety net rather than the thing under test.
    ///
    /// It was 5 s, which a loaded CI container can exceed just spawning
    /// `/bin/echo` — that produced three false failures in one day (`echo`
    /// reported `timedOut` with its output already captured). Generous here
    /// costs nothing: a healthy run finishes in milliseconds and never waits.
    /// The tests that genuinely measure timing — `timeoutKillsAndFlags` and
    /// `cancellationKillsChildAndReturnsPromptly` — keep their tight bounds,
    /// because there the duration *is* the assertion.
    static let generousTimeout: Duration = .seconds(30)

    @Test func capturesStdoutAndExitCode() async {
        let output = await runner.run(
            executable: ChildCommands.echo.executable,
            arguments: ChildCommands.echo.arguments, timeout: Self.generousTimeout
        )
        #expect(output.exitCode == 0)
        #expect(output.stdoutText == ChildCommands.echoOutput)
        #expect(!output.timedOut)
    }

    @Test func capturesStderrAndNonZeroExit() async {
        let output = await runner.run(
            executable: ChildCommands.stderrAndExit3.executable,
            arguments: ChildCommands.stderrAndExit3.arguments, timeout: Self.generousTimeout
        )
        #expect(output.exitCode == 3)
        #expect(output.stderrText == ChildCommands.stderrOutput)
    }

    @Test func launchFailureReportsNilExit() async {
        let output = await runner.run(
            executable: "/no/such/binary", arguments: [], timeout: Self.generousTimeout)
        #expect(output.exitCode == nil)
        #expect(output.stderrText.contains("failed to launch"))
    }

    @Test func timeoutKillsAndFlags() async {
        let clock = ContinuousClock()
        let started = clock.now
        let output = await runner.run(
            executable: ChildCommands.sleepForever.executable,
            arguments: ChildCommands.sleepForever.arguments, timeout: .milliseconds(300)
        )
        #expect(output.timedOut)
        #expect(output.exitCode == nil)
        #expect(clock.now - started < .seconds(10))
    }

    @Test func largeOutputIsCappedNotDeadlocked() async {
        // 2 MB of output with a 64 KB cap — the old blocking design risks a
        // full-pipe deadlock if draining stalls; the cap must also hold.
        let output = await runner.run(
            executable: ChildCommands.spewForever.executable,
            // Short on purpose, unlike the completion cases above: this child
            // never exits, so the timeout is what ends the test. Raising it
            // just adds dead wall-clock to every run.
            arguments: ChildCommands.spewForever.arguments, timeout: .seconds(3),
            maxOutputBytes: 64 * 1024
        )
        #expect(output.stdout.count == 64 * 1024)
    }

    /// A child that forks a long-lived grandchild and exits immediately must
    /// still be reported promptly.
    ///
    /// This is the exact shape of `adb devices` on a machine where the adb
    /// server is not yet running, and it is the failure that made the Linux
    /// app unusable on its first launch: the child exited, corelibs never
    /// reaped it, `terminationHandler` never fired, and the call was suspended
    /// for the life of the process. The window came up with "0 features" and
    /// no error, because the promise behind it simply never settled.
    ///
    /// The bound is what matters. The timeout here is generous *and* the
    /// assertion is that it finished well inside it — a run that takes the
    /// whole timeout has regressed even though it returned.
    ///
    /// POSIX only. The bug is a corelibs one, and `adb` does not have this
    /// shape on Windows anyway — but the reason for the gate is sharper than
    /// that: the child leaves a grandchild alive for thirty seconds, and on
    /// the Windows runner that was enough to push `timeoutKillsAndFlags` (a
    /// neighbour, measuring its own wall clock) from milliseconds to the same
    /// 30.3 s. A regression test that destabilises the suite around it is
    /// worse than no coverage on the platform it was never about.
    ///
    /// What that run *did* establish about Windows is written down in the
    /// parity tracker rather than left as folklore: the call returns correctly
    /// there, but only once the grandchild is gone, so the collector's grace
    /// does not bound the wait on that host.
    #if !os(Windows)
    @Test func aChildThatForksAGrandchildAndExitsIsStillReaped() async {
        let started = ContinuousClock().now
        let output = await runner.run(
            executable: ChildCommands.forksAndExits.executable,
            arguments: ChildCommands.forksAndExits.arguments,
            timeout: Self.generousTimeout
        )
        let elapsed = ContinuousClock().now - started

        #expect(output.exitCode == 0)
        #expect(!output.timedOut)
        #expect(output.stdoutText.contains("started"))

        // The grandchild holds the pipe open for 30 s; EOF is bounded by the
        // collector's grace, so this is a few seconds at most and nowhere near
        // the timeout.
        //
        #expect(elapsed < .seconds(15), "took \(elapsed), which means it waited on something")
    }
    #endif

    @Test func manyConcurrentInvocationsDoNotStarveTheRuntime() async {
        // 16 concurrent slow-ish processes — far past the old failure point.
        // A canary task must keep making progress while they run.
        let canaryTicks = LockedBox(0)
        let canary = Task {
            while !Task.isCancelled {
                canaryTicks.set(canaryTicks.get() + 1)
                try? await Task.sleep(for: .milliseconds(20))
            }
        }

        await withTaskGroup(of: Int32?.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    let output = await runner.run(
                        executable: ChildCommands.sleepThenPrint.executable,
                        arguments: ChildCommands.sleepThenPrint.arguments,
                        timeout: Self.generousTimeout
                    )
                    return output.exitCode
                }
            }
            for await code in group {
                #expect(code == 0)
            }
        }
        canary.cancel()
        #expect(canaryTicks.get() > 5, "canary task starved — runner is blocking cooperative threads")
    }

    @Test func cancellationKillsChildAndReturnsPromptly() async {
        // A long-running child under a generous timeout: cancelling the calling
        // Task must kill it and return now, not block until the 60s timeout.
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task {
await runner.run(
                executable: ChildCommands.sleepForever.executable,
                arguments: ChildCommands.sleepForever.arguments, timeout: .seconds(60)
            )
        }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let output = await task.value
        #expect(clock.now - started < .seconds(10), "cancellation did not tear the child down promptly")
        #expect(!output.timedOut, "a cancelled run is not a timeout")
        #expect(output.exitCode == nil, "a killed child has no clean exit code")
    }
}
