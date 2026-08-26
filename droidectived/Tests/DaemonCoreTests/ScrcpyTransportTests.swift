import ADBKit
import Foundation
import NIOCore
import NIOPosix
import Testing

@testable import DaemonCore

/// The scrcpy transport, against real loopback sockets.
///
/// A fake server rather than a mocked socket, and deliberately: what has to be
/// right is the handshake `adb forward` forces — it accepts a connection before
/// the device side is listening and then drops it, so a connected channel proves
/// nothing and only the first byte does. Stubbing the socket would assert the
/// retry loop against itself. This is a real listener on a real port, which is
/// what the transport meets, and unlike the Reactotron relay's suite it needs no
/// `URLSession`, so it runs on Linux and Windows too.
///
/// Serialized, and every server binds port 0: two listeners racing for a port is
/// a flake that teaches nothing.
@Suite(.serialized) struct ScrcpyTransportTests {
    /// Short deadlines throughout: production waits ten seconds for a device to
    /// boot `app_process`, and a suite that waited that long to prove a timeout
    /// would not get run.
    private static let giveUp = Duration.milliseconds(900)
    private static let firstByte = Duration.milliseconds(250)

    // MARK: - the first-byte handshake

    @Test func connectsOnceTheDeviceSideSendsItsFirstByte() async throws {
        try await withFakeDevice { port, group, _ in
            let socket = try await ScrcpyTransport.connectVideoSocket(
                port: port, group: group, giveUpAfter: Self.giveUp,
                firstByteWithin: Self.firstByte)

            // The dummy byte is not swallowed by the handshake — it reaches the
            // decoder, which is what the Mac's version needed a replay for.
            var iterator = socket.stream.makeAsyncIterator()
            let first = try await iterator.next()
            #expect(first == Data([0x00]))
            try? await socket.channel.close().get()
        }
    }

    @Test func retriesPastTheAcceptsAdbForwardMakesBeforeTheServerListens() async throws {
        // Two accept-then-drop rounds, which is what the tunnel does while the
        // device side is still booting.
        try await withFakeDevice(dropFirst: 2) { port, group, server in
            let socket = try await ScrcpyTransport.connectVideoSocket(
                port: port, group: group, giveUpAfter: .seconds(4),
                firstByteWithin: Self.firstByte)

            try await waitUntil { await server.accepts >= 3 }
            try? await socket.channel.close().get()
        }
    }

