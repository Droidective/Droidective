import ADBKit
import Foundation

/// Turns a scrcpy video stream into what a webview's `VideoDecoder` can take.
///
/// Pure and incremental — decoder events in, wire payloads out, no I/O — so the
/// rules that matter are testable against a captured stream rather than a
/// device. `ScrcpySession` owns the socket; this owns two rules:
///
/// 1. **Nothing decodable is emitted before a `config`.** scrcpy's dimensions
///    arrive in the session header and its SPS/PPS in a separate config packet,
///    so neither alone is enough to configure a decoder. Frames before that are
///    dropped rather than forwarded, because a client cannot do anything with
///    them and forwarding would only make the first `configure` a race.
/// 2. **Every keyframe carries the parameter sets.** In Annex-B mode the
///    decoder reads SPS/PPS from the stream itself, and scrcpy sends them once.
///    Prepending them to each keyframe is what makes the stream self-describing
///    — the cost is a few dozen bytes about once a second, and the benefit is
///    that a decoder which was reset, or a client that reconnects, recovers on
///    the next keyframe instead of never.
struct MirrorStreamMapper {
    /// The stream is not something this can render.
    ///
    /// Only H.264 for now, and it fails loudly rather than streaming bytes no
    /// `VideoDecoder` was configured for. scrcpy defaults to H.264; a device
    /// negotiating anything else is a real state and the message names it.
    struct UnsupportedCodec: Error, Equatable {
        let codec: String
    }

    private var deviceName: String?
    private var size: (width: Int, height: Int)?
    /// The most recent config packet's Annex-B blob, verbatim.
    private var parameterSets: Data?
    private var configured = false

    /// Map one decoder event to whatever should go on the wire for it.
    ///
    /// Returns an array because a single event can produce a `config` and
    /// nothing else, one frame, or nothing at all.
    mutating func map(_ event: ScrcpyStreamDecoder.Event) throws -> [MirrorFramePayload] {
        switch event {
        case let .deviceName(name):
            deviceName = name.isEmpty ? nil : name
            return []
        case let .videoHeader(codec, codecRaw, width, height, _):
            guard codec == .h264 else {
                throw UnsupportedCodec(codec: Self.name(of: codec, raw: codecRaw))
            }
            size = (width, height)
            return []
        case let .packet(header, payload):
            return try map(header, payload: payload)
        }
    }

    private mutating func map(
        _ header: ScrcpyPacketHeader, payload: Data
    ) throws -> [MirrorFramePayload] {
        if header.isConfig {
            parameterSets = payload
            return configPayload().map { [$0] } ?? []
        }
        guard configured else { return [] }
        guard header.isKeyFrame else {
            return [.frame(payload, key: false, pts: header.pts)]
        }
        var bytes = parameterSets ?? Data()
        bytes.append(payload)
        return [.frame(bytes, key: true, pts: header.pts)]
    }

    /// The `config` payload, once both halves have arrived.
    ///
    /// Re-emitted for every config packet rather than only the first: scrcpy
    /// sends a fresh one when the encoding changes, and a client holding a
    /// decoder configured for the old profile would decode garbage.
    private mutating func configPayload() -> MirrorFramePayload? {
        guard let size,
            let sets = parameterSets.flatMap(H264NAL.parameterSets(fromAnnexB:)),
            let codec = H264NAL.avcCodecString(sps: sets.sps)
        else { return nil }
        configured = true
        return .config(
            codec: codec, width: size.width, height: size.height, deviceName: deviceName)
    }

    /// A codec's name for the failure message — its four-character marker when
    /// it is one we know, and the raw word when it is not.
    private static func name(of codec: ScrcpyCodecID?, raw: UInt32) -> String {
        switch codec {
        case .h265: return "h265"
        case .av1: return "av1"
        case .h264: return "h264"
        case .opus: return "opus"
        case .aac: return "aac"
        case .raw: return "raw"
        case nil: return String(format: "0x%08x", raw)
        }
    }
}
