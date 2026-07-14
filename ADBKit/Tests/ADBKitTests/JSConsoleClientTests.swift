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
    func reloadPageSendsPageReloadOverTheSocket() async throws {
        let server = CDPTestServer()
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let client = JSConsoleClient()
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))
        _ = try await client.connect(to: url)
        try await client.reloadPage()
        #expect(await server.receivedMethods.contains("Page.reload"))
        await client.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func reloadPageTimesOutInsteadOfHangingWhenUnanswered() async throws {
        // A proxy relaying to a dead page never answers; the bounded wait must
        // fail the call rather than suspend the caller forever.
        let server = CDPTestServer()
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let client = JSConsoleClient()
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))
        _ = try await client.connect(to: url)
        await server.setMuted(true)
        await #expect(throws: JSConsoleClient.ClientError.self) {
            try await client.reloadPage(replyTimeout: .milliseconds(300))
        }
        await client.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func keepaliveSendsSilentNoOpEvaluatesOnTheWire() async throws {
        // RN's inspector proxy terminates a debugger socket that delivers
        // neither a pong nor a data message inside its heartbeat window, and
        // client pings don't count — the keepalive must be real CDP traffic.
        let server = CDPTestServer()
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let client = JSConsoleClient()
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))
        _ = try await client.connect(to: url, keepaliveInterval: .milliseconds(50))
        try await Task.sleep(for: .milliseconds(400))

        let keepalives = await server.receivedPayloads.filter {
            $0["method"]?.stringValue == "Runtime.evaluate"
                && $0["params"]?["silent"]?.boolValue == true
        }
        #expect(keepalives.count >= 2)
        for frame in keepalives {
            #expect(frame["params"]?["expression"]?.stringValue == "void 0")
            #expect(frame["params"]?["returnByValue"]?.boolValue == true)
        }

        // Real requests still correlate with their own replies while the
        // keepalive replies are silently discarded.
        let outcome = try await client.evaluate("2 + 2")
        guard case let .value(object) = outcome else {
            Issue.record("expected a value alongside keepalive traffic, got \(outcome)")
            return
        }
        #expect(object.description == "4")
        await client.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func newDebuggerCloseSurfacesATakeoverSoTheSessionStandsDown() async throws {
        // dev-middleware closes the previous debugger with this reason when
        // another one (React Native DevTools) attaches; auto-reconnecting
        // would kick that debugger back off, so the event must say takeover.
        let server = CDPTestServer()
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let client = JSConsoleClient()
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)"))
        let stream = try await client.connect(to: url)
        await server.closeGracefully(
            reason: "[NEW_DEBUGGER_OPENED] New debugger opened for the same app instance"
        )
        var takeover: Bool?
        for await event in stream {
            if case let .closed(_, isTakeover) = event { takeover = isTakeover }
        }
        #expect(takeover == true)
        await client.disconnect()
    }

    @Test func takeoverCloseReasonsAreRecognizedAcrossProxyVersions() {
        // Current dev-middleware (RN 0.76+).
        #expect(JSConsoleClient.isDebuggerTakeover(
            "[NEW_DEBUGGER_OPENED] New debugger opened for the same app instance"
        ))
        // The legacy Metro inspector proxy.
        #expect(JSConsoleClient.isDebuggerTakeover("Another debugger is already connected"))
        // Everything else keeps auto-reconnect.
        #expect(!JSConsoleClient.isDebuggerTakeover("[CONNECTION_LOST] Connection lost to device"))
        #expect(!JSConsoleClient.isDebuggerTakeover("[PAGE_NOT_FOUND] Debugger page not found"))
        #expect(!JSConsoleClient.isDebuggerTakeover(""))
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
    /// Every CDP method received, in arrival order — lets tests assert what
    /// actually went over the wire.
    private(set) var receivedMethods: [String] = []
    /// The full frames, for arg-vector-style assertions on request params.
    private(set) var receivedPayloads: [JSONValue] = []

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

    /// Send a proper WebSocket close frame with a reason — what dev-middleware
    /// does when a new debugger takes over an app's connection.
    func closeGracefully(reason: String) {
        guard let box = connection else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = .protocolCode(.normalClosure)
        let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
        box.connection.send(
            content: Data(reason.utf8), contentContext: context, isComplete: true,
            completion: .contentProcessed { _ in }
        )
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
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data),
              let id = root["id"]?.intValue,
              let method = root["method"]?.stringValue else { return }
        receivedMethods.append(method)
        receivedPayloads.append(root)
        guard !muted else { return }
        send(.object(["id": .number(Double(id)), "result": replyResult(for: method)]))
    }

    private func replyResult(for method: String) -> JSONValue {
        switch method {
        case "Runtime.evaluate":
            .object(["result": .object([
                "type": .string("number"), "value": .number(4), "description": .string("4"),
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
