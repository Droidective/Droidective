import ADBKit
import Foundation

/// Where a session's frames go. A protocol so the whole subscription lifecycle
/// is testable without a socket — the socket is exercised separately.
public protocol StreamSink: Sendable {
    func send(_ text: String) async
    func close() async
}

/// What a subscription needs from the rest of the app, injected so the tests
/// drive scripted streams instead of needing a device.
public protocol StreamSource: Sendable {
    func devices() async -> AsyncStream<[Device]>
    func logcat(serial: String) async throws -> AsyncStream<[LogLine]>
    /// Called when a logcat subscription ends, so the underlying adb child is
    /// torn down rather than left running.
    func stopLogcat(serial: String) async
    /// Repeated performance samples until the stream is cancelled. Polling
    /// rather than pushing, because that is what the device supports —
    /// `PerformanceService` reads `/proc` and `dumpsys` on a timer.
    func performance(
        serial: String, packageId: String?, includeProcesses: Bool
    ) async -> AsyncStream<PerformanceService.PerfPoll>
    /// Repeated `/proc/net/dev` samples. Polling for the same reason
    /// `performance` is: the counters are cumulative and throughput is the
    /// difference between two reads.
    func netspeed(serial: String) async -> AsyncStream<NetSample>
    /// Everything the Reactotron relay sees, from the moment it is listening.
    ///
    /// Starting the relay is part of subscribing: a client that asked for the
    /// topic wants the relay up, and a separate "start" call would let the two
    /// disagree about whether it is. Throws when the port is taken, which is the
    /// one failure worth a message rather than an empty feed.
    func reactotron() async throws -> AsyncStream<ReactotronRelay.Event>
    /// Called when the last `reactotron` subscription ends, so the relay stops
    /// listening rather than holding port 9090 for nobody.
    func stopReactotron() async
    /// Starts a shell on a pseudo-terminal. `serial` only scopes the shell's
    /// `ANDROID_SERIAL`; a terminal opens with no device connected.
    ///
    /// Throws rather than returning an optional so the reason reaches the
    /// client: on Windows there is no pty at all, and "your terminal did not
    /// open" is worth far less than being told why.
    func openPty(serial: String?, size: PtySize) throws -> any PtyChannel

    /// A mirror for one device, not yet brought up.
    ///
    /// Throws when the pieces a mirror needs are missing — scrcpy's server jar
    /// above all — so that arrives as a `failed` with a reason rather than as a
    /// subscription that never produces a frame. `ScrcpySession.start()` is the
    /// slow half and stays the caller's to run.
    func openMirror(serial: String, quality: MirrorQuality) async throws -> ScrcpySession
}

