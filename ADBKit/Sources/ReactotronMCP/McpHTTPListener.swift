import Foundation
import MCP
import NIOCore
import NIOHTTP1
import NIOPosix
import os

/// The localhost HTTP front door for MCP: a port of the SDK's conformance
/// `HTTPApp` (the reference implementation its server transport is tested
/// against). One route (`/mcp`), one `Server` + `StatefulHTTPServerTransport`
/// per session (a `Server` accepts exactly one initialize — SDK #144), an
/// idle-session reaper, and the SDK's default validation pipeline
/// (`OriginValidator.localhost()` — the spec's DNS-rebinding defense) plus an
/// optional static bearer token. Binds 127.0.0.1 only, never the LAN.
public actor McpHTTPListener {
    public struct Configuration: Sendable {
        public var port: UInt16
        public var endpoint: String
        public var sessionIdleTimeout: Duration
        /// When set, every request must carry `Authorization: Bearer <token>`.
        public var bearerToken: String?

        public init(
            port: UInt16 = McpConstants.defaultPort,
            endpoint: String = "/mcp",
            sessionIdleTimeout: Duration = .seconds(1800),
            bearerToken: String? = nil
        ) {
            self.port = port
            self.endpoint = endpoint
            self.sessionIdleTimeout = sessionIdleTimeout
            self.bearerToken = bearerToken
        }
    }

    public enum ListenerError: Error, Sendable, LocalizedError {
        case portInUse(UInt16)
        case bindFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .portInUse(port):
                "Port \(port) is already in use — is another MCP server (or the Reactotron "
                    + "desktop app) running?"
            case let .bindFailed(detail):
                "MCP listener failed to start: \(detail)"
            }
        }
    }

    private static let log = Logger(
        subsystem: "com.rohindh.droidective", category: "reactotron-mcp")

    private let configuration: Configuration
    private let factory: McpServerFactory
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var reaperTask: Task<Void, Never>?

    private struct SessionContext {
        let server: Server
        let transport: StatefulHTTPServerTransport
        var lastAccessedAt: ContinuousClock.Instant
    }

    private var sessions: [String: SessionContext] = [:]

    public init(configuration: Configuration, factory: McpServerFactory) {
        self.configuration = configuration
        self.factory = factory
    }

    /// The port actually bound (differs from the configured one only when
    /// constructed with port 0 in tests). Nil until started.
    public var boundPort: UInt16? {
        channel?.localAddress?.port.map(UInt16.init)
    }

    public var activeSessionCount: Int { sessions.count }

    // MARK: - Lifecycle

    /// Bind and start serving. Returns once the socket is listening; throws
    /// `.portInUse` on EADDRINUSE so the UI can say something useful.
    public func start() async throws {
        guard channel == nil else { return }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.group = group

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(listener: self))
                }
            }
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        do {
            // Loopback only — the MCP endpoint must never be LAN-reachable,
            // regardless of the Reactotron relay's own LAN toggle.
            channel = try await bootstrap.bind(
                host: "127.0.0.1", port: Int(configuration.port)
            ).get()
        } catch {
            try? await group.shutdownGracefully()
            self.group = nil
            if let ioError = error as? IOError, ioError.errnoCode == EADDRINUSE {
                throw ListenerError.portInUse(configuration.port)
            }
            throw ListenerError.bindFailed("\(error)")
        }

        Self.log.notice("MCP listener bound on 127.0.0.1:\(self.boundPort ?? 0, privacy: .public)")
        reaperTask = Task { [weak self, configuration] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.reapIdleSessions(olderThan: configuration.sessionIdleTimeout)
            }
        }
    }

    /// Close every session and the socket. Safe to call repeatedly.
    public func stop() async {
        reaperTask?.cancel()
        reaperTask = nil
        for sessionID in sessions.keys {
            await closeSession(sessionID)
        }
        try? await channel?.close()
        channel = nil
        if let group {
            try? await group.shutdownGracefully()
        }
        group = nil
        Self.log.notice("MCP listener stopped")
    }

    // MARK: - Request routing (port of HTTPApp.handleHTTPRequest)

    nonisolated var endpoint: String { configuration.endpoint }

    func handleHTTPRequest(_ request: HTTPRequest) async -> HTTPResponse {
        let sessionID = request.header(HTTPHeaderName.sessionID)

        if let sessionID, var session = sessions[sessionID] {
            session.lastAccessedAt = .now
            sessions[sessionID] = session

            let response = await session.transport.handleRequest(request)
            if request.method.uppercased() == "DELETE", response.statusCode == 200 {
                sessions.removeValue(forKey: sessionID)
            }
            return response
        }

        if request.method.uppercased() == "POST",
           let body = request.body,
           Self.isInitializeRequest(body) {
            return await createSessionAndHandle(request)
        }

        if sessionID != nil {
            return .error(
                statusCode: 404,
                .invalidRequest("Not Found: Session not found or expired"))
        }
        return .error(
            statusCode: 400,
            .invalidRequest("Bad Request: Missing \(HTTPHeaderName.sessionID) header"))
    }

    /// The SDK's `JSONRPCMessageKind` is package-scoped; this is the one
    /// check the router needs from it.
    static func isInitializeRequest(_ body: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) else { return false }
        if let dict = object as? [String: Any] {
            return dict["method"] as? String == "initialize"
        }
        if let array = object as? [Any] {
            return array.contains { ($0 as? [String: Any])?["method"] as? String == "initialize" }
        }
        return false
    }

    // MARK: - Sessions

    private struct FixedSessionIDGenerator: SessionIDGenerator {
        let sessionID: String
        func generateSessionID() -> String { sessionID }
    }

    /// The SDK's default validators, plus the static bearer check when a
    /// token is configured (`AuthorizationTokenValidator` below).
    private func validationPipeline() -> any HTTPRequestValidationPipeline {
        var validators: [any HTTPRequestValidator] = []
        if let token = configuration.bearerToken {
            validators.append(AuthorizationTokenValidator(expectedToken: token))
        }
        validators += [
            OriginValidator.localhost(),
            AcceptHeaderValidator(mode: .sseRequired),
            ContentTypeValidator(),
            ProtocolVersionValidator(),
            SessionValidator(),
        ]
        return StandardValidationPipeline(validators: validators)
    }

    private func createSessionAndHandle(_ request: HTTPRequest) async -> HTTPResponse {
        let sessionID = UUID().uuidString
        let transport = StatefulHTTPServerTransport(
            sessionIDGenerator: FixedSessionIDGenerator(sessionID: sessionID),
            validationPipeline: validationPipeline()
        )

        do {
            let server = await factory.makeServer()
            try await server.start(transport: transport)
            sessions[sessionID] = SessionContext(
                server: server, transport: transport, lastAccessedAt: .now)

            let response = await transport.handleRequest(request)
            if case .error = response {
                sessions.removeValue(forKey: sessionID)
                await transport.disconnect()
            }
            return response
        } catch {
            await transport.disconnect()
            return .error(
                statusCode: 500,
                .internalError("Failed to create session: \(error.localizedDescription)"))
        }
    }

    private func closeSession(_ sessionID: String) async {
        guard let session = sessions.removeValue(forKey: sessionID) else { return }
        await session.transport.disconnect()
        await session.server.stop()
    }

    private func reapIdleSessions(olderThan timeout: Duration) async {
        let now = ContinuousClock.Instant.now
        let expired = sessions.filter { now - $0.value.lastAccessedAt > timeout }
        for sessionID in expired.keys {
            Self.log.notice("MCP session idle-expired")
            await closeSession(sessionID)
        }
    }
}

