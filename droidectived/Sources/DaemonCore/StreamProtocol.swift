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
        /// Everything the Reactotron relay sees: clients connecting, their
        /// commands, and their going away. Host-scoped — the relay listens on
        /// *this* machine and a device reaches it through `adb reverse`.
        case reactotron
        /// A shell on a pseudo-terminal. The first two-way topic: the
        /// subscription carries the shell's output out and the client's
        /// keystrokes back in, which is why `Operation` has more than
        /// subscribe and unsubscribe.
        case pty
        /// A device's screen, as the H.264 frames scrcpy produces, with the
        /// client's taps and keys going back the other way.
        ///
        /// The second two-way topic, and the only one whose payload is a media
        /// stream. The frames are Annex-B and the webview decodes them — see
        /// `MirrorFramePayload` and backlog 25's step 0 in
        /// `docs/desktop-parity.md`.
        case mirror
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
            /// One app's process id, for `logcat`. Becomes `adb logcat --pid`,
            /// so the device filters at the source and the ring buffer holds
            /// only that app's lines — filtering a mixed buffer client-side
            /// would let a chatty neighbour evict the lines being looked for.
            ///
            /// A *pid*, not a package: the client resolves it through
            /// `/v1/logcat/pid` because it is the one that knows when to wait
            /// for an app that is not running yet and when a relaunch has
            /// moved it. Absent means the whole device.
            public let pid: Int?
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
            /// scrcpy's `max_size` and `max_fps` for a `mirror` subscription.
            ///
            /// The client resolves these, because it is the one that knows how
            /// many tiles it is drawing — the Mirror Wall steps quality down as
            /// tiles are added, and the daemon has no view to measure. Absent
            /// means scrcpy's own defaults, which is the single full mirror.
            public let maxSize: Int?
            public let maxFps: Int?

            public init(
                serial: String? = nil, pid: Int? = nil,
                packageId: String? = nil, processes: Bool? = nil,
                data: String? = nil, columns: Int? = nil, rows: Int? = nil,
                maxSize: Int? = nil, maxFps: Int? = nil
            ) {
                self.serial = serial
                self.pid = pid
                self.packageId = packageId
                self.processes = processes
                self.data = data
                self.columns = columns
                self.rows = rows
                self.maxSize = maxSize
                self.maxFps = maxFps
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

            /// The stream quality a mirror subscription asked for, clamped.
            ///
            /// Clamped rather than trusted: these become arguments to a process
            /// on the device, and a negative or absurd value is a scrcpy server
            /// that refuses to start — which reaches the user as a mirror that
            /// never produces a frame rather than as the bad number it was.
            public var mirrorQuality: MirrorQuality {
                MirrorQuality(
                    maxSize: MirrorQuality.clampSize(maxSize),
                    maxFps: MirrorQuality.clampFps(maxFps))
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
            if let error = check(command.id, active, \.acceptsInput) { return error }
            guard let encoded = command.params?.data, !encoded.isEmpty else {
                return .missingData
            }
            guard command.params?.bytes != nil else { return .invalidData }
            return nil
        case .resize:
            if let error = check(command.id, active, \.acceptsResize) { return error }
            guard command.params?.size != nil else { return .missingSize }
            return nil
        }
    }

    /// Whether `id` names a subscription that accepts the operation, by the
    /// trait that decides it.
    ///
    /// An unknown id *is* an error here, unlike `unsubscribe`. The same race
    /// exists — a keystroke can arrive just after a shell exited — but a write
    /// that lands nowhere because the client used the wrong id is a bug that
    /// otherwise presents as a terminal that ignores the keyboard. A client
    /// that has already seen `ended` for the id knows to ignore the answer.
    private static func check(
        _ id: Int, _ active: [Int: Topic], _ trait: KeyPath<Topic, Bool>
    ) -> CommandError? {
        guard let topic = active[id] else { return .unknownSubscription }
        return topic[keyPath: trait] ? nil : .notInteractive
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
        case .devices, .pty, .reactotron: return false
        case .logcat, .performance, .netspeed, .mirror: return true
        }
    }

    /// Whether the client may send into the subscription.
    ///
    /// `pty` takes keystrokes and `mirror` takes control messages — taps, keys,
    /// a clipboard paste. Every other topic is something being observed, and a
    /// `write` against one has no meaning to fall back on.
    public var acceptsInput: Bool {
        switch self {
        case .pty, .mirror: return true
        case .devices, .logcat, .performance, .netspeed, .reactotron: return false
        }
    }

    /// Whether the client may resize it.
    ///
    /// `pty` only, and separate from `acceptsInput` for the same reason that
    /// one names a write to a logcat stream: a terminal's size is an ioctl on
    /// the tty, while a mirror's is scrcpy's own negotiation, fixed for the
    /// session. Folding the two together would let a resize on a mirror
    /// validate and then do nothing, which presents as a mirror that ignores
    /// the window.
    public var acceptsResize: Bool {
        switch self {
        case .pty: return true
        case .devices, .logcat, .performance, .netspeed, .reactotron, .mirror: return false
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
    ///
    /// `mirror` is an increment for the strongest reason of all: an H.264 delta
    /// frame is meaningless without the frames before it. That makes the drop
    /// policy load-bearing rather than incidental — a `dropped` on this topic
    /// means the client must discard frames until the next `key`, which it can
    /// always do because every keyframe carries its own parameter sets. See
    /// `MirrorStreamMapper`.
    public var isSnapshot: Bool {
        switch self {
        case .devices: return true
        case .logcat, .performance, .netspeed, .pty, .reactotron, .mirror: return false
        }
    }
}