/// One WebSocket connection's worth of subscriptions.
///
/// An actor because a connection is genuinely concurrent: producer tasks push
/// items in while the client sends commands and the flusher awaits the socket.
public actor StreamSession {
    /// Items held per subscription before the oldest start being discarded.
    ///
    /// Sized for a chatty logcat: `LogcatStreamer` flushes every 300 ms, and a
    /// busy device produces low thousands of lines a second, so this is a few
    /// seconds of slack for a stalled client before a gap is reported. Bounded
    /// is the point — the number only decides how much stall is invisible.
    public static let defaultCapacity = 4096

    private struct Subscription {
        let topic: StreamProtocol.Topic
        let serial: String?
        /// The shell, for a `pty` subscription. Where a write and a resize go,
        /// and what has to be hung up when the subscription ends.
        let pty: (any PtyChannel)?
        /// The mirror, for a `mirror` subscription. Where a control message
        /// goes, and what has to be stopped — and *awaited* — when the
        /// subscription ends, or its `adb forward` outlives the daemon.
        let mirror: ScrcpySession?
        var buffer: StreamBuffer<Data>
        /// The newest unsent snapshot, for a `isSnapshot` topic. Kept apart
        /// from `buffer` because a snapshot replaces rather than accumulates —
        /// and because an *empty* one still has to be sent.
        var pendingSnapshot: [Data]?
        var pump: Task<Void, Never>?
        var flushing = false

        var hasWork: Bool {
            topic.isSnapshot ? pendingSnapshot != nil : !buffer.isEmpty
        }
    }

    private let sink: any StreamSink
    private let source: any StreamSource
    private let capacity: Int
    private var subscriptions: [Int: Subscription] = [:]
    private var closed = false

    public init(
        sink: any StreamSink, source: any StreamSource,
        capacity: Int = StreamSession.defaultCapacity
    ) {
        self.sink = sink
        self.source = source
        self.capacity = capacity
    }

    // MARK: commands

    /// Handles one client frame. Malformed input is answered, never fatal — a
    /// buggy client must not be able to take the daemon down.
    public func handle(text: String) async {
        guard !closed else { return }
        guard let data = text.data(using: .utf8),
              let command = try? JSONDecoder().decode(StreamProtocol.Command.self, from: data)
        else {
            await sink.send(
                StreamFrame.encode(
                    StreamProtocol.Event<LogLinePayload>.failed(
                        id: 0, message: "malformed command")))
            return
        }

        if let error = StreamProtocol.validate(command, active: activeTopics) {
            await sink.send(
                StreamFrame.encode(
                    StreamProtocol.Event<LogLinePayload>.failed(
                        id: command.id, message: error.message)))
            return
        }

        switch command.op {
        case .subscribe:
            await subscribe(command)
        case .unsubscribe:
            await end(command.id, reason: .unsubscribed)
        case .write:
            // Validation established both the subscription and the bytes; the
            // guard is what makes that a compile-time fact rather than a
            // comment. Unacknowledged on purpose — see `Operation.write`.
            guard let bytes = command.params?.bytes else { return }
            let subscription = subscriptions[command.id]
            subscription?.pty?.write(bytes)
            // A control message before the mirror's control socket is up is
            // dropped inside the session, which is right: nothing is on screen
            // yet, so no tap could have been aimed at anything.
            await subscription?.mirror?.send(control: bytes)
        case .resize:
            guard let size = command.params?.size else { return }
            subscriptions[command.id]?.pty?.resize(to: size)
        }
    }

    private var activeTopics: [Int: StreamProtocol.Topic] {
        subscriptions.mapValues(\.topic)
    }

    /// Tears every subscription down. Idempotent, so a close racing an error
    /// path cannot double-cancel.
    public func shutdown(reason: StreamProtocol.EndReason = .serverStopping) async {
        guard !closed else { return }
        closed = true
        for id in subscriptions.keys {
            await end(id, reason: reason, notify: reason != .serverStopping)
        }
        await sink.close()
    }

    // MARK: subscription lifecycle

    private func subscribe(_ command: StreamProtocol.Command) async {
        guard let topic = command.topic else { return }
        let id = command.id

        // The shell is started *before* the subscription is announced. Sending
        // `subscribed` first means awaiting the sink, which yields the actor —
        // so a client that types the moment it is acknowledged could otherwise
        // reach a subscription whose shell does not exist yet, and the
        // keystrokes would go nowhere without a word.
        var channel: (any PtyChannel)?
        if topic == .pty {
            do {
                channel = try source.openPty(
                    serial: command.params?.serial,
                    size: command.params?.size ?? .standard)
            } catch {
                await sink.send(
                    StreamFrame.encode(
                        StreamProtocol.Event<LogLinePayload>.failed(
                            id: id, message: "\(error)")))
                return
            }
        }

        // The mirror is *opened* before the subscription is announced, for the
        // same reason the shell is: resolving scrcpy can fail (it is not
        // installed) and that belongs in a `failed` instead of a feed that
        // never produces a frame. Bringing it *up* — push, forward, spawn,
        // connect — is a second or two, so that happens in the pump and the
        // client gets its acknowledgement immediately.
        var mirror: ScrcpySession?
        if topic == .mirror {
            guard let serial = command.params?.serial else { return }
            do {
                mirror = try await source.openMirror(
                    serial: serial, quality: command.params?.mirrorQuality ?? .deviceDefault)
            } catch {
                await sink.send(
                    StreamFrame.encode(
                        StreamProtocol.Event<LogLinePayload>.failed(
                            id: id, message: "\(error)")))
                return
            }
        }

        subscriptions[id] = Subscription(
            topic: topic, serial: command.params?.serial, pty: channel, mirror: mirror,
            buffer: StreamBuffer(capacity: capacity))
        await sink.send(
            StreamFrame.encode(StreamProtocol.Event<LogLinePayload>.subscribed(id: id)))

        switch topic {
        case .devices:
            let stream = await source.devices()
            subscriptions[id]?.pump = Task { [weak self] in
                for await devices in stream {
                    await self?.enqueue(id: id, items: devices.compactMap { try? DaemonProtocol.encode($0) })
                }
                await self?.end(id, reason: .deviceDisconnected)
            }
        case .logcat:
            guard let serial = command.params?.serial else { return }
            do {
                let stream = try await source.logcat(serial: serial)
                subscriptions[id]?.pump = Task { [weak self] in
                    for await lines in stream {
                        await self?.enqueue(
                            id: id,
                            items: lines.compactMap { try? DaemonProtocol.encode(LogLinePayload($0)) })
                    }
                    await self?.end(id, reason: .deviceDisconnected)
                }
            } catch {
                // adb refused (device gone, unauthorised). Report it and drop
                // the subscription rather than leaving a dead id registered.
                subscriptions[id] = nil
                await sink.send(
                    StreamFrame.encode(
                        StreamProtocol.Event<LogLinePayload>.failed(
                            id: id, message: "\(error)")))
            }
        case .netspeed:
            guard let serial = command.params?.serial else { return }
            let stream = await source.netspeed(serial: serial)
            subscriptions[id]?.pump = Task { [weak self] in
                for await sample in stream {
                    await self?.enqueue(
                        id: id,
                        items: [try? DaemonProtocol.encode(NetSamplePayload(sample))]
                            .compactMap { $0 })
                }
                await self?.end(id, reason: .deviceDisconnected)
            }

        case .performance:
            guard let serial = command.params?.serial else { return }
            let stream = await source.performance(
                serial: serial, packageId: command.params?.packageId,
                includeProcesses: command.params?.wantsProcesses ?? false)
            subscriptions[id]?.pump = Task { [weak self] in
                for await poll in stream {
                    await self?.enqueue(
                        id: id,
                        items: [try? DaemonProtocol.encode(PerfSamplePayload(poll))]
                            .compactMap { $0 })
                }
                await self?.end(id, reason: .deviceDisconnected)
            }

        case .reactotron:
            do {
                let stream = try await source.reactotron()
                subscriptions[id]?.pump = Task { [weak self] in
                    for await event in stream {
                        await self?.enqueue(
                            id: id,
                            items: [try? DaemonProtocol.encode(ReactotronEventPayload(event))]
                                .compactMap { $0 })
                    }
                    await self?.end(id, reason: .serverStopping)
                }
            } catch {
                // The port being taken is the common one, and it is actionable:
                // another Reactotron is running. Reported rather than left as a
                // feed that never produces anything.
                subscriptions[id] = nil
                await sink.send(
                    StreamFrame.encode(
                        StreamProtocol.Event<LogLinePayload>.failed(
                            id: id, message: "\(error)")))
            }

        case .pty:
            guard let channel else { return }
            let stream = channel.output()
            subscriptions[id]?.pump = Task { [weak self] in
                for await chunk in stream {
                    await self?.enqueue(
                        id: id,
                        items: [try? DaemonProtocol.encode(PtyChunkPayload(chunk))]
                            .compactMap { $0 })
                }
                // The stream finishing *is* the shell exiting — including the
                // case where it never started, because a failed `exec` reaches
                // the parent as the terminal hanging up rather than as a throw.
                await self?.end(id, reason: .processExited)
            }

        case .mirror:
            guard let mirror else { return }
            subscriptions[id]?.pump = Task { [weak self] in
                do {
                    for try await frame in try await mirror.start() {
                        await self?.enqueue(
                            id: id,
                            items: [try? DaemonProtocol.encode(frame)].compactMap { $0 })
                    }
                    await self?.end(id, reason: .deviceDisconnected)
                } catch is CancellationError {
                    // The subscription was torn down under us; `end` has
                    // already run and said so.
                    return
                } catch {
                    // The only topic whose stream can break mid-flight rather
                    // than just stop: the device rejected the server, or the
                    // stream is a codec we cannot hand a `VideoDecoder`. Either
                    // way the reason is the whole value of the event.
                    await self?.fail(id, message: "\(error)")
                }
            }
        }
    }

    private func end(
        _ id: Int, reason: StreamProtocol.EndReason, notify: Bool = true
    ) async {
        guard let subscription = subscriptions.removeValue(forKey: id) else { return }
        subscription.pump?.cancel()
        // Cancelling the pump only stops the reading; the shell is a child
        // process and has to be hung up, or every closed tab leaks one.
        subscription.pty?.terminate()
        // Awaited, not fired off, and this is the one that bites: the mirror
        // owns an `adb forward` that only its own teardown removes, and adb's
        // server is long-lived, so a tunnel left behind here survives the
        // daemon. One leaked listening socket per closed tile.
        await subscription.mirror?.stop()
        // ADBKit kills the adb child on task cancellation, but the streamer
        // owns the process, so it needs telling too.
        if subscription.topic == .logcat, let serial = subscription.serial {
            await source.stopLogcat(serial: serial)
        }
        // The relay is host-wide and shared, so it stops only when the last
        // subscriber goes — a second window watching the timeline must not have
        // its feed cut by the first one closing.
        if subscription.topic == .reactotron,
           !subscriptions.values.contains(where: { $0.topic == .reactotron }) {
            await source.stopReactotron()
        }
        if notify {
            await sink.send(
                StreamFrame.encode(
                    StreamProtocol.Event<LogLinePayload>.ended(id: id, reason: reason)))
        }
    }

    /// A subscription that broke after it had started.
    ///
    /// `ended` says a stream stopped; this says it failed, and the message is
    /// the only place the client learns why. The teardown is the same one an
    /// orderly end does — the `reason` is not sent, which is what `notify:
    /// false` means here.
    private func fail(_ id: Int, message: String) async {
        guard subscriptions[id] != nil else { return }
        await end(id, reason: .deviceDisconnected, notify: false)
        await sink.send(
            StreamFrame.encode(
                StreamProtocol.Event<LogLinePayload>.failed(id: id, message: message)))
    }

    // MARK: the drop-oldest path

    private func enqueue(id: Int, items: [Data]) async {
        guard let subscription = subscriptions[id] else { return }
        if subscription.topic.isSnapshot {
            // Replace, and allow empty: the newest list is the only one worth
            // sending, and an empty one is how "everything unplugged" is said.
            subscriptions[id]?.pendingSnapshot = items
        } else {
            guard !items.isEmpty else { return }
            subscriptions[id]?.buffer.append(contentsOf: items)
        }
        await flushIfIdle(id)
    }

    /// Sends one batch at a time. While a send is in flight the producer keeps
    /// appending, and the buffer discards its oldest — which is exactly where
    /// the drop policy earns its keep: a stalled client costs a bounded amount
    /// of memory and an honest gap, not unbounded growth.
    private func flushIfIdle(_ id: Int) async {
        guard let subscription = subscriptions[id], !subscription.flushing else { return }
        subscriptions[id]?.flushing = true
        defer { subscriptions[id]?.flushing = false }

        while let current = subscriptions[id], current.hasWork {
            if current.topic.isSnapshot {
                guard let snapshot = current.pendingSnapshot else { break }
                subscriptions[id]?.pendingSnapshot = nil
                await sink.send(StreamFrame.batch(id: id, items: snapshot))
                continue
            }

            var buffer = current.buffer
            let (items, dropped) = buffer.drain()
            subscriptions[id]?.buffer = buffer

            if dropped > 0 {
                await sink.send(
                    StreamFrame.encode(
                        StreamProtocol.Event<LogLinePayload>.dropped(id: id, count: dropped)))
            }
            if !items.isEmpty {
                await sink.send(StreamFrame.batch(id: id, items: items))
            }
        }
    }

    // MARK: introspection, for tests

    public var activeSubscriptionIDs: Set<Int> { Set(subscriptions.keys) }
}

