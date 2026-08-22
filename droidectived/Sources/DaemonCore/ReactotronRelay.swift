import ADBKit
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

/// The Reactotron relay: a WebSocket server React Native apps connect *to*.
///
/// **Why this is in the daemon and not ADBKit.** The Mac's relay is
/// `ReactotronServer`, an `NWListener` over `NWProtocolWebSocket` — Apple-only,
/// and gated as such. The portable answer is NIO, which the daemon already
/// links for its own stream socket; putting it in ADBKit instead would drag
/// swift-nio into that package's graph, and ADBKit staying nio-free is exactly
/// what lets `swift test` run on Windows. So the *listener* is here and
/// everything above it — `ReactotronCommand`, the command types, the timeline —
/// is the portable ADBKit code both hosts already share.
///
/// **No authentication, deliberately.** This speaks Reactotron's protocol, and
/// a Reactotron client sends no token: upstream's app does not ask for one, and
/// requiring one would mean no existing app could connect. The exposure is
/// bounded by the bind address instead — see `loopbackOnly`.
public actor ReactotronRelay {
    /// Upstream's port. Changing it means changing it in every app's
    /// `reactotron-react-native` config too, which is why it is the default
    /// rather than a preference.
    public static let defaultPort = 9090

    public enum RelayError: Error, CustomStringConvertible {
        case portInUse(Int)
        case bindFailed(String)

        public var description: String {
            switch self {
            case .portInUse(let port):
                return "Port \(port) is already in use — another Reactotron is probably running."
            case .bindFailed(let detail):
                return "Could not start the Reactotron relay: \(detail)"
            }
        }
    }

    /// What the relay saw. Mirrors `ReactotronServer.Event` in shape but not in
    /// type: this one is the daemon's own, because it has to reach a client as
    /// JSON and the Mac's enum is not a wire format.
    public enum Event: Sendable {
        case listening(port: Int)
        /// A client completed its `client.intro` handshake.
        case connected(connection: Int, clientId: String?, command: ReactotronCommand)
        case command(connection: Int, command: ReactotronCommand)
        case disconnected(connection: Int, reason: String?)
    }

    private let port: Int
    /// False also accepts clients from the local network, which is what the
    /// official Reactotron app does — and it is required when the app loaded its
    /// bundle over Wi-Fi, because the client dials the bundle's host rather than
    /// localhost. True is the safer default: USB devices reach it through
    /// `adb reverse`, and so do emulators.
    private let loopbackOnly: Bool
    /// Created on start and shut down on stop, rather than shared with the
    /// daemon's own listener. One thread is plenty for a relay whose traffic is
    /// one app's log lines, and owning it is what lets `stop()` actually release
    /// the port instead of leaving a group alive behind a closed channel.
    private var group: MultiThreadedEventLoopGroup?
    private var channel: (any Channel)?
    private var listeners: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var connections: [Int: any Channel] = [:]
    /// Ids allocated but since closed. Frames are gated on *this* rather than on
    /// `connections`, because registration is asynchronous while a client can
    /// send its intro in the same packet as the upgrade — gating on presence
    /// would drop the handshake and leave a connected client nobody hears about.
    private var closed: Set<Int> = []
    /// Which connections have introduced themselves, so a `client.intro` that
    /// arrives twice does not report a second client.
    private var introduced: Set<Int> = []

    public init(port: Int = ReactotronRelay.defaultPort, loopbackOnly: Bool = true) {
        self.port = port
        self.loopbackOnly = loopbackOnly
    }

    /// The port actually bound, which is the requested one unless it was 0.
    public var boundPort: Int? {
        channel?.localAddress?.port
    }

    public var isRunning: Bool { channel != nil }

    /// Starts listening. Idempotent: a second call while running is a no-op, so
    /// a UI that asks twice does not end up with two listeners fighting for the
    /// port.
    public func start() async throws {
        guard channel == nil else { return }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 32)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [weak self] channel in
                guard let self else {
                    return channel.eventLoop.makeSucceededFuture(())
                }
                return Self.configure(channel: channel, relay: self)
            }

        let host = loopbackOnly ? "127.0.0.1" : "0.0.0.0"
        do {
            channel = try await bootstrap.bind(host: host, port: port).get()
        } catch {
            // The one failure worth naming: another Reactotron — upstream's app,
            // or a second copy of this one — already has the port. "Address
            // already in use" is not something a UI can act on; "another
            // Reactotron is probably running" is.
            self.group = nil
            try? await group.shutdownGracefully()
            if let io = error as? IOError, io.errnoCode == EADDRINUSE {
                throw RelayError.portInUse(port)
            }
            throw RelayError.bindFailed("\(error)")
        }
        emit(.listening(port: boundPort ?? port))
    }

    /// An event stream. Several may be open at once — the timeline reads one and
    /// anything else observing reads another, the way `ReactotronServer.tap()`
    /// hands out an additive stream on the Mac.
    public func events() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        let id = UUID()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.dropListener(id) }
        }
        return stream
    }

    /// Stops listening and drops every client. Idempotent.
    public func stop() async {
        for (id, connection) in connections {
            closed.insert(id)
            try? await connection.close().get()
        }
        connections.removeAll()
        introduced.removeAll()
        let listening = channel
        channel = nil
        try? await listening?.close().get()
        let running = group
        group = nil
        try? await running?.shutdownGracefully()
        for continuation in listeners.values { continuation.finish() }
        listeners.removeAll()
    }

    // MARK: - the pipeline

    private nonisolated static func configure(
        channel: any Channel, relay: ReactotronRelay
    ) -> EventLoopFuture<Void> {
        // Reactotron's client library speaks plain WebSocket with no
        // subprotocol and no auth header, so the upgrade is unconditional. The
        // guard is the bind address, not the handshake.
        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, _ in
                channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { channel, _ in
                // The id is taken here, before any frame can arrive.
                let id = ReactotronRelay.ids.next()
                return channel.eventLoop.makeCompletedFuture {
                    let handler = RelayConnectionHandler(relay: relay, id: id, channel: channel)
                    try channel.pipeline.syncOperations.addHandler(handler)
                }
            }
        )
        return channel.pipeline.configureHTTPServerPipeline(
            withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in })
        )
    }

    /// The next connection id.
    ///
    /// Handed out *synchronously*, off the actor, so the handler has its id
    /// before the client can send anything. Going through the actor would make
    /// the id arrive after the first frame on a fast local connection.
    private nonisolated static let ids = Counter()

    fileprivate func register(_ id: Int, channel: any Channel) {
        guard !closed.contains(id) else { return }
        connections[id] = channel
    }

    fileprivate func drop(_ id: Int, reason: String?) {
        guard closed.insert(id).inserted else { return }
        connections[id] = nil
        introduced.remove(id)
        emit(.disconnected(connection: id, reason: reason))
    }

    /// One decoded frame.
    ///
    /// An undecodable frame is reported as a command of type `(undecodable)`
    /// carrying a preview rather than dropped, which is what the Mac does: a
    /// client sending malformed JSON is a bug someone needs to see, and silence
    /// makes it look like the relay is not receiving anything at all.
    fileprivate func receive(_ id: Int, text: String) {
        guard !closed.contains(id) else { return }
        guard let command = try? ReactotronCommand.decode(text) else {
            emit(.command(
                connection: id,
                command: ReactotronCommand(
                    type: "(undecodable)", payload: .string(String(text.prefix(300))))))
            return
        }
        guard command.commandType == .clientIntro else {
            emit(.command(connection: id, command: command))
            return
        }
        // A second intro on one connection is the same client saying hello
        // again; reporting it as a new connection would double the client list.
        guard introduced.insert(id).inserted else {
            emit(.command(connection: id, command: command))
            return
        }
        emit(.connected(connection: id, clientId: clientId(of: command), command: command))
    }

    /// The `clientId` an intro declares, if it declared one.
    private func clientId(of command: ReactotronCommand) -> String? {
        guard case .object(let fields) = command.payload,
              case .string(let id) = fields["clientId"]
        else { return nil }
        return id.isEmpty ? nil : id
    }

    private func dropListener(_ id: UUID) {
        listeners[id] = nil
    }

    private func emit(_ event: Event) {
        for continuation in listeners.values { continuation.yield(event) }
    }
}

