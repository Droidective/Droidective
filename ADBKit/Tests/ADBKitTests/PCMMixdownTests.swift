import Foundation
import Testing

@testable import ADBKit

@Suite struct PCMSamplesTests {
    @Test func decodesLittleEndianRegardlessOfHost() {
        #expect(PCMSamples.decode(Data([0x00, 0x80])) == [Int16.min])
        #expect(PCMSamples.decode(Data([0xff, 0x7f])) == [Int16.max])
        #expect(PCMSamples.decode(Data([0x01, 0x00, 0xff, 0xff])) == [1, -1])
    }

    @Test func roundTripsThroughEncode() {
        let samples: [Int16] = [0, 1, -1, 1234, -4321, Int16.max, Int16.min]
        #expect(PCMSamples.decode(PCMSamples.encode(samples)) == samples)
    }

    @Test func ignoresATrailingHalfSample() {
        // A chunk boundary can split a sample; the odd byte must be dropped,
        // not paired with a zero into a bogus value.
        #expect(PCMSamples.decode(Data([0x01, 0x00, 0x02])) == [1])
        #expect(PCMSamples.decode(Data([0x7f])) == [])
        #expect(PCMSamples.decode(Data()) == [])
    }

    @Test func monoInputIsDuplicatedAcrossBothChannels() {
        // A mono USB mic must not end up in the left ear only.
        #expect(PCMSamples.stereo(from: [5, -7], channels: 1) == [5, 5, -7, -7])
    }

    @Test func stereoInputPassesThroughAndMultiChannelKeepsTheFirstPair() {
        #expect(PCMSamples.stereo(from: [1, 2, 3, 4], channels: 2) == [1, 2, 3, 4])
        #expect(PCMSamples.stereo(from: [1, 2, 3, 4, 5, 6], channels: 3) == [1, 2, 4, 5])
    }

    @Test func partialTrailingFramesAreDroppedNotPaddedWithSilence() {
        #expect(PCMSamples.stereo(from: [1, 2, 3], channels: 2) == [1, 2])
        #expect(PCMSamples.stereo(from: [1, 2], channels: 3) == [])
        #expect(PCMSamples.stereo(from: [1, 2], channels: 0) == [])
    }

    @Test func silencingKeepsTheLengthSoTheTimelineDoesNotShift() {
        let data = PCMSamples.encode([500, -500, 32_000])
        let silent = PCMSamples.silenced(data)
        #expect(silent.count == data.count)
        #expect(PCMSamples.decode(silent) == [0, 0, 0])
    }
}

@Suite struct AudioTimelineTests {
    private let timeline = AudioTimeline(
        originDeviceSeconds: 10, originHostSeconds: 100, sampleRate: 48_000)

    @Test func deviceTimestampsCountFromTheOrigin() {
        #expect(timeline.frame(deviceSeconds: 10) == 0)
        #expect(timeline.frame(deviceSeconds: 11) == 48_000)
        #expect(timeline.frame(deviceSeconds: 10.5) == 24_000)
    }

    @Test func hostTimestampsTranslateThroughTheAnchor() {
        // The two clocks read 90 seconds apart; the same instant must land on
        // the same frame from either side.
        #expect(timeline.frame(hostSeconds: 100) == 0)
        #expect(timeline.frame(hostSeconds: 100.5) == timeline.frame(deviceSeconds: 10.5))
        #expect(timeline.frame(hostSeconds: 101) == 48_000)
    }

    @Test func audioBeforeTheOriginIsNegativeNotWrapped() {
        #expect(timeline.frame(deviceSeconds: 9.5) == -24_000)
        #expect(timeline.frame(hostSeconds: 99.5) == -24_000)
    }

    @Test func framesConvertBackToDeviceSeconds() {
        #expect(timeline.deviceSeconds(frame: 0) == 10)
        #expect(timeline.deviceSeconds(frame: 48_000) == 11)
        #expect(abs(timeline.deviceSeconds(frame: 24_000) - 10.5) < 0.000_001)
    }

