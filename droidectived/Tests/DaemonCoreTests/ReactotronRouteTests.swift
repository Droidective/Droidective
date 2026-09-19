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

    // MARK: - Sending a command to a client

    /// A stream source that records what it was asked to send, standing in for
    /// the relay. The relay's own end of this is covered against real sockets
    /// in `ReactotronRelayTests`; what matters here is the wire shape.
    /// A stream source that records what it was asked to send, standing in
    /// for the relay. The relay's own end is covered against real sockets in
    /// `ReactotronRelayTests`; what matters here is the wire shape.
    private final class Source: StreamSource, @unchecked Sendable {
        var sent: [(type: String, payload: JSONValue, connection: Int?)] = []
        var delivered = 1

        func devices() async -> AsyncStream<[Device]> { AsyncStream { $0.finish() } }
        func logcat(serial: String, pid: Int?) async throws -> AsyncStream<[LogLine]> {
            AsyncStream { $0.finish() }
        }
        func stopLogcat(serial: String) async {}
        func performance(
            serial: String, packageId: String?, includeProcesses: Bool
        ) async -> AsyncStream<PerformanceService.PerfPoll> { AsyncStream { $0.finish() } }
        func netspeed(serial: String) async -> AsyncStream<NetSample> { AsyncStream { $0.finish() } }
        func reactotron() async throws -> AsyncStream<ReactotronRelay.Event> {
            AsyncStream { $0.finish() }
        }
        func stopReactotron() async {}
        func openPty(serial: String?, size: PtySize) throws -> any PtyChannel {
            throw StubbedOut.notImplemented
        }
        func sendReactotron(type: String, payload: JSONValue, toConnection: Int?) async -> Int {
            sent.append((type, payload, toConnection))
            return delivered
        }
    }

    private func sendBody(
        _ type: String, _ payload: JSONValue, connection: Int? = nil
    ) throws -> Data {
        try JSONEncoder().encode(
            ReactotronProtocolRoutes.SendRequest(
                type: type, payload: payload, connectionId: connection))
    }

    @Test func passesTheCommandStraightToTheRelay() async throws {
        // The daemon is a relay here, not an interpreter: whatever vocabulary
        // the screen speaks — `state.values.request`, `repl.command` — has to
        // arrive unchanged, or every new Reactotron command would need a
        // daemon change to go with it.
        let source = Source()
        let answer = await ReactotronRoutes.send(
            body: try sendBody("state.values.request", .object(["path": .string("user.name")])),
            source: source)
        #expect(answer.0 == 200)
        #expect(source.sent.count == 1)
        #expect(source.sent.first?.type == "state.values.request")
        #expect(source.sent.first?.payload == .object(["path": .string("user.name")]))
        #expect(source.sent.first?.connection == nil)
    }

    @Test func aimsAtOneClientWhenAsked() async throws {
        let source = Source()
        _ = await ReactotronRoutes.send(
            body: try sendBody("repl.command", .null, connection: 7), source: source)
        #expect(source.sent.first?.connection == 7)
    }

    /// Nobody listening is a 200 carrying zero, not an error. The command was
    /// well-formed and the daemon did what was asked; "no app is connected" is
    /// a state the screen shows, not a failure of the call.
    @Test func reachingNobodyIsStillASuccess() async throws {
        let source = Source()
        source.delivered = 0
        let answer = await ReactotronRoutes.send(
            body: try sendBody("state.values.request", .null), source: source)
        #expect(answer.0 == 200)
        let decoded = try JSONDecoder().decode(
            ReactotronProtocolRoutes.SendResponse.self, from: answer.1)
        #expect(decoded.delivered == 0)
    }

    /// An empty type would be framed and sent, and the client would ignore it
    /// silently — the worst shape of failure, so it is refused here.
    @Test func anEmptyTypeIsRefused() async throws {
        let source = Source()
        let answer = await ReactotronRoutes.send(body: try sendBody("", .null), source: source)
        #expect(answer.0 == 400)
        #expect(source.sent.isEmpty)
    }

    @Test func aSendBodyItCannotReadIsRefused() async {
        let source = Source()
        let answer = await ReactotronRoutes.send(body: Data("{".utf8), source: source)
        #expect(answer.0 == 400)
        #expect(source.sent.isEmpty)
    }
}
