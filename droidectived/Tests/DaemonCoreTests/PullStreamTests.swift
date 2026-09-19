import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The `pull` topic — the progress strip's protocol half.
///
/// The transfer itself is `FileExplorerService`'s and is tested in ADBKit; what
/// is worth testing here is the shape of what a subscriber sees, because the
/// strip is driven entirely by it: a total that is absent has to stay absent,
/// the last event has to say it is the last, and a failure has to arrive as an
/// event rather than as silence.
@Suite struct PullStreamTests {
    /// Collects what the session sent, so the framing is what is asserted.
    private actor FrameSink: StreamSink {
        private var frames: [String] = []

        func send(_ text: String) async { frames.append(text) }
        func close() async {}

        func events() -> [String] {
            frames.compactMap { field($0, "event") }
        }

        func rawFrames(ofEvent event: String) -> [String] {
            frames.filter { field($0, "event") == event }
        }

        private func field(_ frame: String, _ key: String) -> String? {
            guard let data = frame.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return object[key] as? String
        }
    }

    /// A source that reports a scripted sequence, so the session's framing is
    /// what is under test rather than adb.
    private struct ScriptedSource: StreamSource {
        let events: [PullProgressPayload]

        func devices() async -> AsyncStream<[Device]> { AsyncStream { $0.finish() } }

        func logcat(serial: String, pid: Int?) async throws -> AsyncStream<[LogLine]> {
            AsyncStream { $0.finish() }
        }

        func stopLogcat(serial: String) async {}

        func performance(
            serial: String, packageId: String?, includeProcesses: Bool
        ) async -> AsyncStream<PerformanceService.PerfPoll> { AsyncStream { $0.finish() } }

        func netspeed(serial: String) async -> AsyncStream<NetSample> { AsyncStream { $0.finish() } }

        func reactotron() async throws -> AsyncStream<ReactotronRelay.Event> {
            AsyncStream { $0.finish() }
        }

        func stopReactotron() async {}

        func openPty(serial: String?, size: PtySize) throws -> any PtyChannel {
            throw StubbedOut.notImplemented
        }

