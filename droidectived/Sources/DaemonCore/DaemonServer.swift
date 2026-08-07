import ADBKit
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

/// What a route needs from the rest of the app. A protocol so the socket tests
/// drive the real HTTP stack against a scripted device list instead of
/// requiring adb on the test host.
public protocol DaemonBackend: Sendable {
    func listDevices() async -> [Device]
    /// Runs a registry feature. The daemon holds no feature knowledge of its
    /// own — this is a straight pass-through to `FeatureEngine`.
    func runAction(
        featureID: String, serial: String, platform: DevicePlatform,
        params: [String: FeatureValue]
    ) async -> FeatureResult
    /// Every installed app on the device, user and system.
    func listApps(serial: String) async throws -> [AppListing]
    /// One verb against one package.
    func controlApp(
        serial: String, packageId: String, action: AppControlService.AppAction
    ) async throws -> FeatureResult
    /// Every `getprop` key and value on the device.
    func deviceProperties(serial: String) async throws -> [String: String]
    /// Whether this device gives a root shell, and the signals behind the
    /// verdict. Best-effort by design — a probe that fails is a negative
    /// signal, not an error — so it does not throw.
    func rootStatus(serial: String) async -> RootStatus
    /// One directory listing.
    func listFiles(serial: String, path: String, asRoot: Bool) async throws -> [FsEntry]
    /// One mutation against the device's filesystem.
    func fileOperation(
        serial: String, _ operation: FileProtocol.Operation, asRoot: Bool
    ) async throws -> FeatureResult
    /// `stat` for one path; nil when the device could not stat it.
    func fileInfo(
        serial: String, path: String, asRoot: Bool
    ) async throws -> FileExplorerService.FileInfo?
    /// Pulls one device path to a host file path, answering where it landed.
    func pullFile(
        serial: String, path: String, to destination: String, asRoot: Bool
    ) async throws -> String
    /// Every crash the device has recorded, newest first.
    func crashes(serial: String) async throws -> [CrashReport]
    /// Empties the device's crash buffer.
    func clearCrashBuffer(serial: String) async throws
    /// Every Developer Options toggle and animation scale, as the device
    /// currently reports them. Best-effort like the service it wraps — a key
    /// the device refuses reads as its default rather than failing the panel.
    func developerSettings(serial: String) async -> DeviceSettingsProtocol.DevState
    /// Writes one Developer Options row.
    func writeDeveloperSetting(
        serial: String, _ write: DeviceSettingsProtocol.DevWrite
    ) async throws -> AdbResult
    /// The dev-time restriction toggles.
    func restrictions(serial: String) async -> RestrictionsState
    /// Writes one restriction, or remounts the system partition.
    func writeRestriction(
        serial: String, _ write: DeviceSettingsProtocol.RestrictionWrite
    ) async throws -> AdbResult
}

/// `DeviceMonitor` in production.
public struct LiveBackend: DaemonBackend {
    private let monitor: DeviceMonitor
    private let engine: FeatureEngine
    /// The app services are cheap value types over this, so they are built per
    /// call rather than held — there is no state to keep.
    private let client: AdbClient

    public init(monitor: DeviceMonitor, engine: FeatureEngine, client: AdbClient) {
        self.monitor = monitor
        self.engine = engine
        self.client = client
    }

    public func listDevices() async -> [Device] { await monitor.list(force: true) }

    public func runAction(
        featureID: String, serial: String, platform: DevicePlatform,
        params: [String: FeatureValue]
    ) async -> FeatureResult {
        await engine.run(
            featureID: featureID, serial: serial, platform: platform, params: params)
    }

    public func listApps(serial: String) async throws -> [AppListing] {
        try await AppsExplorerService(client: client).listAll(serial: serial)
    }

    public func controlApp(
        serial: String, packageId: String, action: AppControlService.AppAction
    ) async throws -> FeatureResult {
        try await AppControlService(client: client)
            .control(serial: serial, packageId: packageId, action: action)
    }

