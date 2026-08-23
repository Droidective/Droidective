import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The scrcpy → WebCodecs mapping.
///
/// Driven by the *captured emulator stream* wherever it can be, rather than by
/// bytes invented to suit the assertions: the codec string, the packet flags and
/// the Annex-B framing are all things a real device decides, and a synthetic
/// fixture would only prove the mapper agrees with itself.
@Suite struct MirrorStreamTests {
    /// Captured live from emulator-5554 (scrcpy 4.0, forward tunnel, video
    /// socket, max_size=800): dummy `0x00` + 64-byte name "sdk_gphone64_arm64"
    /// + "h264" + session meta (flags 0x80000000, 800x500) + the config packet
    /// with its 33-byte SPS/PPS + the start of the next packet.
    ///
    /// The same bytes as `ScrcpyStreamDecoderTests.fixtureHex`, which is the
    /// canonical copy — that suite owns the capture and regenerating it is
    /// `scripts/emulator-harness.sh --record`. Duplicated rather than shared
    /// because it lives in ADBKit's *test* target, which this package cannot
    /// import, and a real capture is still worth more here than bytes invented
    /// to suit the assertions.
    private static let fixtureHex = """
        0073646b5f6770686f6e6536345f61726d3634000000000000000000000000000000000000\
        00000000000000000000000000000000000000000000000000000000683236348000000000\
        000320000001f4400000000000000000000021000000016742c0298d680c8107e790808080\
        83c2211a800000000168ce01a835c82000000a42f7ce9400003d730000000165b80004059f\
        daef2ea7f14000400b519515
        """

