// The Reactotron listener rides Network.framework's WebSocket stack, so it's
// Apple-only for now; a portable host would re-implement the listener (the
// protocol layer next door is already pure Swift).
#if canImport(Network)
import Foundation
import Network
import os

/// A Reactotron-compatible WebSocket server. The RN app (running
/// `reactotron-react-native`) is the client; this is the server it connects to
/// on port 9090. Speaks Reactotron's JSON-over-WebSocket protocol from Swift.
///
/// This is the inbound mirror of `MirrorTransport`: where that opens an outbound
/// `NWConnection`, this runs an `NWListener` with `NWProtocolWebSocket` and
/// accepts client sockets. The Swift-6 mechanics are the same — box the
/// non-`Sendable` `NWConnection` to cross into the framework's `@Sendable`
/// callbacks, run everything on one serial queue, and hop back onto the actor to
/// touch state.
public actor ReactotronServer {
    public enum ServerError: Error, Sendable, LocalizedError {
        case invalidPort(UInt16)
        case startFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .invalidPort(port): "Invalid port \(port)."
            case let .startFailed(detail): "Reactotron server failed to start: \(detail)"
            }
        }
    }

    /// Why a client connection ended, carried on `.disconnected` so the UI can
    /// say more than a yellow dot. A clean close with `goingAway` (WS 1001)
    /// from an Android client is OkHttp bailing out after its outgoing queue
    /// passed 16 MiB — the app produced events faster than the transport could
    /// drain them (huge console.log payloads, typically).
    public enum DisconnectReason: Sendable, Equatable {
        case clientClosed(goingAway: Bool)
        case transportError(String)
    }

    /// The disconnect reason for a client-sent WS close frame.
    public static func closeReason(_ code: NWProtocolWebSocket.CloseCode) -> DisconnectReason {
        .clientClosed(goingAway: code == .protocolCode(.goingAway))
    }

    /// A readable transport-error description. An app that is killed, crashes,
    /// or loses its adb tunnel drops the TCP stream with no close frame, which
    /// Network.framework reports as raw POSIX jargon ("No message available on
    /// STREAM") — say what actually happened instead. The raw error still goes
    /// to the unified log at the call sites.
    public static func describeTransportError(_ error: NWError) -> String {
        if case let .posix(code) = error, code == .ENODATA || code == .ECONNRESET {
            return "the connection dropped without a goodbye — the app was killed, "
                + "crashed, or the device disconnected"
        }
        return "\(error)"
    }

    /// Events surfaced to the UI as the server runs. `frameBytes` is the wire
    /// size of the frame a command was decoded from, so the timeline can keep
    /// its retained payloads within a byte budget.
    public enum Event: Sendable {
        case listening(port: UInt16)
        /// `clientId` is the resolved Reactotron client id — the one from the
        /// intro payload, or the server-generated id sent back via
        /// `setClientId` when the client connected without one.
        case connected(connectionId: Int, clientId: String, intro: ReactotronCommand, frameBytes: Int)
        case command(connectionId: Int, command: ReactotronCommand, frameBytes: Int)
        /// `reason` is nil for teardown-driven drops (stop, listener death).
        case disconnected(connectionId: Int, reason: DisconnectReason?)
        case failed(reason: String, portInUse: Bool)
    }

    /// `NWConnection` isn't `Sendable`; it's only touched on the serial queue or
    /// while owned by this actor, so box it to cross into `@Sendable` callbacks.
    struct ConnectionBox: @unchecked Sendable {
        let connection: NWConnection
    }

    private static let queue = DispatchQueue(label: "com.rohindh.droidective.reactotron-server")
    /// Why a client dropped is invisible in the UI (the dot just goes yellow) —
    /// keep the transport's own words in the unified log for field diagnosis:
    /// `log show --predicate 'subsystem == "com.rohindh.droidective"'`.
    private static let log = Logger(subsystem: "com.rohindh.droidective", category: "reactotron-server")

    private let port: UInt16
    private let loopbackOnly: Bool
    private let pingInterval: Duration
    private var listener: NWListener?
    private var connections: [Int: ConnectionBox] = [:]
    /// Per-connection frame feeds — the ordered pipeline each socket's raw
    /// frames ride to the actor (see `accept`). Finished when the connection
    /// drops so its consumer drains what already arrived, then ends.
    private var frameFeeds: [Int: AsyncStream<Data>.Continuation] = [:]
    /// The Reactotron clientId of each handshaken connection — an app reload
    /// reconnects with the same clientId, which is how the stale socket is
    /// recognized and dropped.
    private var clientIds: [Int: String] = [:]
    private var nextConnectionId = 1
    private var continuation: AsyncStream<Event>.Continuation?
    /// Additive observers of the same events the primary stream carries (the
    /// MCP layer holds one). Keyed so a tap whose consumer went away can be
    /// removed without touching the others.
    private var taps: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var pingTask: Task<Void, Never>?

    /// - Parameters:
    ///   - loopbackOnly: When true the server is reachable only through
    ///     localhost (`adb reverse`, emulators, iOS Simulators). When false it
    ///     accepts connections from the local network too — what the official
    ///     Reactotron desktop app does, and what a device whose Metro bundle
    ///     was served over Wi-Fi/LAN needs (its client dials the Mac's LAN IP).
    ///   - pingInterval: Cadence of the WebSocket-level keepalive pings
    ///     (mirrors reactotron-core-server's 30s ping), so a half-dead socket
    ///     surfaces as a transport error instead of lingering "connected".
    public init(
        port: UInt16 = 9090,
        loopbackOnly: Bool = true,
        pingInterval: Duration = .seconds(30)
    ) {
        self.port = port
        self.loopbackOnly = loopbackOnly
        self.pingInterval = pingInterval
    }

    /// The port the listener actually bound to (useful when constructed with
    /// port 0 to get an OS-assigned port, e.g. in tests). Nil until ready.
    public var boundPort: UInt16? {
        listener?.port?.rawValue
    }

    /// Start listening. The stream finishes when `stop()` is called or the
    /// listener fails. Restarting stops any previous listener first.
    public func start() throws -> AsyncStream<Event> {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort(port)
        }

        let parameters = NWParameters.tcp
        if loopbackOnly {
            // Loopback covers `adb reverse` tunnels, Android emulators
            // (10.0.2.2 lands on the host's loopback), and iOS Simulators —
            // while keeping the unauthenticated debug server off the LAN.
            parameters.requiredInterfaceType = .loopback
        }
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        // Explicit, generous cap instead of the framework default: Android's
        // RN WebSocket (OkHttp) queues up to 16 MiB outbound, so a single
        // api.response/image frame can approach that — a too-small receive
        // limit would fail the whole connection, not just the frame.
        webSocket.maximumMessageSize = 64 * 1024 * 1024
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            throw ServerError.startFailed("\(error)")
        }
        self.listener = listener

        // Bounded so a chatty client can't queue an unbounded backlog of
        // full-payload events while the consumer (the main actor) is busy —
        // under heavy backpressure the oldest events drop instead.
        let (stream, continuation) = AsyncStream.makeStream(
            of: Event.self, bufferingPolicy: .bufferingNewest(512))
        self.continuation = continuation

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { await self.listenerBecameReady() }
            case let .failed(error):
                Task { await self.failListener(error) }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            let box = ConnectionBox(connection: connection)
            Task { await self.accept(box) }
        }
        listener.start(queue: Self.queue)
        return stream
    }

    /// An additional, independent stream of the same events `start()` delivers.
    /// Registering a tap never affects the primary stream, and a tap survives
    /// `stop()`/`start()` cycles — it ends when its consumer stops iterating.
    /// Buffering matches the primary stream so a slow tap drops its own oldest
    /// events instead of back-pressuring the server.
    public func tap() -> AsyncStream<Event> {
        let id = UUID()
        let (stream, tapContinuation) = AsyncStream.makeStream(
            of: Event.self, bufferingPolicy: .bufferingNewest(512))
        taps[id] = tapContinuation
        tapContinuation.onTermination = { [weak self] _ in
            Task { await self?.removeTap(id) }
        }
        return stream
    }

    private func removeTap(_ id: UUID) {
        taps[id] = nil
    }

    /// Deliver an event to the primary stream and every tap.
    private func emit(_ event: Event) {
        continuation?.yield(event)
        for tapContinuation in taps.values {
            tapContinuation.yield(event)
        }
    }

    /// Tear down the listener and all client sockets. Safe to call repeatedly.
    /// Taps deliberately survive — `start()` calls this to restart, and a tap
    /// consumer (the MCP layer) must keep receiving across restarts.
    public func stop() {
        pingTask?.cancel()
        pingTask = nil
        for box in connections.values {
            box.connection.cancel()
        }
        connections.removeAll()
        for feed in frameFeeds.values { feed.finish() }
        frameFeeds.removeAll()
        clientIds.removeAll()
        listener?.cancel()
        listener = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Listener lifecycle

    private func listenerBecameReady() {
        guard let port = listener?.port?.rawValue else { return }
        emit(.listening(port: port))
        startPinging()
    }

    /// WebSocket-level keepalive, like reactotron-core-server's 30s ping. The
    /// client's socket stack answers pongs automatically; the point is that a
    /// write to a half-dead socket (device off Wi-Fi, adb gone) fails and
    /// surfaces through the connection's state handler as a real disconnect
    /// instead of a forever-green dot.
    private func startPinging() {
        pingTask?.cancel()
        pingTask = Task { [weak self, pingInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pingInterval)
                guard !Task.isCancelled else { break }
                await self?.pingAll()
            }
        }
    }

    private func pingAll() {
        for box in connections.values {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
            let context = NWConnection.ContentContext(identifier: "ping", metadata: [metadata])
            box.connection.send(
                content: Data(), contentContext: context, isComplete: true,
                completion: .contentProcessed { _ in }
            )
        }
    }

    private func failListener(_ error: NWError) {
        var portInUse = false
        if case let .posix(code) = error, code == .EADDRINUSE {
            portInUse = true
        }
        emit(.failed(reason: "\(error)", portInUse: portInUse))
        stop()
    }

    // MARK: - Connections

    private func accept(_ box: ConnectionBox) {
        let id = nextConnectionId
        nextConnectionId += 1
        connections[id] = box

        // Frames reach the actor through one stream and one consumer per
        // connection, not a Task per frame: independent tasks have no FIFO
        // guarantee on actor entry, so a burst could land timeline rows out
        // of wire order. The socket callbacks run on a serial queue, so the
        // yields — and therefore the events — keep the order the app sent.
        let (frames, feed) = AsyncStream.makeStream(
            of: Data.self, bufferingPolicy: .unbounded)
        frameFeeds[id] = feed
        Task { [weak self] in
            for await data in frames {
                await self?.handleFrame(connectionId: id, data: data)
            }
        }

        box.connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case let .failed(error):
                Self.log.error("connection #\(id) failed: \(error, privacy: .public)")
                Task {
                    await self?.dropConnection(
                        id, reason: .transportError(Self.describeTransportError(error)))
                }
            case .cancelled:
                Self.log.notice("connection #\(id) cancelled")
                Task { await self?.dropConnection(id, reason: nil) }
            default:
                break
            }
        }
        box.connection.start(queue: Self.queue)
        Self.receiveLoop(box, id: id, server: self, feed: feed)
    }

    /// Drops the connection and reports why. Racing drop paths (close frame,
    /// then the socket error, then cancelled) all land here; the first wins,
    /// which is the most specific one — the close frame beats its aftermath.
    private func dropConnection(_ id: Int, reason: DisconnectReason?) {
        guard let box = connections.removeValue(forKey: id) else { return }
        clientIds[id] = nil
        // Finish (not cancel) the frame pipeline: frames that arrived before
        // the close still drain into the timeline, then the consumer ends.
        frameFeeds.removeValue(forKey: id)?.finish()
        box.connection.cancel()
        emit(.disconnected(connectionId: id, reason: reason))
    }

    /// Recursive receive loop, off the actor (like `MirrorTransport.receiveLoop`).
    /// Each WebSocket text frame is one Reactotron command; yield it into the
    /// connection's ordered frame feed (see `accept`), then continue receiving.
    private nonisolated static func receiveLoop(
        _ box: ConnectionBox, id: Int, server: ReactotronServer,
        feed: AsyncStream<Data>.Continuation
    ) {
        box.connection.receiveMessage { content, context, _, error in
            if let context,
               let metadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition)
               as? NWProtocolWebSocket.Metadata {
                switch metadata.opcode {
                case .text:
                    if let content {
                        NetworkTrafficMeter.shared.recordReceived(content.count)
                        feed.yield(content)
                    }
                case .close:
                    log.notice("connection #\(id): client sent WS close, code=\(String(describing: metadata.closeCode), privacy: .public)")
                    let reason = closeReason(metadata.closeCode)
                    Task { await server.dropConnection(id, reason: reason) }
                    return
                default:
                    break
                }
            }
            if let error {
                log.error("connection #\(id) receive failed: \(error, privacy: .public)")
                Task {
                    await server.dropConnection(
                        id, reason: .transportError(describeTransportError(error)))
                }
                return
            }
            receiveLoop(box, id: id, server: server, feed: feed)
        }
    }

    /// Internal (not private) so tests can drive the drained-frame paths
    /// deterministically — racing a real socket against `dropConnection` isn't
    /// reliably reproducible.
    func handleFrame(connectionId id: Int, data: Data) {
        guard let command = try? ReactotronCommand.decode(data) else {
            let raw = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            let preview = String(raw.prefix(300))
            emit(.command(
                connectionId: id,
                command: ReactotronCommand(type: "(undecodable)", payload: .string(preview)),
                frameBytes: preview.utf8.count
            ))
            return
        }
        if command.commandType == .clientIntro {
            // A `client.intro` draining after `dropConnection` must not
            // resurrect a ghost client: the connection is gone, so there is
            // no handshake to complete and no future `.disconnected` to pair
            // with a `.connected`. Ordinary commands still drain below —
            // they're timeline data, not client state.
            guard connections[id] != nil else { return }
            let clientId = completeHandshake(connectionId: id, intro: command)
            emit(.connected(
                connectionId: id, clientId: clientId, intro: command, frameBytes: data.count))
        } else {
            emit(.command(connectionId: id, command: command, frameBytes: data.count))
        }
    }

    // MARK: - Handshake

    /// On `client.intro`: assign a clientId if the client has none, drop any
    /// stale connection that shares the clientId (an app reload reconnects
    /// before its old socket dies), then send the (empty) subscription list to
    /// complete the handshake — exactly what `reactotron-core-server` does.
    /// Returns the resolved clientId, carried on the `.connected` event.
    private func completeHandshake(connectionId id: Int, intro: ReactotronCommand) -> String {
        guard let box = connections[id] else { return "connection-\(id)" }
        var clientId = intro.payload?["clientId"]?.stringValue
        if clientId == nil || clientId?.isEmpty == true {
            let generated = UUID().uuidString
            send(type: "setClientId", payload: .string(generated), to: box)
            clientId = generated
        }
        if let clientId {
            dropStaleTwins(of: clientId, keeping: id)
            clientIds[id] = clientId
        }
        send(type: "state.values.subscribe", payload: .object(["paths": .array([])]), to: box)
        return clientId ?? "connection-\(id)"
    }

    /// Forget other connections carrying the same clientId — reported with a
    /// nil reason (no timeline notice: a reload replacing itself isn't news,
    /// matching the official server, which suppresses the disconnect). The
    /// stale socket is closed after a short grace, again like the original.
    private func dropStaleTwins(of clientId: String, keeping id: Int) {
        for (staleId, staleClientId) in clientIds
            where staleClientId == clientId && staleId != id {
            clientIds[staleId] = nil
            frameFeeds.removeValue(forKey: staleId)?.finish()
            guard let stale = connections.removeValue(forKey: staleId) else { continue }
            emit(.disconnected(connectionId: staleId, reason: nil))
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                stale.connection.cancel()
            }
        }
    }

    // MARK: - Server → client

    /// Send a frame to one connection (no-op if it has gone away).
    public func send(type: String, payload: JSONValue, toConnection id: Int) {
        guard let box = connections[id] else { return }
        send(type: type, payload: payload, to: box)
    }

    /// Send a frame to every connected client.
    public func broadcast(type: String, payload: JSONValue) {
        for box in connections.values {
            send(type: type, payload: payload, to: box)
        }
    }

    /// Send one server→client frame: `{ type, payload }` as a WebSocket text frame.
    private func send(type: String, payload: JSONValue, to box: ConnectionBox) {
        let envelope = JSONValue.object(["type": .string(type), "payload": payload])
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        box.connection.send(
            content: data, contentContext: context, isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }
}
#endif
