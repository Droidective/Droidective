import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// Screen recording, from the argument vectors up.
///
/// The ffmpeg command lines get the same treatment every adb command line in
/// this project gets, and for the same reason: the difference between a file
/// that plays and one that does not is a flag, and a flag is only checkable if
/// something reads the vector back. The routes are tested for the part a client
/// depends on — that a wrong-state verb is a 409 and a missing tool is its own
/// code, so the screen can offer the download rather than showing a red box.
@Suite struct RecordRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description = "the device said no"
    }

    private actor Recording {
        private(set) var started: [RecordProtocol.StartRequest] = []
        private(set) var paused = 0
        private(set) var resumed: [RecordProtocol.Options] = []
        private(set) var running = false

        func start(_ request: RecordProtocol.StartRequest) {
            started.append(request)
            running = true
        }
        func pause() { paused += 1 }
        func resume(_ options: RecordProtocol.Options) { resumed.append(options) }
        func stop() { running = false }
    }

    private struct StubBackend: DaemonBackend {
        var log = Recording()
        var failure: (any Error)?
        var ffmpegReady = true

        func recordingStatus() async -> RecordProtocol.StatusResponse {
            let running = await log.running
            return RecordProtocol.StatusResponse(
                recording: running, paused: false, serial: running ? "emulator-5554" : nil,
                elapsedSeconds: running ? 4 : 0, segments: running ? 1 : 0,
                ffmpegReady: ffmpegReady)
        }

        func startRecording(_ request: RecordProtocol.StartRequest) async throws {
            if let failure { throw failure }
            await log.start(request)
        }

        func pauseRecording() async throws {
            if let failure { throw failure }
            await log.pause()
        }

        func resumeRecording(_ options: RecordProtocol.Options) async throws {
            if let failure { throw failure }
            await log.resume(options)
        }

        func stopRecording() async throws -> DeviceRecorder.Finished {
            if let failure { throw failure }
            await log.stop()
            return DeviceRecorder.Finished(
                path: "/tmp/recording-1.mp4", durationSeconds: 12.5, sizeBytes: 2_048)
        }
    }

    private func decode<T: Decodable>(_ answer: DaemonProtocol.Answer, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: answer.body)
    }

    private func encoded(_ value: some Encodable) throws -> Data {
        try DaemonProtocol.encode(value)
    }

    // MARK: - Argument vectors

    /// Three flags carry the whole recording. Without wallclock timestamps a
    /// raw H.264 stream has none at all and ffmpeg invents 25 fps, so a
    /// three-minute capture claims some other length; without `-c:v copy` the
    /// device's encode is thrown away and done again on the host.
    @Test func theEncodeVectorMuxesRatherThanReEncoding() {
        let arguments = RecordArguments.encode(into: "/tmp/out.mp4")

        #expect(arguments.contains("-c:v"))
        #expect(arguments.contains("copy"))
        #expect(arguments.contains("-use_wallclock_as_timestamps"))
        #expect(arguments.contains("pipe:0"))
        #expect(arguments.last == "/tmp/out.mp4")
        // `-f h264` has to sit before `-i`, or it describes the output.
        let format = try? #require(arguments.firstIndex(of: "-f"))
        let input = try? #require(arguments.firstIndex(of: "-i"))
        #expect((format ?? 0) < (input ?? 0))
    }

    @Test func theConcatVectorJoinsWithoutReEncoding() {
        let arguments = RecordArguments.concat(listFile: "/tmp/list.txt", output: "/tmp/out.mp4")

        #expect(arguments.contains("concat"))
        #expect(arguments.contains("-safe"))
        #expect(arguments.contains("copy"))
        #expect(arguments.last == "/tmp/out.mp4")
    }

    /// A quote in a path would end the concat demuxer's line early and the
    /// recording would be silently short. Ours are under a temp directory, but
    /// a list file that truncates at an apostrophe only shows up on somebody
    /// else's machine.
    @Test func theConcatListEscapesAQuoteInAPath() {
        let list = RecordArguments.concatList(["/tmp/a.mp4", "/tmp/Bob's/b.mp4"])

        #expect(list.contains("file '/tmp/a.mp4'"))
        #expect(list.contains(#"file '/tmp/Bob'\''s/b.mp4'"#))
        #expect(list.hasSuffix("\n"))
    }

    /// Control off and audio off, both deliberate: nothing should touch the
    /// device while it records, and scrcpy's audio is a second stream this
    /// build does not mux.
    @Test func theSessionRecordsWithoutControlOrAudio() {
        let params = RecordArguments.serverParams(
            scid: 7, options: ScreenRecordOptions(maxSize: 1080, bitRateMbps: 12, maxFps: 30))

        #expect(params.video)
        #expect(!params.audio)
        #expect(!params.control)
        #expect(params.maxSize == 1080)
        #expect(params.maxFps == 30)
        // Mbps on the way in, bits per second on the way out — scrcpy's unit.
        #expect(params.videoBitRate == 12_000_000)
    }

    /// Zero means "the server's own default" on every one of these, so it has
    /// to pass through as zero rather than becoming a bit-rate of nothing.
    @Test func zeroOptionsStayZero() {
        let params = RecordArguments.serverParams(scid: 1, options: ScreenRecordOptions())
        #expect(params.maxSize == 0)
        #expect(params.videoBitRate == 0)
        #expect(params.maxFps == 0)
    }

    // MARK: - Routes

    @Test func statusAnswersThatNothingIsRecording() async throws {
        let answer = await RecordRoutes.status(backend: StubBackend())
        #expect(answer.status == 200)

        let body = try decode(answer, as: RecordProtocol.StatusResponse.self)
        #expect(!body.recording)
        #expect(body.serial == nil)
        #expect(body.ffmpegReady)
    }

    @Test func startPassesTheOptionsThroughAndAnswersTheNewStatus() async throws {
        let backend = StubBackend()
        let answer = await RecordRoutes.start(
            body: try encoded(RecordProtocol.StartRequest(
                serial: "emulator-5554",
                options: RecordProtocol.Options(maxSize: 1080, bitRateMbps: 8, maxFps: 60))),
            backend: backend)
        #expect(answer.status == 200)

        let started = await backend.log.started
        #expect(started.first?.serial == "emulator-5554")
        #expect(started.first?.options.bitRateMbps == 8)
        let body = try decode(answer, as: RecordProtocol.StatusResponse.self)
        #expect(body.recording)
    }

    @Test func startRefusesARequestWithNoSerial() async throws {
        let answer = await RecordRoutes.start(
            body: try encoded(RecordProtocol.StartRequest(serial: "")), backend: StubBackend())
        #expect(answer.status == 400)
    }

    /// A missing ffmpeg is the one failure with something the screen can do
    /// about it, so it gets a code of its own rather than a generic one.
    @Test func aMissingFfmpegIsItsOwnCode() async throws {
        let backend = StubBackend(failure: DeviceRecorder.RecordError.ffmpegMissing)
        let answer = await RecordRoutes.start(
            body: try encoded(RecordProtocol.StartRequest(serial: "emulator-5554")),
            backend: backend)
        #expect(answer.status == 422)

        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.code == "ffmpeg_missing")
        #expect(body.error.message.contains("Settings"))
    }

    /// Pausing something that is not recording is the client and the daemon
    /// disagreeing about state, not a broken daemon — 409, not 500.
    @Test func aVerbInTheWrongStateIsAConflict() async throws {
        let backend = StubBackend(failure: DeviceRecorder.RecordError.notRecording)
        let answer = await RecordRoutes.pause(backend: backend)
        #expect(answer.status == 409)

        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.code == "wrong_state")
    }

    @Test func aDeviceThatWillNotStreamIsABadGateway() async throws {
        let backend = StubBackend(
            failure: DeviceRecorder.RecordError.startFailed("the device closed the socket"))
        let answer = await RecordRoutes.start(
            body: try encoded(RecordProtocol.StartRequest(serial: "emulator-5554")),
            backend: backend)
        #expect(answer.status == 502)
        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.message.contains("closed the socket"))
    }

    /// A resume carries the options again because each span is its own scrcpy
    /// session: segments recorded at different sizes cannot be concatenated.
    @Test func resumeCarriesTheOptionsForward() async throws {
        let backend = StubBackend()
        let answer = await RecordRoutes.resume(
            body: try encoded(RecordProtocol.Options(maxSize: 720, bitRateMbps: 4, maxFps: 30)),
            backend: backend)
        #expect(answer.status == 200)

        let resumed = await backend.log.resumed
        #expect(resumed.first?.maxSize == 720)
        #expect(resumed.first?.maxFps == 30)
    }

    /// An empty body is a resume with the defaults rather than a 400: the verb
    /// is complete without them, and refusing it would strand a paused
    /// recording.
    @Test func resumeWithNoBodyUsesTheDefaults() async throws {
        let backend = StubBackend()
        let answer = await RecordRoutes.resume(body: Data(), backend: backend)
        #expect(answer.status == 200)
        #expect(await backend.log.resumed.first == RecordProtocol.Options())
    }

    @Test func stopAnswersWhereTheFileLanded() async throws {
        let backend = StubBackend()
        let answer = await RecordRoutes.stop(backend: backend)
        #expect(answer.status == 200)

        let body = try decode(answer, as: RecordProtocol.StoppedResponse.self)
        #expect(body.path == "/tmp/recording-1.mp4")
        #expect(body.durationSeconds == 12.5)
        #expect(body.sizeBytes == 2_048)
    }

    // MARK: - The recorder's own state machine

    private func recorder(_ tools: @escaping @Sendable () async throws -> DeviceRecorder.Tools)
        -> DeviceRecorder
    {
        DeviceRecorder(
            adb: AdbClient(locator: ToolLocator()),
            workDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("record-\(UUID().uuidString)"),
            resolveTools: tools)
    }

    /// Nothing is recording, so there is nothing to report — and a screen that
    /// has just opened relies on that being nil rather than a zeroed status.
    @Test func aFreshRecorderReportsNothing() async {
        let recorder = recorder { throw DeviceRecorder.RecordError.ffmpegMissing }
        #expect(await recorder.status() == nil)
    }

    /// A start that cannot resolve its tools must leave no half-started
    /// recording behind, or the next attempt reports "already recording" and
    /// there is no way back without restarting the daemon.
    @Test func aFailedStartLeavesTheRecorderIdle() async {
        let recorder = recorder { throw DeviceRecorder.RecordError.ffmpegMissing }

        await #expect(throws: DeviceRecorder.RecordError.ffmpegMissing) {
            try await recorder.start(serial: "emulator-5554", options: ScreenRecordOptions())
        }
        #expect(await recorder.status() == nil)

        // And the second attempt fails the same way rather than differently.
        await #expect(throws: DeviceRecorder.RecordError.ffmpegMissing) {
            try await recorder.start(serial: "emulator-5554", options: ScreenRecordOptions())
        }
    }

    /// The finished duration is the video's, not the wall clock from the
    /// button press. scrcpy takes a moment to bring a session up and the file
    /// has no video for it, so a recording timed from `start` claimed seconds
    /// the file did not contain — 30 seconds reported against a 12-second file,
    /// found by recording against a real device rather than by reading this.
    @Test func aFrameSpanIsTheDistanceBetweenTheFirstAndLastFrame() {
        let start = Date(timeIntervalSince1970: 1_000)
        var span = DeviceRecorder.FrameSpan()
        #expect(span.seconds == 0)

        span.first = start
        // One frame is a moment, not a duration.
        span.last = start
        #expect(span.seconds == 0)

        span.last = start.addingTimeInterval(12.5)
        #expect(span.seconds == 12.5)
    }

    /// A clock that ran backwards would report a shrinking recording. It cannot
    /// happen from frames arriving in order, but `Date()` is not monotonic and
    /// a system clock adjustment mid-recording is exactly the case.
    @Test func aFrameSpanNeverGoesNegative() {
        var span = DeviceRecorder.FrameSpan()
        span.first = Date(timeIntervalSince1970: 1_000)
        span.last = Date(timeIntervalSince1970: 900)
        #expect(span.seconds == 0)
    }

    @Test func pausingAndStoppingWithNoRecordingIsRefused() async {
        let recorder = recorder { throw DeviceRecorder.RecordError.ffmpegMissing }

        await #expect(throws: DeviceRecorder.RecordError.notRecording) {
            try await recorder.pause()
        }
        await #expect(throws: DeviceRecorder.RecordError.notRecording) {
            _ = try await recorder.stop()
        }
    }
}
