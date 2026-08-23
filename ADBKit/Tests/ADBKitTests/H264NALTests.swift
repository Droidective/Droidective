import Foundation
import Testing
@testable import ADBKit

@Suite struct H264NALTests {
    @Test func splitsBothThreeAndFourByteStartCodes() {
        // 4-byte start code + NAL [0x67,0xAA], 3-byte start code + NAL [0x68,0xBB].
        let data = Data([0, 0, 0, 1, 0x67, 0xAA, 0, 0, 1, 0x68, 0xBB])
        let nals = H264NAL.nalUnits(fromAnnexB: data)
        #expect(nals.count == 2)
        #expect(Array(nals[0]) == [0x67, 0xAA])
        #expect(Array(nals[1]) == [0x68, 0xBB])
    }

    @Test func typeReadsLowFiveBits() {
        #expect(H264NAL.type(of: Data([0x67])) == 7)  // SPS
        #expect(H264NAL.type(of: Data([0x68])) == 8)  // PPS
        #expect(H264NAL.type(of: Data([0x65])) == 5)  // IDR
        #expect(H264NAL.type(of: Data()) == nil)
    }

    @Test func avccPrefixesEachNalWithBigEndianLength() {
        let data = Data([0, 0, 0, 1, 0x67, 0xAA, 0xBB])  // one 3-byte NAL
        #expect(Array(H264NAL.avcc(fromAnnexB: data)) == [0, 0, 0, 3, 0x67, 0xAA, 0xBB])
    }

    @Test func extractsParameterSetsFromCapturedConfigPacket() {
        // Reuse the real emulator fixture: pull the config packet via the decoder,
        // then split its SPS/PPS.
        let bytes = ScrcpyStreamDecoderTests.hexBytes(ScrcpyStreamDecoderTests.fixtureHex)
        var decoder = ScrcpyStreamDecoder(tunnelForward: true)
        let events = decoder.consume(Data(bytes))
        let configPayload = events.compactMap { event -> Data? in
            if case let .packet(header, payload) = event, header.isConfig { return payload }
            return nil
        }.first
        guard let configPayload else {
            Issue.record("no config packet in fixture")
            return
        }

        let nals = H264NAL.nalUnits(fromAnnexB: configPayload)
        #expect(nals.count == 2)  // SPS + PPS

        guard let sets = H264NAL.parameterSets(fromAnnexB: configPayload) else {
            Issue.record("could not extract SPS/PPS")
            return
        }
        #expect(H264NAL.type(of: sets.sps) == 7)
        #expect(H264NAL.type(of: sets.pps) == 8)

        // AVCC output is each NAL prefixed with a 4-byte length.
        let expectedSize = nals.reduce(0) { $0 + 4 + $1.count }
        #expect(H264NAL.avcc(fromAnnexB: configPayload).count == expectedSize)
    }

    @Test func codecStringReadsTheProfileConstraintsAndLevel() {
        // 0x67 NAL header, then High profile (0x64), no constraints, level 4.0.
        #expect(H264NAL.avcCodecString(sps: Data([0x67, 0x64, 0x00, 0x28])) == "avc1.640028")
        // Constrained Baseline, level 3.1 — the shape most phones send.
        #expect(H264NAL.avcCodecString(sps: Data([0x67, 0x42, 0xE0, 0x1F])) == "avc1.42E01F")
    }

    @Test func codecStringRefusesWhatIsNotAnSps() {
        // A PPS has the right length and the wrong type; guessing a profile
        // from it would hand the webview a decoder config for nothing.
        #expect(H264NAL.avcCodecString(sps: Data([0x68, 0x64, 0x00, 0x28])) == nil)
        #expect(H264NAL.avcCodecString(sps: Data([0x67, 0x64, 0x00])) == nil)
        #expect(H264NAL.avcCodecString(sps: Data()) == nil)
    }

    @Test func codecStringOfTheCapturedEmulatorStream() throws {
        // The real device's own answer, not a synthesised one: Constrained
        // Baseline at level 4.1, which is what the emulator negotiated.
        let bytes = ScrcpyStreamDecoderTests.hexBytes(ScrcpyStreamDecoderTests.fixtureHex)
        var decoder = ScrcpyStreamDecoder(tunnelForward: true)
        let events = decoder.consume(Data(bytes))
        let configPayload = try #require(
            events.compactMap { event -> Data? in
                if case let .packet(header, payload) = event, header.isConfig { return payload }
                return nil
            }.first)
        let sets = try #require(H264NAL.parameterSets(fromAnnexB: configPayload))
        #expect(H264NAL.avcCodecString(sps: sets.sps) == "avc1.42C029")
    }
}
