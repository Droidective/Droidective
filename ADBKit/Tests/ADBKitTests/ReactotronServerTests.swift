#if canImport(Network)
import Foundation
import Testing
@testable import ADBKit

/// Loopback test of the WebSocket server: a real `URLSessionWebSocketTask`
/// client connects to the server on an OS-assigned port and drives the full
/// handshake + event delivery. Hardware-free (pure loopback), with a generous
/// time limit so a stall fails fast instead of hanging the suite.
@Suite struct ReactotronServerTests {
    private typealias Iterator = AsyncStream<ReactotronServer.Event>.Iterator

    @Test(.timeLimit(.minutes(1)))
    func handshakeAndEventDelivery() async throws {
        let server = ReactotronServer(port: 0)
        let stream = try await server.start()
        defer { Task { await server.stop() } }
        var iterator = stream.makeAsyncIterator()

        let port = try await waitForListening(&iterator)

        let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        let introFrame =
            #"{"type":"client.intro","payload":{"name":"SimApp"},"important":false,"date":"d","deltaTime":0}"#
        try await task.send(.string(introFrame))

        let connected = try await nextEvent(&iterator)
        guard case let .connected(_, _, intro, introBytes) = connected else {
            Issue.record("expected .connected, got \(connected)"); return
        }
        #expect(intro.commandType == .clientIntro)
        #expect(introBytes == introFrame.utf8.count)

        // The server completes the handshake with setClientId + subscriptions.
        let replies = [try await receiveText(task), try await receiveText(task)].joined(separator: " ")
        #expect(replies.contains("setClientId"))
        #expect(replies.contains("state.values.subscribe"))

        let logFrame =
            #"{"type":"log","payload":{"level":"warn","message":"hi"},"important":false,"date":"d","deltaTime":1}"#
        try await task.send(.string(logFrame))
        let command = try await nextEvent(&iterator)
        guard case let .command(_, decoded, logBytes) = command else {
            Issue.record("expected .command, got \(command)"); return
        }
        #expect(decoded.commandType == .log)
        #expect(logBytes == logFrame.utf8.count)

        // Server → client: a broadcast frame reaches the connected client.
        await server.broadcast(type: "custom", payload: .string("ping"))
        let pushed = try await receiveText(task)
        #expect(pushed.contains("custom"))
        #expect(pushed.contains("ping"))
    }

