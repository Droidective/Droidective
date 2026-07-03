import Foundation
import Network
import Testing
@testable import ADBKit

/// Loopback wire test of the CDP client: a real `NWListener` WebSocket server
/// scripts CDP replies and pushes an event, and the production
/// `JSConsoleClient` (a `URLSessionWebSocketTask`) drives the full
/// enable → evaluate → getProperties → event-stream → close path. Hardware-free,
/// with a time limit so a stall fails fast.
@Suite struct JSConsoleClientTests {
    @Test(.timeLimit(.minutes(1)))
    func handshakeEvaluateAndConsoleStream() async throws {
        let server = CDPTestServer()
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/inspector/debug?device=0&page=1"))
        let client = JSConsoleClient()
        let stream = try await client.connect(to: url)
        defer { Task { await client.disconnect() } }

        // Evaluate — the server replies with the number 4.
        let outcome = try await client.evaluate("2 + 2")
        guard case let .value(object) = outcome else { Issue.record("expected a value, got \(outcome)"); return }
        #expect(object.type == "number")
        #expect(object.description == "4")

        // Expand an object — the server returns one property `x`.
        let properties = try await client.getProperties(objectId: "obj-1")
        #expect(properties.first?.name == "x")
        #expect(properties.first?.value?.value?.doubleValue == 1)

        // Deep-stringify (Copy as JSON) round-trips the runtime's JSON string.
        let json = await client.deepStringify(objectId: "obj-1")
        #expect(json == "{\n  \"x\": 1\n}")

        // The server pushes a console.log; the event stream delivers it.
        await server.pushConsoleLog("hello")
        var received: ConsoleAPICall?
        for await event in stream {
            if case let .console(call) = event { received = call; break }
        }
        #expect(received?.type == "log")
        #expect(received?.args.first?.value?.stringValue == "hello")
    }

    @Test func debuggerRequestSetsLoopbackOriginForFuseboxProxy() throws {
        // RN's Fusebox inspector proxy 401s the debugger WebSocket without an
        // allowlisted Origin; a regression here silently breaks every connection.
        let url = try #require(URL(string: "ws://127.0.0.1:8081/inspector/debug?device=abc&page=1"))
        let request = JSConsoleClient.debuggerRequest(for: url)
        #expect(request.value(forHTTPHeaderField: "Origin") == "http://localhost:8081")
        #expect(request.url == url)
    }

    @Test(.timeLimit(.minutes(1)))
    func reconnectingReplacesTheConnectionWithoutKillingIt() async throws {
        // Regression: tearing down the old socket wakes its receive loop with a
        // close error *after* the new connection is installed; without the
        // generation guard that error "closed" the new connection too, so every
        // reconnect died instantly and the retry loop spammed Metro with fresh
        // (and leaked) sockets.
        let serverA = CDPTestServer()
        let portA = try await serverA.start()
        let serverB = CDPTestServer()
        let portB = try await serverB.start()
        defer { Task { await serverA.stop(); await serverB.stop() } }

        let client = JSConsoleClient()
        let urlA = try #require(URL(string: "ws://127.0.0.1:\(portA)"))
        let streamA = try await client.connect(to: urlA)
        _ = try await client.evaluate("1")

        let urlB = try #require(URL(string: "ws://127.0.0.1:\(portB)"))
        let streamB = try await client.connect(to: urlB)

        // The old stream ends; the new connection survives and keeps working.
        for await _ in streamA {}
        let outcome = try await client.evaluate("2 + 2")
        guard case let .value(object) = outcome else {
            Issue.record("expected a value after reconnect, got \(outcome)")
            return
        }
        #expect(object.description == "4")

        // Events still flow on the new connection.
        await serverB.pushConsoleLog("after-reconnect")
        var received: ConsoleAPICall?
        for await event in streamB {
            if case let .console(call) = event { received = call; break }
        }
        #expect(received?.args.first?.value?.stringValue == "after-reconnect")
        await client.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func handshakeTimeoutFailsTheConnectInsteadOfHanging() async throws {
        // A proxy accepts the socket for a dead page but never answers
        // Runtime.enable; the connect must give up so the caller's reconnect
        // loop isn't wedged forever.
        let server = CDPTestServer()
        let port = try await server.start()
        await server.setMuted(true)
        defer { Task { await server.stop() } }

        let client = JSConsoleClient()
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))
        await #expect(throws: JSConsoleClient.ClientError.self) {
            _ = try await client.connect(to: url, handshakeTimeout: .milliseconds(300))
        }
        #expect(await !client.isConnected)
    }

    @Test(.timeLimit(.minutes(1)))
    func closingTheSocketSurfacesClosedAndEndsTheStream() async throws {
        let server = CDPTestServer()
        let port = try await server.start()

        let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))
        let client = JSConsoleClient()
        let stream = try await client.connect(to: url)

        // Drop the server: the client should surface .closed and finish the stream.
        await server.stop()
        var sawClosed = false
        for await event in stream {
            if case .closed = event { sawClosed = true }
        }
        #expect(sawClosed)
        await client.disconnect()
    }
}

