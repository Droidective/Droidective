import ADBKit
import Foundation

/// Screen recording for Windows and Linux.
///
/// The Mac records through `ScreenRecorder`, which is an `AVAssetWriter` over
/// the Apple-only mirror stack. Here the same scrcpy stream the mirror already
/// receives is piped into ffmpeg instead, muxed with `-c:v copy`: the device
/// did the encoding either way, so the two produce the same picture from the
/// same bytes.
///
/// **Pause and resume are segmented**, exactly as they are on the Mac and for
/// the same reason: scrcpy's encoder emits a key frame at stream start and
/// ignores the i-frame-interval hint, so a single stream cannot be cut and
/// rejoined without every frame after the resume referring to one that was
/// dropped. Each span is its own session writing its own clean segment, and
/// `stop` concatenates them losslessly.
///
/// One session per device, as on the Mac — scrcpy's encoder is not shareable,
/// which is why `screen-record` and `scrcpy` are both in
/// `WorkspaceRegistry.exclusiveFeatureIDs`.
public actor DeviceRecorder {
    public enum RecordError: Error, LocalizedError, Equatable {
        case ffmpegMissing
        case alreadyRecording
        case notRecording
        case startFailed(String)
        case writeFailed(String)
        case assembleFailed(String)

        public var errorDescription: String? {
            switch self {
            case .ffmpegMissing:
                return "ffmpeg isn't installed. Settings ▸ Tools can download it."
            case .alreadyRecording:
                return "A recording is already in progress."
            case .notRecording:
                return "No active recording."
            case .startFailed(let reason):
                return reason
            case .writeFailed(let reason):
                return reason
            case .assembleFailed(let reason):
                return "Couldn't assemble the recording: \(reason)"
            }
        }
    }

    /// What the screen shows while a recording is up.
    public struct Status: Sendable, Equatable {
        public let serial: String
        public let recording: Bool
        public let paused: Bool
        /// Seconds of video captured so far, across every segment.
        public let elapsedSeconds: Double
        public let segments: Int

        public init(
            serial: String, recording: Bool, paused: Bool,
            elapsedSeconds: Double, segments: Int
        ) {
            self.serial = serial
            self.recording = recording
            self.paused = paused
            self.elapsedSeconds = elapsedSeconds
            self.segments = segments
        }
    }

    public struct Finished: Sendable, Equatable {
        public let path: String
        public let durationSeconds: Double
        public let sizeBytes: Int
    }

    /// One record-to-pause span.
    private struct Segment {
        let url: URL
        let pipe: FfmpegPipe
        let session: ScrcpySession
        let pump: Task<FrameSpan, Never>
        let startedAt: Date
    }

    /// When the first and last frame of a segment arrived.
    ///
    /// The recording's length is this, not the wall clock from `start`: scrcpy
    /// takes a moment to bring a session up and the file has no video for it,
    /// so a duration counted from the button press claims seconds the file
    /// does not contain. The Mac's timer has the same head start; what it must
    /// not do is *report* it as the finished length.
    struct FrameSpan: Sendable {
        var first: Date?
        var last: Date?

        var seconds: TimeInterval {
            guard let first, let last else { return 0 }
            return max(0, last.timeIntervalSince(first))
        }
    }

    /// What a recording needs from the host, resolved when one starts.
    ///
    /// A closure rather than three stored strings: ffmpeg may be downloaded
    /// between one recording and the next, and a path captured at daemon
    /// startup would still say it was missing.
    public struct Tools: Sendable, Equatable {
        public let ffmpeg: String
        public let scrcpyJar: String
        public let scrcpyVersion: String

        public init(ffmpeg: String, scrcpyJar: String, scrcpyVersion: String) {
            self.ffmpeg = ffmpeg
            self.scrcpyJar = scrcpyJar
            self.scrcpyVersion = scrcpyVersion
        }
    }

    private let adb: AdbClient
    private let resolveTools: @Sendable () async throws -> Tools
    private let workDirectory: URL

    private var serial: String?
    private var active: Segment?
    private var finishedSegments: [URL] = []
    private var accumulated: TimeInterval = 0
    /// When the active segment started producing video. Nil until it does —
    /// the clock reads the accumulated total until then, which is honest: no
    /// video has been captured yet.
    private var activeFirstFrame: Date?
    /// Set when the frame pump gave up — a broken recording has to fail out
    /// loud at `stop`, not hand back a file that decodes into nothing.
    private var pumpFailure: String?

    public init(
        adb: AdbClient,
        workDirectory: URL,
        resolveTools: @escaping @Sendable () async throws -> Tools
    ) {
        self.adb = adb
        self.workDirectory = workDirectory
        self.resolveTools = resolveTools
    }

    /// The tools the *current* segment was started with. Held so a resume uses
    /// the same ffmpeg and the same scrcpy server as the segments before it.
    private var tools: Tools?

    public func status() -> Status? {
        guard let serial else { return nil }
        return Status(
            serial: serial,
            recording: true,
            paused: active == nil,
            elapsedSeconds: elapsed(),
            segments: finishedSegments.count + (active == nil ? 0 : 1))
    }

    public func start(serial: String, options: ScreenRecordOptions) async throws {
        guard self.serial == nil else { throw RecordError.alreadyRecording }
        tools = try await resolveTools()
        try FileManager.default.createDirectory(
            at: workDirectory, withIntermediateDirectories: true)
        self.serial = serial
        accumulated = 0
        finishedSegments = []
        pumpFailure = nil
        do {
            try await beginSegment(serial: serial, options: options)
        } catch {
            // Nothing was captured, so leave no half-started recording behind
            // for the next start to trip over.
            self.serial = nil
            tools = nil
            throw error
        }
    }

    public func pause() async throws {
        guard serial != nil else { throw RecordError.notRecording }
        guard let segment = active else { return }
        active = nil
        activeFirstFrame = nil
        await close(segment, keeping: true)
    }

    public func resume(options: ScreenRecordOptions) async throws {
        guard let serial else { throw RecordError.notRecording }
        guard active == nil else { return }
        try await beginSegment(serial: serial, options: options)
    }

    /// Finish, assemble, and hand back the file.
    ///
    /// The result lands in the working directory, not the capture folder: the
    /// Mac gives the finished file to the editor and nothing is saved until
    /// someone says so, and this keeps that shape.
    public func stop() async throws -> Finished {
        guard serial != nil else { throw RecordError.notRecording }
        if let segment = active {
            active = nil
            activeFirstFrame = nil
            await close(segment, keeping: true)
        }
        let segments = finishedSegments
        let duration = accumulated
        let failure = pumpFailure
        let ffmpeg = tools?.ffmpeg
        serial = nil
        tools = nil
        finishedSegments = []
        accumulated = 0
        pumpFailure = nil

        if let failure {
            for url in segments { try? FileManager.default.removeItem(at: url) }
            throw RecordError.writeFailed(failure)
        }
        let usable = segments.filter { size(of: $0) > 0 }
        guard let first = usable.first else {
            throw RecordError.assembleFailed("the device sent no video")
        }
        let output = try await assemble(usable, first: first, ffmpeg: ffmpeg)
        return Finished(
            path: output.path,
            durationSeconds: duration,
            sizeBytes: size(of: output))
    }

    /// Give up on a recording without producing a file — for a client that went
    /// away, or a daemon shutting down.
    public func discard() async {
        if let segment = active {
            active = nil
            activeFirstFrame = nil
            await close(segment, keeping: false)
        }
        for url in finishedSegments { try? FileManager.default.removeItem(at: url) }
        finishedSegments = []
        accumulated = 0
        serial = nil
        tools = nil
        pumpFailure = nil
    }

    // MARK: - Segments

    private func beginSegment(serial: String, options: ScreenRecordOptions) async throws {
        guard let tools else { throw RecordError.notRecording }
        let index = finishedSegments.count
        let url = workDirectory.appendingPathComponent("segment-\(index).mp4")
        let pipe = FfmpegPipe(
            executable: tools.ffmpeg,
            arguments: RecordArguments.encode(into: url.path),
            label: "record-\(index)")
        do {
            try await pipe.start()
        } catch {
            throw RecordError.startFailed(
                (error as? any LocalizedError)?.errorDescription ?? "\(error)")
        }

        let session = ScrcpySession(
            adb: adb,
            config: .init(
                serial: serial,
                serverVersion: tools.scrcpyVersion,
                localJarPath: tools.scrcpyJar,
                params: RecordArguments.serverParams(
                    scid: ScrcpyServerParams.randomSCID(), options: options)))
        let frames: AsyncThrowingStream<MirrorFramePayload, Error>
        do {
            frames = try await session.start()
        } catch {
            await pipe.cancel()
            await session.stop()
            throw RecordError.startFailed(
                (error as? any LocalizedError)?.errorDescription ?? "\(error)")
        }

        let pump = Task { [weak self] () -> FrameSpan in
            var span = FrameSpan()
            do {
                for try await payload in frames {
                    // The mirror's own mapper produced this, base64 and all,
                    // rather than a second path off the socket: it is the thing
                    // that prepends SPS/PPS to every keyframe, and a recorder
                    // that disagreed with the mirror about what a keyframe
                    // carries would be a file only this app could play.
                    guard payload.kind == "frame", let encoded = payload.data,
                          let bytes = Data(base64Encoded: encoded)
                    else { continue }
                    if span.first == nil {
                        span.first = Date()
                        // Told to the actor once, so the live clock starts where
                        // the video does. One hop per segment, not per frame.
                        await self?.noteFirstFrame(span.first)
                    }
                    span.last = Date()
                    try await pipe.write(bytes)
                }
            } catch is CancellationError {
                return span
            } catch {
                await self?.noteFailure(
                    (error as? any LocalizedError)?.errorDescription ?? "\(error)")
            }
            return span
        }

        activeFirstFrame = nil
        active = Segment(url: url, pipe: pipe, session: session, pump: pump, startedAt: Date())
    }

    /// When the active segment's first frame arrived, for the live clock.
    private func noteFirstFrame(_ at: Date?) {
        guard activeFirstFrame == nil else { return }
        activeFirstFrame = at
    }

    private func noteFailure(_ reason: String) {
        guard pumpFailure == nil else { return }
        pumpFailure = reason
    }

    /// Stop the device first, then the muxer: ffmpeg has to see the end of the
    /// stream to write the index, and killing it first leaves a file no player
    /// will open.
    private func close(_ segment: Segment, keeping: Bool) async {
        await segment.session.stop()
        segment.pump.cancel()
        let span = await segment.pump.value
        if keeping {
            accumulated += span.seconds
            if case .failure(let error) = await segment.pipe.finish() {
                noteFailure(error.errorDescription ?? "\(error)")
            }
            finishedSegments.append(segment.url)
        } else {
            await segment.pipe.cancel()
            try? FileManager.default.removeItem(at: segment.url)
        }
    }

    /// One segment is the recording; several are concatenated.
    private func assemble(_ segments: [URL], first: URL, ffmpeg: String?) async throws -> URL {
        let output = workDirectory.appendingPathComponent(
            "recording-\(Int(Date().timeIntervalSince1970)).mp4")
        guard segments.count > 1, let ffmpeg else {
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.moveItem(at: first, to: output)
            return output
        }
        let listFile = workDirectory.appendingPathComponent("segments.txt")
        try Data(RecordArguments.concatList(segments.map(\.path)).utf8).write(to: listFile)
        let pipe = FfmpegPipe(
            executable: ffmpeg,
            arguments: RecordArguments.concat(listFile: listFile.path, output: output.path),
            label: "concat")
        do {
            try await pipe.start()
        } catch {
            throw RecordError.assembleFailed(
                (error as? any LocalizedError)?.errorDescription ?? "\(error)")
        }
        if case .failure(let error) = await pipe.finish() {
            throw RecordError.assembleFailed(error.errorDescription ?? "\(error)")
        }
        for url in segments { try? FileManager.default.removeItem(at: url) }
        try? FileManager.default.removeItem(at: listFile)
        return output
    }

    private func elapsed() -> TimeInterval {
        guard active != nil, let since = activeFirstFrame else { return accumulated }
        return accumulated + Date().timeIntervalSince(since)
    }

    private func size(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? Int) ?? 0
    }
}
