import ADBKit
import Foundation

/// The wire shapes for screen recording.
///
/// One recording at a time, and the daemon holds it: the client is a set of
/// buttons over a session that lives here, which is why start/pause/resume/stop
/// are four verbs rather than a stream. The elapsed time a client shows is its
/// own timer from `startedAt` — a tick per second over a socket would be a
/// stream topic carrying one number.
public enum RecordProtocol {

    /// The knobs, as `ScreenRecordOptions` holds them.
    ///
    /// Audio is deliberately absent rather than accepted-and-ignored: scrcpy
    /// carries device audio as a second stream and muxing it means decoding,
    /// resampling and interleaving against the video's clock, which the Mac
    /// does with AVFoundation and this does not do yet. A field that quietly
    /// did nothing would be worse than the screen saying so.
    public struct Options: Codable, Equatable, Sendable {
        /// Longest side in px; 0 is the device's own size.
        public let maxSize: Int
        /// Video bit-rate in Mbps; 0 is scrcpy's default.
        public let bitRateMbps: Int
        /// Frame-rate cap; 0 is unlimited.
        public let maxFps: Int

        public init(maxSize: Int = 0, bitRateMbps: Int = 0, maxFps: Int = 0) {
            self.maxSize = maxSize
            self.bitRateMbps = bitRateMbps
            self.maxFps = maxFps
        }

        public var model: ScreenRecordOptions {
            ScreenRecordOptions(maxSize: maxSize, bitRateMbps: bitRateMbps, maxFps: maxFps)
        }
    }

    public struct StartRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let options: Options

        public init(serial: String, options: Options = Options()) {
            self.serial = serial
            self.options = options
        }
    }

    /// What is being recorded, or that nothing is.
    ///
    /// `recording: false` is an answer rather than a 404: a screen that has
    /// just opened asks this to find out whether a recording it did not start
    /// is already running, and "no" is the ordinary reply.
    public struct StatusResponse: Codable, Equatable, Sendable {
        public let recording: Bool
        public let paused: Bool
        public let serial: String?
        public let elapsedSeconds: Double
        public let segments: Int
        /// False when ffmpeg is not installed, so a screen can offer the
        /// download before someone presses record rather than after.
        public let ffmpegReady: Bool

        public init(
            recording: Bool, paused: Bool, serial: String?,
            elapsedSeconds: Double, segments: Int, ffmpegReady: Bool
        ) {
            self.recording = recording
            self.paused = paused
            self.serial = serial
            self.elapsedSeconds = elapsedSeconds
            self.segments = segments
            self.ffmpegReady = ffmpegReady
        }

        public init(_ status: DeviceRecorder.Status?, ffmpegReady: Bool) {
            self.init(
                recording: status != nil,
                paused: status?.paused ?? false,
                serial: status?.serial,
                elapsedSeconds: status?.elapsedSeconds ?? 0,
                segments: status?.segments ?? 0,
                ffmpegReady: ffmpegReady)
        }
    }

    /// Where the finished file landed, and what it is.
    ///
    /// A temporary path, not the capture folder — nothing is saved until
    /// someone says so, which is what the Mac's editor-first flow does.
    public struct StoppedResponse: Codable, Equatable, Sendable {
        public let path: String
        public let durationSeconds: Double
        public let sizeBytes: Int

        public init(_ finished: DeviceRecorder.Finished) {
            path = finished.path
            durationSeconds = finished.durationSeconds
            sizeBytes = finished.sizeBytes
        }
    }

    static let badRequest = DaemonProtocol.ErrorBody(
        code: "bad_request", message: "That is not a recording request.", detail: nil)

    /// Why a recording could not start or finish.
    ///
    /// A missing ffmpeg gets its own code, because it is the one failure with
    /// something the screen can offer to do about it.
    static func failure(_ error: any Error) -> (status: Int, body: DaemonProtocol.ErrorBody) {
        let message = (error as? any LocalizedError)?.errorDescription ?? "\(error)"
        guard let recordError = error as? DeviceRecorder.RecordError else {
            return (500, DaemonProtocol.ErrorBody(
                code: "record_failed", message: message, detail: nil))
        }
        switch recordError {
        case .ffmpegMissing:
            return (422, DaemonProtocol.ErrorBody(
                code: "ffmpeg_missing", message: message, detail: nil))
        case .alreadyRecording, .notRecording:
            return (409, DaemonProtocol.ErrorBody(
                code: "wrong_state", message: message, detail: nil))
        case .startFailed, .writeFailed, .assembleFailed:
            return (502, DaemonProtocol.ErrorBody(
                code: "record_failed", message: message, detail: nil))
        }
    }
}

/// The five recording routes.
enum RecordRoutes {
    static func status(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        (200, DaemonProtocol.encoded(await backend.recordingStatus()))
    }

    static func start(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard
            let request = try? JSONDecoder().decode(RecordProtocol.StartRequest.self, from: body),
            !request.serial.isEmpty
        else { return (400, DaemonProtocol.encoded(RecordProtocol.badRequest)) }
        do {
            try await backend.startRecording(request)
            return (200, DaemonProtocol.encoded(await backend.recordingStatus()))
        } catch {
            let refusal = RecordProtocol.failure(error)
            return (refusal.status, DaemonProtocol.encoded(refusal.body))
        }
    }

    static func pause(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        do {
            try await backend.pauseRecording()
            return (200, DaemonProtocol.encoded(await backend.recordingStatus()))
        } catch {
            let refusal = RecordProtocol.failure(error)
            return (refusal.status, DaemonProtocol.encoded(refusal.body))
        }
    }

    static func resume(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        // The options travel again on a resume because each span is its own
        // scrcpy session — a resume with different settings would otherwise
        // produce segments that cannot be concatenated.
        let options =
            (try? JSONDecoder().decode(RecordProtocol.Options.self, from: body))
            ?? RecordProtocol.Options()
        do {
            try await backend.resumeRecording(options)
            return (200, DaemonProtocol.encoded(await backend.recordingStatus()))
        } catch {
            let refusal = RecordProtocol.failure(error)
            return (refusal.status, DaemonProtocol.encoded(refusal.body))
        }
    }

    static func stop(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        do {
            return (200, DaemonProtocol.encoded(
                RecordProtocol.StoppedResponse(try await backend.stopRecording())))
        } catch {
            let refusal = RecordProtocol.failure(error)
            return (refusal.status, DaemonProtocol.encoded(refusal.body))
        }
    }
}