    @Test func nonFiniteOrAbsurdTimestampsPinToTheOriginInsteadOfTrapping() {
        #expect(timeline.frame(deviceSeconds: .nan) == 0)
        #expect(timeline.frame(deviceSeconds: .infinity) == 0)
        #expect(timeline.frame(hostSeconds: -.infinity) == 0)
        #expect(timeline.frame(deviceSeconds: 1e300) == 0)
    }
}

@Suite struct PCMMixdownTests {
    /// One stereo frame of a constant value, `frames` long.
    private func tone(_ value: Int16, frames: Int) -> [Int16] {
        [Int16](repeating: value, count: frames * 2)
    }

    @Test func aLoneSourcePassesThroughUnchanged() {
        var mixdown = PCMMixdown()
        mixdown.add(samples: tone(1_000, frames: 4), at: 0)
        let chunk = mixdown.drain(through: 4)
        #expect(chunk?.startFrame == 0)
        #expect(chunk?.samples == tone(1_000, frames: 4))
    }

    @Test func alignedSourcesSum() {
        var mixdown = PCMMixdown()
        mixdown.add(samples: tone(1_000, frames: 4), at: 0)
        mixdown.add(samples: tone(250, frames: 4), at: 0)
        #expect(mixdown.drain(through: 4)?.samples == tone(1_250, frames: 4))
    }

    @Test func aLateStartingSourceOnlyMixesFromWhereItBegins() {
        var mixdown = PCMMixdown()
        mixdown.add(samples: tone(1_000, frames: 4), at: 0)
        // The mic joins two frames in — narration starting after the recording.
        mixdown.add(samples: tone(500, frames: 2), at: 2)
        let samples = mixdown.drain(through: 4)?.samples
        #expect(samples == tone(1_000, frames: 2) + tone(1_500, frames: 2))
    }

    @Test func gapsInASourceReadAsSilenceNotAsAShift() {
        var mixdown = PCMMixdown()
        mixdown.add(samples: tone(700, frames: 2), at: 0)
        // Frames 2–3 never arrive from either source; frame 4 does.
        mixdown.add(samples: tone(700, frames: 1), at: 4)
        let chunk = mixdown.drain(through: 5)
        #expect(chunk?.samples == tone(700, frames: 2) + tone(0, frames: 2) + tone(700, frames: 1))
    }

    /// What the in-recording mute chips promise: silencing one source leaves
    /// the other one untouched, and the timeline doesn't shift (mute writes
    /// silence rather than dropping samples).
    @Test func mutingOneSourceLeavesTheOtherAudible() {
        var mixdown = PCMMixdown()
        let muted = PCMSamples.decode(PCMSamples.silenced(PCMSamples.encode(tone(9_000, frames: 4))))
        mixdown.add(samples: muted, at: 0)
        mixdown.add(samples: tone(1_200, frames: 4), at: 0)
        let chunk = mixdown.drain(through: 4)
        #expect(chunk?.startFrame == 0)
        #expect(chunk?.samples == tone(1_200, frames: 4))
    }

    @Test func mutingBothSourcesWritesSilenceNotAGap() {
        var mixdown = PCMMixdown()
        mixdown.add(samples: tone(0, frames: 3), at: 0)
        mixdown.add(samples: tone(0, frames: 3), at: 0)
        let chunk = mixdown.drain(through: 3)
        // Three frames of silence, so the next chunk still lands at frame 3.
        #expect(chunk?.samples == tone(0, frames: 3))
        mixdown.add(samples: tone(500, frames: 1), at: 3)
        #expect(mixdown.drain(through: 4)?.startFrame == 3)
    }

    @Test func summedFullScaleSourcesClipRatherThanWrap() {
        var mixdown = PCMMixdown()
        mixdown.add(samples: tone(Int16.max, frames: 2), at: 0)
        mixdown.add(samples: tone(Int16.max, frames: 2), at: 0)
        #expect(mixdown.drain(through: 2)?.samples == tone(Int16.max, frames: 2))

        var negative = PCMMixdown()
        negative.add(samples: tone(Int16.min, frames: 2), at: 0)
        negative.add(samples: tone(Int16.min, frames: 2), at: 0)
        #expect(negative.drain(through: 2)?.samples == tone(Int16.min, frames: 2))
    }

