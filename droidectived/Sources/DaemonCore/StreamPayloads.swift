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
    /// The WebSocket close status, when the client sent one. 1001 is the one
    /// worth acting on — see `ReactotronRelay.Event.disconnected`.
    public let code: Int?
    /// The frame's size on the wire, for the frames that had one.
    ///
    /// It travels because the client cannot recover it: the timeline bounds
    /// itself by retained bytes as well as by row count — one base64 display
    /// image outweighs a thousand log lines — and the only other way to a size
    /// is re-serializing every payload as it arrives, which is the stall the
    /// whole feed is built to avoid.
    public let bytes: Int?

    public init(_ event: ReactotronRelay.Event) {
        switch event {
        case .listening(let port):
            kind = "listening"
            connection = nil
            self.port = port
            clientId = nil
            command = nil
            reason = nil
            code = nil
            bytes = nil
        case .connected(let connection, let clientId, let command, let bytes):
            kind = "connected"
            self.connection = connection
            port = nil
            self.clientId = clientId
            self.command = command
            reason = nil
            code = nil
            self.bytes = bytes
        case .command(let connection, let command, let bytes):
            kind = "command"
            self.connection = connection
            port = nil
            clientId = nil
            self.command = command
            reason = nil
            code = nil
            self.bytes = bytes
        case .disconnected(let connection, let reason, let code):
            kind = "disconnected"
            self.connection = connection
            port = nil
            clientId = nil
            command = nil
            self.reason = reason
            self.code = code
            bytes = nil
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

/// One mirror frame, or the configuration that has to precede them.
///
/// Two kinds in one payload rather than two topics, because the ordering
/// matters and is only free if both travel the same subscription: a client
/// cannot decode a frame before it has configured a decoder, and a second
/// topic would make that a race it had to sequence itself.
///
/// The bytes are **Annex-B**, which is what `VideoDecoder` decodes when
/// `description` is absent — scrcpy's own framing, passed through rather than
/// repackaged as AVCC. Keyframes carry the SPS/PPS ahead of them (see
/// `MirrorStreamMapper`), so the stream stays self-describing.
public struct MirrorFramePayload: Codable, Equatable, Sendable {
    /// "config" or "frame".
    public let kind: String
    /// `config`: the RFC 6381 string `VideoDecoder.configure` takes, read out
    /// of the SPS rather than assumed — the device picks the profile.
    public let codec: String?
    /// `config`: the size scrcpy negotiated, for laying the tile out before a
    /// frame has arrived.
    ///
    /// A hint, not the truth. It is the session's opening dimensions, and the
    /// device can rotate later without the daemon knowing the new geometry —
    /// reading it out of a rotated SPS would mean a full exp-Golomb parse. A
    /// decoded `VideoFrame` carries its own `displayWidth`/`displayHeight`, so
    /// a client should size itself from the frames and use this only to avoid
    /// a zero-sized first layout.
    public let width: Int?
    public let height: Int?
    /// `config`: the device's own name, for the tile caption.
    public let deviceName: String?
    /// `frame`: a keyframe, which is `EncodedVideoChunk`'s `type: "key"`. The
    /// distinction is not cosmetic — a decoder fed a delta frame first has
    /// nothing to apply it to.
    public let key: Bool?
    /// `frame`: presentation timestamp in microseconds, on the *device's*
    /// clock. Passed through rather than restamped: it is what the recorder
    /// would mux by, and a host-clock guess would drift over a long session.
    public let pts: UInt64?
    /// `frame`: base64 Annex-B bytes.
    public let data: String?

    /// The configuration a client needs before any frame can be decoded.
    public static func config(
        codec: String, width: Int, height: Int, deviceName: String?
    ) -> Self {
        .init(
            kind: "config", codec: codec, width: width, height: height,
            deviceName: deviceName, key: nil, pts: nil, data: nil)
    }

    public static func frame(_ bytes: Data, key: Bool, pts: UInt64) -> Self {
        .init(
            kind: "frame", codec: nil, width: nil, height: nil, deviceName: nil,
            key: key, pts: pts, data: bytes.base64EncodedString())
    }

    private init(
        kind: String, codec: String?, width: Int?, height: Int?, deviceName: String?,
        key: Bool?, pts: UInt64?, data: String?
    ) {
        self.kind = kind
        self.codec = codec
        self.width = width
        self.height = height
        self.deviceName = deviceName
        self.key = key
        self.pts = pts
        self.data = data
    }
}