/// A tiny scripted CDP server over `NWListener` + `NWProtocolWebSocket` — the
/// inbound mirror of the production outbound client. Replies to each request by
/// `id`, and can push events to the connected client.
private actor CDPTestServer {
    struct ConnectionBox: @unchecked Sendable {
        let connection: NWConnection
    }

    private static let queue = DispatchQueue(label: "com.rohindh.droidective.cdp-test-server")

    private var listener: NWListener?
    private var connection: ConnectionBox?
    private var readyContinuation: CheckedContinuation<UInt16, Error>?
    /// When muted, requests are read but never answered — a proxy holding a
    /// socket open for a page that will never respond.
    private var muted = false

    func setMuted(_ muted: Bool) { self.muted = muted }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)

        guard let anyPort = NWEndpoint.Port(rawValue: 0) else {
            throw CancellationError()
        }
        let listener = try NWListener(using: parameters, on: anyPort)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleListenerState(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            let box = ConnectionBox(connection: connection)
            Task { await self?.accept(box) }
        }
        listener.start(queue: Self.queue)
        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
        }
    }

    func stop() {
        connection?.connection.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
    }

    func pushConsoleLog(_ message: String) {
        send(.object([
            "method": .string("Runtime.consoleAPICalled"),
            "params": .object([
                "type": .string("log"),
                "args": .array([.object(["type": .string("string"), "value": .string(message)])]),
                "timestamp": .number(1),
            ]),
        ]))
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            readyContinuation?.resume(returning: listener?.port?.rawValue ?? 0)
            readyContinuation = nil
        case let .failed(error):
            readyContinuation?.resume(throwing: error)
            readyContinuation = nil
        default:
            break
        }
    }

    private func accept(_ box: ConnectionBox) {
        connection = box
        box.connection.start(queue: Self.queue)
        Self.receiveLoop(box, server: self)
    }

    private nonisolated static func receiveLoop(_ box: ConnectionBox, server: CDPTestServer) {
        box.connection.receiveMessage { content, context, _, error in
            if let context,
               let metadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition)
               as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .text, let content {
                Task { await server.handleFrame(content) }
            }
            if error != nil { return }
            receiveLoop(box, server: server)
        }
    }

    private func handleFrame(_ data: Data) {
        guard !muted,
              let root = try? JSONDecoder().decode(JSONValue.self, from: data),
              let id = root["id"]?.intValue,
              let method = root["method"]?.stringValue else { return }
        send(.object(["id": .number(Double(id)), "result": replyResult(for: method)]))
    }

    private func replyResult(for method: String) -> JSONValue {
        switch method {
        case "Runtime.evaluate":
            .object(["result": .object([
                "type": .string("number"), "value": .number(4), "description": .string("4"),
            ])])
        case "Runtime.getProperties":
            .object(["result": .array([
                .object([
                    "name": .string("x"),
                    "value": .object(["type": .string("number"), "value": .number(1), "description": .string("1")]),
                    "isOwn": .bool(true),
                ]),
            ])])
        case "Runtime.callFunctionOn":
            .object(["result": .object([
                "type": .string("string"),
                "value": .string("{\n  \"x\": 1\n}"),
            ])])
        default:
            .object([:])
        }
    }

    private func send(_ value: JSONValue) {
        guard let box = connection, let data = try? JSONEncoder().encode(value) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        box.connection.send(
            content: data, contentContext: context, isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }
}