    public func deviceProperties(serial: String) async throws -> [String: String] {
        try await DeviceProps.all(client: client, serial: serial)
    }

    public func rootStatus(serial: String) async -> RootStatus {
        await RootService(client: client).detect(serial: serial)
    }

    public func listFiles(serial: String, path: String, asRoot: Bool) async throws -> [FsEntry] {
        try await FileExplorerService(client: client).list(serial: serial, dir: path, asRoot: asRoot)
    }

    public func fileOperation(
        serial: String, _ operation: FileProtocol.Operation, asRoot: Bool
    ) async throws -> FeatureResult {
        let explorer = FileExplorerService(client: client)
        switch operation {
        case .makeDirectory(let path):
            return try await explorer.makeDirectory(serial: serial, path: path, asRoot: asRoot)
        case .delete(let path):
            return try await explorer.delete(serial: serial, path: path, asRoot: asRoot)
        case .copy(let source, let destination):
            return try await explorer.copy(
                serial: serial, from: source, toDir: destination, asRoot: asRoot)
        case .move(let source, let destination):
            return try await explorer.move(
                serial: serial, from: source, toDir: destination, asRoot: asRoot)
        }
    }

    public func fileInfo(
        serial: String, path: String, asRoot: Bool
    ) async throws -> FileExplorerService.FileInfo? {
        try await FileExplorerService(client: client).info(
            serial: serial, path: path, asRoot: asRoot)
    }

    public func pullFile(
        serial: String, path: String, to destination: String, asRoot: Bool
    ) async throws -> String {
        try await FileExplorerService(client: client).pull(
            serial: serial, path: path, to: URL(fileURLWithPath: destination), asRoot: asRoot
        ).path
    }

    public func crashes(serial: String) async throws -> [CrashReport] {
        try await CrashExtractor(client: client).crashes(serial: serial)
    }

    public func clearCrashBuffer(serial: String) async throws {
        try await CrashExtractor(client: client).clearCrashBuffer(serial: serial)
    }

    public func developerSettings(serial: String) async -> DeviceSettingsProtocol.DevState {
        let service = DeveloperSettingsService(client: client)
        return DeviceSettingsProtocol.DevState(
            toggles: await service.readToggles(serial: serial),
            scales: await service.readScales(serial: serial))
    }

    public func writeDeveloperSetting(
        serial: String, _ write: DeviceSettingsProtocol.DevWrite
    ) async throws -> AdbResult {
        let service = DeveloperSettingsService(client: client)
        switch write {
        case .toggle(let toggle, let on):
            return try await service.set(toggle, on: on, serial: serial)
        case .scale(let scale, let value):
            return try await service.setScale(scale, value: value, serial: serial)
        }
    }

    public func restrictions(serial: String) async -> RestrictionsState {
        await RestrictionsService(client: client).current(serial: serial)
    }

    public func writeRestriction(
        serial: String, _ write: DeviceSettingsProtocol.RestrictionWrite
    ) async throws -> AdbResult {
        let service = RestrictionsService(client: client)
        switch write {
        case .remountSystemReadWrite:
            return try await service.remountSystemReadWrite(serial: serial)
        case .toggle(let key, let on):
            switch key {
            case .adbInstallVerification:
                return try await service.setAdbInstallVerification(serial: serial, on)
            case .packageVerifier:
                return try await service.setPackageVerifier(serial: serial, on)
            case .stayAwake:
                return try await service.setStayAwake(serial: serial, on)
            case .hiddenApiEnforced:
                return try await service.setHiddenApiEnforced(serial: serial, on)
            case .selinuxEnforcing:
                return try await service.setSelinuxEnforcing(serial: serial, on)
            }
        }
    }
}

