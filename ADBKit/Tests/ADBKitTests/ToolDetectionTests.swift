import Foundation
import Testing
@testable import ADBKit

@Suite struct ToolDetectionTests {
    @Test func detectAllReportsEveryToolWithItsVersion() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: [], stdout: "tool version 1.2.3\ntrailing noise")
        let locator = ToolLocator(runner: runner, environment: [:])
        for tool in Tool.allCases {
            await locator.seed(tool, path: "/usr/local/bin/\(tool.rawValue)")
        }
        let service = ToolDetectionService(locator: locator, runner: runner)

        let report = await service.detectAll()

        #expect(report.count == Tool.allCases.count)
        for tool in Tool.allCases {
            #expect(report[tool]?.installed == true, "\(tool) should be installed")
            #expect(report[tool]?.version == "tool version 1.2.3")
        }
    }

    @Test func detectAllReportsMissingToolsAsNotInstalled() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["version"], stdout: "adb 1.0.41")
        let locator = ToolLocator(runner: runner, environment: [:])
        await locator.seed(.adb, path: "/usr/local/bin/adb")
        for tool in Tool.allCases where tool != .adb {
            await locator.seed(tool, path: nil) // negative cache → no login-shell probe
        }
        let service = ToolDetectionService(locator: locator, runner: runner)

        let report = await service.detectAll()

        #expect(report[.adb]?.installed == true)
        #expect(report[.adb]?.version == "adb 1.0.41")
        #expect(report[.ffmpeg]?.installed == false)
        #expect(report[.emulator]?.installed == false)
        #expect(report[.scrcpy]?.installed == false)
    }
}

@Suite struct ToolLocatorCacheTests {
    /// Controllable time source for the locator's negative-result TTL.
    final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSinceReferenceDate: 0)
        var now: Date {
            lock.lock()
            defer { lock.unlock() }
            return date
        }
        func advance(by seconds: TimeInterval) {
            lock.lock()
            date += seconds
            lock.unlock()
        }
    }

    /// Counts filesystem probes. On Windows the locator resolves an off-SDK
    /// tool by scanning `Path` itself rather than shelling out, so "did it
    /// probe again?" shows up here instead of in `runner.invocations`.
    final class ProbeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func bump() {
            lock.lock()
            value += 1
            lock.unlock()
        }
    }

    /// A single-entry `Path` on Windows, so the fallback scan probes exactly
    /// once per miss — matching the one login-shell spawn POSIX makes. Empty
    /// elsewhere, which is what the POSIX cases have always used.
    static var searchPathEnvironment: [String: String] {
        #if os(Windows)
        return ["Path": #"C:\tools"#]
        #else
        return [:]
        #endif
    }

    private func makeLocator(
        runner: MockProcessRunner, clock: FakeClock, executables: Set<String> = [],
        probes: ProbeCounter? = nil
    ) -> ToolLocator {
        ToolLocator(
            runner: runner, environment: Self.searchPathEnvironment,
            now: { clock.now },
            isExecutableFile: { path in
                probes?.bump()
                return executables.contains(path)
            }
        )
    }

    @Test func notFoundExpiresSoAMidSessionInstallIsPickedUp() async {
        let runner = MockProcessRunner()  // unscripted login shell → exit 1 → not found
        let clock = FakeClock()
        let probes = ProbeCounter()
        let locator = makeLocator(runner: runner, clock: clock, probes: probes)
        // One probe per miss on either host: a login-shell spawn on POSIX, a
        // single-entry Path scan on Windows. Same counts, different signal.
        func probeCount() -> Int {
            #if os(Windows)
            return probes.count
            #else
            return runner.invocations.count
            #endif
        }

        #expect(await locator.resolve(.scrcpy) == nil)
        #expect(await locator.resolve(.scrcpy) == nil)
        // Within the TTL the miss is served from cache — a 2 s poll must not
        // re-probe on every tick.
        #expect(probeCount() == 1)

        clock.advance(by: ToolLocator.notFoundTTL + 1)
        #expect(await locator.resolve(.scrcpy) == nil)
        #expect(probeCount() == 2)  // TTL elapsed → probed again
    }

    /// The first probed install-prefix candidate for scrcpy on this host.
    private static var scrcpyCandidate: String {
        #if os(macOS)
        return "/opt/homebrew/bin/scrcpy"
        #elseif os(Windows)
        // No install prefixes on Windows — the fallback scans `Path`.
        return #"C:\tools\scrcpy.exe"#
        #else
        return "/usr/local/bin/scrcpy"
        #endif
    }

    @Test func foundPathsStayCachedIndefinitely() async {
        let runner = MockProcessRunner()
        let clock = FakeClock()
        let locator = makeLocator(
            runner: runner, clock: clock, executables: [Self.scrcpyCandidate]
        )

        #expect(await locator.resolve(.scrcpy) == Self.scrcpyCandidate)
        clock.advance(by: ToolLocator.notFoundTTL * 10)
        #expect(await locator.resolve(.scrcpy) == Self.scrcpyCandidate)
        #expect(runner.invocations.isEmpty)  // never needed the login shell
    }
}
