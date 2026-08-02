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

        if let error = StreamProtocol.validate(command, activeIDs: Set(subscriptions.keys)) {
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
        }
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
        subscriptions[id] = Subscription(
            topic: topic, serial: command.params?.serial,
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
        }
    }

    private func end(
        _ id: Int, reason: StreamProtocol.EndReason, notify: Bool = true
    ) async {
        guard let subscription = subscriptions.removeValue(forKey: id) else { return }
        subscription.pump?.cancel()
        // ADBKit kills the adb child on task cancellation, but the streamer
        // owns the process, so it needs telling too.
        if subscription.topic == .logcat, let serial = subscription.serial {
            await source.stopLogcat(serial: serial)
        }
        if notify {
            await sink.send(
                StreamFrame.encode(
                    StreamProtocol.Event<LogLinePayload>.ended(id: id, reason: reason)))
        }
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

    public init(monitor: DeviceMonitor, streamer: LogcatStreamer) {
        self.monitor = monitor
        self.streamer = streamer
    }

    public func devices() async -> AsyncStream<[Device]> { await monitor.updates() }

    public func logcat(serial: String) async throws -> AsyncStream<[LogLine]> {
        try await streamer.start(serial: serial, filters: LogcatFilters())
    }

    public func stopLogcat(serial: String) async { await streamer.stop() }
}