/// Loopback HTTP for the request/response half of the protocol.
///
/// Streams will ride a WebSocket on this same listener (topic-multiplexed, with
/// the decided drop-oldest policy); this slice is the request path only.
public actor DaemonServer {
    public struct Bound: Sendable {
        public let port: Int
    }

    /// Named so the WebSocket upgrade can take it back out of the pipeline.
    fileprivate static let routesHandlerName = "droidectived.routes"


    private let backend: any DaemonBackend
    private let streamSource: (any StreamSource)?
    private let token: String
    private var group: MultiThreadedEventLoopGroup?
    private var channel: (any Channel)?
    /// Live client connections.
    ///
    /// `shutdownGracefully` waits for every channel to close, and a stream
    /// socket stays open until its client goes away — so without closing these
    /// first, stopping the daemon while anything is subscribed never returns.
    /// The UI kills the daemon on quit, so a stop that hangs is a stop that
    /// gets SIGKILLed with adb children still running.
    private let connections = ConnectionRegistry()

    public init(
        backend: any DaemonBackend, token: String, streamSource: (any StreamSource)? = nil
    ) {
        self.backend = backend
        self.streamSource = streamSource
        self.token = token
    }

    /// Binds 127.0.0.1 on `port` (0 → the OS picks) and starts serving.
    public func start(port: Int) async throws -> Bound {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let backend = self.backend
        let streamSource = self.streamSource
        let token = self.token
        // Captured by the handler so `Host` can be pinned to the live port,
        // which is only known after bind.
        let boundPort = NIOLockedValueBox(0)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 32)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [connections] channel in
                connections.add(channel)
                channel.closeFuture.whenComplete { _ in connections.remove(channel) }
                // The stream socket rides the same listener as the routes, so
                // there is one port, one token and one origin policy rather
                // than two things to keep in agreement.
                let upgrader = NIOWebSocketServerUpgrader(
                    shouldUpgrade: { channel, head in
                        // Auth on the *upgrade* request. Checking after the
                        // handshake would leave an authenticated-looking socket
                        // open to anything that can reach the port.
                        let port = boundPort.withLockedValue { $0 }
                        let refused = DaemonGuards.check(
                            authorization: head.headers.first(name: "Authorization"),
                            host: head.headers.first(name: "Host"),
                            origin: head.headers.first(name: "Origin"),
                            port: port, expectedToken: token)
                        guard refused == nil, head.uri == DaemonProtocol.streamPath,
                              streamSource != nil
                        else { return channel.eventLoop.makeSucceededFuture(nil) }
                        return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
                    },
                    upgradePipelineHandler: { channel, _ in
                        guard let streamSource else {
                            return channel.eventLoop.makeSucceededFuture(())
                        }
                        // The route handler sits after the HTTP codec, which
                        // NIO removes on upgrade — but not handlers added
                        // behind it. Left in place it would be handed
                        // WebSocket frames and trap trying to read them as
                        // HTTP.
                        return channel.pipeline.removeHandler(name: Self.routesHandlerName)
                            .recover { _ in }
                            .flatMap { _ -> EventLoopFuture<Void> in
                                let session = StreamSession(
                                    sink: WebSocketSink(channel: channel), source: streamSource)
                                return channel.eventLoop.makeCompletedFuture {
                                    try channel.pipeline.syncOperations.addHandler(
                                        WebSocketHandler(session: session))
                                }
                            }
                    })

                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in })
                ).flatMapThrowing {
                    try channel.pipeline.syncOperations.addHandler(
                        RequestHandler(backend: backend, token: token, port: boundPort),
                        name: Self.routesHandlerName)
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
        // Stop accepting first, then hang up on everyone still connected, then
        // shut the loops down. Any other order either races new connections in
        // or waits forever on old ones.
        try? await channel?.close().get()
        channel = nil
        for connection in connections.drain() {
            try? await connection.close().get()
        }
        try? await group?.shutdownGracefully()
        group = nil
    }
}

