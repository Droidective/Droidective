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
        case performance
        /// `/proc/net/dev` throughput. Its own topic rather than a field on
        /// `performance`, because the Network Speed screen samples while
        /// nothing is being recorded and Performance deliberately does not.
        case netspeed
        /// A shell on a pseudo-terminal. The first two-way topic: the
        /// subscription carries the shell's output out and the client's
        /// keystrokes back in, which is why `Operation` has more than
        /// subscribe and unsubscribe.
        case pty
    }

    // MARK: client → server

    public struct Command: Codable, Equatable, Sendable {
        public enum Operation: String, Codable, Sendable {
            case subscribe
            case unsubscribe
            /// Keystrokes into an interactive subscription. Base64, and
            /// deliberately unacknowledged — a terminal that answered every
            /// keypress would spend most of a paste talking about itself.
            case write
            /// The window changed. Its own operation rather than a control
            /// sequence inside `write`, because it is an ioctl on the terminal
            /// rather than anything the shell reads.
            case resize
        }
        public let op: Operation
        /// Client-chosen correlation id. Every event carries it back, which is
        /// what makes one socket able to serve many streams.
        public let id: Int
        /// Required for `subscribe`; ignored for everything else — the id alone
        /// identifies which subscription is meant.
        public let topic: Topic?
        public let params: Params?

        public struct Params: Codable, Equatable, Sendable {
            public let serial: String?
            public let filter: String?
            /// The app whose FPS and memory to sample, for `performance`.
            /// Absent means device-wide figures only.
            public let packageId: String?
            /// Whether to add the per-process CPU/RAM table. Two extra
            /// `dumpsys` calls per sample, so it is asked for rather than
            /// assumed.
            public let processes: Bool?
            /// Base64 keystrokes, for `write`.
            ///
            /// Base64 rather than a JSON string because these are *bytes*: a
            /// terminal's input is whatever the keyboard produced, including
            /// the control codes a JSON string cannot carry, and a paste can
            /// hold anything. The same reasoning runs the other way for output
            /// — see `PtyChunkPayload`.
            public let data: String?
            /// The new window, for `resize`. Both or neither: half a size is
            /// not a size.
            public let columns: Int?
            public let rows: Int?

            public init(
                serial: String? = nil, filter: String? = nil,
                packageId: String? = nil, processes: Bool? = nil,
                data: String? = nil, columns: Int? = nil, rows: Int? = nil
            ) {
                self.serial = serial
                self.filter = filter
                self.packageId = packageId
                self.processes = processes
                self.data = data
                self.columns = columns
                self.rows = rows
            }

            public var wantsProcesses: Bool { processes ?? false }

            /// The decoded keystrokes, or nil if `data` is absent or not
            /// base64. One place decides, so validation and the write itself
            /// cannot disagree about what arrived.
            public var bytes: Data? {
                guard let data, !data.isEmpty else { return nil }
                return Data(base64Encoded: data)
            }

            /// The requested window, clamped by `PtySize`, or nil unless both
            /// dimensions are present.
            public var size: PtySize? {
                guard let columns, let rows else { return nil }
                return PtySize(columns: columns, rows: rows)
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
        /// The shell exited. Its own reason because the terminal pane says so
        /// in the tab rather than treating it as a fault — typing `exit` is how
        /// a terminal is meant to end.
        case processExited = "process_exited"
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

    /// Why a command was refused, before it reached anything.
    public enum CommandError: String, Sendable {
        case duplicateID = "duplicate_id"
        case missingTopic = "missing_topic"
        case missingSerial = "missing_serial"
        case unknownSubscription = "unknown_subscription"
        case notInteractive = "not_interactive"
        case missingData = "missing_data"
        case invalidData = "invalid_data"
        case missingSize = "missing_size"

        public var message: String {
            switch self {
            case .duplicateID: return "That subscription id is already in use."
            case .missingTopic: return "subscribe needs a topic."
            case .missingSerial: return "That topic needs a device serial."
            case .unknownSubscription: return "There is no subscription with that id."
            case .notInteractive: return "That subscription does not take input."
            case .missingData: return "write needs base64 data."
            case .invalidData: return "write's data is not base64."
            case .missingSize: return "resize needs both columns and rows."
            }
        }
    }

    /// Validates a command against the live subscriptions. Pure, so the rules
    /// are tested without a socket.
    ///
    /// Takes the topics rather than only the ids because `write` and `resize`
    /// are answerable only against what a subscription *is*: sending keystrokes
    /// to a logcat stream is a client bug worth naming, not something to
    /// quietly discard.
    public static func validate(
        _ command: Command, active: [Int: Topic]
    ) -> CommandError? {
        switch command.op {
        case .unsubscribe:
            // Tearing down an unknown id is deliberately not an error: a client
            // racing its own teardown against an `ended` event would otherwise
            // see a spurious failure for doing the right thing.
            return nil
        case .subscribe:
            guard let topic = command.topic else { return .missingTopic }
            guard active[command.id] == nil else { return .duplicateID }
            if topic.needsSerial, command.params?.serial?.isEmpty ?? true {
                return .missingSerial
            }
            return nil
        case .write:
            if let error = interactive(command.id, active) { return error }
            guard let encoded = command.params?.data, !encoded.isEmpty else {
                return .missingData
            }
            guard command.params?.bytes != nil else { return .invalidData }
            return nil
        case .resize:
            if let error = interactive(command.id, active) { return error }
            guard command.params?.size != nil else { return .missingSize }
            return nil
        }
    }

    /// Whether `id` names a subscription that takes input.
    ///
    /// An unknown id *is* an error here, unlike `unsubscribe`. The same race
    /// exists — a keystroke can arrive just after a shell exited — but a write
    /// that lands nowhere because the client used the wrong id is a bug that
    /// otherwise presents as a terminal that ignores the keyboard. A client
    /// that has already seen `ended` for the id knows to ignore the answer.
    private static func interactive(_ id: Int, _ active: [Int: Topic]) -> CommandError? {
        guard let topic = active[id] else { return .unknownSubscription }
        return topic.acceptsInput ? nil : .notInteractive
    }
}

extension StreamProtocol.Topic {
    /// Whether the topic is scoped to one device. `devices` is host-wide — it
    /// *is* the list of devices — so it takes no serial.
    ///
    /// `pty` is host-wide too, and that is a decision rather than an oversight:
    /// a shell runs on the *host*, and a serial only exports `ANDROID_SERIAL`
    /// into it. A terminal must open with no device connected — which is when
    /// someone most wants one.
    public var needsSerial: Bool {
        switch self {
        case .devices, .pty: return false
        case .logcat, .performance, .netspeed: return true
        }
    }

    /// Whether the client may send into the subscription.
    ///
    /// Only `pty`: every other topic is something being observed, and a `write`
    /// against one has no meaning to fall back on.
    public var acceptsInput: Bool {
        switch self {
        case .pty: return true
        case .devices, .logcat, .performance, .netspeed: return false
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
    /// `performance` and `netspeed` are increments for the same reason
    /// `logcat` is: each sample is a point on a chart, and a client
    /// accumulating a history needs every one of them. Treating one as a
    /// snapshot would silently drop the middle of a graph, which is the one
    /// thing a graph must not do.
    ///
    /// `pty` is the strongest increment of the lot: terminal output is a byte
    /// stream where a discarded chunk can be half an escape sequence, so
    /// everything after it renders wrong. Chunks concatenate losslessly, which
    /// is why a batch of them is safe and a replaced one would not be.
    public var isSnapshot: Bool {
        switch self {
        case .devices: return true
        case .logcat, .performance, .netspeed, .pty: return false
        }
    }
}
