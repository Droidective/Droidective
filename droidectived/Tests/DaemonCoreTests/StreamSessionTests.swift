import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The subscription lifecycle, driven through the sink protocol rather than a
/// socket. The socket is proven separately; what matters here is the ordering
/// and the drop behaviour under a slow client.
@Suite struct StreamSessionTests {
    /// Records frames, and can be made deliberately slow so the producer
    /// outruns it — which is the only way to observe the drop policy.
    private actor RecordingSink: StreamSink {
        private(set) var frames: [String] = []
        private(set) var closed = false
        /// Per-send delay, which is how a slow client is simulated. A hard
        /// gate is the wrong tool: the first frame is sent from inside
        /// `handle`, which is actor-isolated, so blocking it would wedge the
        /// session before the test could ever release it.
        private var delay: Duration = .zero

        func setDelay(_ delay: Duration) { self.delay = delay }

        func send(_ text: String) async {
            if delay > .zero { try? await Task.sleep(for: delay) }
            frames.append(text)
        }

        func close() async { closed = true }

        func events() -> [String] {
            frames.compactMap { frame in
                guard let data = frame.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return object["event"] as? String
            }
        }

        /// Raw JSON strings, not parsed dictionaries: `[String: Any]` is not
        /// `Sendable` and cannot leave the actor. Callers parse with `field`.
        func rawFrames(ofEvent event: String) -> [String] {
            frames.filter { frame in
                guard let data = frame.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return false }
                return object["event"] as? String == event
            }
        }
    }

    /// A terminal without a shell.
    ///
    /// The real one is proven against a real shell in `PtyTests`; what the
    /// session layer has to get right is different — that a write reaches the
    /// terminal, that a resize does, and that ending a subscription hangs it up
    /// — and none of that needs a process.
    private final class FakeChannel: PtyChannel, @unchecked Sendable {
        private let lock = NSLock()
        private let stream: AsyncStream<Data>
        private let continuation: AsyncStream<Data>.Continuation
        private var writes: [Data] = []
        private var sizes: [PtySize] = []
        private var terminations = 0

        init() {
            (stream, continuation) = AsyncStream<Data>.makeStream()
        }

        func output() -> AsyncStream<Data> { stream }

        func write(_ data: Data) {
            lock.lock()
            writes.append(data)
            lock.unlock()
        }

        func resize(to size: PtySize) {
            lock.lock()
            sizes.append(size)
            lock.unlock()
        }

        func terminate() {
            lock.lock()
            terminations += 1
            lock.unlock()
            continuation.finish()
        }

        /// What the shell "printed".
        func emit(_ text: String) { continuation.yield(Data(text.utf8)) }
        func emit(_ bytes: [UInt8]) { continuation.yield(Data(bytes)) }
        /// The shell exited on its own, without anyone unsubscribing.
        func exit() { continuation.finish() }

        var typed: [Data] {
            lock.lock()
            defer { lock.unlock() }
            return writes
        }

        var resizes: [PtySize] {
            lock.lock()
            defer { lock.unlock() }
            return sizes
        }

        var hungUp: Int {
            lock.lock()
            defer { lock.unlock() }
            return terminations
        }
    }

    private struct ScriptedSource: StreamSource, @unchecked Sendable {
        var deviceBatches: [[Device]] = []
        var logBatches: [[LogLine]] = []
        var perfSamples: [PerformanceService.PerfPoll] = []
        var netSamples: [NetSample] = []
        var logcatError: (any Error)?
        /// Handed out by `openPty`, so a test can drive the shell it opened.
        var channel: FakeChannel?
        var ptyError: (any Error)?
        let stopped = StoppedBox()
        let ptyRequests = PtyRequestBox()

        final class PtyRequestBox: @unchecked Sendable {
            private let lock = NSLock()
            private var opens: [(serial: String?, size: PtySize)] = []
            var all: [(serial: String?, size: PtySize)] {
                lock.lock()
                defer { lock.unlock() }
                return opens
            }
            func record(_ serial: String?, _ size: PtySize) {
                lock.lock()
                opens.append((serial, size))
                lock.unlock()
            }
        }

        func openPty(serial: String?, size: PtySize) throws -> any PtyChannel {
            ptyRequests.record(serial, size)
            if let ptyError { throw ptyError }
            guard let channel else { throw PtyError.unsupportedPlatform }
            return channel
        }

        final class StoppedBox: @unchecked Sendable {
            private let lock = NSLock()
            private var serials: [String] = []
            var all: [String] {
                lock.lock()
                defer { lock.unlock() }
                return serials
            }
            func record(_ serial: String) {
                lock.lock()
                serials.append(serial)
                lock.unlock()
            }
        }

        func devices() async -> AsyncStream<[Device]> {
            let batches = deviceBatches
            return AsyncStream { continuation in
                for batch in batches { continuation.yield(batch) }
                continuation.finish()
            }
        }

        func logcat(serial: String) async throws -> AsyncStream<[LogLine]> {
            if let logcatError { throw logcatError }
            let batches = logBatches
            return AsyncStream { continuation in
                for batch in batches { continuation.yield(batch) }
                continuation.finish()
            }
        }

        func stopLogcat(serial: String) async { stopped.record(serial) }

        func netspeed(serial: String) async -> AsyncStream<NetSample> {
            let samples = netSamples
            return AsyncStream { continuation in
                for sample in samples { continuation.yield(sample) }
                continuation.finish()
            }
        }

        func performance(
            serial: String, packageId: String?, includeProcesses: Bool
        ) async -> AsyncStream<PerformanceService.PerfPoll> {
            let samples = perfSamples
            return AsyncStream { continuation in
                for sample in samples { continuation.yield(sample) }
                continuation.finish()
            }
        }
    }

    private static func device(_ serial: String) -> Device {
        Device(
            serial: serial, state: "device", model: nil, product: nil, transportId: nil,
            label: serial, isWireless: false, platform: .android)
    }

    private static func line(_ message: String) -> LogLine {
        LogLine(
            raw: message, time: "01-01 00:00:00.000", pid: "1", tid: "1",
            level: "I", tag: "T", message: message)
    }

    /// Pulls one field out of a frame, caller-side so nothing non-Sendable
    /// crosses the actor boundary.
    private func field<T>(_ key: String, of frame: String, as type: T.Type = T.self) -> T? {
        guard let data = frame.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object[key] as? T
    }

    private func itemCount(of frame: String) -> Int {
        field("items", of: frame, as: [Any].self)?.count ?? 0
    }

    /// Waits for a condition the pump task will satisfy, rather than sleeping a
    /// fixed amount — a fixed sleep is either flaky or slow.
    private func eventually(
        timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock().now + timeout
        while ContinuousClock().now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    @Test func subscribingAcknowledgesThenStreamsThenEnds() async {
        let sink = RecordingSink()
        let source = ScriptedSource(deviceBatches: [[Self.device("emulator-5554")]])
        let session = StreamSession(sink: sink, source: source)

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"devices"}"#)

        #expect(await eventually { await sink.events().contains("ended") })
        // The order is the contract: ack, then data, then a typed end.
        #expect(await sink.events() == ["subscribed", "batch", "ended"])
        let ended = await sink.rawFrames(ofEvent: "ended").first
        #expect(ended.flatMap { field("reason", of: $0, as: String.self) } == "device_disconnected")
    }

    @Test func logcatLinesGoOutAsTheDTONotTheInternalModel() async {
        let sink = RecordingSink()
        let source = ScriptedSource(logBatches: [[Self.line("hello")]])
        let session = StreamSession(sink: sink, source: source)

        await session.handle(
            text: #"{"op":"subscribe","id":4,"topic":"logcat","params":{"serial":"R58M"}}"#)
        #expect(await eventually { await sink.events().contains("batch") })

        let batch = try! #require(await sink.rawFrames(ofEvent: "batch").first)
        #expect(batch.contains(#""message":"hello""#))
        // `id` and `searchKey` are internal rendering concerns and must not leak.
        #expect(!batch.contains("searchKey"))
        #expect(!batch.contains(#""id":"#) || batch.contains(#""id":4"#))
    }

    @Test func performanceSamplesGoOutAsTheDTONotTheInternalModel() async {
        var poll = PerformanceService.PerfPoll()
        poll.cores = [CpuCoreLoad(core: -1, usagePercent: 42.5), CpuCoreLoad(core: 0, usagePercent: 12)]
        poll.ramTotalKb = 8_000_000
        poll.ramUsedKb = 3_200_000
        poll.appFps = FpsStat(fps: 58.5, jankPercent: 4)
        poll.processes = [ProcessLoad(pid: 99, name: "com.example.app", cpuPercent: 7, pssKb: 120)]

        let sink = RecordingSink()
        let source = ScriptedSource(perfSamples: [poll])
        let session = StreamSession(sink: sink, source: source)

        await session.handle(
            text: #"{"op":"subscribe","id":7,"topic":"performance","params":{"serial":"R58M"}}"#)
        #expect(await eventually { await sink.events().contains("batch") })

        let batch = try! #require(await sink.rawFrames(ofEvent: "batch").first)
        // The core's own label travels: -1 is "All cores", and a client
        // re-deriving that would eventually name it something else.
        #expect(batch.contains(#""label":"All cores""#))
        #expect(batch.contains(#""appFps":58.5"#))
        #expect(batch.contains(#""appJankPercent":4"#))
        #expect(batch.contains(#""ramUsedKb":3200000"#))
        #expect(batch.contains(#""name":"com.example.app""#))
    }

    @Test func performanceNeedsASerialLikeLogcatDoes() async {
        // Device-wide figures still come from one device; a subscription with
        // no serial has nothing to sample.
        let sink = RecordingSink()
        let session = StreamSession(sink: sink, source: ScriptedSource())

        await session.handle(text: #"{"op":"subscribe","id":8,"topic":"performance"}"#)

        #expect(await sink.events() == ["failed"])
        let failed = try! #require(await sink.rawFrames(ofEvent: "failed").first)
        #expect(failed.contains("device serial"))
    }

    @Test func everyTopicDeclaresWhetherItNeedsASerialAndWhetherItSnapshots() {
        // The registry-invariant shape: a topic added to the enum without
        // being classified would take the default of whichever switch arm it
        // fell into, and the two questions have opposite right answers.
        for topic in StreamProtocol.Topic.allCases {
            switch topic {
            case .devices:
                #expect(!topic.needsSerial)
                #expect(topic.isSnapshot)
            case .pty:
                // Host-wide: a shell runs here, and a serial only exports
                // ANDROID_SERIAL into it.
                #expect(!topic.needsSerial)
                #expect(!topic.isSnapshot)
            case .logcat, .performance, .netspeed:
                #expect(topic.needsSerial)
                // Increments, all three: dropping the middle of a log or a
                // graph is exactly what a client must be told about.
                #expect(!topic.isSnapshot)
            }
        }
    }

    // MARK: - the terminal

    @Test func aTerminalStreamsWhatTheShellPrintsAsBase64() async {
        let sink = RecordingSink()
        let channel = FakeChannel()
        let session = StreamSession(sink: sink, source: ScriptedSource(channel: channel))

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"pty"}"#)
        #expect(await eventually { await sink.events().contains("subscribed") })
        channel.emit("hello\r\n")

        #expect(await eventually { await sink.events().contains("batch") })
        let batch = try! #require(await sink.rawFrames(ofEvent: "batch").first)
        #expect(batch.contains(Data("hello\r\n".utf8).base64EncodedString()))
    }

    /// Every base64 chunk in a run of batch frames, concatenated.
    ///
    /// Static so it can be used from inside `eventually` without capturing the
    /// suite. Batching is not part of the contract — how the chunks group is up
    /// to the flusher — so the assertion is about the bytes, not the frames.
    private static func decodedChunks(_ frames: [String]) -> Data {
        frames
            .compactMap { $0.data(using: .utf8) }
            .compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .compactMap { $0["items"] as? [[String: String]] }
            .flatMap { $0.compactMap { $0["data"] } }
            .compactMap { Data(base64Encoded: $0) }
            .reduce(into: Data()) { $0 += $1 }
    }

    @Test func aChunkThatSplitsACharacterSurvivesTheWire() async {
        // The reason the payload is base64 rather than a JSON string. A pty read
        // ends wherever the buffer filled, so half of a multi-byte character is
        // an ordinary chunk — and a string round-trip replaces it with U+FFFD,
        // corrupting output that is fine once the client reassembles it. Worse,
        // it only happens on non-ASCII, so it ships.
        let sink = RecordingSink()
        let channel = FakeChannel()
        let session = StreamSession(sink: sink, source: ScriptedSource(channel: channel))
        let euro = Array("€".utf8)  // E2 82 AC

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"pty"}"#)
        #expect(await eventually { await sink.events().contains("subscribed") })
        channel.emit(Array(euro[0 ..< 2]))
        channel.emit([euro[2]])

        #expect(
            await eventually {
                Self.decodedChunks(await sink.rawFrames(ofEvent: "batch")).count == euro.count
            })
        let rejoined = Self.decodedChunks(await sink.rawFrames(ofEvent: "batch"))
        #expect(rejoined == Data(euro))
        #expect(String(data: rejoined, encoding: .utf8) == "€")
    }

    @Test func keystrokesReachTheShell() async {
        let sink = RecordingSink()
        let channel = FakeChannel()
        let session = StreamSession(sink: sink, source: ScriptedSource(channel: channel))

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"pty"}"#)
        await session.handle(
            text: #"{"op":"write","id":1,"params":{"data":"\#(Data("ls\n".utf8).base64EncodedString())"}}"#)

        #expect(channel.typed == [Data("ls\n".utf8)])
        // A keystroke is not acknowledged: a paste would otherwise spend a
        // frame per character talking about itself.
        #expect(await sink.events() == ["subscribed"])
    }

    @Test func aResizeReachesTheTerminal() async {
        let sink = RecordingSink()
        let channel = FakeChannel()
        let session = StreamSession(sink: sink, source: ScriptedSource(channel: channel))

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"pty"}"#)
        await session.handle(text: #"{"op":"resize","id":1,"params":{"columns":120,"rows":40}}"#)

        #expect(channel.resizes == [PtySize(columns: 120, rows: 40)])
        // Unacknowledged, like a keystroke: a drag on a pane divider would
        // otherwise be a frame per pixel.
        #expect(await sink.events() == ["subscribed"])
    }

    @Test func theOpeningSizeAndSerialReachTheShell() async {
        let source = ScriptedSource(channel: FakeChannel())
        let session = StreamSession(sink: RecordingSink(), source: source)

        await session.handle(
            text: #"""
                {"op":"subscribe","id":1,"topic":"pty","params":{"serial":"R58M","columns":132,"rows":43}}
                """#)

        let request = try! #require(source.ptyRequests.all.first)
        #expect(request.serial == "R58M")
        #expect(request.size == PtySize(columns: 132, rows: 43))
    }

    @Test func aTerminalWithNoSizeOpensAtTheVT100Default() async {
        let source = ScriptedSource(channel: FakeChannel())
        let session = StreamSession(sink: RecordingSink(), source: source)

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"pty"}"#)

        #expect(source.ptyRequests.all.first?.size == .standard)
        // And no serial: a terminal opens with nothing connected.
        #expect(source.ptyRequests.all.first?.serial == nil)
    }

    @Test func theShellExitingEndsTheSubscriptionAsItsOwnReason() async {
        // Not `device_disconnected`: typing `exit` is how a terminal is meant
        // to end, and the pane says so in the tab rather than as a fault.
        let sink = RecordingSink()
        let channel = FakeChannel()
        let session = StreamSession(sink: sink, source: ScriptedSource(channel: channel))

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"pty"}"#)
        #expect(await eventually { await sink.events().contains("subscribed") })
        channel.exit()

        #expect(await eventually { await sink.events().contains("ended") })
        let ended = try! #require(await sink.rawFrames(ofEvent: "ended").first)
        #expect(field("reason", of: ended, as: String.self) == "process_exited")
    }

    @Test func unsubscribingHangsTheShellUp() async {
        // Cancelling the pump only stops the reading. Without the hang-up every
        // closed tab leaves a shell behind.
        let sink = RecordingSink()
        let channel = FakeChannel()
        let session = StreamSession(sink: sink, source: ScriptedSource(channel: channel))

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"pty"}"#)
        await session.handle(text: #"{"op":"unsubscribe","id":1}"#)

        #expect(channel.hungUp == 1)
        #expect(await session.activeSubscriptionIDs.isEmpty)
    }

    @Test func closingTheSocketHangsTheShellUp() async {
        // The case that leaks: a client that closes its window without
        // unsubscribing, which is the normal way an app exits.
        let channel = FakeChannel()
        let session = StreamSession(
            sink: RecordingSink(), source: ScriptedSource(channel: channel))

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"pty"}"#)
        await session.shutdown()

        #expect(channel.hungUp == 1)
    }

    @Test func aTerminalThatCannotStartSaysWhy() async {
        // Windows has no pty, and a shell that will not exec fails here too.
        // Either way the client gets the reason rather than a dead tab.
        let sink = RecordingSink()
        let session = StreamSession(
            sink: sink, source: ScriptedSource(ptyError: PtyError.unsupportedPlatform))

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"pty"}"#)

        #expect(await sink.events() == ["failed"])
        let failed = try! #require(await sink.rawFrames(ofEvent: "failed").first)
        #expect(failed.contains("Windows"))
        // And no subscription is left registered against a shell that does not
        // exist — the id has to be reusable.
        #expect(await session.activeSubscriptionIDs.isEmpty)
    }

    @Test func typingAtAStreamThatOnlyObservesIsRefused() async {
        let sink = RecordingSink()
        let source = ScriptedSource(logBatches: [[Self.line("hello")]])
        let session = StreamSession(sink: sink, source: source)

        await session.handle(
            text: #"{"op":"subscribe","id":2,"topic":"logcat","params":{"serial":"R58M"}}"#)
        await session.handle(text: #"{"op":"write","id":2,"params":{"data":"bHM="}}"#)

        let failed = try! #require(await sink.rawFrames(ofEvent: "failed").first)
        #expect(failed.contains("does not take input"))
    }

    @Test func aStalledClientGetsAGapNotUnboundedMemory() async {
        // The whole reason the buffer exists. Hold the sink mid-send while the
        // producer pushes far more than capacity, then let it go.
        let sink = RecordingSink()
        let batches = (0..<50).map { batch in (0..<20).map { Self.line("b\(batch)-\($0)") } }
        let source = ScriptedSource(logBatches: batches)
        let session = StreamSession(sink: sink, source: source, capacity: 16)

        // A sink slow enough that 1000 lines outrun it against a 16-item buffer.
        await sink.setDelay(.milliseconds(2))
        await session.handle(
            text: #"{"op":"subscribe","id":9,"topic":"logcat","params":{"serial":"R58M"}}"#)

        #expect(
            await eventually(timeout: .seconds(30)) { await sink.events().contains("ended") },
            "the scripted stream should finish")
        let dropped = await sink.rawFrames(ofEvent: "dropped")
        let total = dropped.compactMap { field("count", of: $0, as: Int.self) }.reduce(0, +)
        #expect(total > 0, "a stalled client must be told it missed lines")

        // Bounded is the point, and nothing vanishes unaccounted for.
        let delivered = await sink.rawFrames(ofEvent: "batch").map(itemCount).reduce(0, +)
        #expect(delivered + total == 1000, "every line is either delivered or counted as dropped")
        #expect(delivered < 1000, "a slow client should not have received everything")
    }

    /// "Nothing is connected" is a state a client has to be able to reach.
    ///
    /// The device list is a snapshot, so an empty one is not "no news" — it is
    /// the only way to say the last device went away. Swallowing it as an
    /// empty batch left a UI showing a phone that had already been unplugged,
    /// and made a first subscribe with nothing attached indistinguishable from
    /// one that was still loading.
    @Test func anEmptyDeviceListIsDeliveredRatherThanSwallowed() async {
        let sink = RecordingSink()
        let source = ScriptedSource(deviceBatches: [[Self.device("emulator-5554")], []])
        let session = StreamSession(sink: sink, source: source)

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"devices"}"#)
        #expect(await eventually { await sink.events().contains("ended") })

        let batches = await sink.rawFrames(ofEvent: "batch")
        #expect(batches.count == 2, "both the populated list and the empty one")
        #expect(batches.map(itemCount) == [1, 0])
    }

    /// A snapshot topic never reports a gap, and always ends on the truth.
    ///
    /// The drop-oldest policy is built for logcat, where a discarded line is
    /// genuinely lost and the client deserves to be told. A device list is not
    /// like that: the older snapshots are worthless the moment a newer one
    /// exists, so discarding them is free — and a "you missed 16 device lists"
    /// marker is something no client can act on. More lists than the buffer's
    /// capacity must therefore still produce zero `dropped` frames.
    @Test func theDeviceListNeverReportsAGapAndEndsCurrent() async {
        let sink = RecordingSink()
        let batches = (0..<20).map { [Self.device("emulator-\(5554 + $0)")] }
        let source = ScriptedSource(deviceBatches: batches)
        // Far below the number of snapshots: on the buffered path this is
        // exactly the shape that produces gap markers.
        let session = StreamSession(sink: sink, source: source, capacity: 4)

        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"devices"}"#)
        #expect(await eventually { await sink.events().contains("ended") })

        #expect(await sink.rawFrames(ofEvent: "dropped").isEmpty, "a gap marker means nothing here")
        let last = try! #require(await sink.rawFrames(ofEvent: "batch").last)
        #expect(last.contains("emulator-5573"), "the last snapshot is the current one")
    }

    @Test func unsubscribeStopsTheDeviceSideWork() async {
        let sink = RecordingSink()
        // A stream that never finishes, so only the unsubscribe can end it.
        let source = ScriptedSource(logBatches: [])
        let session = StreamSession(sink: sink, source: source)

        await session.handle(
            text: #"{"op":"subscribe","id":2,"topic":"logcat","params":{"serial":"R58M"}}"#)
        await session.handle(text: #"{"op":"unsubscribe","id":2}"#)

        #expect(await session.activeSubscriptionIDs.isEmpty)
        // The adb child must be torn down, not orphaned.
        #expect(source.stopped.all.contains("R58M"))
        let ended = await sink.rawFrames(ofEvent: "ended").first
        #expect(ended.flatMap { field("reason", of: $0, as: String.self) } == "unsubscribed")
    }

    @Test func aFailedLogcatStartLeavesNoDeadSubscription() async {
        struct Boom: Error {}
        let sink = RecordingSink()
        var source = ScriptedSource()
        source.logcatError = Boom()
        let session = StreamSession(sink: sink, source: source)

        await session.handle(
            text: #"{"op":"subscribe","id":3,"topic":"logcat","params":{"serial":"gone"}}"#)

        #expect(await sink.events().contains("failed"))
        #expect(await session.activeSubscriptionIDs.isEmpty, "a dead id must not stay registered")
    }

    @Test func malformedInputIsAnsweredNotFatal() async {
        let sink = RecordingSink()
        let session = StreamSession(sink: sink, source: ScriptedSource())

        await session.handle(text: "not json at all")
        await session.handle(text: #"{"op":"subscribe","id":1}"#)  // no topic

        #expect(await sink.events() == ["failed", "failed"])
        #expect(await session.activeSubscriptionIDs.isEmpty)
        // Still alive and usable afterwards — a buggy client cannot wedge it.
        await session.handle(text: #"{"op":"subscribe","id":1,"topic":"devices"}"#)
        #expect(await eventually { await sink.events().contains("subscribed") })
    }

    @Test func shutdownClosesTheSinkAndClearsEverything() async {
        let sink = RecordingSink()
        let source = ScriptedSource(logBatches: [])
        let session = StreamSession(sink: sink, source: source)

        await session.handle(
            text: #"{"op":"subscribe","id":1,"topic":"logcat","params":{"serial":"R58M"}}"#)
        await session.shutdown()

        #expect(await session.activeSubscriptionIDs.isEmpty)
        #expect(await sink.closed)
        // Idempotent: a close racing an error path must not double-cancel.
        await session.shutdown()
        #expect(await sink.closed)
    }
}