    @Test func givesUpNamingTheSocketWhenTheDeviceSideNeverSpeaks() async throws {
        // Never sends its byte. A connect that "succeeds" on the tunnel alone is
        // the failure mode that would report a black tile as a working mirror.
        try await withFakeDevice(dropFirst: Int.max) { port, group, _ in
            let failure = await #expect(throws: ScrcpyTransport.TransportError.self) {
                _ = try await ScrcpyTransport.connectVideoSocket(
                    port: port, group: group, giveUpAfter: Self.giveUp,
                    firstByteWithin: Self.firstByte)
            }
            #expect("\(failure ?? .adbNotFound)".contains("video"))
        }
    }

    @Test func aSecondarySocketNeedsNoFirstByte() async throws {
        // Audio and control are the server's 2nd and 3rd accepts and carry no
        // dummy byte, so silence is success for them and failure for video.
        try await withFakeDevice(greeting: []) { port, group, server in
            let socket = try await ScrcpyTransport.connectSecondarySocket(
                port: port, group: group, label: "audio", giveUpAfter: Self.giveUp)
            // Polled, not read once: the connect returns as soon as TCP is up,
            // which can be before the fake's own handler has counted the
            // accept. Reading it straight passed on macOS and failed on Linux.
            try await waitUntil { await server.accepts == 1 }

            await #expect(throws: ScrcpyTransport.TransportError.self) {
                _ = try await ScrcpyTransport.connectVideoSocket(
                    port: port, group: group, giveUpAfter: Self.giveUp,
                    firstByteWithin: Self.firstByte)
            }
            try? await socket.channel.close().get()
        }
    }

    @Test func theSocketReallyHasNagleTurnedOff() async throws {
        // Asserted on the connected channel rather than trusted from the
        // bootstrap. The first spelling named the option at the wrong level —
        // `socketOption(.tcp_nodelay)` is SOL_SOCKET, where the value 1 is
        // SO_DEBUG, a privileged option — and on a container without
        // CAP_NET_ADMIN that fails the connect with EPERM.
        //
        // Be clear about what this test is worth: on Darwin it passes either
        // way, because the kernel reports a non-zero TCP_NODELAY on loopback
        // regardless. The regression guard that actually bites is every socket
        // test in this suite failing on Linux, which is how the bug surfaced.
        // This one pins the intent and the level.
        try await withFakeDevice { port, group, _ in
            let socket = try await ScrcpyTransport.connectVideoSocket(
                port: port, group: group, giveUpAfter: Self.giveUp,
                firstByteWithin: Self.firstByte)

            // Non-zero, not `== 1`: it is a boolean flag and the kernel
            // reports it in its own terms — Darwin answers 4.
            let noDelay = try await socket.channel.getOption(.tcpOption(.tcp_nodelay)).get()
            #expect(noDelay != 0, "Nagle is still on, so every touch waits for an ACK")
            try? await socket.channel.close().get()
        }
    }

    // MARK: - streaming

    @Test func streamsWhatTheServerSendsInOrder() async throws {
        let payload = Array(UInt8(1)...UInt8(60))
        try await withFakeDevice(greeting: [0x00] + payload) { port, group, _ in
            let socket = try await ScrcpyTransport.connectVideoSocket(
                port: port, group: group, giveUpAfter: Self.giveUp,
                firstByteWithin: Self.firstByte)

            // Coalescing is the transport's business, not the test's: assert the
            // bytes and their order, not how many reads they arrived in.
            var seen = Data()
            for try await chunk in socket.stream {
                seen.append(chunk)
                if seen.count >= payload.count + 1 { break }
            }
            #expect(Array(seen) == [0x00] + payload)
            try? await socket.channel.close().get()
        }
    }

    @Test func theSocketCarriesControlBytesBackToTheDevice() async throws {
        try await withFakeDevice { port, group, server in
            let socket = try await ScrcpyTransport.connectSecondarySocket(
                port: port, group: group, label: "control", giveUpAfter: Self.giveUp)

            // A control message's shape: this socket is the only one written to,
            // and a mirror nobody can tap is not a mirror.
            let event = Data([0x02, 0x00, 0x00, 0x00, 0x01])
            var buffer = socket.channel.allocator.buffer(capacity: event.count)
            buffer.writeBytes(event)
            try await socket.channel.writeAndFlush(buffer).get()

            try await waitUntil { await server.received == event }
            try? await socket.channel.close().get()
        }
    }

    @Test func theStreamEndsWhenTheDeviceSideHangsUp() async throws {
        try await withFakeDevice { port, group, server in
            let socket = try await ScrcpyTransport.connectVideoSocket(
                port: port, group: group, giveUpAfter: Self.giveUp,
                firstByteWithin: Self.firstByte)
            await server.stop()

            // Finishes rather than hanging: a stream that never ends is a tile
            // that stays black with nothing watching for the reconnect.
            var chunks = 0
            for try await _ in socket.stream { chunks += 1 }
            #expect(chunks >= 1)
        }
    }

    // MARK: - the tunnel

    @Test func aBringUpThatFailsStillRemovesTheForward() async throws {
        // The leak the Mac was caught doing once per quit, in its other shape:
        // the forward is open before the server is spawned, so a spawn that
        // fails leaves a tunnel registered in the long-lived adb server. The
        // caller never received a session and has no reason to stop one.
        let adb = RecordingAdb(forwardedPort: 41234)
        let transport = transport(over: adb, scid: 0xDEAD_BEEF)

        await #expect(throws: (any Error).self) { _ = try await transport.start() }

        let removals = await adb.invocations.filter { $0.contains("--remove") }
        #expect(removals == [["-s", "emulator-5554", "forward", "--remove", "tcp:41234"]])
    }

    @Test func stoppingTwiceRemovesTheForwardOnce() async throws {
        let adb = RecordingAdb(forwardedPort: 41234)
        let transport = transport(over: adb, scid: 1)

        _ = try? await transport.start()
        await transport.stop()
        await transport.stop()

        let removals = await adb.invocations.filter { $0.contains("--remove") }
        #expect(removals.count == 1)
    }

    @Test func theTunnelIsOpenedForTheSocketTheServerParamsName() async throws {
        let adb = RecordingAdb(forwardedPort: 41234)
        let transport = transport(over: adb, scid: 0x1234_5678)

        _ = try? await transport.start()

        // The scid *is* the socket name, and a mismatch here is a session that
        // connects to some other scrcpy's server.
        let forwards = await adb.invocations.filter { $0.contains("tcp:0") }
        #expect(
            forwards == [
                ["-s", "emulator-5554", "forward", "tcp:0", "localabstract:scrcpy_12345678"]
            ])
    }

    // MARK: - helpers

    private func transport(over adb: RecordingAdb, scid: UInt32) -> ScrcpyTransport {
        ScrcpyTransport(
            adb: adb.client(),
            config: .init(
                serial: "emulator-5554",
                params: ScrcpyServerParams(scid: scid),
                serverVersion: "4.0",
                // Never spawned: `startServer` failing is what leaves the
                // forward open, which is the state under test.
                localJarPath: "/nonexistent/scrcpy-server"))
    }

    /// A fake device side and an event loop group, both torn down afterwards.
    private func withFakeDevice(
        dropFirst: Int = 0,
        greeting: [UInt8] = [0x00],
        _ body: (UInt16, MultiThreadedEventLoopGroup, FakeScrcpyServer) async throws -> Void
    ) async throws {
        let server = FakeScrcpyServer(dropFirst: dropFirst, greeting: greeting)
        let port = try await server.start()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            try await body(port, group, server)
        } catch {
            try? await group.shutdownGracefully()
            await server.stop()
            throw error
        }
        try? await group.shutdownGracefully()
        await server.stop()
    }

    /// Poll a condition rather than sleeping a fixed time: a socket round trip
    /// is fast but not instant, and a fixed sleep is either a flake or a stall.
    private func waitUntil(
        _ condition: @Sendable () async -> Bool,
        within limit: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock().now.advanced(by: limit)
        while ContinuousClock().now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("condition never became true")
    }
}

