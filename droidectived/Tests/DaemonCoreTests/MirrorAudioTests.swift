import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The mirror's audio half, from the socket's bytes to the wire.
///
/// The interesting decisions are all refusals: scrcpy answers a device that
/// *cannot* capture audio with a codec sentinel rather than an error, and a
/// client fed those bytes anyway would play noise. Every one of them has to
/// leave the mirror silent and otherwise working — losing the sound is not
/// losing the mirror.
@Suite struct MirrorAudioTests {
    /// The audio socket's shape: a 4-byte codec id, then `[12B header][payload]`.
    private func socketBytes(codec: UInt32, packets: [(pts: UInt64, payload: [UInt8])]) -> Data {
        var data = Data()
        withUnsafeBytes(of: codec.bigEndian) { data.append(contentsOf: $0) }
        for packet in packets {
            withUnsafeBytes(of: packet.pts.bigEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(packet.payload.count).bigEndian) {
                data.append(contentsOf: $0)
            }
            data.append(contentsOf: packet.payload)
        }
        return data
    }

    /// Run the session's own pump over a canned socket and collect what reached
    /// the wire.
    private func pumped(_ bytes: Data) async -> [MirrorFramePayload] {
        let (source, sourceSink) = AsyncThrowingStream.makeStream(of: Data.self)
        sourceSink.yield(bytes)
        sourceSink.finish()

        let (wire, wireSink) = AsyncThrowingStream.makeStream(of: MirrorFramePayload.self)
        await ScrcpySession.pumpAudio(source, into: wireSink)
        wireSink.finish()

        return await Self.drain(wire)
    }

    /// Everything the wire carried. The stream is a throwing one, but this pump
    /// is written never to throw — losing the sound must not look like losing
    /// the mirror — so a throw here is a real failure and not swallowed.
    private static func drain(
        _ wire: AsyncThrowingStream<MirrorFramePayload, Error>
    ) async -> [MirrorFramePayload] {
        var collected: [MirrorFramePayload] = []
        do {
            for try await payload in wire { collected.append(payload) }
        } catch {
            Issue.record("the audio pump threw: \(error)")
        }
        return collected
    }

    private let raw = ScrcpyCodecID.raw.rawValue

    @Test func rawPcmReachesTheWireBehindTheFormatThatDescribesIt() async {
        let payloads = await pumped(
            socketBytes(codec: raw, packets: [(pts: 1_000, payload: [1, 2, 3, 4])]))

        // Order is the whole reason audio shares the video subscription: a
        // client cannot play a buffer before it knows the format.
        #expect(payloads.map(\.kind) == ["audioConfig", "audio"])
        #expect(payloads.first?.sampleRate == 48_000)
        #expect(payloads.first?.channels == 2)
        #expect(payloads.last?.pts == 1_000)
        #expect(payloads.last?.data == Data([1, 2, 3, 4]).base64EncodedString())
    }

    @Test func aDeviceThatCannotCaptureAudioIsSilentRatherThanNoisy() async {
        // Codec id 0: Android < 11, or output capture refused. scrcpy says it
        // with a sentinel rather than an error, so nothing downstream would
        // notice if the bytes were forwarded anyway.
        #expect(await pumped(socketBytes(codec: 0, packets: [])).isEmpty)
    }

    @Test func aDeviceSideConfigurationErrorIsAlsoJustSilence() async {
        #expect(await pumped(socketBytes(codec: 1, packets: [])).isEmpty)
    }

    @Test func aCodecThisClientCannotPlaySendsNothingAtAll() async {
        // Opus is a codec we model, so it decodes — and that is exactly why it
        // needs saying: the page has no decoder, and forwarding it would put
        // compressed frames into a PCM graph.
        let payloads = await pumped(
            socketBytes(
                codec: ScrcpyCodecID.opus.rawValue,
                packets: [(pts: 1_000, payload: [9, 9, 9, 9])]))
        #expect(payloads.isEmpty)
    }

    @Test func aConfigPacketIsNotAudioToPlay() async {
        // Raw PCM never needs one, so a config packet on this socket describes
        // a codec that does — it is not samples.
        let configFlag: UInt64 = 1 << 62
        let payloads = await pumped(
            socketBytes(
                codec: raw,
                packets: [
                    (pts: configFlag, payload: [7, 7]),
                    (pts: 2_000, payload: [1, 2]),
                ]))

        #expect(payloads.map(\.kind) == ["audioConfig", "audio"])
        #expect(payloads.last?.pts == 2_000)
    }

    @Test func anEmptyPacketIsNotForwarded() async {
        // A zero-length buffer is nothing to play, and a graph fed one still
        // pays for the hop.
        let payloads = await pumped(
            socketBytes(codec: raw, packets: [(pts: 1_000, payload: [])]))
        #expect(payloads.map(\.kind) == ["audioConfig"])
    }

    @Test func aSocketSplitAcrossReadsStillDecodes() async {
        // TCP does not respect packet boundaries, and the codec id alone can
        // arrive in two reads.
        let whole = socketBytes(codec: raw, packets: [(pts: 1_000, payload: [1, 2, 3, 4])])
        let (source, sourceSink) = AsyncThrowingStream.makeStream(of: Data.self)
        for byte in whole { sourceSink.yield(Data([byte])) }
        sourceSink.finish()

        let (wire, wireSink) = AsyncThrowingStream.makeStream(of: MirrorFramePayload.self)
        await ScrcpySession.pumpAudio(source, into: wireSink)
        wireSink.finish()

        #expect(await Self.drain(wire).map(\.kind) == ["audioConfig", "audio"])
    }

    @Test func theSubscriptionAsksForSoundRatherThanAlwaysGettingIt() {
        // A wall of six tiles that never plays audio would otherwise be six
        // device-side encoders for nothing.
        #expect(StreamProtocol.Command.Params().wantsAudio == false)
        #expect(StreamProtocol.Command.Params(audio: false).wantsAudio == false)
        #expect(StreamProtocol.Command.Params(audio: true).wantsAudio)
    }

    @Test func theAudioPayloadsSurviveTheWire() throws {
        // They ride the same envelope as the video kinds, so a field added for
        // one must not be dropped for the other.
        for payload in [
            MirrorFramePayload.audioConfig(sampleRate: 48_000, channels: 2),
            MirrorFramePayload.audio(Data([1, 2, 3]), pts: 42),
            MirrorFramePayload.frame(Data([4, 5]), key: true, pts: 7),
        ] {
            let round = try JSONDecoder().decode(
                MirrorFramePayload.self, from: DaemonProtocol.encoded(payload))
            #expect(round == payload)
        }
    }
}