    @Test func drainNeverRunsAheadOfWhatWasWritten() {
        var mixdown = PCMMixdown()
        mixdown.add(samples: tone(100, frames: 3), at: 0)
        // Asked for 10 frames, only 3 exist: emit those, and don't advance past
        // them (frames 3+ may still arrive).
        let chunk = mixdown.drain(through: 10)
        #expect(chunk?.samples.count == 3 * 2)
        #expect(mixdown.drain(through: 10) == nil)

        mixdown.add(samples: tone(100, frames: 1), at: 3)
        #expect(mixdown.drain(through: 10)?.startFrame == 3)
    }

    @Test func nothingBufferedDrainsToNil() {
        var mixdown = PCMMixdown()
        #expect(mixdown.drain(through: 100) == nil)
        #expect(mixdown.flush() == nil)
        mixdown.add(samples: [], at: 0)
        #expect(mixdown.drain(through: 100) == nil)
    }

    @Test func samplesArrivingAfterTheirSpanWasEmittedAreDropped() {
        var mixdown = PCMMixdown()
        mixdown.add(samples: tone(1_000, frames: 4), at: 0)
        _ = mixdown.drain(through: 4)
        // A straggler for frames 0–1: too late to mix, and it must not be
        // re-emitted at the new edge (which would duplicate audio).
        mixdown.add(samples: tone(9_000, frames: 2), at: 0)
        #expect(mixdown.drain(through: 10) == nil)

        // The part of a straddling chunk that is still ahead of the edge is kept.
        mixdown.add(samples: tone(300, frames: 6), at: 2)
        let chunk = mixdown.drain(through: 8)
        #expect(chunk?.startFrame == 4)
        #expect(chunk?.samples == tone(300, frames: 4))
    }

    @Test func aRunawaySourceCannotGrowTheBufferWithoutBound() {
        var mixdown = PCMMixdown(sampleRate: 48_000, channels: 2, maxBufferedSeconds: 0.5)
        mixdown.add(samples: tone(500, frames: 48_000), at: 0)
        #expect(mixdown.bufferedFrames == 24_000)
        // Far beyond the window: dropped outright rather than allocating a
        // multi-minute gap of silence.
        mixdown.add(samples: tone(500, frames: 10), at: 5_000_000)
        #expect(mixdown.bufferedFrames == 24_000)
    }

    @Test func flushEmitsTheTailThenNothing() {
        var mixdown = PCMMixdown()
        mixdown.add(samples: tone(400, frames: 5), at: 0)
        _ = mixdown.drain(through: 2)
        let tail = mixdown.flush()
        #expect(tail?.startFrame == 2)
        #expect(tail?.samples == tone(400, frames: 3))
        #expect(mixdown.flush() == nil)
    }

    @Test func monoAndOtherLayoutsCountFramesByChannel() {
        var mixdown = PCMMixdown(sampleRate: 48_000, channels: 1)
        mixdown.add(samples: [10, 20, 30], at: 0)
        mixdown.add(samples: [1, 2, 3], at: 0)
        #expect(mixdown.drain(through: 3)?.samples == [11, 22, 33])
    }
}

@Suite struct AudioLevelTests {
    @Test func silenceReadsZeroAndFullScaleReadsOne() {
        #expect(AudioLevel.rms([0, 0, 0]) == 0)
        #expect(AudioLevel.rms([]) == 0)
        #expect(abs(AudioLevel.rms([Int16.max, Int16.max]) - 1) < 0.001)
        #expect(AudioLevel.rms([Int16.min, Int16.min]) == 1)
    }

    @Test func quietSignalsSitBetween() {
        let level = AudioLevel.rms([3_276, -3_276, 3_276, -3_276])
        #expect(level > 0.09 && level < 0.11)
    }
}