    private static func hexBytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        let clean = hex.filter { !$0.isWhitespace }
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index ..< next], radix: 16) else { break }
            out.append(byte)
            index = next
        }
        return out
    }

    /// Where the captured config packet ends: dummy 1 + name 64 + codec 4 +
    /// session meta 12 + packet header 12 + SPS/PPS 33. Everything after it is
    /// the *start* of the next packet — the capture was taken to prove the
    /// handshake, so it stops mid-frame.
    private static let capturedPrefix = 1 + 64 + 4 + 12 + 12 + 33

    /// The real stream's events, optionally followed by complete media packets.
    ///
    /// The handshake, the dimensions and the SPS/PPS are the device's own. The
    /// appended frames are synthesised, because the capture has no complete one
    /// — and for these rules their bytes are arbitrary anyway: what is under
    /// test is the framing around them.
    private func capturedEvents(
        followedBy frames: [(key: Bool, pts: UInt64, payload: Data)] = []
    ) -> [ScrcpyStreamDecoder.Event] {
        var bytes = Data(Self.hexBytes(Self.fixtureHex).prefix(Self.capturedPrefix))
        for frame in frames { bytes.append(Self.packet(frame)) }
        var decoder = ScrcpyStreamDecoder(tunnelForward: true)
        return decoder.consume(bytes)
    }

    /// One scrcpy media packet: the 8-byte pts/flags word then the 4-byte size.
    private static func packet(_ frame: (key: Bool, pts: UInt64, payload: Data)) -> Data {
        var out = Data()
        let ptsFlags = frame.pts | (frame.key ? 1 << 61 : 0)
        withUnsafeBytes(of: ptsFlags.bigEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(frame.payload.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(frame.payload)
        return out
    }

    private func map(_ events: [ScrcpyStreamDecoder.Event]) throws -> [MirrorFramePayload] {
        var mapper = MirrorStreamMapper()
        var out: [MirrorFramePayload] = []
        for event in events { out.append(contentsOf: try mapper.map(event)) }
        return out
    }

    @Test func configCarriesWhatVideoDecoderNeedsToBeConfigured() throws {
        let payloads = try map(capturedEvents())
        let config = try #require(payloads.first { $0.kind == "config" })

        // The device's own answer: Constrained Baseline at level 4.1, and the
        // 800×500 the emulator negotiated.
        #expect(config.codec == "avc1.42C029")
        #expect(config.width == 800)
        #expect(config.height == 500)
        #expect(config.deviceName == "sdk_gphone64_arm64")
        // A config is not a frame and must not look like one.
        #expect(config.data == nil)
        #expect(config.key == nil)
    }

    @Test func theConfigComesBeforeAnyFrame() throws {
        // The whole reason both kinds share one topic: a client cannot decode
        // before it has configured, and ordering is the guarantee that makes
        // that free rather than something it has to sequence itself.
        let payloads = try map(
            capturedEvents(followedBy: [(key: true, pts: 1, payload: Data([0x65, 0xAA]))]))
        let config = try #require(payloads.firstIndex { $0.kind == "config" })
        let firstFrame = try #require(payloads.firstIndex { $0.kind == "frame" })
        #expect(config < firstFrame)
    }

    @Test func aKeyframeCarriesTheParameterSetsAheadOfIt() throws {
        // Annex-B decoding reads SPS/PPS out of the stream, and scrcpy sends
        // them once. Without this a decoder that was reset — or a client that
        // reconnected — never recovers.
        let idr = Data([0, 0, 0, 1, 0x65, 0xAA, 0xBB])
        let events = capturedEvents(followedBy: [(key: true, pts: 42, payload: idr)])
        let sets = try #require(
            events.compactMap { event -> Data? in
                if case let .packet(header, payload) = event, header.isConfig { return payload }
                return nil
            }.first)

        let payloads = try map(events)
        let keyframe = try #require(payloads.first { $0.kind == "frame" && $0.key == true })
        let bytes = try #require(keyframe.data.flatMap { Data(base64Encoded: $0) })
        #expect(bytes == sets + idr)
    }

    @Test func aFrameKeepsTheDevicesOwnTimestamp() throws {
        // Passed through rather than restamped on the host clock, which would
        // drift against the device over a long session.
        let payloads = try map(
            capturedEvents(followedBy: [
                (key: true, pts: 111_222, payload: Data([0, 0, 0, 1, 0x65])),
                (key: false, pts: 111_555, payload: Data([0, 0, 0, 1, 0x41])),
            ]))
        let frames = payloads.filter { $0.kind == "frame" }
        #expect(frames.map(\.pts) == [111_222, 111_555])
        #expect(frames.map(\.key) == [true, false])
    }

    @Test func framesBeforeAConfigAreDroppedRatherThanForwarded() throws {
        // A frame with nothing to configure a decoder is not something a client
        // can act on, and forwarding it would make the first `configure` a race.
        var mapper = MirrorStreamMapper()
        let orphan = ScrcpyPacketHeader(
            isConfig: false, isKeyFrame: true, pts: 1, payloadSize: 4)
        #expect(try mapper.map(.packet(orphan, payload: Data([1, 2, 3, 4]))).isEmpty)
    }

    @Test func aDeltaFrameIsPassedThroughUntouched() throws {
        var mapper = MirrorStreamMapper()
        _ = try mapper.map(.videoHeader(
            codec: .h264, codecRaw: 0x6832_3634, width: 1080, height: 2400, clientResize: false))
        // A config first, so the mapper has something to configure with.
        let sps = Data([0, 0, 0, 1, 0x67, 0x42, 0xC0, 0x29, 0, 0, 0, 1, 0x68, 0xCE])
        _ = try mapper.map(.packet(
            ScrcpyPacketHeader(isConfig: true, isKeyFrame: false, pts: 0, payloadSize: sps.count),
            payload: sps))

        let delta = Data([0, 0, 0, 1, 0x41, 0xAA, 0xBB])
        let out = try mapper.map(.packet(
            ScrcpyPacketHeader(
                isConfig: false, isKeyFrame: false, pts: 999, payloadSize: delta.count),
            payload: delta))
        #expect(out.count == 1)
        #expect(out[0].key == false)
        #expect(out[0].data.flatMap { Data(base64Encoded: $0) } == delta)
    }

    @Test func aStreamWeCannotDecodeFailsNamingTheCodec() throws {
        // Better a named failure than bytes streamed at a decoder that was
        // never configured for them.
        var mapper = MirrorStreamMapper()
        #expect(throws: MirrorStreamMapper.UnsupportedCodec(codec: "h265")) {
            _ = try mapper.map(.videoHeader(
                codec: .h265, codecRaw: 0x6832_3635, width: 1080, height: 2400,
                clientResize: false))
        }
    }

    @Test func anUnknownCodecIsReportedAsItsRawMarker() throws {
        var mapper = MirrorStreamMapper()
        #expect(throws: MirrorStreamMapper.UnsupportedCodec(codec: "0xdeadbeef")) {
            _ = try mapper.map(.videoHeader(
                codec: nil, codecRaw: 0xDEAD_BEEF, width: 1, height: 1, clientResize: false))
        }
    }

    @Test func aSecondConfigReconfiguresRatherThanBeingIgnored() throws {
        // scrcpy sends a fresh config when the encoding changes; a client left
        // holding a decoder configured for the old profile decodes garbage.
        var mapper = MirrorStreamMapper()
        _ = try mapper.map(.videoHeader(
            codec: .h264, codecRaw: 0x6832_3634, width: 800, height: 500, clientResize: false))

        let baseline = Data([0, 0, 0, 1, 0x67, 0x42, 0xC0, 0x29, 0, 0, 0, 1, 0x68, 0xCE])
        let high = Data([0, 0, 0, 1, 0x67, 0x64, 0x00, 0x28, 0, 0, 0, 1, 0x68, 0xCE])
        let header = ScrcpyPacketHeader(
            isConfig: true, isKeyFrame: false, pts: 0, payloadSize: baseline.count)

        let first = try mapper.map(.packet(header, payload: baseline))
        let second = try mapper.map(.packet(header, payload: high))
        #expect(first.first?.codec == "avc1.42C029")
        #expect(second.first?.codec == "avc1.640028")
    }

    @Test func payloadsEncodeTheShapeTheWebviewParses() throws {
        // The wire contract, pinned: a client reads `kind` and then the fields
        // that kind carries, so a rename here is a broken tile.
        let config = MirrorFramePayload.config(
            codec: "avc1.42C029", width: 800, height: 500, deviceName: "pixel")
        let frame = MirrorFramePayload.frame(Data([0xAA]), key: true, pts: 1234)

        let configJSON = try String(decoding: JSONEncoder().encode(config), as: UTF8.self)
        for field in ["\"kind\":\"config\"", "\"codec\":\"avc1.42C029\"", "\"width\":800"] {
            #expect(configJSON.contains(field))
        }
        let frameJSON = try String(decoding: JSONEncoder().encode(frame), as: UTF8.self)
        for field in ["\"kind\":\"frame\"", "\"key\":true", "\"pts\":1234", "\"data\":\"qg==\""] {
            #expect(frameJSON.contains(field))
        }
    }
}
