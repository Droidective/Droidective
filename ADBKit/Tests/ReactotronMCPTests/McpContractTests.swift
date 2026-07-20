import ADBKit
import Foundation
import MCP
import Testing
@testable import ReactotronMCP

/// Records what the tools send to the relay; can auto-answer a request type
/// by feeding a response command back into the store (the fake RN app).
actor FakeSender: McpCommandSender {
    struct Sent: Equatable {
        let type: String
        let payload: JSONValue
        let connectionId: Int?
    }

    private(set) var sent: [Sent] = []
    private var autoResponses: [String: ReactotronCommand] = [:]
    private let store: McpCommandStore

    init(store: McpCommandStore) {
        self.store = store
    }

    /// When a command of `requestType` is sent, ingest `response` from
    /// `connectionId` — simulating the app answering.
    func autoRespond(to requestType: String, with response: ReactotronCommand) {
        autoResponses[requestType] = response
    }

    func send(type: String, payload: JSONValue, toConnection id: Int) async {
        sent.append(Sent(type: type, payload: payload, connectionId: id))
        if let response = autoResponses[type] {
            await store.ingest(.command(connectionId: id, command: response, frameBytes: 64))
        }
    }

    func broadcast(type: String, payload: JSONValue) async {
        sent.append(Sent(type: type, payload: payload, connectionId: nil))
    }
}

@Suite struct McpContractTests {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func makeWorld() -> (store: McpCommandStore, sender: FakeSender, handlers: McpToolHandlers) {
        let store = McpCommandStore()
        let sender = FakeSender(store: store)
        let handlers = McpToolHandlers(store: store, sender: sender)
        return (store, sender, handlers)
    }