/// The device side of `adb forward`, faked.
///
/// `dropFirst` reproduces the tunnel's defining behaviour: it accepts and then
/// drops, as many times as asked, before it starts behaving like a server that
/// is genuinely listening.
private actor FakeScrcpyServer {
    private var dropsRemaining: Int
    private let greeting: [UInt8]
    private(set) var accepts = 0
    private(set) var received = Data()

    private var group: MultiThreadedEventLoopGroup?
    private var channel: (any Channel)?

    init(dropFirst: Int = 0, greeting: [UInt8] = [0x00]) {
        dropsRemaining = dropFirst
        self.greeting = greeting
    }

    func start() async throws -> UInt16 {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [self] channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        FakeConnectionHandler(server: self))
                }
            }
        let bound = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        channel = bound
        guard let port = bound.localAddress?.port, let narrowed = UInt16(exactly: port) else {
            throw FakeError.noPort
        }
        return narrowed
    }

    func stop() async {
        let bound = channel
        channel = nil
        try? await bound?.close().get()
        let running = group
        group = nil
        try? await running?.shutdownGracefully()
    }

    /// Whether this accept should be dropped, and the greeting if not. One call
    /// per connection, so the count and the decision cannot disagree.
    func accept() -> [UInt8]? {
        accepts += 1
        if dropsRemaining > 0 {
            dropsRemaining -= 1
            return nil
        }
        return greeting
    }

    func record(_ bytes: Data) { received.append(bytes) }

    enum FakeError: Error { case noPort }
}

private final class FakeConnectionHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let server: FakeScrcpyServer

    init(server: FakeScrcpyServer) { self.server = server }

    func channelActive(context: ChannelHandlerContext) {
        let channel = context.channel
        Task {
            guard let greeting = await server.accept() else {
                try? await channel.close().get()
                return
            }
            guard !greeting.isEmpty else { return }
            var buffer = channel.allocator.buffer(capacity: greeting.count)
            buffer.writeBytes(greeting)
            try? await channel.writeAndFlush(buffer).get()
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let bytes = Data(unwrapInboundIn(data).readableBytesView)
        Task { await server.record(bytes) }
    }
}

/// An adb that answers `push` and `forward` without a device, recording every
/// argument vector so a test can assert the tunnel was opened and handed back.
private actor RecordingAdb {
    private(set) var invocations: [[String]] = []
    private let forwardedPort: Int

    init(forwardedPort: Int) { self.forwardedPort = forwardedPort }

    /// `nonisolated` so a test can build the client without awaiting: it only
    /// assembles values, and the recording itself goes through the actor.
    nonisolated func client() -> AdbClient {
        let runner = Runner(adb: self)
        // `isExecutableFile` is what decides adb was found. The path is never
        // actually spawned — `startServer` failing on it is the point.
        return AdbClient(
            locator: ToolLocator(
                runner: runner,
                environment: ["ANDROID_HOME": "/fake-sdk"],
                isExecutableFile: { $0.hasSuffix("adb") }),
            runner: runner)
    }

    func record(_ arguments: [String]) { invocations.append(arguments) }

    /// `adb forward tcp:0 …` prints the port it picked, which is the one the
    /// teardown has to hand back.
    func reply(to arguments: [String]) -> String {
        arguments.contains("tcp:0") ? "\(forwardedPort)\n" : ""
    }

    private struct Runner: ProcessRunning {
        let adb: RecordingAdb

        func run(
            executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int
        ) async -> ProcessOutput {
            await adb.record(arguments)
            let stdout = await adb.reply(to: arguments)
            return ProcessOutput(
                stdout: Data(stdout.utf8), stderr: Data(), exitCode: 0, timedOut: false)
        }
    }
}
