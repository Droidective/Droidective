import ADBKit
import Foundation
import NIOCore
import NIOEmbedded
import NIOWebSocket
import Testing

@testable import DaemonCore

/// How this daemon's two WebSocket servers answer a ping.
///
/// RFC 6455 §5.1 masks client→server frames only, so every `ping` that arrives
/// carries a masking key — and both handlers used to answer by copying the
/// inbound frame and flipping its opcode, which sends that key back out on a
/// server→client frame. A conformant client closes the connection with 1002
/// the moment it sees the mask bit, so a feed died on the first keepalive and
/// reported "incorrect masking": a message that reads like a desynchronised
/// frame header and had an investigation looking for a length-encoding bug.
///
/// Asserted on the frames themselves through an `EmbeddedChannel` rather than
/// against a client library. Masking is not observable from a decoded message,
/// the `URLSession` client the socket suites use is Apple-only, and a client
/// strict enough to catch this simply hangs instead of failing — so the bytes
/// are the only honest place to look, and looking here runs on every platform.
@Suite struct WebSocketPongTests {
    /// A ping exactly as one arrives from a client: masked, with application
    /// data the pong is required to echo back (§5.5.3).
    ///
    /// The bytes are XORed here because that is the shape the decoder hands on
    /// — `WebSocketFrame.data` holds the frame as it came off the wire and
    /// `unmaskedData` is what decodes it. Building the frame around plaintext
    /// instead would make the whole suite assert against a frame no client
    /// sends.
    private func maskedPing(_ payload: String = "keepalive") throws -> WebSocketFrame {
        let bytes: [UInt8] = [0x6B, 0x59, 0x25, 0xFE]
        let key = try #require(WebSocketMaskingKey(bytes))
        var buffer = ByteBufferAllocator().buffer(capacity: payload.utf8.count)
        buffer.writeBytes(Array(payload.utf8).enumerated().map { $1 ^ bytes[$0 % 4] })
        return WebSocketFrame(fin: true, opcode: .ping, maskKey: key, data: buffer)
    }

    private func expectAValidPong(_ answer: WebSocketFrame?, echoing payload: String) throws {
        let pong = try #require(answer, "a ping must be answered")
        #expect(pong.opcode == .pong)
        #expect(pong.fin)
        #expect(
            pong.maskKey == nil,
            "a server must not mask; a masked pong is closed on with 1002")
        var data = pong.unmaskedData
        #expect(data.readString(length: data.readableBytes) == payload)
    }

    @Test func theStreamSocketAnswersWithAnUnmaskedPong() throws {
        let channel = EmbeddedChannel()
        let session = StreamSession(sink: SilentSink(), source: SilentSource())
        try channel.pipeline.syncOperations.addHandler(WebSocketHandler(session: session))

        try channel.writeInbound(try maskedPing())
        try expectAValidPong(try channel.readOutbound(as: WebSocketFrame.self), echoing: "keepalive")
        _ = try channel.finish()
    }

    @Test func theReactotronRelayAnswersWithAnUnmaskedPong() throws {
        // The same handler bug, in the other listener. One helper answers both
        // now, but they are separate classes and a future edit can only revert
        // one of them.
        let channel = EmbeddedChannel()
        let relay = ReactotronRelay(port: 0)
        try channel.pipeline.syncOperations.addHandler(
            RelayConnectionHandler(relay: relay, id: 1, channel: channel))

        try channel.writeInbound(try maskedPing("rn-app"))
        try expectAValidPong(try channel.readOutbound(as: WebSocketFrame.self), echoing: "rn-app")
        // Not finished: this handler registers itself with the relay from a
        // `Task` in its own init, and shutting the embedded loop down under it
        // makes NIO log a scheduling error for something this test is not
        // about.
    }

    @Test func aPongCarriesThePingsApplicationDataDecoded() throws {
        // Reading `data` rather than `unmaskedData` would echo the payload
        // still XORed with the client's key — a pong that passes the masking
        // rule and fails the one that says a ping's body comes back verbatim,
        // which is what a keepalive with a correlating token checks.
        let pong = WebSocketFrame.pong(for: try maskedPing("token-42"))
        var data = pong.unmaskedData
        #expect(data.readString(length: data.readableBytes) == "token-42")
        #expect(pong.maskKey == nil)
    }
}

/// A sink that keeps nothing: these tests are about the frame written for a
/// ping, which never reaches the session at all.
private struct SilentSink: StreamSink {
    func send(_ text: String) async {}
    func close() async {}
}

private struct SilentSource: StreamSource {
    func devices() async -> AsyncStream<[Device]> { AsyncStream { $0.finish() } }
    func logcat(serial: String, pid: Int?) async throws -> AsyncStream<[LogLine]> {
        AsyncStream { $0.finish() }
    }
    func stopLogcat(serial: String) async {}
    func performance(
        serial: String, packageId: String?, includeProcesses: Bool
    ) async -> AsyncStream<PerformanceService.PerfPoll> {
        AsyncStream { $0.finish() }
    }
    func netspeed(serial: String) async -> AsyncStream<NetSample> {
        AsyncStream { $0.finish() }
    }
    func openPty(serial: String?, size: PtySize) throws -> any PtyChannel {
        throw PtyError.unsupportedPlatform
    }
    func reactotron() async throws -> AsyncStream<ReactotronRelay.Event> {
        AsyncStream { $0.finish() }
    }
    func stopReactotron() async {}
}
