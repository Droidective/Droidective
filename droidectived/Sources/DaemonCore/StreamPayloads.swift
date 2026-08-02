import ADBKit
import Foundation

/// Wire shapes for stream items.
///
/// `Device` goes out as itself — it is already `Codable` and is a stable
/// public model. `LogLine` does not: it is an internal rendering model that
/// carries a per-line `UUID` and a precomputed `searchKey` for the Mac UI's
/// filtering, neither of which belongs in a protocol other programs depend on.
/// An explicit DTO means refactoring `LogLine` cannot silently reshape the API.
public struct LogLinePayload: Codable, Equatable, Sendable {
    public let time: String
    public let pid: String
    public let tid: String
    public let level: String
    public let tag: String
    public let message: String

    public init(_ line: LogLine) {
        time = line.time
        pid = line.pid
        tid = line.tid
        level = line.level
        tag = line.tag
        message = line.message
    }
}

/// Frame assembly.
///
/// Items are buffered pre-encoded, so a dropped item costs one wasted encode
/// rather than forcing the buffer to be generic over every topic's model. The
/// batch frame is therefore assembled from ready JSON rather than re-encoded.
public enum StreamFrame {
    /// Key order matches `JSONEncoder`'s `.sortedKeys`, so hand-assembled
    /// frames and `DaemonProtocol.encode` produce byte-identical output — which
    /// is what lets one set of golden-string tests cover both paths.
    public static func batch(id: Int, items: [Data]) -> String {
        let joined = items.map { String(decoding: $0, as: UTF8.self) }.joined(separator: ",")
        return #"{"event":"batch","id":\#(id),"items":[\#(joined)]}"#
    }

    public static func encode<Payload: Codable & Sendable>(
        _ event: StreamProtocol.Event<Payload>
    ) -> String {
        guard let data = try? DaemonProtocol.encode(event) else {
            // Encoding a fixed-shape event cannot realistically fail; if it
            // somehow does, say so on the wire rather than dropping the frame
            // and leaving the client waiting forever.
            return #"{"event":"failed","id":\#(event.id),"message":"encode failed"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}
