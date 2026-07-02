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
        guard case let .connected(_, intro, introBytes) = connected else {
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
