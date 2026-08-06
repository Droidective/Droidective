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

/// One performance sample.
///
/// A DTO for the same reason `LogLinePayload` is: `PerfPoll` and the models
/// under it are shaped for the Mac's charts (`Identifiable`, computed labels),
/// and a protocol other programs depend on should not move when those do.
///
/// Every field is optional-shaped the way the sample itself is: the first
/// sample after a subscribe has no CPU figures at all, because a percentage is
/// a delta and there is nothing yet to subtract from. Sending it anyway — with
/// no cores — is deliberate: it is how a client learns the stream is alive.
public struct PerfSamplePayload: Codable, Equatable, Sendable {
    public struct Core: Codable, Equatable, Sendable {
        /// -1 is the all-cores aggregate, as `CpuCoreLoad` numbers it.
        public let core: Int
        public let label: String
        public let usagePercent: Double
    }

    public struct Process: Codable, Equatable, Sendable {
        public let pid: Int
        public let name: String
        public let cpuPercent: Double?
        public let pssKb: Int?
    }

    public let cores: [Core]
    public let ramTotalKb: Int?
    public let ramUsedKb: Int?
    public let appFps: Double?
    /// Percent of frames that missed the deadline, when any were drawn.
    public let appJankPercent: Double?
    public let appPssKb: Int?
    public let downloadBytesPerSec: Double?
    public let uploadBytesPerSec: Double?
    public let processes: [Process]

    public init(_ poll: PerformanceService.PerfPoll) {
        cores = poll.cores.map {
            Core(core: $0.core, label: $0.label, usagePercent: $0.usagePercent)
        }
        ramTotalKb = poll.ramTotalKb
        ramUsedKb = poll.ramUsedKb
        appFps = poll.appFps?.fps
        appJankPercent = poll.appFps?.jankPercent
        appPssKb = poll.appPssKb
        downloadBytesPerSec = poll.downloadBytesPerSec
        uploadBytesPerSec = poll.uploadBytesPerSec
        processes = poll.processes.map {
            Process(pid: $0.pid, name: $0.name, cpuPercent: $0.cpuPercent, pssKb: $0.pssKb)
        }
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
