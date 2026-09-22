import ADBKit
import Foundation

/// One device's mirror: the transport, the scrcpy stream decoder, and the
/// mapping onto the wire, with a single teardown that covers all three.
///
/// The Mac's `MirrorSession` also owns the decode, the display layer, the audio
/// player and the recorder. This one owns none of those, because the webview
/// decodes (see backlog 25's step 0 in `docs/desktop-parity.md`) — so what is
/// left is exactly the part that has to be right: bytes off the socket, framed,
/// in order, and a teardown that cannot leak the `adb forward`.
public actor ScrcpySession {
    public struct Configuration: Sendable {
        public var serial: String
        public var serverVersion: String
        public var localJarPath: String
        /// scrcpy's own knobs. The caller decides quality, because the Mirror
        /// Wall steps it down per tile.
        public var params: ScrcpyServerParams

        public init(
            serial: String,
            serverVersion: String,
            localJarPath: String,
            params: ScrcpyServerParams
        ) {
            self.serial = serial
            self.serverVersion = serverVersion
            self.localJarPath = localJarPath
            self.params = params
        }
    }

    private let transport: ScrcpyTransport
    private let tunnelForward: Bool
    private var pump: Task<Void, Never>?
    private var audioPump: Task<Void, Never>?
    private var sendControl: (@Sendable (Data) -> Void)?
    private var stopped = false

    public init(adb: AdbClient, config: Configuration) {
        transport = ScrcpyTransport(
            adb: adb,
            config: .init(
                serial: config.serial,
                params: config.params,
                serverVersion: config.serverVersion,
                localJarPath: config.localJarPath))
        tunnelForward = config.params.tunnelForward
    }

    /// Bring the mirror up and stream its frames.
    ///
    /// The stream finishes when the device side goes away and throws when the
    /// stream is not decodable — an unsupported codec is a real state, not
    /// something to paper over with bytes nobody configured a decoder for.
    public func start() async throws -> AsyncThrowingStream<MirrorFramePayload, Error> {
        let bytes = try await transport.start()
        sendControl = await transport.controlSender()
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: MirrorFramePayload.self)
        // Terminal on the *consumer* going away too: a client that unsubscribes
        // or drops its socket must take the scrcpy server and the tunnel with
        // it, not leave them running for a tile nobody is watching.
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        // Audio, when the session asked for it, folds into the *same*
        // continuation as the video — one ordered stream, so a client cannot
        // be handed a buffer before the format that describes it.
        if let audioBytes = await transport.audioByteStream() {
            audioPump = Task { await Self.pumpAudio(audioBytes, into: continuation) }
        }
        pump = Task { [tunnelForward] in
            var decoder = ScrcpyStreamDecoder(tunnelForward: tunnelForward)
            var mapper = MirrorStreamMapper()
            do {
                for try await chunk in bytes {
                    for event in decoder.consume(chunk) {
                        for payload in try mapper.map(event) { continuation.yield(payload) }
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }

    /// Decode the audio socket and forward raw PCM, as the Mac's
    /// `MirrorSession.consumeAudio` does.
    ///
    /// Only `raw` is forwarded. The server answers `0` for "this device cannot
    /// capture audio" (Android < 11, or output capture refused) and `1` for a
    /// device-side configuration error; both arrive as a nil codec with no
    /// packets behind them, and both leave the mirror silent but otherwise
    /// working. A codec we do model but cannot play — Opus, AAC — is the same
    /// answer for a different reason, and is treated the same way rather than
    /// pushing bytes at a graph that would render them as noise.
    ///
    /// A failure here never touches the video continuation: losing the sound
    /// is not losing the mirror.
    static func pumpAudio(
        _ bytes: AsyncThrowingStream<Data, Error>,
        into continuation: AsyncThrowingStream<MirrorFramePayload, Error>.Continuation
    ) async {
        var decoder = ScrcpyAudioStreamDecoder()
        var isRaw = false
        do {
            for try await chunk in bytes {
                if Task.isCancelled { return }
                for event in decoder.consume(chunk) {
                    switch event {
                    case let .codec(codec, _):
                        isRaw = codec == .raw
                        if isRaw {
                            continuation.yield(.audioConfig(
                                sampleRate: rawSampleRate, channels: rawChannels))
                        }
                    case let .packet(header, payload):
                        // A config packet on the audio socket describes a codec
                        // that needs one; raw PCM never does, so it is not
                        // audio to play.
                        guard isRaw, !header.isConfig, !payload.isEmpty else { continue }
                        continuation.yield(.audio(payload, pts: header.pts))
                    }
                }
            }
        } catch {
            // Silence, not a dead mirror.
        }
    }

    /// scrcpy's raw audio encoder is fixed at 48 kHz stereo s16le
    /// (`AudioCapture`), which is why `ScrcpyServerParams` asks for `raw`: the
    /// client needs no decoder, only a graph to push samples into.
    static let rawSampleRate = 48_000
    static let rawChannels = 2

    /// Send a control message — a touch, a key, a clipboard paste. Encode with
    /// `ScrcpyControlMessage`, which is the portable ADBKit half both hosts use.
    public func send(control bytes: Data) {
        sendControl?(bytes)
    }

    /// Tear the session down. Idempotent, terminal, and **awaited** — the
    /// transport's `adb forward` outlives the process otherwise, which is the
    /// leak the Mac was caught doing once per quit.
    public func stop() async {
        guard !stopped else { return }
        stopped = true
        pump?.cancel()
        pump = nil
        audioPump?.cancel()
        audioPump = nil
        sendControl = nil
        await transport.stop()
    }
}
