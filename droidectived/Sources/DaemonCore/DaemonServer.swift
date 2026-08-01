import ADBKit
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix

/// What a route needs from the rest of the app. A protocol so the socket tests
/// drive the real HTTP stack against a scripted device list instead of
/// requiring adb on the test host.
public protocol DaemonBackend: Sendable {
    func listDevices() async -> [Device]
}

/// `DeviceMonitor` in production.
public struct LiveBackend: DaemonBackend {
    private let monitor: DeviceMonitor
    public init(monitor: DeviceMonitor) { self.monitor = monitor }
    public func listDevices() async -> [Device] { await monitor.list(force: true) }
}

/// Loopback HTTP for the request/response half of the protocol.
///
/// Streams will ride a WebSocket on this same listener (topic-multiplexed, with
/// the decided drop-oldest policy); this slice is the request path only.
public actor DaemonServer {
    public struct Bound: Sendable {
        public let port: Int
    }

    private let backend: any DaemonBackend
    private let token: String
    private var group: MultiThreadedEventLoopGroup?
    private var channel: (any Channel)?

    public init(backend: any DaemonBackend, token: String) {
        self.backend = backend
        self.token = token
    }

    /// Binds 127.0.0.1 on `port` (0 → the OS picks) and starts serving.
    public func start(port: Int) async throws -> Bound {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let backend = self.backend
        let token = self.token
        // Captured by the handler so `Host` can be pinned to the live port,
        // which is only known after bind.
        let boundPort = NIOLockedValueBox(0)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 32)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMapThrowing {
                    try channel.pipeline.syncOperations.addHandler(
                        RequestHandler(backend: backend, token: token, port: boundPort))
                }
            }

        // Loopback only. Nothing reaches this from another host, by construction
        // rather than by firewall.
        let channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
        self.channel = channel
        let resolved = channel.localAddress?.port ?? port
        boundPort.withLockedValue { $0 = resolved }
        return Bound(port: resolved)
    }

    public func stop() async {
        try? await channel?.close().get()
        channel = nil
        try? await group?.shutdownGracefully()
        group = nil
    }
}

/// One request at a time per connection: collect the head, ignore the body
/// (every route takes its arguments in the path for this slice), answer.
private final class RequestHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let backend: any DaemonBackend
    private let token: String
    private let port: NIOLockedValueBox<Int>
    private var head: HTTPRequestHead?

    init(backend: any DaemonBackend, token: String, port: NIOLockedValueBox<Int>) {
        self.backend = backend
        self.token = token
        self.port = port
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            self.head = head
        case .body:
            break
        case .end:
            guard let head else { return }
            self.head = nil
            let loop = context.eventLoop
            let boxedContext = NIOLoopBound(context, eventLoop: loop)
            let port = self.port.withLockedValue { $0 }
            let backend = self.backend
            let token = self.token
            // The route is async; hop the answer back onto the event loop.
            Task { [self] in
                let (status, body) = await Self.respond(
                    head: head, port: port, token: token, backend: backend)
                loop.execute {
                    self.write(context: boxedContext.value, status: status, body: body)
                }
            }
        }
    }

    /// Pure-ish routing: guards, then the route. Split out so the socket tests
    /// and any future unit test exercise the same decision path.
    static func respond(
        head: HTTPRequestHead, port: Int, token: String, backend: any DaemonBackend
    ) async -> (HTTPResponseStatus, Data) {
        func encoded(_ body: some Encodable) -> Data {
            (try? DaemonProtocol.encode(body)) ?? Data("{}".utf8)
        }

        if let refusal = DaemonGuards.check(
            authorization: head.headers.first(name: "Authorization"),
            host: head.headers.first(name: "Host"),
            origin: head.headers.first(name: "Origin"),
            port: port, expectedToken: token
        ) {
            return (
                HTTPResponseStatus(statusCode: DaemonProtocol.status(for: refusal)),
                encoded(DaemonProtocol.errorBody(for: refusal))
            )
        }
        guard head.method == .POST else {
            return (.methodNotAllowed, encoded(DaemonProtocol.methodNotAllowed))
        }
        guard let route = DaemonProtocol.Route(rawValue: head.uri) else {
            return (.notFound, encoded(DaemonProtocol.notFound))
        }
        switch route {
        case .devicesList:
            let devices = await backend.listDevices()
            return (.ok, encoded(DaemonProtocol.DevicesResponse(devices: devices)))
        }
    }

    private func write(context: ChannelHandlerContext, status: HTTPResponseStatus, body: Data) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: String(body.count))
        // No CORS headers, deliberately: nothing browser-based should be
        // reaching this, and advertising otherwise would undo the Origin check.
        context.write(
            wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: status, headers: headers))),
            promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        // Close through the channel, not the context: `Channel` is Sendable and
        // the completion closure is not on the event loop's isolation.
        let channel = context.channel
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            channel.close(promise: nil)
        }
    }
}
