import ADBKit
import Foundation
import Testing
@testable import ReactotronMCP

/// The MCP ring buffer: retention caps, derived side-state (clients, latest
/// state, custom commands), and event-driven request/response correlation.
@Suite struct McpCommandStoreTests {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func intro(name: String, extra: String = "") throws -> ReactotronCommand {
        ReactotronCommand(
            type: "client.intro",
            payload: try json(#"{"name":"\#(name)","platform":"android"\#(extra)}"#)
        )
    }

    private func log(_ message: String) -> ReactotronCommand {
        ReactotronCommand(type: "log", payload: .object(["message": .string(message)]))
    }

    private func connect(
        _ store: McpCommandStore, connectionId: Int, clientId: String, name: String
    ) async throws {
        await store.ingest(.connected(
            connectionId: connectionId, clientId: clientId,
            intro: try intro(name: name), frameBytes: 50
        ))
    }

    // MARK: - Buffering

    @Test func buffersCommandsWithMonotonicMessageIdsAndClientAttribution() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "A")
        await store.ingest(.command(connectionId: 1, command: log("one"), frameBytes: 10))
        await store.ingest(.command(connectionId: 1, command: log("two"), frameBytes: 10))

        let all = await store.commands()
        #expect(all.count == 3) // intro + two logs
        #expect(all.map(\.messageId) == [1, 2, 3])
        #expect(all.allSatisfy { $0.clientId == "app-a" })
        let logs = await store.commands(ofType: "log")
        #expect(logs.map { $0.command.payload?["message"]?.stringValue } == ["one", "two"])
    }

    @Test func itemCapDropsOldestFirst() async throws {
        let store = McpCommandStore(maxItems: 8, maxBytes: .max)
        for index in 0 ..< 20 {
            await store.ingest(.command(connectionId: 1, command: log("\(index)"), frameBytes: 10))
        }
        let kept = await store.commands()
        #expect(kept.count <= 8)
        // Newest always survives; the survivors are a suffix (oldest dropped).
        #expect(kept.last?.command.payload?["message"]?.stringValue == "19")
        let numbers = kept.compactMap { $0.command.payload?["message"]?.stringValue }.compactMap(Int.init)
        #expect(numbers == Array((20 - numbers.count) ..< 20))
    }

    @Test func byteCapDropsOldestFirstAndKeepsNewest() async throws {
        let store = McpCommandStore(maxItems: .max, maxBytes: 1000)
        for index in 0 ..< 10 {
            await store.ingest(.command(connectionId: 1, command: log("\(index)"), frameBytes: 300))
        }
        let kept = await store.commands()
        #expect(kept.count < 10)
        #expect(kept.last?.command.payload?["message"]?.stringValue == "9")
        // A single frame bigger than the whole budget still lands (newest kept).
        await store.ingest(.command(connectionId: 1, command: log("huge"), frameBytes: 5000))
        #expect(await store.commands().last?.command.payload?["message"]?.stringValue == "huge")
    }

    @Test func clearEmptiesTheBufferButKeepsClients() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "A")
        await store.ingest(.command(connectionId: 1, command: log("x"), frameBytes: 10))
        await store.clear()
        #expect(await store.commands().isEmpty)
        #expect(await store.connectedClients.count == 1)
        // messageIds keep climbing after clear — correlation markers stay valid.
        await store.ingest(.command(connectionId: 1, command: log("y"), frameBytes: 10))
        #expect(await store.commands().first?.messageId == 3)
    }

    @Test func bufferedTypesAreDistinctInFirstSeenOrder() async throws {
        let store = McpCommandStore()
        await store.ingest(.command(connectionId: 1, command: log("a"), frameBytes: 5))
        await store.ingest(.command(
            connectionId: 1, command: ReactotronCommand(type: "display"), frameBytes: 5))
        await store.ingest(.command(connectionId: 1, command: log("b"), frameBytes: 5))
        #expect(await store.bufferedTypes() == ["log", "display"])
    }

    // MARK: - Clients & derived state

    @Test func connectDisconnectMaintainsTheClientList() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "A")
        try await connect(store, connectionId: 2, clientId: "app-b", name: "B")
        #expect(await store.connectedClients.map(\.clientId) == ["app-a", "app-b"])
        #expect(await store.connectedClients.first?.name == "A")

        await store.ingest(.disconnected(connectionId: 1, reason: nil))
        #expect(await store.connectedClients.map(\.clientId) == ["app-b"])
    }

    @Test func reconnectWithSameClientIdReplacesTheRecord() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "Old")
        try await connect(store, connectionId: 5, clientId: "app-a", name: "New")
        let clients = await store.connectedClients
        #expect(clients.count == 1)
        #expect(clients.first?.connectionId == 5)
        #expect(clients.first?.name == "New")
    }

    @Test func introCarriesMcpRedactionConfig() async throws {
        let store = McpCommandStore()
        await store.ingest(.connected(
            connectionId: 1, clientId: "app-a",
            intro: try intro(
                name: "A",
                extra: #","mcpRedaction":{"additionalRules":{"sensitiveKeys":["companyToken"]}}"#
            ),
            frameBytes: 80
        ))
        let record = try #require(await store.connectedClients.first)
        #expect(record.redaction?.additionalRules?.sensitiveKeys == ["companyToken"])
    }

    @Test func latestStateIsCachedPerClient() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "A")
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "state.values.response",
                payload: try json(#"{"path":null,"value":{"count":1},"valid":true}"#)),
            frameBytes: 40
        ))
        let cached = try #require(await store.latestState(clientId: "app-a"))
        #expect(cached["value"]?["count"]?.intValue == 1)
        // Sole connected client also resolves with no clientId.
        #expect(await store.latestState(clientId: nil) != nil)
    }

    @Test func customCommandRegistryFollowsRegisterAndUnregister() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "A")
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "customCommand.register",
                payload: try json(#"{"id":1,"command":"show_dev_menu","title":"Dev menu"}"#)),
            frameBytes: 30
        ))
        #expect(await store.customCommands(clientId: "app-a").count == 1)

        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "customCommand.unregister",
                payload: try json(#"{"id":1,"command":"show_dev_menu"}"#)),
            frameBytes: 30
        ))
        #expect(await store.customCommands(clientId: "app-a").isEmpty)
    }

    @Test func disconnectDropsTheClientsCustomCommands() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "A")
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "customCommand.register",
                payload: try json(#"{"id":1,"command":"c"}"#)),
            frameBytes: 20
        ))
        await store.ingest(.disconnected(connectionId: 1, reason: nil))
        #expect(await store.customCommands(clientId: "app-a").isEmpty)
    }

    @Test func stateValuesChangeRefreshesSubscriptionPaths() async throws {
        let store = McpCommandStore()
        await store.setSubscriptions(["stale.path"])
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "state.values.change",
                payload: try json(#"{"changes":[{"path":"user.name","value":"x"},{"path":"cart","value":[]}]}"#)),
            frameBytes: 40
        ))
        #expect(await store.subscriptions == ["user.name", "cart"])
    }

    @Test func listeningStateTracksServerLifecycle() async {
        let store = McpCommandStore()
        #expect(await !store.isListening)
        await store.ingest(.listening(port: 9090))
        #expect(await store.isListening)
        #expect(await store.port == 9090)
        await store.ingest(.failed(reason: "boom", portInUse: false))
        #expect(await !store.isListening)
    }

    // MARK: - Correlation

    @Test func awaitCommandResumesWhenTheResponseArrives() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "A")
        let marker = await store.lastMessageId

        async let waited = store.awaitCommand(
            ofType: "state.values.response", clientId: "app-a",
            afterMessageId: marker, timeout: .seconds(5)
        )
        // Give the wait a beat to register, then deliver the response.
        try await Task.sleep(for: .milliseconds(50))
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(
                type: "state.values.response", payload: try json(#"{"valid":true}"#)),
            frameBytes: 20
        ))
        let result = try #require(await waited)
        #expect(result.command.type == "state.values.response")
        #expect(result.clientId == "app-a")
    }

    @Test func awaitCommandServesAResponseThatBeatTheWait() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "A")
        let marker = await store.lastMessageId
        // Response lands before awaitCommand is even called (send → fast app).
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(type: "state.keys.response", payload: .null),
            frameBytes: 10
        ))
        let result = await store.awaitCommand(
            ofType: "state.keys.response", clientId: "app-a",
            afterMessageId: marker, timeout: .milliseconds(100)
        )
        #expect(result != nil)
    }

    @Test func awaitCommandIgnoresStaleResponsesBeforeTheMarker() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "A")
        // A stale response from an earlier request sits in the buffer.
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(type: "state.values.response", payload: .null),
            frameBytes: 10
        ))
        let marker = await store.lastMessageId
        let result = await store.awaitCommand(
            ofType: "state.values.response", clientId: "app-a",
            afterMessageId: marker, timeout: .milliseconds(150)
        )
        #expect(result == nil) // timed out rather than matching the stale one
    }

    @Test func awaitCommandTimesOutAtTheDeadline() async {
        let store = McpCommandStore()
        let start = ContinuousClock.now
        let result = await store.awaitCommand(
            ofType: "never.arrives", clientId: nil,
            afterMessageId: 0, timeout: .milliseconds(120)
        )
        #expect(result == nil)
        #expect(ContinuousClock.now - start >= .milliseconds(100))
    }

    @Test func awaitCommandMatchesOnlyTheRequestedClient() async throws {
        let store = McpCommandStore()
        try await connect(store, connectionId: 1, clientId: "app-a", name: "A")
        try await connect(store, connectionId: 2, clientId: "app-b", name: "B")
        let marker = await store.lastMessageId

        async let waited = store.awaitCommand(
            ofType: "state.action.complete", clientId: "app-b",
            afterMessageId: marker, timeout: .milliseconds(400)
        )
        try await Task.sleep(for: .milliseconds(50))
        // The wrong client answers first — must not satisfy the wait.
        await store.ingest(.command(
            connectionId: 1,
            command: ReactotronCommand(type: "state.action.complete", payload: .null),
            frameBytes: 10
        ))
        try await Task.sleep(for: .milliseconds(50))
        await store.ingest(.command(
            connectionId: 2,
            command: ReactotronCommand(type: "state.action.complete", payload: .null),
            frameBytes: 10
        ))
        let result = try #require(await waited)
        #expect(result.clientId == "app-b")
    }
}
