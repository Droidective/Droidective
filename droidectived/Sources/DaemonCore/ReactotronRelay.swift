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
        case connected(connection: Int, clientId: String?, command: ReactotronCommand, bytes: Int)
        /// `bytes` is the frame's own size on the wire, which only the relay
        /// knows: a client reading decoded envelopes could only get it back by
        /// re-serializing the payload, and re-serializing every frame is the
        /// stall a streaming timeline is built to avoid. It travels so the
        /// timeline can bound itself by memory as well as by count — one
        /// base64 display image outweighs a thousand log lines.
        case command(connection: Int, command: ReactotronCommand, bytes: Int)
        /// `code` is the WebSocket close status, when the client sent a close
        /// frame carrying one. It matters because 1001 is not a generic
        /// goodbye: Android's WebSocket closes *itself* going-away once 16 MB
        /// are queued, so 1001 means the app produced events faster than the
        /// connection could drain them — a diagnosis with an actual fix (log
        /// ids, not whole objects), and one nothing else on the wire reveals.
        case disconnected(connection: Int, reason: String?, code: Int?)
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

    /// Where the relay is between idle and listening.
    ///
    /// An actor is not a lock across a suspension, and both transitions suspend:
    /// `start` awaits a bind, `stop` awaits a channel close and a graceful
    /// shutdown. So the two can interleave, and both orders were broken —
    /// a start landing mid-stop saw a nil channel, bound the same port, and got
    /// EADDRINUSE from a socket that was still open ("another Reactotron is
    /// probably running", with nothing else on the port); a stop landing
    /// mid-start shut down the event-loop group the bind was still waiting on,
    /// which never completes, wedging the relay for the life of the process.
    ///
    /// The sequence that provokes it is ordinary: closing a timeline tab and
    /// reopening it, or React's double-mount on the first open.
    private enum Phase {
        case idle
        case transitioning
        case running
    }

    private var phase: Phase = .idle
    /// Callers waiting for a transition to finish, resumed in `settle(into:)`.
    /// A list of continuations rather than a spin: the waiter has nothing to do
    /// until the socket is genuinely free or genuinely bound.
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(port: Int = ReactotronRelay.defaultPort, loopbackOnly: Bool = true) {
        self.port = port
        self.loopbackOnly = loopbackOnly
    }

    /// Suspends until no start or stop is in flight.
    private func quiesce() async {
        while phase == .transitioning {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    /// Ends a transition and wakes everyone who was waiting on it.
    private func settle(into next: Phase) {
        phase = next
        let pending = waiting
        waiting.removeAll()
        for continuation in pending { continuation.resume() }
    }

    /// The port actually bound, which is the requested one unless it was 0.
    public var boundPort: Int? {
        channel?.localAddress?.port
    }

    public var isRunning: Bool { channel != nil }

    /// Starts listening.
    ///
    /// Idempotent: a second call while running is a no-op, so a UI that asks
    /// twice does not end up with two listeners fighting for the port. A call
    /// arriving mid-stop waits for the socket to be released first rather than
    /// binding over it — see `Phase`.
    public func start() async throws {
        await quiesce()
        guard channel == nil else { return }
        phase = .transitioning
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
            channel = try await Self.bindRetryingAddressInUse(bootstrap, host: host, port: port)
        } catch {
            // The one failure worth naming: another Reactotron — upstream's app,
            // or a second copy of this one — already has the port. "Address
            // already in use" is not something a UI can act on; "another
            // Reactotron is probably running" is.
            self.group = nil
            try? await group.shutdownGracefully()
            settle(into: .idle)
            if let io = error as? IOError, io.errnoCode == EADDRINUSE {
                throw RelayError.portInUse(port)
            }
            throw RelayError.bindFailed("\(error)")
        }
        settle(into: .running)
        emit(.listening(port: boundPort ?? port))
    }

    /// How long a bind keeps retrying `EADDRINUSE` before reporting it.
    ///
    /// Short enough that a genuine holder — upstream's Reactotron app, a second
    /// copy of this one — is still reported promptly, long enough to outlast our
    /// own previous listener finishing its teardown.
    private static let rebindAttempts = 6
    private static let rebindDelay = Duration.milliseconds(40)

    /// Binds, retrying `EADDRINUSE` for a bounded window.
    ///
    /// `stop()` awaits the channel's `closeFuture` *and* the event-loop group's
    /// graceful shutdown, which are the strongest completion signals NIO offers,
    /// and it is still possible for a bind moments later to be refused. The
    /// window is between the last fd closing and the kernel releasing the
    /// listening socket, and no future can report the second one — `SO_REUSEADDR`
    /// does not cover it either, because that waives `TIME_WAIT`, not a socket
    /// still in `LISTEN`.
    ///
    /// So this is not a workaround for a teardown that returns early. It is the
    /// ordinary handling for acquiring a contended kernel resource: retry
    /// briefly, then report. `stoppingReleasesThePort` is what caught it —
    /// twice on CI, on the *second* bind of a port this process had just
    /// released, which is the case a foreign holder cannot explain.
    ///
    /// Only `EADDRINUSE` is retried. Every other bind failure is a fact that a
    /// second attempt cannot change, and retrying it would just delay the error.
    private static func bindRetryingAddressInUse(
        _ bootstrap: ServerBootstrap, host: String, port: Int
    ) async throws -> any Channel {
        for attempt in 1... {
            do {
                return try await bootstrap.bind(host: host, port: port).get()
            } catch let error as IOError where error.errnoCode == EADDRINUSE {
                guard attempt < rebindAttempts else { throw error }
                try? await Task.sleep(for: rebindDelay)
            }
        }
        // `1...` never terminates; the loop leaves via return or throw.
        throw RelayError.bindFailed("unreachable")
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

    /// Stops listening and drops every client.
    ///
    /// Idempotent, and it waits out a start rather than tearing down a relay
    /// that has not finished binding — shutting down the event-loop group a bind
    /// is still waiting on is a future that never completes.
    public func stop() async {
        await quiesce()
        phase = .transitioning
        for (id, connection) in connections {
            closed.insert(id)
            try? await connection.close().get()
        }
        connections.removeAll()
        introduced.removeAll()
        let listening = channel
        channel = nil
        if let listening {
            try? await listening.close().get()
            // Then wait for the channel to actually *be* closed.
            //
            // `close()`'s future completes when the close has been put through
            // the pipeline; `closeFuture` is the one that fires when the
            // channel is inactive and its socket released. Awaiting only the
            // first let `stop()` return with the listener still holding the
            // port, and a bind moments later was refused —
            // `stoppingReleasesThePort` caught it on CI three times, on a port
            // nothing else on the machine could have taken.
            //
            // Already-completed when the close was quick, so this costs
            // nothing in the ordinary case.
            try? await listening.closeFuture.get()
        }
        let running = group
        group = nil
        try? await running?.shutdownGracefully()
        for continuation in listeners.values { continuation.finish() }
        listeners.removeAll()
        settle(into: .idle)
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

    fileprivate func drop(_ id: Int, reason: String?, code: Int?) {
        guard closed.insert(id).inserted else { return }
        connections[id] = nil
        introduced.remove(id)
        emit(.disconnected(connection: id, reason: reason, code: code))
    }

    /// One decoded frame.
    ///
    /// An undecodable frame is reported as a command of type `(undecodable)`
    /// carrying a preview rather than dropped, which is what the Mac does: a
    /// client sending malformed JSON is a bug someone needs to see, and silence
    /// makes it look like the relay is not receiving anything at all.
    fileprivate func receive(_ id: Int, text: String) {
        guard !closed.contains(id) else { return }
        let bytes = text.utf8.count
        guard let command = try? ReactotronCommand.decode(text) else {
            emit(.command(
                connection: id,
                command: ReactotronCommand(
                    type: "(undecodable)", payload: .string(String(text.prefix(300)))),
                bytes: bytes))
            return
        }
        guard command.commandType == .clientIntro else {
            emit(.command(connection: id, command: command, bytes: bytes))
            return
        }
        // A second intro on one connection is the same client saying hello
        // again; reporting it as a new connection would double the client list.
        guard introduced.insert(id).inserted else {
            emit(.command(connection: id, command: command, bytes: bytes))
            return
        }
        emit(.connected(
            connection: id, clientId: clientId(of: command), command: command, bytes: bytes))
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
            end(reason: "client closed", code: Self.closeCode(frame))
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
        end(reason: nil, code: nil)
        context.fireChannelInactive()
    }

    /// A close frame's status code. RFC 6455 puts it in the first two bytes,
    /// big-endian, and makes it optional — a bare close frame carries none, and
    /// the code that matters here (1001) is always sent.
    private static func closeCode(_ frame: WebSocketFrame) -> Int? {
        var payload = frame.unmaskedData
        guard let code: UInt16 = payload.readInteger() else { return nil }
        return Int(code)
    }

    /// Finishes the frame stream rather than cancelling it, so frames that
    /// arrived before the close still reach the timeline — then reports the
    /// disconnect after them, in order.
    private func end(reason: String?, code: Int?) {
        frames.finish()
        let relay = self.relay
        let id = self.id
        let pump = self.pump
        Task {
            await pump.value
            await relay.drop(id, reason: reason, code: code)
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