/// The production source: ADBKit.
public struct LiveStreamSource: StreamSource {
    private let monitor: DeviceMonitor
    private let streamer: LogcatStreamer
    private let performanceService: PerformanceService
    private let networkService: NetworkSpeedService
    private let relay: ReactotronRelay
    private let client: AdbClient
    private let locator: ToolLocator
    /// The app's bundled `scrcpy-server`, when it passed one.
    private let bundledScrcpyServer: String?

    public init(
        monitor: DeviceMonitor, streamer: LogcatStreamer, performance: PerformanceService,
        networkSpeed: NetworkSpeedService, reactotron: ReactotronRelay,
        client: AdbClient, locator: ToolLocator,
        bundledScrcpyServer: String? = nil
    ) {
        self.monitor = monitor
        self.streamer = streamer
        performanceService = performance
        networkService = networkSpeed
        relay = reactotron
        self.client = client
        self.locator = locator
        self.bundledScrcpyServer = bundledScrcpyServer
    }

    public func devices() async -> AsyncStream<[Device]> { await monitor.updates() }

    public func logcat(serial: String) async throws -> AsyncStream<[LogLine]> {
        try await streamer.start(serial: serial, filters: LogcatFilters())
    }

    public func stopLogcat(serial: String) async { await streamer.stop() }

