import ADBKit
import Foundation
import NIOCore
import NIOPosix

/// Brings up a scrcpy mirroring session and streams its raw video bytes.
///
/// **Why this is in the daemon and not ADBKit.** The Mac's is `MirrorTransport`,
/// an `NWConnection` over `adb forward` — Apple-only, and gated as such. The
/// portable answer is NIO, which the daemon already links; putting it in ADBKit
/// instead would drag swift-nio into that package's graph, and ADBKit staying
/// nio-free is exactly what lets `swift test` run on Windows. So the *sockets*
/// are here and everything above them — `ScrcpyServerParams`,
/// `ScrcpyStreamDecoder`, `ScrcpyControlMessage`, `H264NAL` — is the portable
/// ADBKit code both hosts already share. The same split `ReactotronRelay` made.
///
/// The protocol is scrcpy's own: push the server jar, open a forward tunnel
/// (`adb forward tcp:0` so adb picks a free port, which is what keeps a stock
/// scrcpy or a second app instance from colliding), start the server, then
/// connect its sockets in the order it accepts them and pump bytes. Feed the
/// byte stream into a `ScrcpyStreamDecoder`.
///
/// `stop()` tears the whole thing down, is idempotent, and is **terminal** — the
/// `adb forward` outlives the process otherwise, which is the leak the Mac was
/// caught doing once per quit. Callers must await it rather than fire it off.
public actor ScrcpyTransport {
    public struct Configuration: Sendable {
        public var serial: String
        public var params: ScrcpyServerParams
        public var serverVersion: String
        public var localJarPath: String
        public var remoteJarPath: String

        public init(
            serial: String,
            params: ScrcpyServerParams,
            serverVersion: String,
            localJarPath: String,
            remoteJarPath: String = "/data/local/tmp/scrcpy-server.jar"
        ) {
            self.serial = serial
            self.params = params
            self.serverVersion = serverVersion
            self.localJarPath = localJarPath
            self.remoteJarPath = remoteJarPath
        }
    }

    public enum TransportError: Error, CustomStringConvertible, Sendable {
        case adbNotFound
        case pushFailed(String)
        case forwardFailed(String)
        case serverFailedToStart(String)
        case connectFailed(String)
        /// The device accepted the socket and then dropped it, which is what
        /// `adb forward` does before the device-side server is listening.
        case deviceSideNotReady

        public var description: String {
            switch self {
            case .adbNotFound: "adb not found — the mirror needs it to connect."
            case let .pushFailed(detail): "Couldn't push scrcpy-server: \(detail)"
            case let .forwardFailed(detail): "Couldn't open the adb tunnel: \(detail)"
            case let .serverFailedToStart(detail): "scrcpy-server didn't start: \(detail)"
            case let .connectFailed(detail): "Couldn't connect to the device stream: \(detail)"
            case .deviceSideNotReady: "The device side isn't listening yet."
            }
        }
    }

    /// A connected socket and the bytes arriving on it.
    struct Socket {
        let channel: any Channel
        let stream: AsyncThrowingStream<Data, Error>
    }

    private let adb: AdbClient
    private let config: Configuration

    /// Created on start and shut down on stop rather than shared with the
    /// daemon's listener: owning it is what lets `stop()` actually release the
    /// sockets. One thread is plenty — the encoded stream is scrcpy's bitrate,
    /// single-digit megabits, not the decoded frames.
    private var group: MultiThreadedEventLoopGroup?
    private var videoChannel: (any Channel)?
    private var audioChannel: (any Channel)?
    private var controlChannel: (any Channel)?
    private var audioStream: AsyncThrowingStream<Data, Error>?
    private var controlIncomingStream: AsyncStream<Data>?
    private var controlIncomingContinuation: AsyncStream<Data>.Continuation?
    private var serverProcess: Process?
    /// The server's stderr, and the reason it is a file rather than a `Pipe`:
    /// a pipe nobody drains fills and wedges the child, and draining one
    /// portably is a per-platform problem (ADBKit's `PipeCollector` needs a
    /// dedicated thread off Darwin because corelibs never delivers the empty
    /// EOF callback). A file never blocks a writer, and this is only ever read
    /// on the failure path.
    private var serverLogURL: URL?
    /// Held so teardown can close it *before* deleting the file.
    ///
    /// `Process` does not close a `FileHandle` it was handed, so without this
    /// the fd lives until the `Process` is released — one per session, six for
    /// a full Mirror Wall, and again on every reconnect. On Windows it is worse
    /// than untidy: deleting a file this process still has open fails with
    /// ERROR_SHARING_VIOLATION, the same Win32 32 that `FileRetry` exists for.
    private var serverLogHandle: FileHandle?
    private var forwardedPort: UInt16?
    /// Terminal latch: actors are reentrant, so `stop()` can run at any of
    /// `start()`'s suspension points — including *before* the fields it cleans
    /// are set. Without it, `start()` resumes and finishes building a session
    /// whose stop already happened, stranding an adb child, a forward, and a
    /// device-side server in accept-wait that nothing will ever clean up.
    private var stopped = false

    public init(adb: AdbClient, config: Configuration) {
        self.adb = adb
        self.config = config
    }

    /// Push the server, open the tunnel, start the server, connect its sockets,
    /// and return the video byte stream.
    ///
    /// A failed bring-up cleans up after itself. The Mac leans on
    /// `MirrorSessions` registering the model before `start()` runs, precisely
    /// because a start that fails part-way has still opened the tunnel; here
    /// there is nothing to lean on, and a caller that never received a session
    /// has no reason to think it owes it a `stop()`. So the forward cannot
    /// survive a throw.
    public func start() async throws -> AsyncThrowingStream<Data, Error> {
        do {
            return try await bringUp()
        } catch {
            await teardown()
            throw error
        }
    }

    private func bringUp() async throws -> AsyncThrowingStream<Data, Error> {
        try await abortIfStopped()
        let adbPath = try await resolveAdbPath()
        try await abortIfStopped()
        try await pushServer()
        try await abortIfStopped()
        let port = try await openForward()
        try await abortIfStopped()
        try startServer(adbPath: adbPath)
        try await abortIfStopped()

        let loops = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        group = loops
        // The server accepts sockets in a fixed order on the same port:
        // 1 = video, 2 = audio (if enabled), 3 = control (if enabled). Connect
        // them in that order or they map to the wrong streams.
        let video: Socket
        do {
            video = try await Self.connectVideoSocket(port: port, group: loops)
        } catch let error as TransportError {
            // Only here does the server's own complaint mean anything: a video
            // socket that never produced a byte usually failed on the device
            // side (a version mismatch, a permission), and that reason is in
            // the log rather than in the socket error.
            throw TransportError.connectFailed("\(error)" + serverLog())
        }
        videoChannel = video.channel
        try await abortIfStopped()
        if config.params.audio {
            let audio = try await Self.connectSecondarySocket(
                port: port, group: loops, label: "audio")
            audioChannel = audio.channel
            audioStream = audio.stream
        }
        try await abortIfStopped()
        if config.params.control {
            let control = try await Self.connectSecondarySocket(
                port: port, group: loops, label: "control")
            controlChannel = control.channel
            adoptControlIncoming(control.stream)
        }
        try await abortIfStopped()
        return video.stream
    }

    /// A `stop()` that interleaved mid-`start()` found nothing to clean —
    /// re-run the teardown against whatever this call has created since, and
    /// bail out as a cancellation, because a stop is a teardown rather than a
    /// device failure.
    private func abortIfStopped() async throws {
        guard stopped else { return }
        await teardown()
        throw CancellationError()
    }

    /// Tear everything down: close the sockets, kill the server, remove the
    /// tunnel. Safe to call repeatedly, and terminal.
    public func stop() async {
        stopped = true
        await teardown()
    }

    private func teardown() async {
        // Channels first, then the group: shutting down a group with live
        // channels leaves the close futures nowhere to run.
        for channel in [videoChannel, audioChannel, controlChannel] {
            try? await channel?.close().get()
        }
        videoChannel = nil
        audioChannel = nil
        controlChannel = nil
        audioStream = nil
        controlIncomingContinuation?.finish()
        controlIncomingContinuation = nil
        controlIncomingStream = nil
        let loops = group
        group = nil
        try? await loops?.shutdownGracefully()
        if let process = serverProcess, process.isRunning { process.terminate() }
        serverProcess = nil
        // Close before deleting, not after: see `serverLogHandle`.
        try? serverLogHandle?.close()
        serverLogHandle = nil
        if let url = serverLogURL {
            try? FileManager.default.removeItem(at: url)
            serverLogURL = nil
        }
        // Last, and awaited: this is the one that outlives the process.
        if let port = forwardedPort {
            _ = try? await adb.run(on: config.serial, ["forward", "--remove", "tcp:\(port)"])
            forwardedPort = nil
        }
    }

    // MARK: - Steps

    private func resolveAdbPath() async throws -> String {
        guard let path = await adb.locator.resolve(.adb) else { throw TransportError.adbNotFound }
        return path
    }

    private func pushServer() async throws {
        let result: AdbResult
        do {
            result = try await adb.run(
                on: config.serial,
                ["push", config.localJarPath, config.remoteJarPath],
                timeout: .seconds(60))
        } catch {
            throw TransportError.adbNotFound
        }
        guard result.succeeded else {
            throw TransportError.pushFailed(friendlyAdbError(result, fallback: "adb push failed"))
        }
    }

    /// `adb forward tcp:0 …` allocates a free local port and prints it.
    private func openForward() async throws -> UInt16 {
        let result: AdbResult
        do {
            result = try await adb.run(
                on: config.serial,
                ["forward", "tcp:0", "localabstract:\(config.params.socketName)"])
        } catch {
            throw TransportError.adbNotFound
        }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, let port = UInt16(text) else {
            throw TransportError.forwardFailed(
                friendlyAdbError(result, fallback: "adb forward failed"))
        }
        forwardedPort = port
        return port
    }

    private func startServer(adbPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-s", config.serial]
            + config.params.shellArguments(
                serverVersion: config.serverVersion, remoteJarPath: config.remoteJarPath)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrcpy-server-\(config.params.socketName).log")
        if let log = Self.openLog(at: logURL) {
            process.standardError = log
            serverLogHandle = log
            serverLogURL = logURL
        }
        do {
            try process.run()
        } catch {
            throw TransportError.serverFailedToStart("\(error)")
        }
        serverProcess = process
    }

    /// Create the log and open it for writing, or nil if the temp directory
    /// will not have it.
    ///
    /// Writing empty `Data` rather than `FileManager.createFile`: that returns a
    /// `@discardableResult` Bool on Darwin and a must-use one off it, so the
    /// obvious spelling compiles on macOS and fails the Linux build under
    /// warnings-as-errors. This one spelling suits every platform.
    private nonisolated static func openLog(at url: URL) -> FileHandle? {
        guard (try? Data().write(to: url)) != nil else { return nil }
        return try? FileHandle(forWritingTo: url)
    }

    /// The tail of whatever the server said, for a failure message.
    private func serverLog() -> String {
        guard let url = serverLogURL,
            let data = try? Data(contentsOf: url), !data.isEmpty
        else { return "" }
        let text = String(decoding: data.suffix(8192), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "" : " | server: \(text)"
    }

    // MARK: - Sockets
    //
    // Static and injectable-timeout on purpose: this is the half of the
    // transport that is genuinely new off Apple, and it is the half a test can
    // drive against a fake scrcpy server with no device, no adb and no actor.

    /// Connect the video socket, retrying until the server is really listening
    /// or the deadline passes (it takes about a second to boot via
    /// `app_process`).
    ///
    /// `adb forward` accepts the local connect *immediately*, even before the
    /// device-side server is listening, and then drops it. So a connected
    /// channel proves nothing — the proof is the first byte (scrcpy's
    /// forward-mode dummy `0x00`), and an immediate EOF means retry. Unlike the
    /// Mac's version this needs no replay: NIO lets the handler signal that the
    /// first byte arrived without consuming it from the stream.
    nonisolated static func connectVideoSocket(
        port: UInt16,
        group: MultiThreadedEventLoopGroup,
        giveUpAfter: Duration = .seconds(10),
        firstByteWithin: Duration = .milliseconds(800)
    ) async throws -> Socket {
        try await retryingConnect(
            port: port, group: group, giveUpAfter: giveUpAfter, gap: .milliseconds(200),
            label: "video", firstByteWithin: firstByteWithin)
    }

    /// Connect a secondary socket (audio or control — the server's 2nd/3rd
    /// accepted connection). No dummy byte here; only the video socket carries
    /// one, so readiness is the connect itself.
    nonisolated static func connectSecondarySocket(
        port: UInt16,
        group: MultiThreadedEventLoopGroup,
        label: String,
        giveUpAfter: Duration = .seconds(5)
    ) async throws -> Socket {
        try await retryingConnect(
            port: port, group: group, giveUpAfter: giveUpAfter, gap: .milliseconds(150),
            label: label, firstByteWithin: nil)
    }

    private nonisolated static func retryingConnect(
        port: UInt16,
        group: MultiThreadedEventLoopGroup,
        giveUpAfter: Duration,
        gap: Duration,
        label: String,
        firstByteWithin: Duration?
    ) async throws -> Socket {
        let deadline = ContinuousClock().now.advanced(by: giveUpAfter)
        var lastError = "timed out"
        while ContinuousClock().now < deadline {
            // A cancelled bring-up must exit rather than spin: every attempt
            // would fail instantly and burn a core until the deadline.
            try Task.checkCancellation()
            do {
                return try await connectOnce(
                    port: port, group: group, firstByteWithin: firstByteWithin)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = "\(error)"
                try? await Task.sleep(for: gap)
            }
        }
        throw TransportError.connectFailed("\(label) socket: \(lastError)")
    }

    /// One attempt. `firstByteWithin` nil means the connect itself is the
    /// readiness test, which is right for the audio and control sockets.
    private nonisolated static func connectOnce(
        port: UInt16,
        group: MultiThreadedEventLoopGroup,
        firstByteWithin: Duration?
    ) async throws -> Socket {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
        // Pinned to one loop rather than handed the whole group: the readiness
        // promise, the handler that fulfils it and the timeout that gives up on
        // it must all run on the *same* loop, or two of them can fulfil it at
        // once — and a doubly-fulfilled NIO promise traps.
        let loop = group.next()
        let ready = firstByteWithin.map { _ in loop.makePromise(of: Void.self) }
        let bootstrap = ClientBootstrap(group: loop)
            // Nagle off. The control socket sends tiny writes (a touch is ~32
            // bytes) and the video socket reads a latency-sensitive stream;
            // batching either behind delayed ACKs costs tens of milliseconds
            // of lag for no win on a loopback tunnel.
            .channelOption(.socketOption(.tcp_nodelay), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        ScrcpySocketHandler(
                            continuation: continuation,
                            ready: ready,
                            firstByteWithin: firstByteWithin.map(timeAmount)))
                }
            }

        let channel: any Channel
        do {
            channel = try await bootstrap.connect(host: "127.0.0.1", port: Int(port)).get()
        } catch {
            // Nobody will fulfil the promise now, and an unfulfilled NIO
            // promise traps on deinit.
            ready?.fail(error)
            continuation.finish(throwing: error)
            throw TransportError.connectFailed("\(error)")
        }

        if let ready {
            do {
                // Safe to await unguarded: the handler fulfils this on the
                // first byte, on an EOF, or on its own scheduled timeout, so it
                // always completes. Racing it against a `Task.sleep` here
                // instead would deadlock — a task group waits for every child,
                // and `future.get()` does not answer cancellation, so the
                // timeout branch would wait forever on the very promise that
                // only the close it never reaches would settle.
                try await ready.futureResult.get()
            } catch {
                try? await channel.close().get()
                throw error
            }
        }
        return Socket(channel: channel, stream: stream)
    }

    private nonisolated static func timeAmount(_ duration: Duration) -> TimeAmount {
        let (seconds, attoseconds) = duration.components
        return .nanoseconds(seconds * 1_000_000_000 + attoseconds / 1_000_000_000)
    }

    // MARK: - Audio and control

    /// Raw bytes from the audio socket (codec id then framed PCM packets), or
    /// nil if audio isn't enabled. Parse with `ScrcpyAudioStreamDecoder`.
    public func audioByteStream() -> AsyncThrowingStream<Data, Error>? { audioStream }

    /// A sink for control bytes, or nil if control isn't enabled. NIO preserves
    /// per-channel write order, so callers can fire touch and key events in
    /// sequence without awaiting each one.
    public func controlSender() -> (@Sendable (Data) -> Void)? {
        guard let channel = controlChannel else { return nil }
        return { data in
            NetworkTrafficMeter.shared.recordSent(data.count)
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            channel.writeAndFlush(buffer, promise: nil)
        }
    }

    /// Bytes the device sends back over the control socket (clipboard, acks), or
    /// nil if control isn't enabled. Parse with `ScrcpyDeviceMessageDecoder`.
    public func controlIncoming() -> AsyncStream<Data>? { controlIncomingStream }

    /// Re-shape the control socket's throwing stream as a non-throwing one: the
    /// control socket dropping is not a session failure the way the video
    /// socket's is, so it finishes rather than throwing.
    private func adoptControlIncoming(_ source: AsyncThrowingStream<Data, Error>) {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        controlIncomingStream = stream
        controlIncomingContinuation = continuation
        Task {
            do {
                for try await chunk in source { continuation.yield(chunk) }
            } catch {
                // Fall through: the stream ends either way.
            }
            continuation.finish()
        }
    }
}

