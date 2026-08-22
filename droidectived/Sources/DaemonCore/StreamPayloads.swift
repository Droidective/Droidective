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

/// Whatever the shell just wrote, base64.
///
/// Base64 because this is the one payload that is *bytes* rather than a record.
/// A read from a pty splits wherever the buffer filled, which is as likely as
/// not to be the middle of a multi-byte character or an escape sequence — so
/// decoding here would corrupt output that is perfectly fine once the client
/// reassembles it, and it would do so only sometimes, on non-ASCII, which is
/// the worst way to find out.
///
/// An object rather than a bare string so a client's frame handling stays the
/// same shape for every topic.
public struct PtyChunkPayload: Codable, Equatable, Sendable {
    public let data: String

    public init(_ chunk: Data) {
        data = chunk.base64EncodedString()
    }
}

/// One thing the Reactotron relay saw.
///
/// A flat envelope with an optional command rather than four payload types,
/// because the timeline renders them as one list and a client switching on a
/// `kind` string is simpler than a client decoding four shapes off one topic.
///
/// The command travels as the raw `ReactotronCommand` it decoded to: unlike
/// `LogLine`, that type *is* the protocol — it mirrors upstream's wire format
/// and `ReactotronCommandType` is derived from it — so a DTO here would be a
/// second spelling of a contract that is not ours to reshape.
public struct ReactotronEventPayload: Codable, Sendable {
    /// "listening", "connected", "command" or "disconnected".
    public let kind: String
    /// Which client. Absent for `listening`, which is about the relay itself.
    public let connection: Int?
    public let port: Int?
    /// What the app called itself in its `client.intro`, when it said.
    public let clientId: String?
    public let command: ReactotronCommand?
    /// Why a client went away, when the transport said. Absent for an ordinary
    /// close, which needs no explanation.
    public let reason: String?

    public init(_ event: ReactotronRelay.Event) {
        switch event {
        case .listening(let port):
            kind = "listening"
            connection = nil
            self.port = port
            clientId = nil
            command = nil
            reason = nil
        case .connected(let connection, let clientId, let command):
            kind = "connected"
            self.connection = connection
            port = nil
            self.clientId = clientId
            self.command = command
            reason = nil
        case .command(let connection, let command):
            kind = "command"
            self.connection = connection
            port = nil
            clientId = nil
            self.command = command
            reason = nil
        case .disconnected(let connection, let reason):
            kind = "disconnected"
            self.connection = connection
            port = nil
            clientId = nil
            command = nil
            self.reason = reason
        }
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

/// One network sample: device-wide throughput, the cumulative totals since
/// boot, and the per-interface breakdown behind them.
public struct NetSamplePayload: Codable, Equatable, Sendable {
    public struct Interface: Codable, Equatable, Sendable {
        public let name: String
        public let downloadBytesPerSec: Double
        public let uploadBytesPerSec: Double
        public let rxBytes: UInt64
        public let txBytes: UInt64
    }

    public let downloadBytesPerSec: Double
    public let uploadBytesPerSec: Double
    /// Since the device booted, not since the stream started — the screen
    /// derives its own session totals by differencing against the first
    /// sample, which is the only way a mid-session subscribe reads right.
    public let totalRxBytes: UInt64
    public let totalTxBytes: UInt64
    public let interfaces: [Interface]

    public init(_ sample: NetSample) {
        downloadBytesPerSec = sample.downloadBytesPerSec
        uploadBytesPerSec = sample.uploadBytesPerSec
        totalRxBytes = sample.totalRxBytes
        totalTxBytes = sample.totalTxBytes
        interfaces = sample.interfaces.map {
            Interface(
                name: $0.name, downloadBytesPerSec: $0.downloadBytesPerSec,
                uploadBytesPerSec: $0.uploadBytesPerSec,
                rxBytes: $0.rxBytes, txBytes: $0.txBytes)
        }
    }
}
