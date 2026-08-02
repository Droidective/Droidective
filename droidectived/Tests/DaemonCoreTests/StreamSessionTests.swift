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

    private struct ScriptedSource: StreamSource, @unchecked Sendable {
        var deviceBatches: [[Device]] = []
        var logBatches: [[LogLine]] = []
        var logcatError: (any Error)?
        let stopped = StoppedBox()

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
