import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The Reactotron relay, against real sockets.
///
/// A fake would prove nothing here: the whole class is a WebSocket listener, and
/// what has to be right is the handshake, the masking, the frame reassembly and
/// the ordering — none of which survives being mocked. `URLSessionWebSocketTask`
/// stands in for the React Native client, which is what one actually is.
///
/// Serialized, and every relay binds port 0: two listeners racing for a port is
/// a flake, and a test that fails because another test was still shutting down
/// teaches nothing.
#if canImport(Darwin)
@Suite(.serialized) struct ReactotronRelayTests {
    /// A relay on an OS-chosen port, with its event stream already open.
    ///
    /// The stream is taken before `start()` on purpose — that ordering is what
    /// `LiveStreamSource.reactotron()` relies on, and a test that started first
    /// would pass while the production path missed its `listening` event.
    private func relay() async throws -> (ReactotronRelay, AsyncStream<ReactotronRelay.Event>, Int) {
        let relay = ReactotronRelay(port: 0)
        let events = await relay.events()
        try await relay.start()
        let port = try #require(await relay.boundPort)
        return (relay, events, port)
    }

    /// Collects events off the stream, so a test can wait for the one it wants
    /// without assuming how many arrive first.
    private actor Collected {
        private(set) var events: [ReactotronRelay.Event] = []

        func add(_ event: ReactotronRelay.Event) { events.append(event) }

        /// Waits until `matching` finds something, or gives up. Generous,
        /// because it is a socket round trip that normally takes milliseconds.
        func wait(
            timeout: Duration = .seconds(10),
            _ matching: @Sendable ([ReactotronRelay.Event]) -> Bool
        ) async -> Bool {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while ContinuousClock.now < deadline {
                if matching(events) { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return matching(events)
        }
    }

    private func collect(_ stream: AsyncStream<ReactotronRelay.Event>) -> (Collected, Task<Void, Never>) {
        let collected = Collected()
        let task = Task {
            for await event in stream { await collected.add(event) }
        }
        return (collected, task)
    }

    /// A client, connected. `URLSession` masks its frames as the RFC requires,
    /// which is the half a hand-rolled fake would get wrong.
    private func client(port: Int) -> URLSessionWebSocketTask {
        let task = URLSession.shared.webSocketTask(
            with: URL(string: "ws://127.0.0.1:\(port)")!)
        task.resume()
        return task
    }

    private func intro(_ clientId: String) -> String {
        """
        {"type":"client.intro","payload":{"clientId":"\(clientId)","name":"Demo","reactotronCoreClientVersion":"3.0.0"}}
        """
    }

    // MARK: - the handshake

    @Test func reportsThePortItBoundTo() async throws {
        let (relay, events, port) = try await relay()
        defer { Task { await relay.stop() } }
        let (collected, reader) = collect(events)
        defer { reader.cancel() }

        #expect(port > 0)
        #expect(await collected.wait { events in
            events.contains { event in
                if case .listening(let reported) = event { return reported == port }
                return false
            }
        })
    }