/// Funnels one socket's inbound bytes into an `AsyncThrowingStream`, and decides
/// whether the device side ever really showed up.
///
/// Every path that settles `ready` — a byte, an EOF, an error, the timeout —
/// runs on this channel's own event loop, which is single-threaded. That is the
/// whole reason the timeout lives here rather than beside the `await`: it needs
/// to be serialized against the other three, because an unfulfilled NIO promise
/// traps when it deinits and a double-fulfilled one traps immediately.
private final class ScrcpySocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let firstByteWithin: TimeAmount?
    private var ready: EventLoopPromise<Void>?

    init(
        continuation: AsyncThrowingStream<Data, Error>.Continuation,
        ready: EventLoopPromise<Void>?,
        firstByteWithin: TimeAmount?
    ) {
        self.continuation = continuation
        self.ready = ready
        self.firstByteWithin = firstByteWithin
    }

    /// Start the clock on connect rather than on `handlerAdded`, so the wait
    /// measures the device's silence and not the pipeline's setup.
    func channelActive(context: ChannelHandlerContext) {
        guard let firstByteWithin else { return }
        context.eventLoop.scheduleTask(in: firstByteWithin) { [weak self] in
            guard let self, let pending = ready else { return }
            ready = nil
            pending.fail(ScrcpyTransport.TransportError.deviceSideNotReady)
        }
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        guard buffer.readableBytes > 0 else { return }
        let bytes = Data(buffer.readableBytesView)
        NetworkTrafficMeter.shared.recordReceived(bytes.count)
        continuation.yield(bytes)
        ready?.succeed(())
        ready = nil
    }

    /// An EOF with no byte before it is `adb forward` accepting for a server
    /// that is not listening yet — the caller's cue to retry.
    func channelInactive(context: ChannelHandlerContext) {
        ready?.fail(ScrcpyTransport.TransportError.deviceSideNotReady)
        ready = nil
        continuation.finish()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        ready?.fail(error)
        ready = nil
        continuation.finish(throwing: error)
        context.close(promise: nil)
    }
}
