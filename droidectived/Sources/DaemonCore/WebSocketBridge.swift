import Foundation
import NIOCore
import NIOWebSocket

/// Carries a `StreamSession`'s frames onto a WebSocket channel.
///
/// Text frames only. The stream protocol is JSON, and accepting binary would
/// mean a second encoding path with no client that wants it.
final class WebSocketSink: StreamSink, @unchecked Sendable {
    private let channel: any Channel

    init(channel: any Channel) { self.channel = channel }

    func send(_ text: String) async {
        var buffer = channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        // Awaited, not fire-and-forget: this is what makes a slow client
        // actually slow from the session's point of view, which is what makes
        // the bounded buffer and its drop policy do their job. Firing and
        // forgetting would move the unbounded queue into NIO instead.
        try? await channel.writeAndFlush(frame).get()
    }

    func close() async {
        try? await channel.close().get()
    }
}

extension WebSocketFrame {
    /// The pong owed to `ping`.
    ///
    /// Built fresh rather than by flipping the inbound frame's opcode, which is
    /// what both of this daemon's handlers used to do and is a protocol
    /// violation: RFC 6455 masks client→server only, so a `ping` arrives masked
    /// and carries its masking key, and copying the frame sends that key
    /// straight back out. A conformant client sees the mask bit on a
    /// server→client frame, closes with 1002 and reports "incorrect masking" —
    /// which reads exactly like a desynchronised frame header and sent one
    /// investigation looking for a length-encoding bug that was never there.
    ///
    /// The cost was a feed that stopped dead on the first keepalive: any client
    /// that pings — `websockets`, OkHttp with a ping interval, a browser — lost
    /// the socket and everything subscribed on it.
    ///
    /// `unmaskedData`, because §5.5.3 requires the pong to carry the ping's
    /// application data, and `data` is still XORed with the key.
    static func pong(for ping: WebSocketFrame) -> WebSocketFrame {
        WebSocketFrame(fin: true, opcode: .pong, data: ping.unmaskedData)
    }
}

/// Feeds inbound frames to the session and keeps the connection honest.
final class WebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let session: StreamSession
    /// Reassembles continuation frames. A client is entitled to split a large
    /// command across frames, and treating each fragment as a whole message
    /// would reject perfectly legal traffic.
    private var fragments = ""

    init(session: StreamSession) { self.session = session }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .connectionClose:
            let session = self.session
            let channel = context.channel
            Task {
                await session.shutdown(reason: .unsubscribed)
                try? await channel.close().get()
            }
        case .ping:
            context.writeAndFlush(NIOAny(WebSocketFrame.pong(for: frame)), promise: nil)
        case .text, .continuation:
            // `unmaskedData`, never `data`: the RFC requires every
            // client-to-server frame to be masked, so the raw buffer is XORed
            // with the frame's key and reads as garbage. Getting this wrong
            // does not fail loudly — the JSON simply never parses, and the
            // client waits forever for a reply that cannot come.
            var payload = frame.unmaskedData
            fragments += payload.readString(length: payload.readableBytes) ?? ""
            guard frame.fin else { return }
            let message = fragments
            fragments = ""
            let session = self.session
            Task { await session.handle(text: message) }
        default:
            // Binary and anything else: ignored rather than fatal. A confused
            // client must not be able to kill the connection for the streams
            // that are working.
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        // The socket went away without a close frame — tear the subscriptions
        // down anyway, or their adb children outlive the client.
        let session = self.session
        Task { await session.shutdown(reason: .serverStopping) }
        context.fireChannelInactive()
    }
}