        func pull(
            serial: String, path: String, destination: String, asRoot: Bool
        ) async -> AsyncStream<PullProgressPayload> {
            let events = self.events
            return AsyncStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    @Test func aPullIsASnapshotTopicNeedingASerial() {
        // Not just an assertion about a table: the strip shows one transfer's
        // current state, so an older percentage is worthless and a `dropped`
        // marker would be noise a progress bar cannot act on.
        #expect(StreamProtocol.Topic.pull.isSnapshot)
        #expect(StreamProtocol.Topic.pull.needsSerial)
        #expect(!StreamProtocol.Topic.pull.acceptsInput)
        #expect(!StreamProtocol.Topic.pull.acceptsResize)
    }

    @Test func theSubscriptionCarriesThePathAndTheDestination() throws {
        let json = Data(#"""
        {"op":"subscribe","id":1,"topic":"pull","params":{
          "serial":"emulator-5554","path":"/sdcard/big.zip",
          "destination":"/home/me/Downloads/big.zip","asRoot":true}}
        """#.utf8)
        let decoded = try JSONDecoder().decode(StreamProtocol.Command.self, from: json)
        #expect(decoded.topic == .pull)
        #expect(decoded.params?.path == "/sdcard/big.zip")
        #expect(decoded.params?.destination == "/home/me/Downloads/big.zip")
        #expect(decoded.params?.asRoot == true)
    }

    @Test func anAbsentTotalStaysAbsentOnTheWire() throws {
        // A directory pull has no single number to divide by. Encoding a zero
        // would make the strip read 0% for the whole transfer instead of
        // showing that it cannot know.
        let payload = PullProgressPayload(copied: 1024, total: nil)
        let encoded = try DaemonProtocol.encode(payload)
        let decoded = try JSONDecoder().decode(PullProgressPayload.self, from: encoded)
        #expect(decoded.total == nil)
        #expect(decoded.copied == 1024)
        #expect(!decoded.done)
    }

    @Test func theLastEventCarriesThePathAndSaysItIsTheLast() throws {
        let payload = PullProgressPayload(
            copied: 2048, total: 2048, path: "/home/me/Downloads/big.zip", done: true)
        let decoded = try JSONDecoder().decode(
            PullProgressPayload.self, from: DaemonProtocol.encode(payload))
        #expect(decoded.done)
        #expect(decoded.path == "/home/me/Downloads/big.zip")
        #expect(decoded.failure == nil)
    }

    @Test func aFailureArrivesAsAnEventRatherThanSilence() throws {
        // Silence is indistinguishable from a slow pull, which is how a strip
        // ends up stuck at 40% forever.
        let payload = PullProgressPayload(
            copied: 0, total: 900, done: true, failure: "adb: no such file")
        let decoded = try JSONDecoder().decode(
            PullProgressPayload.self, from: DaemonProtocol.encode(payload))
        #expect(decoded.done)
        #expect(decoded.failure == "adb: no such file")
        #expect(decoded.path == nil)
    }

    @Test func aSubscriptionWithNoPathIsRefusedRatherThanLeftOpen() async throws {
        // Nothing to pull is not a pull. Returning quietly would leave a
        // subscription open and silent, which a client cannot tell from a slow
        // transfer — so it is refused with a reason.
        let sink = FrameSink()
        let session = StreamSession(sink: sink, source: ScriptedSource(events: []))
        await session.handle(
            text: #"{"op":"subscribe","id":4,"topic":"pull","params":{"serial":"R58M"}}"#)
        #expect(await sink.events() == ["failed"])
        let failed = try #require(await sink.rawFrames(ofEvent: "failed").first)
        #expect(failed.contains("destination"))
    }

    @Test func aSubscriptionWithNoDestinationIsRefusedToo() async {
        let sink = FrameSink()
        let session = StreamSession(sink: sink, source: ScriptedSource(events: []))
        await session.handle(text: #"""
        {"op":"subscribe","id":9,"topic":"pull","params":{"serial":"R58M","path":"/sdcard/x"}}
        """#)
        #expect(await sink.events() == ["failed"])
    }

    @Test func everyScriptedEventReachesTheSubscriber() async throws {
        let sink = FrameSink()
        let session = StreamSession(
            sink: sink,
            source: ScriptedSource(events: [
                PullProgressPayload(copied: 0, total: 100),
                PullProgressPayload(copied: 50, total: 100),
                PullProgressPayload(copied: 100, total: 100, path: "/tmp/x", done: true),
            ]))
        await session.handle(text: #"""
        {"op":"subscribe","id":5,"topic":"pull","params":{
          "serial":"R58M","path":"/sdcard/x","destination":"/tmp/x"}}
        """#)
        try await Task.sleep(for: .milliseconds(200))
        let frames = await sink.rawFrames(ofEvent: "batch")
        #expect(frames.contains { $0.contains("\"copied\":50") })
        #expect(frames.contains { $0.contains("\"done\":true") })
    }

    @Test func aFinishedPullEndsAsCompletedRatherThanUnsubscribed() async throws {
        // "unsubscribed" would make the strip read as cancelled at the moment
        // the transfer succeeded.
        let sink = FrameSink()
        let session = StreamSession(
            sink: sink,
            source: ScriptedSource(events: [
                PullProgressPayload(copied: 1, total: 1, path: "/tmp/x", done: true),
            ]))
        await session.handle(text: #"""
        {"op":"subscribe","id":6,"topic":"pull","params":{
          "serial":"R58M","path":"/sdcard/x","destination":"/tmp/x"}}
        """#)
        try await Task.sleep(for: .milliseconds(200))
        let ended = await sink.rawFrames(ofEvent: "ended")
        #expect(ended.contains { $0.contains("completed") })
    }
}