/// One client's frames.
///
/// Reassembles continuations and reads `unmaskedData`, for the same reasons
/// `WebSocketHandler` does: every client-to-server frame is masked, and a client
/// may split a large command across frames. Getting either wrong fails silently
/// — the JSON never parses and the timeline simply stays empty.
///
/// Frames reach the actor through **one stream with one consumer**, not a `Task`
/// per frame. Independent tasks have no FIFO guarantee on actor entry, so a
/// burst would land timeline rows out of the order the app logged them — which
/// is the one thing a timeline must not do. The channel's callbacks are serial,
/// so the yields keep the wire order and the consumer preserves it.
private final class RelayConnectionHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let relay: ReactotronRelay
    private let id: Int
    private let frames: AsyncStream<String>.Continuation
    private let pump: Task<Void, Never>
    private var fragments = ""

    init(relay: ReactotronRelay, id: Int, channel: any Channel) {
        self.relay = relay
        self.id = id
        let (stream, continuation) = AsyncStream<String>.makeStream(
            of: String.self, bufferingPolicy: .unbounded)
        frames = continuation
        pump = Task {
            await relay.register(id, channel: channel)
            for await text in stream {
                await relay.receive(id, text: text)
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .connectionClose:
            end(reason: "client closed")
        case .ping:
            var pong = frame
            pong.opcode = .pong
            context.writeAndFlush(NIOAny(pong), promise: nil)
        case .text, .continuation:
            var payload = frame.unmaskedData
            fragments += payload.readString(length: payload.readableBytes) ?? ""
            guard frame.fin else { return }
            frames.yield(fragments)
            fragments = ""
        default:
            // Binary and the rest: ignored rather than fatal. A confused client
            // must not be able to kill the timeline it is feeding.
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        end(reason: nil)
        context.fireChannelInactive()
    }

    /// Finishes the frame stream rather than cancelling it, so frames that
    /// arrived before the close still reach the timeline — then reports the
    /// disconnect after them, in order.
    private func end(reason: String?) {
        frames.finish()
        let relay = self.relay
        let id = self.id
        let pump = self.pump
        Task {
            await pump.value
            await relay.drop(id, reason: reason)
        }
    }
}

/// A lock-protected counter, for ids that must be handed out off the actor.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
