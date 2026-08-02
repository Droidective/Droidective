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
            var response = frame
            response.opcode = .pong
            context.writeAndFlush(NIOAny(response), promise: nil)
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
