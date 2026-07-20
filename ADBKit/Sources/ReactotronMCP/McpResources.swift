import ADBKit
import Foundation
import MCP

/// The 8-resource contract of upstream `lib/reactotron-mcp/src/resources.ts`:
/// seven static resources plus the `reactotron://timeline/{type}` template
/// (listed per buffered type, completable). All reads snapshot the store,
/// redact per originating client, and serialize through the 800k truncation.
public struct McpResources: Sendable {
    let store: McpCommandStore

    public init(store: McpCommandStore) {
        self.store = store
    }

    // MARK: - Listing

    struct StaticResource {
        let name: String
        let uri: String
        let description: String
    }

    static let staticResources: [StaticResource] = [
        StaticResource(
            name: "timeline", uri: "reactotron://timeline",
            description: "Read this first to understand what's happening in the app. Returns "
                + "summarized debug events (type, timestamp, and a short preview) newest-first. "
                + "Payloads are stripped to keep the response small. Use the timeline_by_type "
                + "resource template to get full event data filtered by type "
                + "(e.g. reactotron://timeline/api.response)."
        ),
        StaticResource(
            name: "state", uri: "reactotron://state/current",
            description: "Latest cached Redux/MST state snapshot. May be stale — use the "
                + "request_state tool for a fresh snapshot. Returns no_state_received if the "
                + "app hasn't sent state yet."
        ),
        StaticResource(
            name: "network", uri: "reactotron://network/log",
            description: "Captured HTTP requests and responses. Each entry shows URL, method, "
                + "status, duration, headers, and previews of request/response bodies "
                + "(truncated to 500 chars). Use timeline_by_type with type 'api.response' "
                + "for full request/response data."
        ),
        StaticResource(
            name: "apps", uri: "reactotron://apps",
            description: "Apps currently connected to Reactotron with their clientId, name, "
                + "platform, and version. Read this to find the clientId needed for "
                + "multi-app filtering."
        ),
        StaticResource(
            name: "benchmarks", uri: "reactotron://benchmarks",
            description: "Performance benchmark results from connected apps, sorted by time. "
                + "Each has title, steps, and durations."
        ),
        StaticResource(
            name: "subscriptions", uri: "reactotron://state/subscriptions",
            description: "State subscription changes. Shows values at subscribed paths whenever "
                + "they change. Use the subscribe_state tool to add subscriptions."
        ),
        StaticResource(
            name: "asyncstorage", uri: "reactotron://asyncstorage",
            description: "AsyncStorage mutations captured from the app. Shows setItem, "
                + "removeItem, mergeItem, multiSet, multiRemove, multiMerge, and clear "
                + "operations with their keys and values."
        ),
    ]

    static let timelineTemplate = Resource.Template(
        uriTemplate: "reactotron://timeline/{type}",
        name: "timeline_by_type",
        description: "Timeline events filtered by command type, with full payloads. Available "
            + "types depend on what the app has sent (e.g. api.response, log, "
            + "state.values.response, benchmark.report). Read the timeline resource first "
            + "to see which types are present.",
        mimeType: "application/json"
    )

    /// `resources/list`: the static resources plus one entry per buffered
    /// command type (upstream's ResourceTemplate `list` callback).
    public func list() async -> [Resource] {
        var resources = Self.staticResources.map {
            Resource(name: $0.name, uri: $0.uri, description: $0.description,
                     mimeType: "application/json")
        }
        for type in await store.bufferedTypes() {
            resources.append(Resource(
                name: "timeline:\(type)",
                uri: "reactotron://timeline/\(type)",
                mimeType: "application/json"
            ))
        }
        return resources
    }

    public func templates() -> [Resource.Template] {
        [Self.timelineTemplate]
    }

    /// Completion values for the template's `type` argument.
    public func completeType(prefix: String) async -> [String] {
        await store.bufferedTypes().filter { $0.hasPrefix(prefix) }
    }

    // MARK: - Reading

    public func read(uri: String) async throws -> ReadResource.Result {
        switch uri {
        case "reactotron://timeline": return await timeline(uri: uri)
        case "reactotron://state/current": return await currentState(uri: uri)
        case "reactotron://network/log": return await networkLog(uri: uri)
        case "reactotron://apps": return await apps(uri: uri)
        case "reactotron://benchmarks": return await benchmarks(uri: uri)
        case "reactotron://state/subscriptions": return await stateSubscriptions(uri: uri)
        case "reactotron://asyncstorage": return await asyncStorage(uri: uri)
        default:
            if uri.hasPrefix("reactotron://timeline/") {
                let type = String(uri.dropFirst("reactotron://timeline/".count))
                return await timelineByType(uri: uri, type: type)
            }
            throw MCPError.invalidParams("Unknown resource: \(uri)")
        }
    }

