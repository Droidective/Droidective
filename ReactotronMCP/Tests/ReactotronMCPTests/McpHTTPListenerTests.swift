#if canImport(Network)

import ADBKit
import Foundation
import MCP
import Testing
@testable import ReactotronMCP

/// Real-socket tests: the NIO listener on an OS-assigned port, exercised by
/// the SDK's own Streamable HTTP client (the realistic interop check) and by
/// raw URLSession requests for the rejection paths.
@Suite struct McpHTTPListenerTests {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func makeListener(
        bearerToken: String? = nil
    ) async throws -> (listener: McpHTTPListener, store: McpCommandStore, port: UInt16) {
        let store = McpCommandStore()
        let sender = FakeSender(store: store)
        let factory = McpServerFactory(store: store, sender: sender, version: "0.0.1-test")
        let listener = McpHTTPListener(
            configuration: McpHTTPListener.Configuration(port: 0, bearerToken: bearerToken),
            factory: factory
        )
        try await listener.start()
        let port = try #require(await listener.boundPort)
        return (listener, store, port)
    }

    private static let initializeBody = Data(#"""
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{
      "protocolVersion":"2025-11-25","capabilities":{},
      "clientInfo":{"name":"raw-test","version":"1.0"}}}
    """#.utf8)

    /// Raw POST /mcp; returns status + response headers.
    private func rawPost(
        port: UInt16,
        body: Data = McpHTTPListenerTests.initializeBody,
        path: String = "/mcp",
        headers: [String: String] = [:]
    ) async throws -> (status: Int, headers: [AnyHashable: Any]) {
        var request = URLRequest(url: try #require(
            URL(string: "http://127.0.0.1:\(port)\(path)")))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        return (http.statusCode, http.allHeaderFields)
    }

    @Test(.timeLimit(.minutes(1)))
    func fullClientRoundTripOverRealHTTP() async throws {
        let (listener, store, port) = try await makeListener()
        defer { Task { await listener.stop() } }

        // A connected fake app with one buffered log.
        await store.ingest(.connected(
            connectionId: 1, clientId: "app-1",
            intro: ReactotronCommand(
                type: "client.intro",
                payload: try json(#"{"name":"SocketApp","platform":"android"}"#)),
            frameBytes: 40))
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "log", payload: try json(#"{"level":"warn","message":"over http"}"#)),
            frameBytes: 30))

        let transport = HTTPClientTransport(
            endpoint: try #require(URL(string: "http://127.0.0.1:\(port)/mcp")))
        let client = Client(name: "socket-test", version: "1.0")
        let initResult = try await client.connect(transport: transport)
        #expect(initResult.serverInfo.name == "droidective-reactotron")
        #expect(await listener.activeSessionCount == 1)

        let (tools, _) = try await client.listTools()
        #expect(tools.count == 10)

        let contents = try await client.readResource(uri: "reactotron://timeline")
        let timeline = try json(try #require(contents.first?.text))
        #expect(timeline["eventCount"]?.intValue == 2)
        #expect(timeline["_meta"]?["app"]?["name"]?.stringValue == "SocketApp")

        let (cleared, isError) = try await client.callTool(name: "clear_timeline", arguments: [:])
        #expect(isError != true)
        guard case let .text(text, _, _) = try #require(cleared.first) else {
            Issue.record("expected text content"); return
        }
        #expect(try json(text)["status"]?.stringValue == "cleared")

        await client.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentSessionsGetIndependentServers() async throws {
        let (listener, _, port) = try await makeListener()
        defer { Task { await listener.stop() } }
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/mcp"))

        let first = Client(name: "client-a", version: "1.0")
        let second = Client(name: "client-b", version: "1.0")
        _ = try await first.connect(transport: HTTPClientTransport(endpoint: url))
        _ = try await second.connect(transport: HTTPClientTransport(endpoint: url))
        #expect(await listener.activeSessionCount == 2)

        async let toolsA = first.listTools()
        async let toolsB = second.listTools()
        let (a, b) = try await (toolsA, toolsB)
        #expect(a.tools.count == 10)
        #expect(b.tools.count == 10)

        await first.disconnect()
        await second.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func requestsOffTheEndpointAre404() async throws {
        let (listener, _, port) = try await makeListener()
        defer { Task { await listener.stop() } }
        let (status, _) = try await rawPost(port: port, path: "/other")
        #expect(status == 404)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonInitializePostWithoutSessionIs400() async throws {
        let (listener, _, port) = try await makeListener()
        defer { Task { await listener.stop() } }
        let (status, _) = try await rawPost(
            port: port,
            body: Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8))
        #expect(status == 400)
    }

    @Test(.timeLimit(.minutes(1)))
    func crossOriginInitializeIsRejected() async throws {
        let (listener, _, port) = try await makeListener()
        defer { Task { await listener.stop() } }
        // DNS-rebinding shape: a browser page on evil.com posting to
        // 127.0.0.1. OriginValidator.localhost() must reject it.
        let (status, _) = try await rawPost(
            port: port, headers: ["Origin": "http://evil.example.com"])
        #expect(status == 403)

        // Localhost origins pass (the validator's patterns require a port).
        let (allowed, _) = try await rawPost(
            port: port, headers: ["Origin": "http://localhost:3000"])
        #expect(allowed == 200)
    }

    @Test(.timeLimit(.minutes(1)))
    func bearerTokenIsEnforcedWhenConfigured() async throws {
        let (listener, _, port) = try await makeListener(bearerToken: "sekrit-123")
        defer { Task { await listener.stop() } }

        let (missing, _) = try await rawPost(port: port)
        #expect(missing == 401)

        let (wrong, _) = try await rawPost(
            port: port, headers: ["Authorization": "Bearer nope"])
        #expect(wrong == 401)

        let (right, headers) = try await rawPost(
            port: port, headers: ["Authorization": "Bearer sekrit-123"])
        #expect(right == 200)
        #expect(headers["Mcp-Session-Id"] != nil || headers["MCP-Session-Id"] != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func deleteEndsTheSession() async throws {
        let (listener, _, port) = try await makeListener()
        defer { Task { await listener.stop() } }

        let (status, headers) = try await rawPost(port: port)
        #expect(status == 200)
        let sessionID = try #require(
            (headers["Mcp-Session-Id"] ?? headers["MCP-Session-Id"]) as? String)
        #expect(await listener.activeSessionCount == 1)

        var request = URLRequest(url: try #require(
            URL(string: "http://127.0.0.1:\(port)/mcp")))
        request.httpMethod = "DELETE"
        request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(await listener.activeSessionCount == 0)
    }

    @Test func controllerStartsStopsAndReportsStatus() async throws {
        let controller = McpServerController()
        #expect(await controller.status == .stopped)

        let (stream, continuation) = AsyncStream.makeStream(of: ReactotronServer.Event.self)
        let store = await controller.commandStore
        let sender = FakeSender(store: store)
        try await controller.start(
            events: stream, sender: sender, version: "0.0.1-test", port: 0)
        guard case let .listening(port) = await controller.status else {
            Issue.record("expected .listening"); return
        }
        #expect(port > 0)

        // Events flow through the tap into the controller's store.
        continuation.yield(.command(
            connectionId: 1, command: ReactotronCommand(type: "log"), frameBytes: 10))
        try await Task.sleep(for: .milliseconds(200))
        #expect(await store.bufferedCount == 1)

        await controller.stop()
        #expect(await controller.status == .stopped)
        continuation.finish()
    }

    @Test func portConflictSurfacesAsPortInUse() async throws {
        let (listener, _, port) = try await makeListener()
        defer { Task { await listener.stop() } }

        let store = McpCommandStore()
        let factory = McpServerFactory(
            store: store, sender: FakeSender(store: store), version: "t")
        let second = McpHTTPListener(
            configuration: McpHTTPListener.Configuration(port: port), factory: factory)
        await #expect(throws: McpHTTPListener.ListenerError.self) {
            try await second.start()
        }
    }
}

#endif
