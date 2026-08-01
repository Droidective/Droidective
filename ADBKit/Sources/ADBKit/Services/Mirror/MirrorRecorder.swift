#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import Foundation

/// Records the live mirror by passthrough-muxing the already-compressed H.264
/// sample buffers into an `.mp4` (no re-encode, negligible cost — so the mirror
/// stays fully live while recording). Audio rides alongside in a *single* AAC
/// track fed by up to two sources — the device's own audio and the Mac's
/// microphone — because players (QuickTime, browsers, chat apps) play only the
/// first audio track, so two tracks would silently drop one source for whoever
/// the clip is sent to. The first appended video sample must be a key frame;
/// `MirrorSession` gates on that, and the writer session starts on that frame's
/// timestamp, which is also the origin of the audio timeline.
///
/// Only ever driven from `MirrorSession`'s serialized isolation (AVFoundation
/// owns its own internal threading), so it's safe to hand across the actor's
/// `await` on `finish()`.
final class MirrorRecorder: @unchecked Sendable {
    enum RecorderError: Error { case cannotConfigure }

    /// How far behind the newest sample the mixer commits audio, giving the
    /// other source a moment to deliver its half of the same span. Only applies
    /// when both sources are live; a single source is appended as it arrives.
    private static let mixLagSeconds = 0.25

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let audioFormat: CMAudioFormatDescription?
    private let audioMode: RecordAudioMode
    private var started = false

    /// Set on the first appended video sample: the device-clock origin the
    /// writer session opened on, paired with the host clock at that instant so
    /// microphone timestamps can be translated onto the same timeline.
    private var timeline: AudioTimeline?
    /// Only used when both sources are on — a single source needs no mixing and
    /// keeps the exact path it had before the microphone existed.
    private var mixdown: PCMMixdown?
    /// Newest frame either source has delivered, for the lagged mixer drain.
    private var newestFrame: Int64 = 0
    private var deviceMuted = false
    private var microphoneMuted = false

    /// - Parameter audio: which sources feed the AAC track. `.muted` writes no
    ///   audio track at all. Pass a mode including `.device` only when the
    ///   session actually supplies device PCM (raw audio on).
    init(url: URL, formatDescription: CMVideoFormatDescription, audio: RecordAudioMode) throws {
        audioMode = audio
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        videoInput = AVAssetWriterInput(
            mediaType: .video, outputSettings: nil, sourceFormatHint: formatDescription)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw RecorderError.cannotConfigure }
        writer.add(videoInput)

        if audio.hasAudio {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: MirrorAudioPlayer.sampleRate,
                AVNumberOfChannelsKey: Int(MirrorAudioPlayer.channelCount),
                AVEncoderBitRateKey: 128_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw RecorderError.cannotConfigure }
            writer.add(input)
            audioInput = input
            audioFormat = Self.pcmFormat()
        } else {
            audioInput = nil
            audioFormat = nil
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        if !started {
            guard writer.startWriting() else { return }
            let origin = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: origin)
            started = true
            // The two clocks are anchored here, at the one instant both are
            // known to refer to: the frame the file opens on.
            timeline = AudioTimeline(
                originDeviceSeconds: origin.seconds,
                originHostSeconds: CMClockGetTime(CMClockGetHostTimeClock()).seconds,
                sampleRate: Int(MirrorAudioPlayer.sampleRate))
            if audioMode.mixesSources {
                mixdown = PCMMixdown(
                    sampleRate: Int(MirrorAudioPlayer.sampleRate),
                    channels: Int(MirrorAudioPlayer.channelCount))
            }
        }
        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }

    /// Mute or unmute a source mid-recording. Muting silences the samples rather
    /// than dropping them, so the track keeps one continuous timeline.
    func setDeviceMuted(_ muted: Bool) { deviceMuted = muted }

    func setMicrophoneMuted(_ muted: Bool) { microphoneMuted = muted }

    /// One chunk of raw interleaved s16le PCM from the device at `pts` (device
    /// clock). A no-op until the video session has started, so audio shares the
    /// video's timeline; a little leading audio before the first key frame is
    /// dropped.
    func appendDeviceAudio(_ pcm: Data, pts: CMTime) {
        guard audioMode.includesDevice, let timeline else { return }
        ingest(deviceMuted ? PCMSamples.silenced(pcm) : pcm,
               frame: timeline.frame(deviceSeconds: pts.seconds), pts: pts)
    }

    /// One chunk of microphone PCM stamped on the *host* clock, translated onto
    /// the device timeline through the anchor taken when recording opened.
    func appendMicrophoneAudio(_ pcm: Data, hostSeconds: Double) {
        guard audioMode.includesMicrophone, let timeline else { return }
        let frame = timeline.frame(hostSeconds: hostSeconds)
        ingest(microphoneMuted ? PCMSamples.silenced(pcm) : pcm,
               frame: frame, pts: Self.time(seconds: timeline.deviceSeconds(frame: frame)))
    }

    /// With one source the samples go straight to the track, exactly as they did
    /// before the microphone existed — no buffering, no re-timestamping. With
    /// two, they go through the mixdown instead and come back out summed.
    private func ingest(_ pcm: Data, frame: Int64, pts: CMTime) {
        guard started else { return }
        guard mixdown != nil, let timeline else {
            appendToTrack(pcm, pts: pts)
            return
        }
        let samples = PCMSamples.decode(pcm)
        guard !samples.isEmpty else { return }
        mixdown?.add(samples: samples, at: frame)
        newestFrame = max(newestFrame, frame + Int64(samples.count / Int(MirrorAudioPlayer.channelCount)))
        let lagFrames = Int64(Self.mixLagSeconds * MirrorAudioPlayer.sampleRate)
        if let chunk = mixdown?.drain(through: newestFrame - lagFrames) {
            emit(chunk, timeline: timeline)
        }
    }

    private func emit(_ chunk: PCMMixdown.Chunk, timeline: AudioTimeline) {
        appendToTrack(
            PCMSamples.encode(chunk.samples),
            pts: Self.time(seconds: timeline.deviceSeconds(frame: chunk.startFrame)))
    }

    private func appendToTrack(_ pcm: Data, pts: CMTime) {
        guard let audioInput, let audioFormat, audioInput.isReadyForMoreMediaData,
              let sampleBuffer = Self.audioSampleBuffer(pcm, pts: pts, format: audioFormat)
        else { return }
        audioInput.append(sampleBuffer)
    }

    private static func time(seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 1_000_000)
    }

    /// Finalize the container and return whether it completed. No-op cancel if
    /// nothing was ever written.
    func finish() async -> Bool {
        guard started else {
            writer.cancelWriting()
            return false
        }
        // Commit whatever the mixer was still holding back for its lag window.
        if let timeline, let tail = mixdown?.flush() { emit(tail, timeline: timeline) }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        return writer.status == .completed
    }

    // MARK: - PCM → CMSampleBuffer

    private static func pcmFormat() -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: MirrorAudioPlayer.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: MirrorAudioPlayer.channelCount, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format)
        return format
    }

    private static func audioSampleBuffer(
        _ pcm: Data, pts: CMTime, format: CMAudioFormatDescription
    ) -> CMSampleBuffer? {
        let frameCount = pcm.count / 4  // 2 channels × 2 bytes
        guard frameCount > 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: pcm.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: pcm.count, flags: 0, blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let blockBuffer else { return nil }
        let copied = pcm.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: pcm.count)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(MirrorAudioPlayer.sampleRate)),
            presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleSize = 4
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: format,
            sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }
        return sampleBuffer
    }
}
#endif
