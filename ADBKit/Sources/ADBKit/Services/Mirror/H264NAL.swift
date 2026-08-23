import Foundation

/// H.264 NAL-unit helpers. scrcpy sends an Annex-B byte stream (NAL units
/// separated by `00 00 01` / `00 00 00 01` start codes); VideoToolbox wants AVCC
/// (each NAL prefixed with its 4-byte big-endian length) plus a format
/// description built from the SPS/PPS. Pure / unit-tested.
public enum H264NAL {
    public static let spsType: UInt8 = 7
    public static let ppsType: UInt8 = 8
    public static let idrType: UInt8 = 5

    /// NAL unit type — the low 5 bits of the first byte.
    public static func type(of nal: Data) -> UInt8? {
        guard let first = nal.first else { return nil }
        return first & 0x1f
    }

    /// Split an Annex-B buffer into NAL-unit payloads (start codes stripped).
    public static func nalUnits(fromAnnexB data: Data) -> [Data] {
        let bytes = [UInt8](data)
        let count = bytes.count
        var units: [Data] = []

        func startCodeLength(at index: Int) -> Int {
            if index + 3 <= count, bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                return 3
            }
            if index + 4 <= count,
               bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                return 4
            }
            return 0
        }

        var index = 0
        while index < count, startCodeLength(at: index) == 0 { index += 1 }
        while index < count {
            let prefix = startCodeLength(at: index)
            guard prefix > 0 else { break }
            let nalStart = index + prefix
            var scan = nalStart
            while scan < count, startCodeLength(at: scan) == 0 { scan += 1 }
            if nalStart < scan { units.append(Data(bytes[nalStart ..< scan])) }
            index = scan
        }
        return units
    }

    /// Convert an Annex-B buffer to AVCC: every NAL prefixed with its 4-byte
    /// big-endian length.
    public static func avcc(fromAnnexB data: Data) -> Data {
        var out = Data()
        for nal in nalUnits(fromAnnexB: data) {
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
            out.append(nal)
        }
        return out
    }

    /// The RFC 6381 codec parameter for an SPS — `avc1.PPCCLL`, which is the
    /// string WebCodecs' `VideoDecoder.configure` wants.
    ///
    /// The three bytes are `profile_idc`, the constraint-flags byte and
    /// `level_idc`, and they sit immediately after the SPS's own NAL header
    /// byte. Reading them out beats hard-coding a profile: the daemon has to
    /// hand the webview a string its decoder will actually accept, and the
    /// device picks the profile, not us.
    ///
    /// Uppercase hex. Both cases parse, and this is the spelling proved against
    /// a real WebKitGTK by `scripts/probe-webkit-webcodecs.sh`.
    public static func avcCodecString(sps: Data) -> String? {
        let bytes = [UInt8](sps)
        guard bytes.count >= 4, type(of: sps) == spsType else { return nil }
        return String(format: "avc1.%02X%02X%02X", bytes[1], bytes[2], bytes[3])
    }

    /// Extract the first SPS and PPS NAL payloads from an Annex-B config blob.
    public static func parameterSets(fromAnnexB data: Data) -> (sps: Data, pps: Data)? {
        var sps: Data?
        var pps: Data?
        for nal in nalUnits(fromAnnexB: data) {
            switch type(of: nal) {
            case spsType where sps == nil: sps = nal
            case ppsType where pps == nil: pps = nal
            default: break
            }
        }
        guard let sps, let pps else { return nil }
        return (sps, pps)
    }
}
