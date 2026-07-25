#if canImport(Network)
import Foundation
import Network
import Testing
@testable import ADBKit

@Suite struct MirrorTransportSocketTests {
    /// The control socket sends ~32-byte touch events; Nagle batching them
    /// behind delayed ACKs adds tens of milliseconds of input and display lag.
    @Test func streamSocketsDisableNagle() {
        let parameters = MirrorTransport.socketParameters()
        let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options
        #expect(tcp?.noDelay == true)
    }
}

/// `stop()` is terminal even against a `start()` still in flight. Actors are
/// reentrant, so `stop()` can run at any of `start()`'s suspension points —
/// including before the fields it cleans are set. Without the latch, `start()`
/// resumed and finished building a session whose stop already happened,
/// stranding an adb child, a forward, and a device-side server in accept-wait.
@Suite struct MirrorTransportStopTests {
    private static let serial = "emulator-test"

    private static func makeConfig() -> MirrorTransport.Configuration {
        MirrorTransport.Configuration(
            serial: serial,
            params: ScrcpyServerParams(scid: 0x1234, maxSize: 800),
            serverVersion: "3.1",
            localJarPath: "/fake/scrcpy-server.jar")
    }

    @Test func startAfterStopAbortsWithoutTouchingAdb() async throws {
        let runner = MockProcessRunner()
        let adb = await makeTestClient(runner: runner)
        let transport = MirrorTransport(adb: adb, config: Self.makeConfig())

        await transport.stop()
        await #expect(throws: CancellationError.self) {
            _ = try await transport.start()
        }
        #expect(runner.invocations.isEmpty)
    }

    @Test func stopDuringBringUpRemovesTheForwardItRaced() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", Self.serial, "push"])
        runner.script(argsPrefix: ["-s", Self.serial, "forward", "tcp:0"], stdout: "51234")
        runner.script(argsPrefix: ["-s", Self.serial, "forward", "--remove"])
        // Park start() inside openForward's adb call, the suspension where a
        // racing stop() finds no serverProcess and no forwardedPort to clean.
        let holding = HoldingRunner(
            base: runner, holdPrefix: ["-s", Self.serial, "forward", "tcp:0"])
        let locator = ToolLocator(runner: holding, environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        let adb = AdbClient(locator: locator, runner: holding, log: CommandLog())
        let transport = MirrorTransport(adb: adb, config: Self.makeConfig())

        let bringUp = Task { try await transport.start() }
        await holding.waitUntilHeld()
        await transport.stop() // interleaves mid-start: nothing to clean yet
        holding.releaseHeld()

        await #expect(throws: CancellationError.self) { _ = try await bringUp.value }
        // The checkpoint after openForward must tear down the forward that
        // start() created for the already-stopped session.
        #expect(runner.invocations.contains(
            MockProcessRunner.Invocation(
                executable: "/fake/adb",
                arguments: ["-s", Self.serial, "forward", "--remove", "tcp:51234"])))
    }
}

/// Wraps the mock runner so one invocation (matched by argument prefix) parks
/// until released, letting a test interleave actor calls at a precise
/// suspension point instead of racing the scheduler.
private final class HoldingRunner: ProcessRunning, @unchecked Sendable {
    private let base: MockProcessRunner
    private let holdPrefix: [String]
    private let lock = NSLock()
    private var began: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private var didBegin = false
    private var released = false

    init(base: MockProcessRunner, holdPrefix: [String]) {
        self.base = base
        self.holdPrefix = holdPrefix
    }

    /// Suspends until the held invocation has started.
    func waitUntilHeld() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didBegin {
                lock.unlock()
                continuation.resume()
                return
            }
            began = continuation
            lock.unlock()
        }
    }

    func releaseHeld() {
        lock.lock()
        released = true
        let waiting = release
        release = nil
        lock.unlock()
        waiting?.resume()
    }

    /// Synchronous so the lock stays out of async contexts (Swift 6 forbids
    /// `NSLock.lock()` there). Returns whether the caller still needs to park.
    private func markBegan() -> Bool {
        lock.lock()
        didBegin = true
        let observer = began
        began = nil
        let alreadyReleased = released
        lock.unlock()
        observer?.resume()
        return !alreadyReleased
    }

    func run(
        executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int
    ) async -> ProcessOutput {
        if arguments.starts(with: holdPrefix), markBegan() {
            await withCheckedContinuation { continuation in
                lock.lock()
                if released {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                release = continuation
                lock.unlock()
            }
        }
        return await base.run(
            executable: executable, arguments: arguments,
            timeout: timeout, maxOutputBytes: maxOutputBytes)
    }
}
#endif
