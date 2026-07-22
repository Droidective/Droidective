import ADBKit
import Foundation

/// A command as retained by the MCP buffer: the raw wire command plus the
/// server-enriched fields upstream's `Command` carries (`messageId` assigned
/// monotonically here, `clientId` resolved from the connection's handshake).
public struct McpBufferedCommand: Sendable, Equatable {
    public let messageId: Int
    public let connectionId: Int
    public let clientId: String?
    public let command: ReactotronCommand
    public let frameBytes: Int

    public init(
        messageId: Int, connectionId: Int, clientId: String?,
        command: ReactotronCommand, frameBytes: Int
    ) {
        self.messageId = messageId
        self.connectionId = connectionId
        self.clientId = clientId
        self.command = command
        self.frameBytes = frameBytes
    }
}

/// A connected app, derived from its `client.intro` (upstream reads
/// `server.connections`; this store derives the same list from events).
public struct McpClientRecord: Sendable, Equatable {
    public let connectionId: Int
    public let clientId: String
    public let intro: ReactotronCommand
    /// The app's `mcpRedaction` wishes from the intro payload, if any.
    public let redaction: McpRedactionConfig?

    public var name: String? { intro.payload?["name"]?.stringValue }
    public var platform: String? { intro.payload?["platform"]?.stringValue }
    public var platformVersion: String? { intro.payload?["platformVersion"]?.stringValue }
}