/// Rejects requests whose `Authorization` header doesn't carry the expected
/// static bearer token — the right weight for a localhost devtool (the SDK's
/// `BearerTokenValidator` models full OAuth resource servers).
struct AuthorizationTokenValidator: HTTPRequestValidator {
    let expectedToken: String

    func validate(_ request: HTTPRequest, context: HTTPValidationContext) -> HTTPResponse? {
        guard let authorization = request.header(HTTPHeaderName.authorization),
              authorization == "Bearer \(expectedToken)" else {
            return .error(
                statusCode: 401,
                .invalidRequest("Unauthorized: missing or invalid bearer token"))
        }
        return nil
    }
}

// MARK: - NIO adapter (port of HTTPApp.HTTPHandler)

/// Converts between NIO HTTP parts and the SDK's framework-agnostic
/// `HTTPRequest`/`HTTPResponse`, delegating all logic to the listener actor.
/// State is only touched on the channel's event loop; responses are written
/// back through `eventLoop.execute`.
private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let listener: McpHTTPListener

    private struct RequestState {
        var head: HTTPRequestHead
        var bodyBuffer: ByteBuffer
    }

    /// `ChannelHandlerContext` isn't Sendable; it's only touched through
    /// `eventLoop.execute`, so box it to cross the Task hop (the same
    /// pattern as `ReactotronServer.ConnectionBox`).
    private struct ContextBox: @unchecked Sendable {
        let context: ChannelHandlerContext
    }

    private var requestState: RequestState?

    init(listener: McpHTTPListener) {
        self.listener = listener
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case let .head(head):
            requestState = RequestState(
                head: head, bodyBuffer: context.channel.allocator.buffer(capacity: 0))
        case var .body(buffer):
            requestState?.bodyBuffer.writeBuffer(&buffer)
        case .end:
            guard let state = requestState else { return }
            requestState = nil
            // Convert to the SDK's Sendable HTTPRequest *before* leaving the
            // event loop — NIO's head/buffer types can't cross the Task hop.
            let request = makeHTTPRequest(from: state)
            let version = state.head.version
            let box = ContextBox(context: context)
            Task { await self.handleRequest(request, version: version, box: box) }
        }
    }

    private func handleRequest(
        _ request: HTTPRequest, version: HTTPVersion, box: ContextBox
    ) async {
        guard request.path == listener.endpoint else {
            await writeResponse(
                .error(statusCode: 404, .invalidRequest("Not Found")),
                version: version, box: box)
            return
        }
        let response = await listener.handleHTTPRequest(request)
        await writeResponse(response, version: version, box: box)
    }

    private func makeHTTPRequest(from state: RequestState) -> HTTPRequest {
        var headers: [String: String] = [:]
        for (name, value) in state.head.headers {
            headers[name] = headers[name].map { $0 + ", " + value } ?? value
        }
        let body: Data? = state.bodyBuffer.readableBytes > 0
            ? state.bodyBuffer.getBytes(at: 0, length: state.bodyBuffer.readableBytes)
                .map { Data($0) }
            : nil
        let path = String(state.head.uri.split(separator: "?").first ?? Substring(state.head.uri))
        return HTTPRequest(
            method: state.head.method.rawValue, headers: headers, body: body, path: path)
    }

    private func writeResponse(
        _ response: HTTPResponse, version: HTTPVersion, box: ContextBox
    ) async {
        let eventLoop = box.context.eventLoop
        let statusCode = response.statusCode
        let headers = response.headers

        switch response {
        case let .stream(stream, _):
            eventLoop.execute {
                var head = HTTPResponseHead(
                    version: version, status: HTTPResponseStatus(statusCode: statusCode))
                for (name, value) in headers { head.headers.add(name: name, value: value) }
                box.context.write(self.wrapOutboundOut(.head(head)), promise: nil)
                box.context.flush()
            }
            do {
                for try await chunk in stream {
                    eventLoop.execute {
                        var buffer = box.context.channel.allocator.buffer(capacity: chunk.count)
                        buffer.writeBytes(chunk)
                        box.context.writeAndFlush(
                            self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                    }
                }
            } catch {
                // Stream ended with an error — fall through and close out.
            }
            eventLoop.execute {
                box.context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }
        default:
            let bodyData = response.bodyData
            eventLoop.execute {
                var head = HTTPResponseHead(
                    version: version, status: HTTPResponseStatus(statusCode: statusCode))
                for (name, value) in headers { head.headers.add(name: name, value: value) }
                box.context.write(self.wrapOutboundOut(.head(head)), promise: nil)
                if let body = bodyData {
                    var buffer = box.context.channel.allocator.buffer(capacity: body.count)
                    buffer.writeBytes(body)
                    box.context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }
                box.context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}
