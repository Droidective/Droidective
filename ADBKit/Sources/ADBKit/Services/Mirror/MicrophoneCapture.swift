// Host microphone capture for recordings. Apple-only (AVFoundation capture +
// CoreMedia timestamps) and deliberately confined to this one file, so the
// Windows/Linux port gates it wholesale and swaps in its own input backend
// behind the same chunk-callback shape.
#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import Foundation

/// One delivery of microphone audio, already in the recorder's format.
public struct MicrophoneChunk: Sendable {
    /// Interleaved s16le PCM, 48 kHz, stereo — the same shape scrcpy sends, so
    /// both sources meet in one format.
    public let pcm: Data
    /// Capture timestamp on the *host* clock, in seconds. `AudioTimeline`
    /// translates it onto the device timeline the video is written on.
    public let hostSeconds: Double
    /// 0…1 signal level for the meter, computed here so the UI doesn't have to
    /// touch the samples.
    public let level: Float
}

/// Captures the Mac's microphone as 48 kHz stereo s16le PCM.
///
/// `AVCaptureAudioDataOutput.audioSettings` does the sample-rate and
/// bit-depth conversion in the capture graph (a macOS-only capability), so the
/// only conversion left here is the channel layout, which is pure and tested
/// (`PCMSamples.stereo`).
///
/// `AVCaptureSession` isn't `Sendable` and both its configuration and its
/// teardown block, so every touch of it is funnelled through one serial queue
/// and the async entry points hop onto that queue rather than blocking a
/// cooperative thread.
public final class MicrophoneCapture: NSObject, @unchecked Sendable {
    /// A selectable host input.
    public struct Input: Sendable, Identifiable, Equatable {
        public let id: String
        public let name: String
    }

    public enum Authorization: Sendable, Equatable {
        case notDetermined
        case denied
        case authorized
    }

    public enum CaptureError: Error, LocalizedError, Equatable {
        case notAuthorized
        case noInputDevice
        case configurationFailed
        case unsupportedFormat(sampleRate: Int, channels: Int)

        public var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Droidective doesn’t have microphone access."
            case .noInputDevice:
                return "No microphone is available."
            case .configurationFailed:
                return "Couldn’t start the microphone."
            case let .unsupportedFormat(sampleRate, channels):
                return "The microphone delivered \(sampleRate) Hz / \(channels)ch audio, "
                    + "which can’t be mixed into the recording."
            }
        }
    }

    /// The rate everything downstream assumes: scrcpy's raw audio, the AAC
    /// encoder, and the mixdown timeline all run at 48 kHz stereo.
    public static let sampleRate = 48_000
    public static let channelCount = 2

    // MARK: - Device discovery

    /// Every input the user can pick, default input first. Names come from the
    /// system, so a picker can show them as-is.
    public static func availableInputs() -> [Input] {
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let inputs = discovered.map { Input(id: $0.uniqueID, name: $0.localizedName) }
        guard let defaultID, let index = inputs.firstIndex(where: { $0.id == defaultID }) else {
            return inputs
        }
        var ordered = inputs
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    public static func authorization() -> Authorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Show the system prompt (only ever shown once by macOS; a previously
    /// denied app resolves immediately to false).
    public static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - Capture

    private let deviceID: String?
    private let queue = DispatchQueue(label: "com.rohindh.droidective.microphone")
    private let session = AVCaptureSession()
    private var onChunk: (@Sendable (MicrophoneChunk) -> Void)?
    /// Set when a delivered buffer can't be used; reported once so a bad format
    /// doesn't spam the log for every 10 ms of audio.
    private var formatFailure: CaptureError?
    private var running = false

    /// - Parameter deviceID: an `Input.id`, or nil for the system default input.
    public init(deviceID: String? = nil) {
        self.deviceID = deviceID
        super.init()
    }

    /// Build the graph and start delivering chunks. Throws if access was denied,
    /// the device is gone, or the graph won't configure.
    ///
    /// A first-ever use prompts here rather than relying on the caller having
    /// asked: recordings start from several places (the Screen Record screen,
    /// the mirror's record button, a hotkey) and only one of them has a picker
    /// to hang the request off.
    public func start(onChunk: @escaping @Sendable (MicrophoneChunk) -> Void) async throws {
        switch Self.authorization() {
        case .authorized:
            break
        case .notDetermined:
            guard await Self.requestAccess() else { throw CaptureError.notAuthorized }
        case .denied:
            throw CaptureError.notAuthorized
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try configure(onChunk: onChunk)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if running { session.stopRunning() }
                running = false
                onChunk = nil
                continuation.resume()
            }
        }
    }

    /// A format problem seen while capturing, if any — the recording continues
    /// without microphone audio rather than failing outright.
    public func failure() async -> CaptureError? {
        await withCheckedContinuation { (continuation: CheckedContinuation<CaptureError?, Never>) in
            queue.async { [self] in continuation.resume(returning: formatFailure) }
        }
    }

    private func configure(onChunk: @escaping @Sendable (MicrophoneChunk) -> Void) throws {
        guard !running else { return }
        let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) }
            ?? AVCaptureDevice.default(for: .audio)
        guard let device else { throw CaptureError.noInputDevice }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw CaptureError.noInputDevice
        }

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureError.configurationFailed
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        // The capture graph converts to the recorder's rate and bit depth. The
        // channel count is deliberately left to the device — a mono mic that
        // can't be upmixed here would otherwise fail the whole graph — and
        // `PCMSamples.stereo` squares it up.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CaptureError.configurationFailed
        }
        session.addOutput(output)
        session.commitConfiguration()

        self.onChunk = onChunk
        formatFailure = nil
        session.startRunning()
        running = true
    }
}

extension MicrophoneCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Called on `queue`, the same serial queue that owns the session.
        guard let onChunk, formatFailure == nil else { return }
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { return }

        let channels = Int(asbd.mChannelsPerFrame)
        guard Int(asbd.mSampleRate.rounded()) == Self.sampleRate, channels > 0 else {
            formatFailure = .unsupportedFormat(
                sampleRate: Int(asbd.mSampleRate.rounded()), channels: channels)
            return
        }
        guard let data = Self.copyBytes(from: sampleBuffer) else { return }

        let samples = PCMSamples.stereo(from: PCMSamples.decode(data), channels: channels)
        guard !samples.isEmpty else { return }
        onChunk(MicrophoneChunk(
            pcm: PCMSamples.encode(samples),
            hostSeconds: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds,
            level: AudioLevel.rms(samples)))
    }

    private static func copyBytes(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: length)
        let status = bytes.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: length, destination: base)
        }
        guard status == kCMBlockBufferNoErr else { return nil }
        return Data(bytes)
    }
}
#endif