/// The MCP layer's own retention — upstream's `commandBuffer` beside the
/// relay, independent of the UI timeline (`clear_timeline` clears only this).
/// Fed by a `ReactotronServer` tap via `ingest`; everything else is reads.
///
/// Reliability posture: bounded by item count *and* bytes (upstream caps only
/// count), and request/response correlation is event-driven (upstream polls
/// every 100 ms) — `awaitCommand` resumes on ingest, with an `afterMessageId`
/// marker so a response can never be satisfied by a stale earlier command.
public actor McpCommandStore {
    private var buffer: [McpBufferedCommand] = []
    private var totalBytes = 0
    private var nextMessageId = 1

    private var clients: [McpClientRecord] = []
    /// clientId → latest `state.values.response` payload (the
    /// `reactotron://state/current` cache).
    private var latestStateByClient: [String: JSONValue] = [:]
    /// clientId → command name → registration payload
    /// (from `customCommand.register`/`unregister`).
    private var customCommandsByClient: [String: [String: JSONValue]] = [:]
    /// State paths currently subscribed via the MCP tools (mirrors upstream
    /// `server.subscriptions`, refreshed by `state.values.change`).
    private var subscriptionPaths: [String] = []

    private var listeningPort: UInt16?

    /// Server-side redaction posture, hot-updatable from Settings (upstream
    /// `updateRedactionConfig`). Lives here so tools/resources and the UI
    /// share one source of truth.
    private var redactionServerConfig: McpRedactionServerConfig = .standard

    private struct PendingWait {
        let type: String
        let clientId: String?
        let afterMessageId: Int
        let continuation: CheckedContinuation<McpBufferedCommand?, Never>
    }

    private var pendingWaits: [UUID: PendingWait] = [:]

    private let maxItems: Int
    private let maxBytes: Int

    public init(maxItems: Int = McpConstants.bufferSize, maxBytes: Int = McpConstants.maxBufferBytes) {
        self.maxItems = maxItems
        self.maxBytes = maxBytes
    }

    // MARK: - Ingest

    /// Feed one relay event in. The caller owns the task iterating the tap:
    /// `for await event in tap { await store.ingest(event) }`.
    public func ingest(_ event: ReactotronServer.Event) {
        switch event {
        case let .listening(port):
            listeningPort = port
        case let .connected(connectionId, clientId, intro, frameBytes):
            clients.removeAll { $0.connectionId == connectionId || $0.clientId == clientId }
            clients.append(McpClientRecord(
                connectionId: connectionId,
                clientId: clientId,
                intro: intro,
                redaction: McpRedactionConfig(json: intro.payload?["mcpRedaction"])
            ))
            append(command: intro, connectionId: connectionId, frameBytes: frameBytes)
        case let .command(connectionId, command, frameBytes):
            append(command: command, connectionId: connectionId, frameBytes: frameBytes)
        case let .disconnected(connectionId, _):
            if let dropped = clients.first(where: { $0.connectionId == connectionId }) {
                customCommandsByClient[dropped.clientId] = nil
            }
            clients.removeAll { $0.connectionId == connectionId }
        case .failed:
            listeningPort = nil
        }
    }

    private func append(command: ReactotronCommand, connectionId: Int, frameBytes: Int) {
        let clientId = clients.first { $0.connectionId == connectionId }?.clientId
        let buffered = McpBufferedCommand(
            messageId: nextMessageId,
            connectionId: connectionId,
            clientId: clientId,
            command: command,
            frameBytes: frameBytes
        )
        nextMessageId += 1
        buffer.append(buffered)
        totalBytes += frameBytes
        trim()
        deriveSideState(from: buffered)
        resolveWaits(with: buffered)
    }

    private func trim() {
        let drop = ReactotronTimeline.dropCount(
            sizes: buffer.lazy.map(\.frameBytes),
            count: buffer.count,
            totalBytes: totalBytes,
            maxCount: maxItems,
            maxBytes: maxBytes
        )
        guard drop > 0 else { return }
        for dropped in buffer.prefix(drop) { totalBytes -= dropped.frameBytes }
        buffer.removeFirst(drop)
    }

    private func deriveSideState(from buffered: McpBufferedCommand) {
        let command = buffered.command
        switch command.commandType {
        case .stateValuesResponse:
            latestStateByClient[buffered.clientId ?? ""] = command.payload ?? .null
        case .stateValuesChange:
            // Mirror upstream: the change event names the currently
            // subscribed paths.
            if let changes = command.payload?["changes"]?.arrayValue {
                subscriptionPaths = changes.compactMap { $0["path"]?.stringValue }
            }
        case .customCommandRegister:
            guard let clientId = buffered.clientId,
                  let name = command.payload?["command"]?.stringValue else { break }
            customCommandsByClient[clientId, default: [:]][name] = command.payload ?? .null
        case .customCommandUnregister:
            guard let clientId = buffered.clientId,
                  let name = command.payload?["command"]?.stringValue else { break }
            customCommandsByClient[clientId]?[name] = nil
        default:
            break
        }
    }

    // MARK: - Reads

    public var redactionConfig: McpRedactionServerConfig { redactionServerConfig }

    public func setRedactionConfig(_ config: McpRedactionServerConfig) {
        redactionServerConfig = config
    }

    public var isListening: Bool { listeningPort != nil }
    public var port: UInt16? { listeningPort }
    public var connectedClients: [McpClientRecord] { clients }
    public var lastMessageId: Int { nextMessageId - 1 }
    public var bufferedCount: Int { buffer.count }
    public var subscriptions: [String] { subscriptionPaths }

    /// Buffered commands, oldest first, optionally filtered.
    public func commands(ofType type: String? = nil, clientId: String? = nil) -> [McpBufferedCommand] {
        buffer.filter { buffered in
            (type == nil || buffered.command.type == type)
                && (clientId == nil || buffered.clientId == clientId)
        }
    }

    /// Distinct command types currently in the buffer (drives the
    /// `reactotron://timeline/{type}` template's completion).
    public func bufferedTypes() -> [String] {
        var seen = Set<String>()
        return buffer.compactMap { seen.insert($0.command.type).inserted ? $0.command.type : nil }
    }

    /// Latest cached `state.values.response` payload for a client (or the
    /// sole/anonymous client when nil).
    public func latestState(clientId: String?) -> JSONValue? {
        if let clientId { return latestStateByClient[clientId] }
        if clients.count == 1, let sole = clients.first {
            return latestStateByClient[sole.clientId]
        }
        return latestStateByClient[""]
    }

    /// Registered custom commands for a client, registration order not
    /// guaranteed (upstream returns a Map's values).
    public func customCommands(clientId: String) -> [JSONValue] {
        Array((customCommandsByClient[clientId] ?? [:]).values)
    }

    /// Empty the MCP buffer (the UI timeline is untouched — upstream parity).
    public func clear() {
        buffer.removeAll()
        totalBytes = 0
    }

    /// Forget all connected clients — called when the relay is torn down,
    /// which cancels sockets without per-connection disconnect events, so
    /// agents would otherwise see ghost apps.
    public func clearClients() {
        clients.removeAll()
        customCommandsByClient.removeAll()
        listeningPort = nil
    }

    /// Replace the subscribed-paths list (kept when tools subscribe before
    /// any `state.values.change` confirms).
    public func setSubscriptions(_ paths: [String]) {
        subscriptionPaths = paths
    }

    // MARK: - Correlation

    /// Wait for the next command of `type` (optionally from `clientId`) whose
    /// `messageId` is greater than `afterMessageId`. Call with
    /// `afterMessageId: store.lastMessageId` captured *before* sending the
    /// request — a response already in flight still matches, a stale one
    /// can't. Returns nil on timeout. Every continuation resumes exactly once.
    public func awaitCommand(
        ofType type: String,
        clientId: String?,
        afterMessageId: Int,
        timeout: Duration = McpConstants.commandTimeout
    ) async -> McpBufferedCommand? {
        // Already arrived between send and await? Serve it from the buffer.
        if let existing = buffer.last(where: { buffered in
            buffered.messageId > afterMessageId
                && buffered.command.type == type
                && (clientId == nil || buffered.clientId == clientId)
        }) {
            return existing
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingWaits[id] = PendingWait(
                    type: type, clientId: clientId,
                    afterMessageId: afterMessageId, continuation: continuation
                )
                Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    await self?.expireWait(id)
                }
            }
        } onCancel: {
            Task { [weak self] in await self?.expireWait(id) }
        }
    }

    private func expireWait(_ id: UUID) {
        pendingWaits.removeValue(forKey: id)?.continuation.resume(returning: nil)
    }

    private func resolveWaits(with buffered: McpBufferedCommand) {
        for (id, wait) in pendingWaits where wait.type == buffered.command.type
            && buffered.messageId > wait.afterMessageId
            && (wait.clientId == nil || wait.clientId == buffered.clientId) {
            pendingWaits.removeValue(forKey: id)?.continuation.resume(returning: buffered)
        }
    }
}