    // MARK: - Shared shaping (ports of connectionMeta / filterByClient / json)

    private struct Snapshot {
        let clients: [McpClientRecord]
        var redactor: McpRedactor
    }

    private func snapshot() async -> Snapshot {
        let clients = await store.connectedClients
        return await Snapshot(
            clients: clients,
            redactor: McpRedactor(config: store.redactionConfig, clients: clients)
        )
    }

    private func appInfo(_ client: McpClientRecord) -> JSONValue {
        var info: [String: JSONValue] = [
            "id": .number(Double(client.connectionId)),
            "clientId": .string(client.clientId),
        ]
        if let name = client.name { info["name"] = .string(name) }
        if let platform = client.platform { info["platform"] = .string(platform) }
        if let version = client.platformVersion { info["platformVersion"] = .string(version) }
        return .object(info)
    }

    private func connectionMeta(_ clients: [McpClientRecord]) -> JSONValue {
        if clients.isEmpty {
            return .object([
                "connection": .string("no_apps_connected"),
                "hint": .string("No apps are connected to Reactotron. Start your React Native / "
                    + "React app with Reactotron configured."),
            ])
        }
        if clients.count == 1 {
            let sole = clients[0]
            return .object([
                "connection": .string("single_app"),
                "app": appInfo(sole),
                "hint": .string("Connected to \(sole.name ?? "?") (\(sole.platform ?? "?")). "
                    + "All data is from this app."),
            ])
        }
        return .object([
            "connection": .string("multiple_apps"),
            "apps": .array(clients.map(appInfo)),
            "hint": .string("Multiple apps are connected. If the user hasn't specified which "
                + "app, ask them. Then pass clientId to filter data. Check the workspace's "
                + "package.json name to see if it matches one of these app names."),
        ])
    }

    /// Single connected app ⇒ scope to it; multiple ⇒ aggregate all.
    private func filterByClient(
        _ commands: [McpBufferedCommand], clients: [McpClientRecord]
    ) -> [McpBufferedCommand] {
        guard clients.count == 1, let sole = clients.first else { return commands }
        return commands.filter { $0.clientId == sole.clientId }
    }

