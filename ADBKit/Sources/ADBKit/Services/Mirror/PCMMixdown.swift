import Foundation

// Deliberately free of Apple frameworks even though it sits in the Mirror
// subsystem: the mixing math is the part most worth testing, and it stays
// compilable (and tested) on the Windows/Linux port where the media stack
// around it is gated out.

/// Interleaved signed-16-bit little-endian PCM — the format scrcpy sends
/// (`audio_codec=raw`) and the one the recorder's AAC encoder is fed.
public enum PCMSamples {
    /// Decode a little-endian s16 buffer. A trailing odd byte (a chunk split
    /// mid-sample) is ignored rather than misread as a sample.
    public static func decode(_ data: Data) -> [Int16] {
        let count = data.count / 2
        guard count > 0 else { return [] }
        var samples = [Int16](repeating: 0, count: count)
        // Explicit little-endian assembly, not a raw load: the wire format is
        // fixed, so it must not follow the host's endianness.
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for index in 0 ..< count {
                let low = UInt16(raw[index * 2])
                let high = UInt16(raw[index * 2 + 1])
                samples[index] = Int16(bitPattern: low | (high << 8))
            }
        }
        return samples
    }

    public static func encode(_ samples: [Int16]) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            for (index, sample) in samples.enumerated() {
                let bits = UInt16(bitPattern: sample)
                raw[index * 2] = UInt8(bits & 0xff)
                raw[index * 2 + 1] = UInt8(bits >> 8)
            }
        }
        return data
    }

    /// Silence every sample — how a live mute is applied, so the track keeps a
    /// continuous timeline instead of developing a hole.
    public static func silenced(_ data: Data) -> Data {
        Data(count: data.count)
    }

    /// Square an input's channel layout up to the stereo the recorder mixes in:
    /// a mono mic is duplicated across both channels (rather than landing in the
    /// left ear only), and a multi-channel interface is reduced to its first
    /// two. A trailing partial frame is dropped.
    public static func stereo(from samples: [Int16], channels: Int) -> [Int16] {
        guard channels > 0 else { return [] }
        let frames = samples.count / channels
        guard channels != 2 else { return Array(samples.prefix(frames * 2)) }
        var stereo = [Int16](repeating: 0, count: frames * 2)
        for frame in 0 ..< frames {
            let source = frame * channels
            stereo[frame * 2] = samples[source]
            stereo[frame * 2 + 1] = channels == 1 ? samples[source] : samples[source + 1]
        }
        return stereo
    }
}

/// Maps the two clocks a recording sees onto one sample timeline.
///
/// Device audio is stamped in the device's clock (the same clock the video
/// packets carry, which is what the writer session opens on); microphone
/// samples arrive stamped in the *host's* clock. Anchoring both at the moment
/// recording starts is what keeps narration from drifting away from the picture
/// over a long take.
public struct AudioTimeline: Sendable, Equatable {
    /// Device-clock timestamp the writer session started on (seconds).
    public let originDeviceSeconds: Double
    /// Host-clock reading taken at that same instant (seconds).
    public let originHostSeconds: Double
    public let sampleRate: Int

    public init(originDeviceSeconds: Double, originHostSeconds: Double, sampleRate: Int = 48_000) {
        self.originDeviceSeconds = originDeviceSeconds
        self.originHostSeconds = originHostSeconds
        self.sampleRate = sampleRate
    }

    /// Frame index for a device-clock timestamp. Negative before the origin —
    /// the mixer drops those, which is the leading audio that precedes the
    /// first key frame.
    public func frame(deviceSeconds: Double) -> Int64 {
        frameCount(seconds: deviceSeconds - originDeviceSeconds)
    }

    /// Frame index for a host-clock timestamp, translated through the anchor.
    public func frame(hostSeconds: Double) -> Int64 {
        frameCount(seconds: hostSeconds - originHostSeconds)
    }

    /// The device-clock timestamp a frame index sits at — what an emitted chunk
    /// is stamped with on its way into the writer.
    public func deviceSeconds(frame: Int64) -> Double {
        originDeviceSeconds + Double(frame) / Double(sampleRate)
    }

    private func frameCount(seconds: Double) -> Int64 {
        let frames = (seconds * Double(sampleRate)).rounded()
        // A non-finite or absurd timestamp (a corrupt packet header) must not
        // trap the Int64 conversion; pin it to the origin instead.
        guard frames.isFinite, frames > -9e18, frames < 9e18 else { return 0 }
        return Int64(frames)
    }
}