    /// One sample per second, which is what the Mac's monitor uses: fast
    /// enough that a spike is visible, slow enough that the sampling itself
    /// does not become the load being measured.
    public static let performanceInterval = Duration.seconds(1)

    public func performance(
        serial: String, packageId: String?, includeProcesses: Bool
    ) async -> AsyncStream<PerformanceService.PerfPoll> {
        let service = performanceService
        return AsyncStream { continuation in
            let task = Task {
                // Forget any baseline from a previous subscription: a delta
                // against a reading from ten minutes ago is not a spike, it is
                // an artefact.
                await service.reset()
                while !Task.isCancelled {
                    let poll = await service.poll(
                        serial: serial, packageId: packageId,
                        includeProcesses: includeProcesses)
                    guard !Task.isCancelled else { break }
                    continuation.yield(poll)
                    try? await Task.sleep(for: Self.performanceInterval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One sample a second, matching the Mac's `NetworkView`.
    ///
    /// The first poll after a reset yields nothing — `NetworkSpeedService`
    /// needs two reads to have a delta — so a subscriber sees its first sample
    /// one interval in, which is the honest answer rather than a fabricated
    /// zero.
    public func netspeed(serial: String) async -> AsyncStream<NetSample> {
        let service = networkService
        return AsyncStream { continuation in
            let task = Task {
                await service.reset()
                while !Task.isCancelled {
                    if let sample = await service.poll(serial: serial) {
                        guard !Task.isCancelled else { break }
                        continuation.yield(sample)
                    }
                    try? await Task.sleep(for: Self.performanceInterval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The relay's events, with the relay started if it was not.
    ///
    /// The stream is taken *before* `start()` so a subscriber cannot miss the
    /// `listening` event it is waiting for — the other way round, a fast bind
    /// emits into no listeners and the UI never learns the port.
    public func reactotron() async throws -> AsyncStream<ReactotronRelay.Event> {
        let stream = await relay.events()
        try await relay.start()
        return stream
    }

    public func stopReactotron() async {
        await relay.stop()
    }

    /// A login shell, matching the Mac's terminal: `-l`, so the rc files that
    /// define someone's aliases and PATH are read.
    public func openPty(serial: String?, size: PtySize) throws -> any PtyChannel {
        #if os(Windows)
        // ConPTY is a different API rather than a variation on this one, so the
        // subsystem is absent rather than stubbed and this is where a client
        // finds out. See `Pty`.
        throw PtyError.unsupportedPlatform
        #else
        return try Pty.spawn(environment: Pty.childEnvironment(serial: serial), size: size)
        #endif
    }

    /// Errors a mirror can hit before it has a socket to fail on.
    public enum MirrorError: Error, CustomStringConvertible {
        case scrcpyServerMissing

        public var description: String {
            switch self {
            case .scrcpyServerMissing:
                // Named rather than generic, because it is the one thing the
                // user can act on. The app normally passes its own bundled
                // jar, so reaching this means either a damaged install or a
                // daemon someone started by hand without one.
                return """
                    scrcpy's server was not found. The app bundles it, so this \
                    usually means a damaged install; a daemon started by hand \
                    needs either --scrcpy-server or an installed scrcpy.
                    """
            }
        }
    }

    /// The bundled jar the app shipped, or an installed scrcpy's.
    ///
    /// The bundle wins, and does not fall back: if the app said where it put
    /// the jar and it is not there, quietly mirroring through some other
    /// scrcpy the machine happens to have is a version mismatch waiting to
    /// happen — the server aborts on one. A developer running the daemon by
    /// hand passes no path and gets the installed one.
    private func scrcpyServer() async -> ScrcpyServerInfo? {
        if let bundledScrcpyServer {
            let exists = FileManager.default.isReadableFile(atPath: bundledScrcpyServer)
            return exists ? ScrcpyServerLocator.bundled(jarPath: bundledScrcpyServer) : nil
        }
        return await ScrcpyServerLocator.resolve(locator: locator)
    }

    public func openMirror(serial: String, quality: MirrorQuality) async throws -> ScrcpySession {
        guard let server = await scrcpyServer() else {
            throw MirrorError.scrcpyServerMissing
        }
        return ScrcpySession(
            adb: client,
            config: .init(
                serial: serial,
                serverVersion: server.version,
                localJarPath: server.jarPath,
                // The quality is the client's to choose: the Mirror Wall steps
                // it down as tiles are added, and only the client knows how
                // many it is drawing.
                params: ScrcpyServerParams(
                    scid: ScrcpyServerParams.randomSCID(),
                    maxSize: quality.maxSize,
                    maxFps: quality.maxFps)))
    }
}