    private func fullCommand(_ buffered: McpBufferedCommand) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string(buffered.command.type),
            "messageId": .number(Double(buffered.messageId)),
            "important": .bool(buffered.command.isImportant),
        ]
        if let payload = buffered.command.payload { object["payload"] = payload }
        if let date = buffered.command.date { object["date"] = .string(date) }
        if let deltaTime = buffered.command.deltaTime { object["deltaTime"] = .number(deltaTime) }
        if let clientId = buffered.clientId { object["clientId"] = .string(clientId) }
        return .object(object)
    }

    private func jsonContent(uri: String, _ data: JSONValue, guidance: String? = nil) -> ReadResource.Result {
        ReadResource.Result(contents: [.text(
            McpSerialization.safeSerialize(data, guidance: guidance),
            uri: uri,
            mimeType: "application/json"
        )])
    }

    // MARK: - The resources

    private func timeline(uri: String) async -> ReadResource.Result {
        var snapshot = await snapshot()
        let events = filterByClient(await store.commands(), clients: snapshot.clients)
        let summarized = events.reversed().map { buffered in
            snapshot.redactor.redact(
                McpSerialization.summarizeCommand(buffered), clientId: buffered.clientId)
        }
        return jsonContent(
            uri: uri,
            .object([
                "_meta": connectionMeta(snapshot.clients),
                "eventCount": .number(Double(events.count)),
                "events": .array(Array(summarized)),
            ]),
            guidance: "Events are summarized. Use the timeline_by_type resource "
                + "(e.g. reactotron://timeline/api.response) to get full payloads for a "
                + "specific event type."
        )
    }

    private func timelineByType(uri: String, type: String) async -> ReadResource.Result {
        var snapshot = await snapshot()
        let events = filterByClient(await store.commands(ofType: type), clients: snapshot.clients)
        let redacted = events.reversed().map { buffered in
            snapshot.redactor.redact(fullCommand(buffered), clientId: buffered.clientId)
        }
        return jsonContent(
            uri: uri,
            .object([
                "_meta": connectionMeta(snapshot.clients),
                "type": .string(type),
                "eventCount": .number(Double(events.count)),
                "events": .array(Array(redacted)),
            ]),
            guidance: "Too many \(type) events to return in full. Try clear_timeline to "
                + "reset, then reproduce the issue to capture fewer events."
        )
    }

    private func currentState(uri: String) async -> ReadResource.Result {
        var snapshot = await snapshot()
        let stateResponses = filterByClient(
            await store.commands(ofType: "state.values.response"), clients: snapshot.clients)
        let latest = stateResponses.last
        let stateValue = latest?.command.payload?["value"] ?? .object([
            "status": .string("no_state_received"),
            "message": .string("No state snapshot received yet. Use the request_state tool "
                + "to request one."),
        ])
        // payload.path anchors state-path patterns when the cached snapshot
        // is a subtree (from a prior request_state with a path).
        let statePath = latest?.command.payload?["path"]?.stringValue ?? ""
        let redacted = snapshot.redactor.redactState(
            stateValue, clientId: latest?.clientId, statePath: statePath)
        return jsonContent(
            uri: uri,
            .object(["_meta": connectionMeta(snapshot.clients), "state": redacted]),
            guidance: "State is too large. Use the request_state tool with a path like "
                + "'user.profile' to fetch a specific slice. Use request_state_keys to "
                + "explore the state shape first."
        )
    }

    private func networkLog(uri: String) async -> ReadResource.Result {
        var snapshot = await snapshot()
        let requests = filterByClient(
            await store.commands(ofType: "api.response"), clients: snapshot.clients)
        let entries = requests.map { buffered in
            snapshot.redactor.redact(
                McpSerialization.summarizeNetworkEntry(buffered), clientId: buffered.clientId)
        }
        return jsonContent(
            uri: uri,
            .object(["_meta": connectionMeta(snapshot.clients), "entries": .array(entries)]),
            guidance: "Network log is too large. Use timeline_by_type with type "
                + "'api.response' for full data, or clear_timeline to reset and capture "
                + "fewer events."
        )
    }

    private func apps(uri: String) async -> ReadResource.Result {
        let clients = await store.connectedClients
        return jsonContent(uri: uri, .object([
            "_meta": connectionMeta(clients),
            "apps": .array(clients.map(appInfo)),
        ]))
    }

    private func benchmarks(uri: String) async -> ReadResource.Result {
        var snapshot = await snapshot()
        let reports = filterByClient(
            await store.commands(ofType: "benchmark.report"), clients: snapshot.clients)
        let entries = reports.map { buffered in
            var merged: [String: JSONValue] = buffered.command.payload?.objectValue ?? [:]
            if let date = buffered.command.date { merged["date"] = .string(date) }
            if let clientId = buffered.clientId { merged["clientId"] = .string(clientId) }
            return snapshot.redactor.redact(.object(merged), clientId: buffered.clientId)
        }
        return jsonContent(uri: uri, .object([
            "_meta": connectionMeta(snapshot.clients),
            "benchmarks": .array(entries),
        ]))
    }

    private func stateSubscriptions(uri: String) async -> ReadResource.Result {
        var snapshot = await snapshot()
        let changes = filterByClient(
            await store.commands(ofType: "state.values.change"), clients: snapshot.clients)
        let entries = changes.map { buffered in
            var merged: [String: JSONValue] = buffered.command.payload?.objectValue ?? [:]
            if let date = buffered.command.date { merged["date"] = .string(date) }
            if let clientId = buffered.clientId { merged["clientId"] = .string(clientId) }
            return snapshot.redactor.redact(.object(merged), clientId: buffered.clientId)
        }
        let active = await store.subscriptions
        return jsonContent(
            uri: uri,
            .object([
                "_meta": connectionMeta(snapshot.clients),
                "activeSubscriptions": .array(active.map(JSONValue.string)),
                "changes": .array(entries),
            ]),
            guidance: "Subscription changes are too large. Consider unsubscribing from paths "
                + "with large values, or use request_state with a specific path instead."
        )
    }

    private func asyncStorage(uri: String) async -> ReadResource.Result {
        var snapshot = await snapshot()
        let mutations = filterByClient(
            await store.commands(ofType: "asyncStorage.mutation"), clients: snapshot.clients)
        let entries = mutations.map { buffered -> JSONValue in
            var entry: [String: JSONValue] = [:]
            if let date = buffered.command.date { entry["date"] = .string(date) }
            if let clientId = buffered.clientId { entry["clientId"] = .string(clientId) }
            entry["action"] = buffered.command.payload?["action"] ?? .null
            entry["data"] = snapshot.redactor.redactAsyncStorage(
                buffered.command.payload?["data"] ?? .null, clientId: buffered.clientId)
            return .object(entry)
        }
        return jsonContent(
            uri: uri,
            .object(["_meta": connectionMeta(snapshot.clients), "mutations": .array(entries)]),
            guidance: "AsyncStorage mutations are too large. Try clear_timeline to reset, "
                + "then reproduce the specific interaction you want to inspect."
        )
    }
}