/// Sums two live PCM sources onto one timeline.
///
/// Each source calls `add` with its samples positioned by frame index; `drain`
/// emits the contiguous run that is old enough to be considered complete.
/// Whatever a source hasn't delivered for an emitted span reads as silence, so
/// one source stalling (or being muted) never stalls the other — it just leaves
/// the recording quieter.
///
/// Sums accumulate in `Int32` and are clamped once, on the way out: summing two
/// full-scale sources clips rather than wrapping into a loud crackle.
public struct PCMMixdown: Sendable, Equatable {
    public struct Chunk: Sendable, Equatable {
        public let startFrame: Int64
        /// Interleaved samples, `channels` per frame.
        public let samples: [Int16]

        public init(startFrame: Int64, samples: [Int16]) {
            self.startFrame = startFrame
            self.samples = samples
        }
    }

    public let sampleRate: Int
    public let channels: Int
    /// How far ahead of the emitted edge samples may be buffered before the
    /// excess is dropped. Bounds memory when one source races ahead of a
    /// stalled one (or ahead of a drain that never comes).
    private let maxBufferedFrames: Int

    /// Interleaved running sums for frames `[baseFrame, baseFrame + count/channels)`.
    private var accumulator: [Int32] = []
    /// First frame not yet emitted — the timeline's moving edge.
    private var baseFrame: Int64 = 0
    /// One past the newest frame any source has written.
    private var highWaterFrame: Int64 = 0

    public init(sampleRate: Int = 48_000, channels: Int = 2, maxBufferedSeconds: Double = 2) {
        self.sampleRate = sampleRate
        self.channels = channels
        maxBufferedFrames = max(channels, Int(Double(sampleRate) * maxBufferedSeconds))
    }

    /// Frames written but not yet emitted.
    public var bufferedFrames: Int { max(0, Int(highWaterFrame - baseFrame)) }

    /// Mix one source's samples in at `frame`.
    ///
    /// Samples that fall before the emitted edge are dropped (they arrived too
    /// late to be mixed), and samples beyond the buffering window are dropped
    /// too — in both cases without shifting anything else, so a late or runaway
    /// source can't push the other one out of sync.
    public mutating func add(samples: [Int16], at frame: Int64) {
        let frameCount = samples.count / channels
        guard frameCount > 0 else { return }
        let end = frame + Int64(frameCount)
        guard end > baseFrame else { return }

        let start = max(frame, baseFrame)
        guard start < baseFrame + Int64(maxBufferedFrames) else { return }
        let clampedEnd = min(end, baseFrame + Int64(maxBufferedFrames))
        let skippedFrames = Int(start - frame)

        let required = Int(clampedEnd - baseFrame) * channels
        if accumulator.count < required {
            accumulator.append(contentsOf: repeatElement(0, count: required - accumulator.count))
        }
        var destination = Int(start - baseFrame) * channels
        var source = skippedFrames * channels
        while destination < required {
            accumulator[destination] += Int32(samples[source])
            destination += 1
            source += 1
        }
        highWaterFrame = max(highWaterFrame, clampedEnd)
    }

    /// Emit everything up to (not including) `frame` that has been written.
    ///
    /// Callers pass an edge that lags the newest sample seen, giving the other
    /// source a moment to deliver its half of that span before it is committed.
    public mutating func drain(through frame: Int64) -> Chunk? {
        let end = min(frame, highWaterFrame)
        guard end > baseFrame else { return nil }
        let count = Int(end - baseFrame) * channels
        var samples = [Int16](repeating: 0, count: count)
        for index in 0 ..< count {
            samples[index] = Int16(clamping: accumulator[index])
        }
        accumulator.removeFirst(count)
        let chunk = Chunk(startFrame: baseFrame, samples: samples)
        baseFrame = end
        return chunk
    }

    /// Emit everything buffered, ignoring the lag — for finalizing a recording.
    public mutating func flush() -> Chunk? { drain(through: highWaterFrame) }
}

/// Signal level for the microphone meter, as a 0…1 fraction of full scale.
public enum AudioLevel {
    public static func rms(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for sample in samples {
            let value = Double(sample) / 32_768
            sum += value * value
        }
        return Float(min(1, (sum / Double(samples.count)).squareRoot()))
    }
}
