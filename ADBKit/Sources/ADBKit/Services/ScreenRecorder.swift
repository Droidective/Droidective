// Rides the Apple-only mirror pipeline (see MirrorSession); other hosts will
// record via the scrcpy desktop app instead.
#if canImport(AVFoundation) && canImport(Network)
import Foundation

/// Screen recording built on the in-app scrcpy client (the bundled server), so
/// it needs no separate scrcpy install. A headless `MirrorSession` brings up the
/// device stream and records it straight to an `.mp4` (H.264 passthrough video +
/// AAC audio on Android 11+).
///
/// **Pause/resume is segmented.** scrcpy's encoder emits a key frame only at
/// stream start (it ignores the i-frame-interval hint), so a recording can't be
/// paused-and-resumed on one stream without corrupting the video (frames after a
/// resume would reference dropped ones). Instead each record/resume span is its
/// own session writing its own clean segment; `stop()` losslessly concatenates
/// the segments with ffmpeg. The finished file is handed to the editor; nothing
/// lands in the capture folder until the user saves.
public actor ScreenRecorder {
    public enum RecordingError: Error, LocalizedError {
        case alreadyRecording
        case notRecording
        case startFailed(String)
        case concatFailed(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "A recording is already in progress."
            case .notRecording: return "No active recording."
            case .startFailed(let reason): return reason
            case .concatFailed(let reason): return "Couldn’t assemble the recording: \(reason)"
            }
        }
    }

    private let client: AdbClient
    private let server: ScrcpyServerInfo
    /// Bundled ffmpeg path, for concatenating paused/resumed segments. Without it
    /// only single-segment (never-paused) recordings are supported.
    private let ffmpegPath: String?

    /// What the recording is capturing right now, for the UI's mute controls
    /// and level meter.
    public struct AudioStatus: Sendable, Equatable {
        public let mode: RecordAudioMode
        /// What the device half of the recording is: its playback, its own
        /// microphone, or nothing.
        public let deviceSource: DeviceAudioSource
        public let deviceMuted: Bool
        public let microphoneMuted: Bool
        /// 0…1 level of the last microphone chunk; 0 when the mic isn't running.
        public let microphoneLevel: Float
        /// Why the microphone isn't contributing, if it isn't. The recording
        /// keeps going without it rather than failing.
        public let microphoneFailure: String?
    }

    private var session: MirrorSession?
    private var currentURL: URL?
    private var segments: [URL] = []
    private var serial = ""
    private var options = ScreenRecordOptions()

    /// The microphone runs per segment: it starts with a segment and stops on
    /// pause, so a paused recording doesn't hold the mic open (and doesn't keep
    /// the system's recording indicator lit).
    private var microphone: MicrophoneCapture?
    private var microphonePump: Task<Void, Never>?
    private var microphoneSink: AsyncStream<MicrophoneChunk>.Continuation?
    private var microphoneLevel: Float = 0
    private var microphoneFailure: String?
    /// Mute state survives pause/resume, so each new segment starts out matching
    /// what the user last chose.
    private var deviceMuted = false
    private var microphoneMuted = false

    public init(client: AdbClient, server: ScrcpyServerInfo, ffmpegPath: String? = nil) {
        self.client = client
        self.server = server
        self.ffmpegPath = ffmpegPath
    }

    /// Actively capturing or holding finished segments (paused).
    public var isRecording: Bool { session != nil || !segments.isEmpty }
    /// Recording started but currently paused between segments.
    public var isPaused: Bool { session == nil && !segments.isEmpty }

    /// The latest decoded frame of the segment being captured, for a live preview
    /// of what's being recorded. `nil` between segments (paused) or before the
    /// first frame decodes. This is free: the session already decodes every frame
    /// for snapshots (`MirrorSession` does so unconditionally), so it reads the
    /// latest without a second device connection or draining the record stream.
    public func previewFrame() async -> MirrorSession.Snapshot? {
        await session?.snapshot()
    }

    public func audioStatus() -> AudioStatus {
        AudioStatus(
            mode: options.audio.mode,
            deviceSource: options.audio.deviceSource,
            deviceMuted: deviceMuted,
            microphoneMuted: microphoneMuted,
            microphoneLevel: microphoneMuted ? 0 : microphoneLevel,
            microphoneFailure: microphoneFailure)
    }

    /// Silence either source mid-recording. The capture keeps running — muted
    /// samples are written as silence — so unmuting is instant and the audio
    /// track keeps one continuous timeline.
    public func setMuted(device: Bool, microphone: Bool) async {
        deviceMuted = device
        microphoneMuted = microphone
        await session?.setAudioMuted(device: device, microphone: microphone)
    }

    public func start(serial: String, options: ScreenRecordOptions = ScreenRecordOptions()) async throws {
        guard !isRecording else { throw RecordingError.alreadyRecording }
        self.serial = serial
        self.options = options
        try await startSegment()
    }

    /// Finalize the current segment (keeping it) so a later resume appends a new
    /// one. No-op if already paused.
    public func pause() async {
        await finalizeSegment()
    }

    /// Begin a fresh segment after a pause.
    public func resume() async throws {
        guard isPaused else { return }
        try await startSegment()
    }

    /// Stop, finalize the last segment, and return the recording — a single
    /// segment as-is, or all segments concatenated losslessly.
    public func stop() async throws -> URL {
        await finalizeSegment()
        let segs = segments
        segments = []
        guard let first = segs.first else { throw RecordingError.notRecording }
        // Concatenating (>1) already rewrites the container via ffmpeg; a single
        // segment is remuxed too so AVFoundation can decode it (the editor's
        // player + previews otherwise fail on AVAssetWriter's passthrough output).
        guard segs.count > 1 else { return await remux(first) ?? first }
        return try await concatenate(segs)
    }

    private func remux(_ source: URL) async -> URL? {
        guard let ffmpegPath else { return nil }
        let output = Self.tempURL(ext: "mp4")
        let result = await SystemProcessRunner().run(
            executable: ffmpegPath,
            arguments: VideoEditing.remuxArguments(input: source.path, output: output.path),
            timeout: .seconds(60), maxOutputBytes: 4 * 1024 * 1024)
        guard result.exitCode == 0 else {
            try? FileManager.default.removeItem(at: output)
            return nil
        }
        try? FileManager.default.removeItem(at: source)
        return output
    }

    /// Abort and discard everything (view dismissed / app quit).
    public func abort() async {
        await stopMicrophone()
        if let session { await session.stop() }
        let leftovers = segments + [currentURL].compactMap { $0 }
        session = nil
        currentURL = nil
        segments = []
        for url in leftovers { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Segments

    private func startSegment() async throws {
        let params = ScrcpyServerParams(
            scid: UInt32.random(in: 1 ... 0x7fff_ffff),
            audio: options.audio.deviceSource.isOn,
            audioSource: options.audio.deviceSource.scrcpySource,
            control: false,
            maxSize: options.maxSize,
            videoBitRate: options.bitRateMbps > 0 ? options.bitRateMbps * 1_000_000 : 0,
            maxFps: options.maxFps)
        let config = MirrorTransport.Configuration(
            serial: serial, params: params,
            serverVersion: server.version, localJarPath: server.jarPath)
        let session = MirrorSession(adb: client, config: config)
        // start() drives decode + recording from the session's own task; the
        // returned display stream is bounded and left undrained (we only record).
        _ = await session.start()

        let temp = Self.tempURL(ext: "mp4")
        // Arm recording up front; the session creates the recorder when the config
        // packet lands so this segment captures from its first key frame.
        await session.setAudioMuted(device: deviceMuted, microphone: microphoneMuted)
        try await session.startRecording(to: temp, audio: options.audio.mode)
        guard await Self.waitUntilStreaming(session: session) else {
            await session.stop()
            throw RecordingError.startFailed("Couldn’t get video from the device.")
        }
        self.session = session
        self.currentURL = temp
        await startMicrophone(feeding: session)
    }

    private func finalizeSegment() async {
        guard let session, let currentURL else { return }
        self.session = nil
        self.currentURL = nil
        await stopMicrophone()
        _ = try? await session.stopRecording(url: currentURL)
        await session.stop()
        segments.append(currentURL)
    }

    // MARK: - Microphone

    /// Bring the host microphone up for this segment and pump its chunks into
    /// the session. A microphone that won't start (unplugged, access revoked)
    /// is reported through `audioStatus()` and the recording continues without
    /// it — losing the narration is better than losing the take.
    private func startMicrophone(feeding session: MirrorSession) async {
        guard options.audio.mode.includesMicrophone else { return }
        let capture = MicrophoneCapture(deviceID: options.audio.microphoneDeviceID)
        // A stream rather than a Task per chunk: chunks must reach the writer in
        // order, and separate Tasks carry no ordering guarantee.
        let (stream, sink) = AsyncStream.makeStream(
            of: MicrophoneChunk.self, bufferingPolicy: .bufferingNewest(200))
        do {
            try await capture.start { sink.yield($0) }
        } catch {
            sink.finish()
            microphoneFailure = Self.message(for: error)
            return
        }
        microphone = capture
        microphoneSink = sink
        microphoneFailure = nil
        microphonePump = Task { [weak self] in
            for await chunk in stream {
                await self?.deliver(chunk, to: session)
            }
        }
    }

    private func deliver(_ chunk: MicrophoneChunk, to session: MirrorSession) async {
        microphoneLevel = chunk.level
        await session.appendMicrophoneAudio(chunk.pcm, hostSeconds: chunk.hostSeconds)
    }

    private func stopMicrophone() async {
        microphonePump?.cancel()
        microphonePump = nil
        microphoneSink?.finish()
        microphoneSink = nil
        if let microphone {
            // A format the graph couldn't deliver only shows up while capturing,
            // so it's collected on the way out.
            if microphoneFailure == nil, let failure = await microphone.failure() {
                microphoneFailure = failure.errorDescription
            }
            await microphone.stop()
        }
        microphone = nil
        microphoneLevel = 0
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func waitUntilStreaming(session: MirrorSession) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(15))
        while clock.now < deadline {
            if await session.currentDimensions() != nil { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    private func concatenate(_ segments: [URL]) async throws -> URL {
        guard let ffmpegPath else {
            throw RecordingError.concatFailed("ffmpeg is unavailable")
        }
        let listURL = Self.tempURL(ext: "txt")
        let body = segments.map { "file '\($0.path)'" }.joined(separator: "\n")
        do {
            try body.write(to: listURL, atomically: true, encoding: .utf8)
        } catch {
            throw RecordingError.concatFailed(error.localizedDescription)
        }
        let output = Self.tempURL(ext: "mp4")
        let result = await SystemProcessRunner().run(
            executable: ffmpegPath,
            arguments: VideoEditing.concatArguments(listFile: listURL.path, output: output.path),
            timeout: .seconds(120), maxOutputBytes: 4 * 1024 * 1024)
        try? FileManager.default.removeItem(at: listURL)
        for url in segments { try? FileManager.default.removeItem(at: url) }
        guard result.exitCode == 0 else {
            let tail = VideoEditing.stderrTail(result.stderrText)
            throw RecordingError.concatFailed(tail.isEmpty ? "ffmpeg failed" : tail)
        }
        return output
    }

    private static func tempURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("droidective-recording-\(ScreenCaptureService.stamp())-\(UInt32.random(in: 0 ... 0xffff_ffff))")
            .appendingPathExtension(ext)
    }
}
#endif
