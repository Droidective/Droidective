import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The relay's device side: the `adb reverse` tunnel that lets a device's
/// `localhost:9090` reach the relay at all.
@Suite struct ReactotronRouteTests {
    /// Records every reverse asked for, and answers from a script.
    private struct Backend: DaemonBackend {
        /// One entry per attempt, consumed in order. Running past the end keeps
        /// answering with the last one.
        let script: [AdbResult]
        let calls = Calls()

        final class Calls: @unchecked Sendable {
            private let lock = NSLock()
            private var seen: [(serial: String, port: Int, remove: Bool)] = []
            var all: [(serial: String, port: Int, remove: Bool)] {
                lock.lock()
                defer { lock.unlock() }
                return seen
            }
            func record(_ serial: String, _ port: Int, _ remove: Bool) {
                lock.lock()
                seen.append((serial, port, remove))
                lock.unlock()
            }
        }

        func reverseTcp(serial: String, port: Int, remove: Bool) async -> AdbResult {
            let index = calls.all.filter { $0.serial == serial && $0.remove == remove }.count
            calls.record(serial, port, remove)
            return script[min(index, script.count - 1)]
        }
    }

    private static func ok() -> AdbResult {
        AdbResult(stdout: "", stderr: "", exitCode: 0, timedOut: false)
    }

    private static func failed(_ stderr: String) -> AdbResult {
        AdbResult(stdout: "", stderr: stderr, exitCode: 1, timedOut: false)
    }

    private func decode(_ answer: DaemonProtocol.Answer) throws
        -> ReactotronProtocolRoutes.ReverseResponse
    {
        try JSONDecoder().decode(
            ReactotronProtocolRoutes.ReverseResponse.self, from: answer.1)
    }

    private func request(_ serials: [String], port: Int? = nil) throws -> Data {
        try JSONEncoder().encode(
            ReactotronProtocolRoutes.ReverseRequest(serials: serials, port: port))
    }

    @Test func opensTheTunnelOnEveryDeviceAsked() async throws {
        let backend = Backend(script: [Self.ok()])
        let answer = await ReactotronRoutes.reverse(
            body: try request(["R58M", "emulator-5554"]), backend: backend)
        let response = try decode(answer)

        #expect(response.results.map(\.serial) == ["R58M", "emulator-5554"])
        #expect(response.results.filter(\.ok).count == 2)
        // The port is in the tunnel, not just in the message: a reverse to the
        // wrong port silently succeeds and the app never arrives.
        #expect(backend.calls.all.allSatisfy { $0.port == 9090 && !$0.remove })
    }

    @Test func usesUpstreamsPortUnlessToldOtherwise() async throws {
        let backend = Backend(script: [Self.ok()])
        _ = await ReactotronRoutes.reverse(body: try request(["R58M"], port: 9999), backend: backend)
        #expect(backend.calls.all.first?.port == 9999)
    }

    @Test func namesTheCommandItRan() async throws {
        // Both apps show it — the Mac in its Commands tab — so both name it the
        // same way rather than each inventing a wording.
        let backend = Backend(script: [Self.ok()])
        let response = try decode(
            await ReactotronRoutes.reverse(body: try request(["R58M"]), backend: backend))
        #expect(response.command == "adb reverse tcp:9090 tcp:9090")
    }

    @Test func retriesADeviceThatIsNotReadyYet() async throws {
        // A freshly attached or just-booted device rejects reverse for a moment.
        // Without the retry, "plug in and open Reactotron" fails about as often
        // as it works.
        let backend = Backend(script: [Self.failed("device offline"), Self.ok()])
        let response = try decode(
            await ReactotronRoutes.reverse(body: try request(["R58M"]), backend: backend))

        #expect(response.results.first?.ok == true)
        #expect(backend.calls.all.count == 2)
    }

    @Test func givesUpAfterThreeAndSaysWhatAdbSaid() async throws {
        // The reason travels: "device offline" and "more than one device" want
        // different things done about them, and `ok: false` says neither.
        let backend = Backend(script: [Self.failed("error: device unauthorized")])
        let response = try decode(
            await ReactotronRoutes.reverse(body: try request(["R58M"]), backend: backend))

        #expect(response.results.first?.ok == false)
        #expect(response.results.first?.detail == "error: device unauthorized")
        #expect(backend.calls.all.count == ReactotronRoutes.attempts)
    }

    @Test func fallsBackToTheExitCodeWhenAdbSaidNothing() async throws {
        let backend = Backend(
            script: [AdbResult(stdout: "", stderr: "", exitCode: 7, timedOut: false)])
        let response = try decode(
            await ReactotronRoutes.reverse(body: try request(["R58M"]), backend: backend))
        #expect(response.results.first?.detail == "exit 7")
    }

    @Test func removingTheTunnelDoesNotRetry() async throws {
        // Teardown is best-effort: a device that has already gone is the outcome
        // asked for, not something to keep trying at.
        let backend = Backend(script: [Self.failed("device not found")])
        let response = try decode(
            await ReactotronRoutes.unreverse(body: try request(["R58M"]), backend: backend))

        #expect(backend.calls.all.count == 1)
        #expect(backend.calls.all.first?.remove == true)
        #expect(response.command == "adb reverse --remove tcp:9090")
    }

    @Test func aSuccessfulRemovalCarriesNoDetail() async throws {
        // adb prints nothing when a removal works, so the generic fallback would
        // fill this with "exit 0" — a detail that reads like a diagnostic and
        // says nothing. Spotted against a real emulator.
        let backend = Backend(script: [Self.ok()])
        let response = try decode(
            await ReactotronRoutes.unreverse(body: try request(["R58M"]), backend: backend))
        #expect(response.results.first?.ok == true)
        #expect(response.results.first?.detail.isEmpty == true)
    }

    @Test func noDevicesIsAnEmptyResultRatherThanARefusal() async throws {
        // The button exists with nothing connected; answering 400 would make the
        // UI show an error for a state that is simply "nothing to do".
        let backend = Backend(script: [Self.ok()])
        let response = try decode(
            await ReactotronRoutes.reverse(body: try request([]), backend: backend))
        #expect(response.results.isEmpty)
        #expect(backend.calls.all.isEmpty)
    }

    @Test func aBodyItCannotReadIsRefused() async {
        let backend = Backend(script: [Self.ok()])
        let answer = await ReactotronRoutes.reverse(body: Data("{".utf8), backend: backend)
        #expect(answer.0 == 400)
    }
}
