import Foundation

/// The multiplexed stream protocol: one WebSocket carrying every subscription,
/// rather than a socket per stream. A UI showing logcat plus device changes
/// plus performance would otherwise hold three sockets with three lifecycles.
public enum StreamProtocol {
    /// Topics a client may subscribe to. A table, so a completeness test can
    /// iterate it — the same reason the HTTP routes are one.
    public enum Topic: String, Codable, CaseIterable, Sendable {
        case devices
        case logcat
    }

    // MARK: client → server

    public struct Command: Codable, Equatable, Sendable {
        public enum Operation: String, Codable, Sendable {
            case subscribe
            case unsubscribe
        }
        public let op: Operation
        /// Client-chosen correlation id. Every event carries it back, which is
        /// what makes one socket able to serve many streams.
        public let id: Int
        /// Required for `subscribe`, ignored for `unsubscribe` — the id alone
        /// identifies what to tear down.
        public let topic: Topic?
        public let params: Params?

        public struct Params: Codable, Equatable, Sendable {
            public let serial: String?
            public let filter: String?
            public init(serial: String? = nil, filter: String? = nil) {
                self.serial = serial
                self.filter = filter
            }
        }

        public init(op: Operation, id: Int, topic: Topic? = nil, params: Params? = nil) {
            self.op = op
            self.id = id
            self.topic = topic
            self.params = params
        }
    }

    // MARK: server → client

    /// Event kinds. `dropped` is a first-class event rather than a field on
    /// `batch`, so a gap is still reported when it happens between batches.
    public enum EventKind: String, Codable, Sendable {
        case subscribed
        case batch
        case dropped
        case ended
        case failed
    }

    /// Why a subscription stopped, so the UI can distinguish "the device went
    /// away" from "you asked me to stop" without parsing prose.
    public enum EndReason: String, Codable, Sendable {
        case unsubscribed
        case deviceDisconnected = "device_disconnected"
        case serverStopping = "server_stopping"
    }

    /// A server→client frame. Generic over the payload so each topic keeps its
    /// own ADBKit model rather than everything degrading to `[String: Any]`.
    public struct Event<Payload: Codable & Sendable>: Codable, Sendable {
        public let id: Int
        public let event: EventKind
        public let items: [Payload]?
        public let count: Int?
        public let reason: EndReason?
        public let message: String?

        private init(
            id: Int, event: EventKind, items: [Payload]? = nil, count: Int? = nil,
            reason: EndReason? = nil, message: String? = nil
        ) {
            self.id = id
            self.event = event
            self.items = items
            self.count = count
            self.reason = reason
            self.message = message
        }

        public static func subscribed(id: Int) -> Self { .init(id: id, event: .subscribed) }
        public static func batch(id: Int, items: [Payload]) -> Self {
            .init(id: id, event: .batch, items: items)
        }
        /// Emitted when the bounded buffer discarded items — never silently.
        public static func dropped(id: Int, count: Int) -> Self {
            .init(id: id, event: .dropped, count: count)
        }
        public static func ended(id: Int, reason: EndReason) -> Self {
            .init(id: id, event: .ended, reason: reason)
        }
        public static func failed(id: Int, message: String) -> Self {
            .init(id: id, event: .failed, message: message)
        }
    }

    /// Why a `subscribe` was refused, before any stream exists.
    public enum SubscribeError: String, Sendable {
        case duplicateID = "duplicate_id"
        case missingTopic = "missing_topic"
        case missingSerial = "missing_serial"

        public var message: String {
            switch self {
            case .duplicateID: return "That subscription id is already in use."
            case .missingTopic: return "subscribe needs a topic."
            case .missingSerial: return "That topic needs a device serial."
            }
        }
    }

    /// Validates a command against the live subscriptions. Pure, so the rules
    /// are tested without a socket.
    public static func validate(
        _ command: Command, activeIDs: Set<Int>
    ) -> SubscribeError? {
        switch command.op {
        case .unsubscribe:
            // Tearing down an unknown id is deliberately not an error: a client
            // racing its own teardown against an `ended` event would otherwise
            // see a spurious failure for doing the right thing.
            return nil
        case .subscribe:
            guard let topic = command.topic else { return .missingTopic }
            guard !activeIDs.contains(command.id) else { return .duplicateID }
            if topic.needsSerial, command.params?.serial?.isEmpty ?? true {
                return .missingSerial
            }
            return nil
        }
    }
}

extension StreamProtocol.Topic {
    /// Whether the topic is scoped to one device. `devices` is host-wide — it
    /// *is* the list of devices — so it takes no serial.
    public var needsSerial: Bool {
        switch self {
        case .devices: return false
        case .logcat: return true
        }
    }

    /// Whether each batch is the complete current state rather than what is
    /// new since the last one.
    ///
    /// `devices` republishes the whole list; `logcat` publishes the lines that
    /// just arrived. Two things follow, and both are wrong if the distinction
    /// is ignored:
    ///
    /// - **An empty batch is meaningful for a snapshot.** "No devices are
    ///   connected" is a state a client has to be able to reach, and it is
    ///   the only way to say a device went away. For an increment, an empty
    ///   batch says nothing and is not worth a frame.
    /// - **A snapshot supersedes rather than queues.** An older device list is
    ///   worthless once a newer one exists, so an unsent one is replaced, not
    ///   buffered — which also means a snapshot topic can never emit a
    ///   `dropped` marker. A gap in a stream of complete states is not
    ///   something any client could act on.
    public var isSnapshot: Bool {
        switch self {
        case .devices: return true
        case .logcat: return false
        }
    }
}