    /// An app reload reconnects with the same clientId while its old socket is
    /// still open. The stale connection must be dropped silently (nil reason —
    /// no timeline notice) and a client with a *different* clientId must be
    /// left alone.
    @Test(.timeLimit(.minutes(1)))
    func reloadWithSameClientIdReplacesTheStaleConnection() async throws {
        let server = ReactotronServer(port: 0)
        let stream = try await server.start()
        defer { Task { await server.stop() } }
        var iterator = stream.makeAsyncIterator()
        let port = try await waitForListening(&iterator)
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))

        func connect(clientId: String) async throws -> URLSessionWebSocketTask {
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            try await task.send(.string(
                #"{"type":"client.intro","payload":{"name":"App","clientId":"\#(clientId)"},"important":false,"date":"d","deltaTime":0}"#
            ))
            return task
        }

        let first = try await connect(clientId: "same-app")
        guard case let .connected(firstId, firstClientId, _, _) = try await nextEvent(&iterator) else {
            Issue.record("expected first .connected"); return
        }

        // Reload: a second socket, same clientId. The stale one goes first —
        // silently — then the new one completes its handshake.
        let second = try await connect(clientId: "same-app")
        defer { second.cancel(with: .goingAway, reason: nil) }
        guard case let .disconnected(droppedId, reason) = try await nextEvent(&iterator) else {
            Issue.record("expected .disconnected for the stale twin"); return
        }
        #expect(droppedId == firstId)
        #expect(reason == nil)
        guard case let .connected(secondId, secondClientId, _, _) = try await nextEvent(&iterator) else {
            Issue.record("expected second .connected"); return
        }
        #expect(secondId != firstId)
        #expect(firstClientId == "same-app")
        #expect(secondClientId == "same-app")

        // A different app coexists — no dedupe, both stay live.
        let third = try await connect(clientId: "other-app")
        defer { third.cancel(with: .goingAway, reason: nil) }
        guard case .connected = try await nextEvent(&iterator) else {
            Issue.record("expected third .connected"); return
        }
        try await second.send(.string(
            #"{"type":"log","payload":{"level":"debug","message":"still alive"},"important":false,"date":"d","deltaTime":1}"#
        ))
        guard case let .command(commandConnection, decoded, _) = try await nextEvent(&iterator) else {
            Issue.record("expected .command from the surviving client"); return
        }
        #expect(commandConnection == secondId)
        #expect(decoded.commandType == .log)

        // The stale socket really is closed (after the 500ms grace): its next
        // receive fails instead of hanging on a half-open connection.
        // (It got no server frames beyond the handshake subscribe.)
        _ = try? await receiveText(first) // state.values.subscribe
        do {
            _ = try await receiveText(first)
            Issue.record("stale socket should have been closed")
        } catch {
            // expected: the server cancelled the connection
        }
    }

    /// A burst of frames must reach the event stream in wire order — the
    /// server pipes each connection's frames through one ordered consumer, so
    /// timeline rows can't leapfrog each other under load.
    @Test(.timeLimit(.minutes(1)))
    func burstOfFramesArrivesInWireOrder() async throws {
        let server = ReactotronServer(port: 0)
        let stream = try await server.start()
        defer { Task { await server.stop() } }
        var iterator = stream.makeAsyncIterator()
        let port = try await waitForListening(&iterator)

        let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }
        try await task.send(.string(
            #"{"type":"client.intro","payload":{"name":"BurstApp"},"important":false,"date":"d","deltaTime":0}"#
        ))
        guard case .connected = try await nextEvent(&iterator) else {
            Issue.record("expected .connected"); return
        }

        let count = 100
        for index in 0..<count {
            try await task.send(.string(
                #"{"type":"log","payload":{"level":"debug","message":"\#(index)"},"important":false,"date":"d","deltaTime":1}"#
            ))
        }
        for index in 0..<count {
            guard case let .command(_, command, _) = try await nextEvent(&iterator) else {
                Issue.record("expected .command #\(index)"); return
            }
            #expect(command.payload?["message"]?.stringValue == "\(index)")
        }
    }

    /// A `client.intro` that drains out of a connection's frame feed *after*
    /// the connection dropped must not resurrect a ghost client: no
    /// `.connected` is emitted for a connection the server no longer tracks.
    /// Ordinary commands still drain — they're timeline data, not client state.
    @Test(.timeLimit(.minutes(1)))
    func drainedIntroAfterDropDoesNotResurrectAGhostClient() async throws {
        let server = ReactotronServer(port: 0)
        let stream = try await server.start()
        defer { Task { await server.stop() } }
        var iterator = stream.makeAsyncIterator()
        _ = try await waitForListening(&iterator)

        // Connection 999 was never accepted (stands in for one already
        // dropped): its drained intro must vanish, its drained log must land.
        let intro = Data(
            #"{"type":"client.intro","payload":{"name":"Ghost"},"important":false,"date":"d","deltaTime":0}"#
                .utf8)
        await server.handleFrame(connectionId: 999, data: intro)
        let log = Data(
            #"{"type":"log","payload":{"level":"debug","message":"drained"},"important":false,"date":"d","deltaTime":1}"#
                .utf8)
        await server.handleFrame(connectionId: 999, data: log)

        let event = try await nextEvent(&iterator)
        guard case let .command(connectionId, command, _) = event else {
            Issue.record("expected the drained log as the next event, got \(event)")
            return
        }
        #expect(connectionId == 999)
        #expect(command.commandType == .log)
    }

    /// A tap receives the same events as the primary stream without stealing
    /// from it, and keeps receiving across a `stop()`/`start()` restart.
    @Test(.timeLimit(.minutes(1)))
    func tapMirrorsThePrimaryStreamAndSurvivesRestart() async throws {
        let server = ReactotronServer(port: 0)
        let stream = try await server.start()
        var iterator = stream.makeAsyncIterator()
        var tapIterator = await server.tap().makeAsyncIterator()
        _ = try await waitForListening(&iterator)

        let frame = Data(
            #"{"type":"log","payload":{"level":"warn","message":"both"},"important":false,"date":"d","deltaTime":1}"#
                .utf8)
        await server.handleFrame(connectionId: 1, data: frame)

        guard case let .command(_, primary, _) = try await nextEvent(&iterator) else {
            Issue.record("expected .command on the primary stream"); return
        }
        // The tap also carries lifecycle events (.listening) — drain to the
        // first command rather than assuming arrival order.
        let tapped = try await nextTapCommand(&tapIterator)
        #expect(primary == tapped)

        // Restart: the primary stream is replaced, the tap keeps flowing.
        await server.stop()
        let restarted = try await server.start()
        var restartedIterator = restarted.makeAsyncIterator()
        _ = try await waitForListening(&restartedIterator)
        await server.handleFrame(connectionId: 2, data: frame)
        _ = try await nextTapCommand(&tapIterator)
        await server.stop()
    }

    private func nextTapCommand(_ iterator: inout Iterator) async throws -> ReactotronCommand {
        while let event = await iterator.next() {
            if case let .command(_, command, _) = event { return command }
        }
        throw ReactotronServer.ServerError.startFailed("tap ended before a command arrived")
    }

    private func waitForListening(_ iterator: inout Iterator) async throws -> UInt16 {
        while let event = await iterator.next() {
            if case let .listening(port) = event { return port }
        }
        throw ReactotronServer.ServerError.startFailed("stream ended before listening")
    }

    private func nextEvent(_ iterator: inout Iterator) async throws -> ReactotronServer.Event {
        guard let event = await iterator.next() else {
            throw ReactotronServer.ServerError.startFailed("stream ended early")
        }
        return event
    }

    private func receiveText(_ task: URLSessionWebSocketTask) async throws -> String {
        switch try await task.receive() {
        case let .string(text): return text
        case let .data(data): return String(decoding: data, as: UTF8.self)
        @unknown default: return ""
        }
    }
}
#endif