    private func connectApp(
        _ store: McpCommandStore, connectionId: Int = 1, clientId: String = "app-1",
        name: String = "TestApp", platform: String = "android"
    ) async throws {
        await store.ingest(.connected(
            connectionId: connectionId, clientId: clientId,
            intro: ReactotronCommand(
                type: "client.intro",
                payload: try json(#"{"name":"\#(name)","platform":"\#(platform)"}"#)),
            frameBytes: 40
        ))
    }

    private func resultBody(_ result: CallTool.Result) throws -> JSONValue {
        guard case let .text(text, _, _) = try #require(result.content.first) else {
            throw MCPError.internalError("expected text content")
        }
        return try json(text)
    }

    // MARK: - Registry invariants (the FeatureRegistry pattern)

    @Test func registryHasTheTenUpstreamToolsUniquelyNamed() {
        let names = McpToolRegistry.all.map(\.name)
        #expect(names == [
            "dispatch_action", "request_state", "request_state_keys", "swap_state",
            "send_custom_command", "list_custom_commands", "show_overlay",
            "clear_timeline", "subscribe_state", "unsubscribe_state",
        ])
        #expect(Set(names).count == names.count)
    }

    @Test func everyRegisteredSchemaDecodesToAnObjectSchema() throws {
        for def in McpToolRegistry.all {
            let schema = try #require(def.inputSchema, "schema for \(def.name) failed to decode")
            guard case let .object(root) = schema else {
                Issue.record("schema for \(def.name) is not an object"); continue
            }
            #expect(root["type"] == .string("object"), "schema for \(def.name) missing type")
            #expect(def.tool != nil)
            #expect(!def.description.isEmpty)
        }
    }

    @Test func everyRegisteredToolResolvesToAHandler() async throws {
        let (store, _, handlers) = makeWorld()
        try await connectApp(store)
        for def in McpToolRegistry.all {
            // Minimal viable arguments per tool; a missing dispatch case
            // would throw methodNotFound and fail this loop.
            let args: [String: Value] = switch def.name {
            case "dispatch_action": ["actionType": .string("PING")]
            case "swap_state": ["state": .object([:])]
            case "send_custom_command": ["command": .string("ping")]
            case "show_overlay": ["uri": .null]
            case "subscribe_state", "unsubscribe_state": ["path": .string("x")]
            default: [:]
            }
            _ = try await handlers.call(name: def.name, arguments: args)
        }
    }

    @Test func unknownToolThrows() async {
        let (_, _, handlers) = makeWorld()
        await #expect(throws: MCPError.self) {
            _ = try await handlers.call(name: "bogus_tool", arguments: nil)
        }
    }

    // MARK: - resolveClientId semantics (upstream error strings)

    @Test func toolsErrorWhenNoAppsConnected() async throws {
        let (_, _, handlers) = makeWorld()
        let body = try resultBody(try await handlers.call(name: "request_state", arguments: nil))
        #expect(body["status"]?.stringValue == "error")
        #expect(body["message"]?.stringValue == "No apps connected to Reactotron.")
    }

    @Test func toolsListAvailableAppsWhenAmbiguous() async throws {
        let (store, _, handlers) = makeWorld()
        try await connectApp(store, connectionId: 1, clientId: "id-a", name: "AppA")
        try await connectApp(store, connectionId: 2, clientId: "id-b", name: "AppB", platform: "ios")
        let body = try resultBody(try await handlers.call(name: "request_state", arguments: nil))
        let message = try #require(body["message"]?.stringValue)
        #expect(message.hasPrefix("Multiple apps connected. Specify clientId. Available: "))
        #expect(message.contains("AppA (android): id-a"))
        #expect(message.contains("AppB (ios): id-b"))
    }

    // MARK: - Request/response tools against the fake app

    @Test func dispatchActionConfirmsWhenTheAppAnswers() async throws {
        let (store, sender, handlers) = makeWorld()
        try await connectApp(store)
        await sender.autoRespond(
            to: "state.action.dispatch",
            with: ReactotronCommand(type: "state.action.complete", payload: .null)
        )
        let body = try resultBody(try await handlers.call(
            name: "dispatch_action",
            arguments: ["actionType": .string("user/setName"),
                        "actionPayload": .object(["name": .string("Alice")])]
        ))
        #expect(body["status"]?.stringValue == "dispatched")
        #expect(body["confirmed"]?.boolValue == true)
        #expect(body["action"]?["type"]?.stringValue == "user/setName")

        let dispatch = try #require(await sender.sent.first)
        #expect(dispatch.type == "state.action.dispatch")
        #expect(dispatch.payload["action"]?["type"]?.stringValue == "user/setName")
        #expect(dispatch.connectionId == 1)
    }

    @Test func requestStateReturnsTheRedactedSlice() async throws {
        let (store, sender, handlers) = makeWorld()
        try await connectApp(store)
        await sender.autoRespond(
            to: "state.values.request",
            with: ReactotronCommand(
                type: "state.values.response",
                payload: try json(
                    #"{"path":"user","value":{"name":"alice","password":"hunter2"},"valid":true}"#))
        )
        let body = try resultBody(try await handlers.call(
            name: "request_state", arguments: ["path": .string("user")]))
        #expect(body["status"]?.stringValue == "success")
        #expect(body["state"]?["name"]?.stringValue == "alice")
        #expect(body["state"]?["password"]?.stringValue == McpRedaction.redactedMarker)
    }

    @Test func requestStateReportsNoResponseOnTimeout() async throws {
        let store = McpCommandStore()
        let sender = FakeSender(store: store) // never answers
        let handlers = McpToolHandlers(store: store, sender: sender)
        try await connectApp(store)
        // Shrink the wait by asking through the store's own timeout: the
        // handler uses McpConstants.commandTimeout (1.5s) — acceptable here.
        let body = try resultBody(try await handlers.call(name: "request_state", arguments: nil))
        #expect(body["status"]?.stringValue == "no_response")
        #expect(body["message"]?.stringValue?.contains("Redux or MST") == true)
    }

    @Test func subscribeToolsMaintainThePathListAndBroadcast() async throws {
        let (store, sender, handlers) = makeWorld()
        try await connectApp(store)
        _ = try await handlers.call(
            name: "subscribe_state", arguments: ["path": .string("user.name")])
        let body = try resultBody(try await handlers.call(
            name: "subscribe_state", arguments: ["path": .string("cart")]))
        #expect(body["activeSubscriptions"]?.arrayValue?.compactMap(\.stringValue)
            == ["user.name", "cart"])

        let unsubBody = try resultBody(try await handlers.call(
            name: "unsubscribe_state", arguments: ["path": .string("user.name")]))
        #expect(unsubBody["activeSubscriptions"]?.arrayValue?.compactMap(\.stringValue) == ["cart"])

        let broadcasts = await sender.sent.filter { $0.type == "state.values.subscribe" }
        #expect(broadcasts.count == 3)
        #expect(broadcasts.last?.payload["paths"]?.arrayValue?.compactMap(\.stringValue) == ["cart"])
    }

    @Test func clearTimelineReportsRemovedCountAndClearsOnlyTheBuffer() async throws {
        let (store, _, handlers) = makeWorld()
        try await connectApp(store)
        await store.ingest(.command(
            connectionId: 1, command: ReactotronCommand(type: "log"), frameBytes: 10))
        let body = try resultBody(try await handlers.call(name: "clear_timeline", arguments: nil))
        #expect(body["status"]?.stringValue == "cleared")
        #expect(body["eventsRemoved"]?.intValue == 2)
        #expect(await store.commands().isEmpty)
        #expect(await store.connectedClients.count == 1)
    }

    @Test func showOverlayEmbedsALocalPngAndFillsDimensions() async throws {
        let (store, sender, handlers) = makeWorld()
        try await connectApp(store)
        // Minimal PNG header: signature + IHDR with 320x200 at offsets 16/20.
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png += Data([0, 0, 0, 13]) + Data("IHDR".utf8)
        png += Data([0, 0, 0x01, 0x40, 0, 0, 0, 0xC8, 8, 6, 0, 0, 0])
        let fixture = png
        let handlersWithFile = McpToolHandlers(
            store: store, sender: await sender as any McpCommandSender,
            readFile: { _ in fixture }
        )
        let body = try resultBody(try await handlersWithFile.call(
            name: "show_overlay", arguments: ["uri": .string("/tmp/mock.png")]))
        #expect(body["status"]?.stringValue == "sent")
        #expect(body["overlay"]?["width"]?.intValue == 320)
        #expect(body["overlay"]?["height"]?.intValue == 200)
        #expect(body["overlay"]?["opacity"]?.doubleValue == 0.5)

        let overlay = try #require(await sender.sent.last)
        #expect(overlay.type == "overlay")
        #expect(overlay.payload["uri"]?.stringValue?.hasPrefix("data:image/png;base64,") == true)
    }

    @Test func showOverlayRejectsUnsupportedAndOversizedImages() async throws {
        let (store, _, handlers) = makeWorld()
        try await connectApp(store)
        let unsupported = try resultBody(try await handlers.call(
            name: "show_overlay", arguments: ["uri": .string("/tmp/mock.webp")]))
        #expect(unsupported["message"]?.stringValue
            == "Unsupported image format: .webp. Use PNG, JPEG, or GIF.")

        let big = Data(count: McpConstants.maxOverlayImageBytes + 1)
        let handlersWithBigFile = McpToolHandlers(
            store: store, sender: FakeSender(store: store), readFile: { _ in big })
        let oversized = try resultBody(try await handlersWithBigFile.call(
            name: "show_overlay", arguments: ["uri": .string("/tmp/big.png")]))
        #expect(oversized["message"]?.stringValue?.contains("Maximum is 2MB") == true)
    }

    // MARK: - Image probe

    @Test func imageProbeReadsPngJpegGifHeaders() {
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png += Data([0, 0, 0, 13]) + Data("IHDR".utf8)
        png += Data([0, 0, 0x01, 0x40, 0, 0, 0, 0xC8, 8, 6, 0, 0, 0])
        #expect(McpImageProbe.size(of: png, extension: "png")! == (320, 200))

        var gif = Data("GIF89a".utf8)
        gif += Data([0x40, 0x01, 0xC8, 0x00, 0, 0, 0, 0, 0])
        #expect(McpImageProbe.size(of: gif, extension: "gif")! == (320, 200))

        // JPEG: SOI + SOF0 segment carrying 200x320.
        var jpeg = Data([0xFF, 0xD8])
        jpeg += Data([0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0xC8, 0x01, 0x40, 0x03])
        jpeg += Data(count: 16)
        #expect(McpImageProbe.size(of: jpeg, extension: "jpg")! == (320, 200))

        #expect(McpImageProbe.size(of: Data([0, 1, 2]), extension: "png") == nil)
        #expect(McpImageProbe.size(of: png, extension: "webp") == nil)
    }

    // MARK: - Resources

    @Test func timelineResourceSummarizesNewestFirstWithMeta() async throws {
        let (store, _, _) = makeWorld()
        let resources = McpResources(store: store)
        try await connectApp(store)
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "log", payload: try json(#"{"level":"debug","message":"first"}"#)),
            frameBytes: 20))
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "log", payload: try json(#"{"level":"warn","message":"second"}"#)),
            frameBytes: 20))

        let result = try await resources.read(uri: "reactotron://timeline")
        let body = try json(try #require(result.contents.first?.text))
        #expect(body["_meta"]?["connection"]?.stringValue == "single_app")
        #expect(body["eventCount"]?.intValue == 3)
        let previews = try #require(body["events"]?.arrayValue)
            .compactMap { $0["payloadPreview"]?.stringValue }
        #expect(previews.first == "[warn] second") // newest first
        #expect(body["events"]?.arrayValue?.first?["payload"] == nil) // stripped
    }

    @Test func timelineByTypeReturnsFullRedactedPayloads() async throws {
        let (store, _, _) = makeWorld()
        let resources = McpResources(store: store)
        try await connectApp(store)
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "api.response",
                payload: try json(#"""
                {"duration":9,"request":{"method":"GET","url":"https://x.dev/me",
                 "headers":{"Authorization":"Bearer secret-token-12345"}},
                 "response":{"status":200,"body":"{}"}}
                """#)),
            frameBytes: 80))

        let result = try await resources.read(uri: "reactotron://timeline/api.response")
        let body = try json(try #require(result.contents.first?.text))
        #expect(body["type"]?.stringValue == "api.response")
        let event = try #require(body["events"]?.arrayValue?.first)
        #expect(event["payload"]?["request"]?["headers"]?["Authorization"]?.stringValue
            == McpRedaction.redactedMarker)
        #expect(event["payload"]?["request"]?["url"]?.stringValue == "https://x.dev/me")
    }

    @Test func networkResourceRedactsSummaries() async throws {
        let (store, _, _) = makeWorld()
        let resources = McpResources(store: store)
        try await connectApp(store)
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "api.response",
                payload: try json(#"""
                {"duration":5,"request":{"method":"POST","url":"https://x.dev/login?token=abc&page=1",
                 "headers":{"Cookie":"session=xyz"},"data":"user=a&password=b"},
                 "response":{"status":401,"headers":{},"body":"denied"}}
                """#)),
            frameBytes: 90))

        let result = try await resources.read(uri: "reactotron://network/log")
        let body = try json(try #require(result.contents.first?.text))
        let entry = try #require(body["entries"]?.arrayValue?.first)
        #expect(entry["request"]?["headers"]?["Cookie"]?.stringValue == McpRedaction.redactedMarker)
        #expect(entry["request"]?["url"]?.stringValue
            == "https://x.dev/login?token=\(McpRedaction.redactedMarker)&page=1")
        #expect(entry["request"]?["data"]?.stringValue
            == "user=a&password=\(McpRedaction.redactedMarker)")
        #expect(entry["response"]?["status"]?.intValue == 401)
    }

    @Test func stateCurrentFallsBackWhenNothingCached() async throws {
        let (store, _, _) = makeWorld()
        let resources = McpResources(store: store)
        let result = try await resources.read(uri: "reactotron://state/current")
        let body = try json(try #require(result.contents.first?.text))
        #expect(body["_meta"]?["connection"]?.stringValue == "no_apps_connected")
        #expect(body["state"]?["status"]?.stringValue == "no_state_received")
    }

    @Test func appsResourceListsConnectedApps() async throws {
        let (store, _, _) = makeWorld()
        let resources = McpResources(store: store)
        try await connectApp(store, connectionId: 3, clientId: "abc", name: "Foodhub")
        let result = try await resources.read(uri: "reactotron://apps")
        let body = try json(try #require(result.contents.first?.text))
        let app = try #require(body["apps"]?.arrayValue?.first)
        #expect(app["clientId"]?.stringValue == "abc")
        #expect(app["name"]?.stringValue == "Foodhub")
        #expect(app["id"]?.intValue == 3)
    }

    @Test func asyncStorageResourceRedactsByStorageKey() async throws {
        let (store, _, _) = makeWorld()
        let resources = McpResources(store: store)
        try await connectApp(store)
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "asyncStorage.mutation",
                payload: try json(
                    #"{"action":"setItem","data":{"key":"auth:token","value":"tok-123"}}"#)),
            frameBytes: 40))
        let result = try await resources.read(uri: "reactotron://asyncstorage")
        let body = try json(try #require(result.contents.first?.text))
        let mutation = try #require(body["mutations"]?.arrayValue?.first)
        #expect(mutation["action"]?.stringValue == "setItem")
        #expect(mutation["data"]?["value"]?.stringValue == McpRedaction.redactedMarker)
    }

    @Test func unknownResourceUriThrows() async {
        let (store, _, _) = makeWorld()
        let resources = McpResources(store: store)
        await #expect(throws: MCPError.self) {
            _ = try await resources.read(uri: "reactotron://nope")
        }
    }

    @Test func resourceListIncludesTemplateInstancesPerBufferedType() async throws {
        let (store, _, _) = makeWorld()
        let resources = McpResources(store: store)
        await store.ingest(.command(
            connectionId: 1, command: ReactotronCommand(type: "log"), frameBytes: 5))
        let list = await resources.list()
        #expect(list.contains { $0.uri == "reactotron://timeline" })
        #expect(list.contains { $0.uri == "reactotron://timeline/log" && $0.name == "timeline:log" })
        #expect(await resources.completeType(prefix: "lo") == ["log"])
        #expect(resources.templates().first?.uriTemplate == "reactotron://timeline/{type}")
    }

    // MARK: - Full stack over InMemoryTransport

    @Test(.timeLimit(.minutes(1)))
    func endToEndOverInMemoryTransport() async throws {
        let (store, sender, _) = makeWorld()
        try await connectApp(store)
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "log", payload: try json(#"{"level":"error","message":"boom"}"#)),
            frameBytes: 30))
        await sender.autoRespond(
            to: "state.keys.request",
            with: ReactotronCommand(
                type: "state.keys.response",
                payload: try json(#"{"path":"","keys":["user","cart"],"valid":true}"#))
        )

        let factory = McpServerFactory(store: store, sender: sender, version: "0.0.1-test")
        let server = await factory.makeServer()
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        try await server.start(transport: serverTransport)
        let client = Client(name: "test-client", version: "1.0")
        let initResult = try await client.connect(transport: clientTransport)
        #expect(initResult.serverInfo.name == "droidective-reactotron")

        let (tools, _) = try await client.listTools()
        #expect(tools.count == 10)
        #expect(tools.map(\.name).contains("dispatch_action"))

        let (resources, _) = try await client.listResources()
        #expect(resources.contains { $0.uri == "reactotron://timeline" })

        let contents = try await client.readResource(uri: "reactotron://timeline")
        let timeline = try json(try #require(contents.first?.text))
        #expect(timeline["eventCount"]?.intValue == 2)

        let (keysContent, keysIsError) = try await client.callTool(
            name: "request_state_keys", arguments: [:])
        #expect(keysIsError != true)
        guard case let .text(keysText, _, _) = try #require(keysContent.first) else {
            Issue.record("expected text content"); return
        }
        let keysBody = try json(keysText)
        #expect(keysBody["status"]?.stringValue == "success")
        #expect(keysBody["keys"]?.arrayValue?.compactMap(\.stringValue) == ["user", "cart"])

        await client.disconnect()
        await server.stop()
    }
}
