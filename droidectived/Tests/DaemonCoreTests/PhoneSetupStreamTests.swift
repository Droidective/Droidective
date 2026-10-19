import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The `phonesetup` topic: a set-up run that names its stages as it goes.
///
/// The run itself is `PhoneAppSetupService`'s and is tested in ADBKit. What is
/// tested here is what a subscriber sees and what the live source adds: every
/// stage reaches the client, the last event says it is the last, the
/// subscription ends `completed`, and the run's adb commands reach the Command
/// Log even though stream topics never pass through the routes' scope.
@Suite struct PhoneSetupStreamTests {
    private actor FrameSink: StreamSink {
        private var frames: [String] = []

        func send(_ text: String) async { frames.append(text) }
        func close() async {}

        func rawFrames(ofEvent event: String) -> [String] {
            frames.filter { $0.contains("\"event\":\"\(event)\"") }
        }
    }

    private struct ScriptedSource: StreamSource {
        let events: [PhoneSetupProtocol.Progress]

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

        func phoneSetup(serial: String) async -> AsyncStream<PhoneSetupProtocol.Progress> {
            let events = self.events
            return AsyncStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    @Test func aRunIsASnapshotTopicNeedingASerial() {
        #expect(StreamProtocol.Topic.phoneSetup.rawValue == "phonesetup")
        #expect(StreamProtocol.Topic.phoneSetup.isSnapshot)
        #expect(StreamProtocol.Topic.phoneSetup.needsSerial)
        #expect(!StreamProtocol.Topic.phoneSetup.acceptsInput)
        #expect(!StreamProtocol.Topic.phoneSetup.acceptsResize)
    }

    @Test func aRunWithoutASerialIsRefused() async {
        let sink = FrameSink()
        let session = StreamSession(sink: sink, source: ScriptedSource(events: []))
        await session.handle(text: #"{"op":"subscribe","id":3,"topic":"phonesetup"}"#)
        #expect(await sink.rawFrames(ofEvent: "failed").count == 1)
    }

    @Test func theLastStageAndTheOutcomeReachTheSubscriberThenItCompletes() async throws {
        let sink = FrameSink()
        let session = StreamSession(
            sink: sink,
            source: ScriptedSource(events: [
                .init(stage: "Downloading 0.1.1… 50%"),
                .init(stage: "Installing 0.1.1…"),
                .init(done: true, failure: "Couldn't install 0.1.1: The APK is invalid or corrupt."),
            ]))
        await session.handle(text: #"""
        {"op":"subscribe","id":7,"topic":"phonesetup","params":{"serial":"S1"}}
        """#)
        try await Task.sleep(for: .milliseconds(200))

        let batches = await sink.rawFrames(ofEvent: "batch")
        #expect(batches.contains { $0.contains(#""done":true"#) && $0.contains("invalid or corrupt") })
        #expect(await sink.rawFrames(ofEvent: "ended").contains { $0.contains("completed") })
    }

    // MARK: - The live source

    /// A phone with the app current and nothing granted: the run grants three
    /// permissions, so there is a stage, adb commands, and an outcome.
    private struct Phone: ProcessRunning {
        func run(
            executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int
        ) async -> ProcessOutput {
            let line = arguments.dropFirst(3).joined(separator: " ")
            let stdout: String
            switch line {
            case "pm list packages 'com.droidective.android'": stdout = "package:com.droidective.android\n"
            case "getprop ro.build.version.sdk": stdout = "36\n"
            case "dumpsys package 'com.droidective.android'": stdout = "    versionName=0.1.1\n"
            default: stdout = ""
            }
            return ProcessOutput(stdout: Data(stdout.utf8), stderr: Data(), exitCode: 0, timedOut: false)
        }
    }

    private struct Offline: HTTPFetching {
        func data(from url: URL) async throws -> Data { throw URLError(.notConnectedToInternet) }
        func download(
            from url: URL, to destination: URL, onProgress: (@Sendable (Double) -> Void)?
        ) async throws { throw URLError(.notConnectedToInternet) }
    }

    @Test func theLiveRunNamesItsStagesAndRecordsItsCommands() async throws {
        let locator = ToolLocator(runner: Phone(), environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        let log = CommandLog()
        let client = AdbClient(locator: locator, runner: Phone(), log: log)
        let source = LiveStreamSource(
            monitor: DeviceMonitor(client: client), streamer: LogcatStreamer(client: client),
            performance: PerformanceService(client: client),
            networkSpeed: NetworkSpeedService(client: client), reactotron: ReactotronRelay(),
            client: client, locator: locator,
            phoneAppSetup: PhoneAppSetupService(client: client, http: Offline()),
            phoneAppReleases: PhoneAppReleaseCheck(http: Offline()))

        var events: [PhoneSetupProtocol.Progress] = []
        for await event in await source.phoneSetup(serial: "S1") { events.append(event) }

        #expect(events.first?.stage == "Granting permissions…")
        let last = try #require(events.last)
        #expect(last.done == true)
        // The fake phone never records a grant, so the run says so, with the
        // status it read back beside it.
        #expect(last.failure?.hasPrefix("Android didn't record the grant for") == true)
        #expect(last.status?.appVersion == "0.1.1")
        #expect(last.status?.latestProblem != nil)
        let grants = await log.snapshot().filter { $0.command.contains("pm grant") }
        #expect(grants.count == 3)
    }
}