    @Test func aClientIntroBecomesAConnection() async throws {
        // The handshake is what tells the UI an app is there at all; a client
        // whose intro was read as an ordinary command would show up as a log
        // line and never as a client.
        let (relay, events, port) = try await relay()
        defer { Task { await relay.stop() } }
        let (collected, reader) = collect(events)
        defer { reader.cancel() }

        let socket = client(port: port)
        defer { socket.cancel() }
        try await socket.send(.string(intro("demo-app")))

        #expect(await collected.wait { events in
            events.contains { event in
                if case .connected(_, let clientId, _, _) = event { return clientId == "demo-app" }
                return false
            }
        })
    }

    @Test func anIntroWithNoClientIdStillConnects() async throws {
        // Upstream's client only sends one once it has been given a name, so a
        // first run has none — and refusing the connection would mean the app
        // never appears.
        let (relay, events, port) = try await relay()
        defer { Task { await relay.stop() } }
        let (collected, reader) = collect(events)
        defer { reader.cancel() }

        let socket = client(port: port)
        defer { socket.cancel() }
        try await socket.send(.string(#"{"type":"client.intro","payload":{"name":"Demo"}}"#))

        #expect(await collected.wait { events in
            events.contains { event in
                if case .connected(_, let clientId, _, _) = event { return clientId == nil }
                return false
            }
        })
    }

    @Test func aSecondIntroOnOneConnectionIsNotASecondClient() async throws {
        // Otherwise a client that re-introduces itself — which upstream's does
        // after a reload — doubles the client list.
        let (relay, events, port) = try await relay()
        defer { Task { await relay.stop() } }
        let (collected, reader) = collect(events)
        defer { reader.cancel() }

        let socket = client(port: port)
        defer { socket.cancel() }
        try await socket.send(.string(intro("demo-app")))
        #expect(await collected.wait { $0.contains { isConnected($0) } })
        try await socket.send(.string(intro("demo-app")))
        // The second one arrives as a command, so wait for *that* and then count.
        #expect(await collected.wait { $0.filter { isCommand($0) }.count >= 1 })
        #expect(await collected.events.filter { isConnected($0) }.count == 1)
    }

    // MARK: - commands

    @Test func decodesACommandWithTheProtocolBothAppsShare() async throws {
        let (relay, events, port) = try await relay()
        defer { Task { await relay.stop() } }
        let (collected, reader) = collect(events)
        defer { reader.cancel() }

        let socket = client(port: port)
        defer { socket.cancel() }
        try await socket.send(.string(intro("demo-app")))
        try await socket.send(
            .string(#"{"type":"log","payload":{"level":"debug","message":"hello"},"important":true}"#))

        #expect(await collected.wait { events in
            events.contains { event in
                guard case .command(_, let command, _) = event else { return false }
                return command.commandType == .log && command.isImportant
            }
        })
    }

    @Test func keepsCommandsInTheOrderTheAppSentThem() async throws {
        // The one thing a timeline must not do is reorder.
        //
        // This asserts the observable property, not the mechanism: swapping the
        // single-consumer stream for a Task per frame still passes here, because
        // forty frames on one event loop happen to arrive in order anyway. The
        // stream is what makes it a *guarantee* — independent tasks have no FIFO
        // ordering on actor entry — and that is not something a test can
        // reliably provoke. Checked by mutation and recorded so nobody reads
        // this as covering the design.
        let (relay, events, port) = try await relay()
        defer { Task { await relay.stop() } }
        let (collected, reader) = collect(events)
        defer { reader.cancel() }

        let socket = client(port: port)
        defer { socket.cancel() }
        try await socket.send(.string(intro("demo-app")))
        for index in 0 ..< 40 {
            try await socket.send(
                // `\#(…)`, not `\(…)`: interpolation in a raw string needs the
                // pound. Without it the frame carries a literal backslash-paren,
                // which is invalid JSON — so the relay reported forty
                // undecodable frames and the count still looked right.
                .string(#"{"type":"log","payload":{"message":"item\#(index)"}}"#))
        }

        #expect(await collected.wait { $0.filter { isCommand($0) }.count == 40 })
        let messages = await collected.events.compactMap { event -> String? in
            guard case .command(_, let command, _) = event,
                  case .object(let payload) = command.payload,
                  case .string(let message) = payload["message"]
            else { return nil }
            return message
        }
        #expect(messages == (0 ..< 40).map { "item\($0)" })
    }

    @Test func reportsEachFramesSizeSoTheTimelineCanBoundItself() async throws {
        // The size has to be the frame's own bytes. A client can only get back
        // to one by re-serializing the payload it just decoded, and doing that
        // per frame is the stall the feed exists to avoid — so if this arrives
        // wrong, the timeline's memory bound is wrong with it.
        let (relay, events, port) = try await relay()
        defer { Task { await relay.stop() } }
        let (collected, reader) = collect(events)
        defer { reader.cancel() }

        let socket = client(port: port)
        defer { socket.cancel() }
        // Multi-byte on purpose: bytes, not characters. "é" is two.
        let frame = #"{"type":"log","payload":{"message":"café"}}"#
        try await socket.send(.string(frame))

        #expect(await collected.wait { events in
            events.contains { event in
                guard case .command(_, _, let bytes) = event else { return false }
                return bytes == frame.utf8.count
            }
        })
        #expect(frame.utf8.count != frame.count, "otherwise the test proves nothing about bytes")
    }

    @Test func reportsAFrameItCouldNotDecodeRatherThanDroppingIt() async throws {
        // A client sending malformed JSON is a bug someone has to see. Silence
        // makes it look like the relay is receiving nothing at all.
        let (relay, events, port) = try await relay()
        defer { Task { await relay.stop() } }
        let (collected, reader) = collect(events)
        defer { reader.cancel() }

        let socket = client(port: port)
        defer { socket.cancel() }
        try await socket.send(.string("{not json at all"))

        #expect(await collected.wait { events in
            events.contains { event in
                guard case .command(_, let command, _) = event else { return false }
                return command.type == "(undecodable)"
            }
        })
    }

    // MARK: - going away

    @Test func reportsAClientThatDisconnects() async throws {
        let (relay, events, port) = try await relay()
        defer { Task { await relay.stop() } }
        let (collected, reader) = collect(events)
        defer { reader.cancel() }

        let socket = client(port: port)
        try await socket.send(.string(intro("demo-app")))
        #expect(await collected.wait { $0.contains { isConnected($0) } })
        socket.cancel(with: .goingAway, reason: nil)

        // 1001 rather than any close: Android's own WebSocket sends going-away
        // when 16 MB of Reactotron events have queued up behind it, which is a
        // diagnosis with a fix ("log ids, not whole objects"). Without the code
        // the timeline can only say the app went away, so this asserts the
        // number travels — read off a real client's close frame, which is the
        // only place the two-byte big-endian layout can be got wrong.
        #expect(await collected.wait { events in
            events.contains { event in
                guard case .disconnected(_, _, let code) = event else { return false }
                return code == 1001
            }
        })
    }

    @Test func commandsSentBeforeACloseStillArrive() async throws {
        // The frame stream is *finished* rather than cancelled on close, so what
        // the app logged on its way out is not lost — which is exactly the
        // traffic someone is looking for after a crash.
        let (relay, events, port) = try await relay()
        defer { Task { await relay.stop() } }
        let (collected, reader) = collect(events)
        defer { reader.cancel() }

        let socket = client(port: port)
        try await socket.send(.string(intro("demo-app")))
        try await socket.send(.string(#"{"type":"log","payload":{"message":"last words"}}"#))
        socket.cancel(with: .goingAway, reason: nil)

        #expect(await collected.wait { events in
            events.contains { event in
                guard case .command(_, let command, _) = event,
                      case .object(let payload) = command.payload,
                      case .string(let message) = payload["message"]
                else { return false }
                return message == "last words"
            }
        })
    }

    /// Ports the OS will never hand out by itself.
    ///
    /// `port: 0` draws from the ephemeral range (49152–65535 on macOS), and the
    /// other *suites* — this one is `.serialized`, they are not — bind that way
    /// while this one runs. The test below is shaped "release a port, then take
    /// it again", so an ephemeral port gets handed to one of them in the gap
    /// between: it failed twice running on CI, on 49407 and then 49412. Nothing
    /// auto-binds down here, so the gap stops mattering.
    ///
    /// Several candidates because a developer's machine may already be using
    /// one, which is a different problem from the one being tested.
    private static let reservedPorts = [28_411, 28_412, 28_413, 28_414]

    /// The first reserved port this machine will actually give us.
    private static func freeReservedPort() async -> Int? {
        for candidate in reservedPorts {
            let probe = ReactotronRelay(port: candidate)
            guard (try? await probe.start()) != nil else { continue }
            await probe.stop()
            return candidate
        }
        return nil
    }

    @Test func stoppingReleasesThePort() async throws {
        let port = try #require(await Self.freeReservedPort(), "no reserved port was free")
        let relay = ReactotronRelay(port: port)
        try await relay.start()
        #expect(await relay.boundPort == port)
        await relay.stop()
        #expect(await relay.isRunning == false)

        // The failure this catches is a relay that closed its channel but kept
        // its event-loop group, so the next start reports the port in use — and
        // the feature simply refuses to come back. Still caught: a leak makes
        // the port unavailable to *anyone*, so this start throws.
        let second = ReactotronRelay(port: port)
        try await second.start()
        #expect(await second.boundPort == port)
        await second.stop()
    }

    @Test func aStartAndAStopThatRaceLeaveAConsistentRelay() async throws {
        // The sequence a timeline tab makes every time it is closed and
        // reopened, and the one React's double-mount makes on the very first
        // open: unsubscribe (stop) immediately followed by subscribe (start).
        //
        // Both suspend — a graceful shutdown and a bind are each async — and an
        // actor is reentrant across a suspension. Both orders used to be broken:
        // a start landing mid-stop saw a nil channel, bound the same port again
        // and got EADDRINUSE from a socket the stop had not finished releasing
        // ("another Reactotron is probably running", with nothing else on the
        // port); a stop landing mid-start shut down the event-loop group the
        // bind was still waiting on, which never completes and wedges the relay
        // for the life of the process.
        //
        // What is asserted is the *invariant*, not the winner. Which of the two
        // enters the actor first is genuinely unspecified — an earlier version
        // of this test assumed the start won, and flaked once the whole suite
        // was running alongside it. What the fix guarantees is that neither
        // order throws, neither hangs, and the relay never ends up half-way:
        // listening with no port, or stopped while still holding one.
        let relay = ReactotronRelay(port: 0)
        try await relay.start()
        #expect(await relay.boundPort != nil)
        defer { Task { await relay.stop() } }

        for _ in 0 ..< 5 {
            async let stopped: Void = relay.stop()
            async let started: Void = relay.start()
            await stopped
            try await started
            let running = await relay.isRunning
            let port = await relay.boundPort
            #expect(
                running == (port != nil),
                "running and bound have to agree whichever order won")
            // Put the next round on a known footing rather than letting the
            // previous winner decide it.
            if !running { try await relay.start() }
        }
    }

    @Test func aSecondStartIsANoOpRatherThanASecondListener() async throws {
        let (relay, _, port) = try await relay()
        defer { Task { await relay.stop() } }
        try await relay.start()
        #expect(await relay.boundPort == port)
    }

    @Test func aTakenPortIsReportedAsSuchRatherThanAsNothing() async throws {
        // "Address already in use" is not something a UI can act on; "another
        // Reactotron is probably running" is, and it is almost always true.
        let first = ReactotronRelay(port: 0)
        try await first.start()
        let port = try #require(await first.boundPort)
        defer { Task { await first.stop() } }

        let second = ReactotronRelay(port: port)
        await #expect(throws: ReactotronRelay.RelayError.self) {
            try await second.start()
        }
    }

    // MARK: - the wire shape

    @Test func everyEventEncodesTheShapeTheUIParses() throws {
        func encoded(_ event: ReactotronRelay.Event) throws -> String {
            String(decoding: try DaemonProtocol.encode(ReactotronEventPayload(event)), as: UTF8.self)
        }
        #expect(try encoded(.listening(port: 9090)).contains(#""kind":"listening""#))
        #expect(try encoded(.listening(port: 9090)).contains(#""port":9090"#))

        let command = ReactotronCommand(type: "log", payload: .string("hi"))
        let connected = try encoded(.connected(connection: 2, clientId: "app", command: command, bytes: 41))
        #expect(connected.contains(#""kind":"connected""#))
        #expect(connected.contains(#""clientId":"app""#))
        #expect(connected.contains(#""connection":2"#))

        #expect(try encoded(.command(connection: 2, command: command, bytes: 41)).contains(#""type":"log""#))
        #expect(try encoded(.command(connection: 2, command: command, bytes: 41)).contains(#""bytes":41"#))
        // `listening` and `disconnected` carry no frame, so they carry no size
        // rather than a zero the client would have to know to ignore.
        #expect(!(try encoded(.listening(port: 9090)).contains("bytes")))
        let gone = try encoded(.disconnected(connection: 2, reason: "client closed", code: 1001))
        #expect(gone.contains(#""reason":"client closed""#))
        #expect(gone.contains(#""code":1001"#))
    }

    private func isConnected(_ event: ReactotronRelay.Event) -> Bool {
        if case .connected = event { return true }
        return false
    }

    private func isCommand(_ event: ReactotronRelay.Event) -> Bool {
        if case .command = event { return true }
        return false
    }
}
#endif