/// Thread-safe set of open child channels. Identity-keyed, since `Channel` is
/// a reference type with no useful equality of its own.
private final class ConnectionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var channels: [ObjectIdentifier: any Channel] = [:]

    func add(_ channel: any Channel) {
        lock.lock()
        channels[ObjectIdentifier(channel)] = channel
        lock.unlock()
    }

    func remove(_ channel: any Channel) {
        lock.lock()
        channels[ObjectIdentifier(channel)] = nil
        lock.unlock()
    }

    /// Everything currently open, clearing the registry.
    func drain() -> [any Channel] {
        lock.lock()
        defer {
            channels.removeAll()
            lock.unlock()
        }
        return Array(channels.values)
    }
}

/// One request at a time per connection: collect the head, ignore the body
/// (every route takes its arguments in the path for this slice), answer.
private final class RequestHandler: ChannelInboundHandler, RemovableChannelHandler,
    @unchecked Sendable
{
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let backend: any DaemonBackend
    private let token: String
    private let port: NIOLockedValueBox<Int>
    private var head: HTTPRequestHead?
    private var body = ByteBufferAllocator().buffer(capacity: 0)

    init(backend: any DaemonBackend, token: String, port: NIOLockedValueBox<Int>) {
        self.backend = backend
        self.token = token
        self.port = port
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            self.head = head
        case .body(var buffer):
            body.writeBuffer(&buffer)
        case .end:
            guard let head else { return }
            self.head = nil
            let body = self.body
            self.body = ByteBufferAllocator().buffer(capacity: 0)
            let loop = context.eventLoop
            let boxedContext = NIOLoopBound(context, eventLoop: loop)
            let port = self.port.withLockedValue { $0 }
            let backend = self.backend
            let token = self.token
            // The route is async; hop the answer back onto the event loop.
            Task { [self] in
                let (status, responseBody) = await Self.respond(
                    head: head, body: body, port: port, token: token, backend: backend)
                loop.execute {
                    self.write(context: boxedContext.value, status: status, body: responseBody)
                }
            }
        }
    }

    /// Pure-ish routing: guards, then the route. Split out so the socket tests
    /// and any future unit test exercise the same decision path.
    static func respond(
        head: HTTPRequestHead, body: ByteBuffer, port: Int, token: String,
        backend: any DaemonBackend
    ) async -> (HTTPResponseStatus, Data) {
        func encoded(_ body: some Encodable) -> Data { DaemonProtocol.encoded(body) }

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

        case .featuresList:
            return (.ok, encoded(ActionProtocol.features()))

        case .deviceProps:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                DaemonProtocol.DeviceRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            do {
                let properties = try await backend.deviceProperties(serial: request.serial)
                return (.ok, encoded(DaemonProtocol.DevicePropsResponse(properties: properties)))
            } catch {
                // adb's answer, not a daemon fault — the same 502 the app
                // list uses, carrying adb's own words.
                return (.badGateway, encoded(DaemonProtocol.ErrorBody(
                    code: "adb_failed", message: "Could not read the device properties.",
                    detail: "\(error)")))
            }

        case .deviceRoot:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                DaemonProtocol.DeviceRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            // Best-effort by construction: a probe the device refuses is a
            // negative signal, so there is no failure branch to map.
            let status = await backend.rootStatus(serial: request.serial)
            return (.ok, encoded(DaemonProtocol.RootStatusResponse(status)))

        // The filesystem half lives in `FileRoutes`, so this switch stays a
        // table of routes rather than a fifth of the protocol inline.
        case .filesList:
            return Self.answer(
                await FileRoutes.list(body: Data(body.readableBytesView), backend: backend))
        case .filesOp:
            return Self.answer(
                await FileRoutes.operation(body: Data(body.readableBytesView), backend: backend))
        case .filesInfo:
            return Self.answer(
                await FileRoutes.info(body: Data(body.readableBytesView), backend: backend))
        case .filesPull:
            return Self.answer(
                await FileRoutes.pull(body: Data(body.readableBytesView), backend: backend))

        case .crashesList:
            return Self.answer(
                await CrashRoutes.list(body: Data(body.readableBytesView), backend: backend))
        case .crashesClear:
            return Self.answer(
                await CrashRoutes.clear(body: Data(body.readableBytesView), backend: backend))

        case .devSettingsRead:
            return Self.answer(await DeviceSettingsRoutes.developerRead(
                body: Data(body.readableBytesView), backend: backend))
        case .devSettingsWrite:
            return Self.answer(await DeviceSettingsRoutes.developerWrite(
                body: Data(body.readableBytesView), backend: backend))
        case .restrictionsRead:
            return Self.answer(await DeviceSettingsRoutes.restrictionsRead(
                body: Data(body.readableBytesView), backend: backend))
        case .restrictionsWrite:
            return Self.answer(await DeviceSettingsRoutes.restrictionsWrite(
                body: Data(body.readableBytesView), backend: backend))

        case .actionsRun:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                ActionProtocol.RunRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            guard let platform = request.resolvedPlatform else {
                return (.badRequest, encoded(DaemonProtocol.unknownPlatform))
            }
            // Unknown ids are a 404 rather than a 500: asking for a feature
            // that does not exist is the client's mistake, not a daemon fault,
            // and `run` would otherwise answer with a generic failure that a
            // UI cannot distinguish from a device problem.
            guard FeatureEngine.implementedIDs.contains(request.featureId) else {
                return (.notFound, encoded(DaemonProtocol.unknownFeature))
            }
            let result = await backend.runAction(
                featureID: request.featureId, serial: request.serial,
                platform: platform, params: request.featureValues)
            // A failed action is a *successful* request: 200 with ok=false.
            // Mapping it to 5xx would conflate "the device said no" with "the
            // daemon broke", which is the distinction `AdbClient` exists to
            // preserve.
            return (.ok, encoded(ActionProtocol.RunResponse(result)))

        case .appsList:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                AppProtocol.ListRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            do {
                let apps = try await backend.listApps(serial: request.serial)
                return (.ok, encoded(AppProtocol.ListResponse(
                    apps: apps.map(AppProtocol.AppSummary.init))))
            } catch {
                // adb refused: the device went away, or is unauthorised. That
                // is the device's answer rather than a daemon fault, so it
                // goes out as a 502 carrying adb's own words.
                return (.badGateway, encoded(DaemonProtocol.ErrorBody(
                    code: "adb_failed", message: "Could not list apps.",
                    detail: "\(error)")))
            }

        case .appsControl:
            let raw = Data(body.readableBytesView)
            guard let request = try? JSONDecoder().decode(
                AppProtocol.ControlRequest.self, from: raw)
            else { return (.badRequest, encoded(DaemonProtocol.badRequest)) }
            guard let action = request.resolvedAction else {
                return (.badRequest, encoded(AppProtocol.unknownAction))
            }
            do {
                let result = try await backend.controlApp(
                    serial: request.serial, packageId: request.packageId, action: action)
                return (.ok, encoded(ActionProtocol.RunResponse(result)))
            } catch {
                return (.badGateway, encoded(DaemonProtocol.ErrorBody(
                    code: "adb_failed", message: "The app action failed.",
                    detail: "\(error)")))
            }
        }
    }

    /// A `FileRoutes` answer as NIO wants it. Those handlers deal in a plain
    /// status code so they can be tested without a socket.
    private static func answer(_ answer: DaemonProtocol.Answer) -> (HTTPResponseStatus, Data) {
        (HTTPResponseStatus(statusCode: answer.status), answer.body)
    }

    private func write(context: ChannelHandlerContext, status: HTTPResponseStatus, body: Data) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: String(body.count))
        // This handler closes the connection after every response, so say so.
        // Without it a client pools the socket, reuses one the server has
        // already dropped, and sees a lost connection instead of its answer —
        // intermittent by nature, which is the worst kind of bug to ship in a
        // tool people debug with.
        headers.add(name: "Connection", value: "close")
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
