import ADBKit
import Foundation
import Testing

@testable import DaemonCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Whether this host's Foundation ships a WebSocket client.
private let hasWebSocketClient: Bool = {
    #if canImport(Darwin)
    return true
    #else
    return false
    #endif
}()

/// Drives the stream socket end to end with a real WebSocket client. The
/// session's logic is covered by `StreamSessionTests`; what this proves is that
/// the upgrade, the auth on it, and the frame plumbing are actually wired up.
///
/// The **server** is portable NIO and runs everywhere. The *client* is not:
/// corelibs-Foundation has no `URLSessionWebSocketTask` ("WebSockets not
/// supported by libcurl"), so these are Apple-scoped. Note that leaving them
/// enabled off-Darwin would be worse than skipping them — the two refusal
/// cases assert that a throw happens, and the unsupported-client error is a
/// throw, so they would pass for entirely the wrong reason.
///
/// Restoring Linux coverage needs a portable WebSocket client for tests; the
/// raw-socket probe that found the masking bug is the obvious basis for one.
/// Tracked in docs/cross-platform.md.
@Suite(.timeLimit(.minutes(1)), .enabled(if: hasWebSocketClient)) struct WebSocketTests {
    private struct StubBackend: DaemonBackend {
        func listDevices() async -> [Device] { [] }
        func runAction(
            featureID: String, serial: String, platform: DevicePlatform,
            params: [String: FeatureValue]
        ) async -> FeatureResult {
            FeatureResult(ok: true, message: "stub")
        }

        func listApps(serial: String) async throws -> [AppListing] { [] }

        func controlApp(
            serial: String, packageId: String, action: AppControlService.AppAction
        ) async throws -> FeatureResult {
            FeatureResult(ok: true, message: "stub")
        }

        func deviceProperties(serial: String) async throws -> [String: String] {
            ["ro.product.model": "Pixel", "ro.build.version.release": "14"]
        }

        func rootStatus(serial: String) async -> RootStatus {
            RootStatus(hasRootShell: false, likelyRooted: false, summary: "stub", signals: [])
        }

        func listFiles(serial: String, path: String, asRoot: Bool) async throws -> [FsEntry] { [] }

        func fileOperation(
            serial: String, _ operation: FileProtocol.Operation, asRoot: Bool
        ) async throws -> FeatureResult {
            FeatureResult(ok: true, message: "stub")
        }

        func fileInfo(
            serial: String, path: String, asRoot: Bool
        ) async throws -> FileExplorerService.FileInfo? { nil }

        func pullFile(
            serial: String, path: String, to destination: String, asRoot: Bool
        ) async throws -> String { destination }

        func crashes(serial: String) async throws -> [CrashReport] { [] }

        func clearCrashBuffer(serial: String) async throws {}
    }

    private struct FixedSource: StreamSource {
        let devices: [Device]
        func devices() async -> AsyncStream<[Device]> {
            let value = devices
            return AsyncStream { continuation in
                continuation.yield(value)
                continuation.finish()
            }
        }
        func logcat(serial: String) async throws -> AsyncStream<[LogLine]> {
            AsyncStream { $0.finish() }
        }
        func stopLogcat(serial: String) async {}
        func performance(
            serial: String, packageId: String?, includeProcesses: Bool
        ) async -> AsyncStream<PerformanceService.PerfPoll> {
            AsyncStream { $0.finish() }
        }
    }

    private static func device(_ serial: String) -> Device {
        Device(
            serial: serial, state: "device", model: nil, product: nil, transportId: nil,
            label: serial, isWireless: false, platform: .android)
    }

    private func withServer(
        _ body: (_ port: Int, _ token: String) async throws -> Void
    ) async throws {
        let token = DaemonToken.generate()
        let server = DaemonServer(
            backend: StubBackend(), token: token,
            streamSource: FixedSource(devices: [Self.device("emulator-5554")]))
        let bound = try await server.start(port: 0)
        do { try await body(bound.port, token) } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    private func socket(port: Int, token: String?) -> URLSessionWebSocketTask {
        var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/v1/stream")!)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        return task
    }

    private struct ReceiveTimedOut: Error {}

    /// Always bounded. A refused upgrade leaves `receive()` waiting on a socket
    /// that will never answer, and a test that hangs is worse than one that
    /// fails — it takes the whole suite with it.
    private func receiveText(
        _ task: URLSessionWebSocketTask, timeout: Duration = .seconds(10)
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                switch try await task.receive() {
                case .string(let text): return text
                case .data(let data): return String(decoding: data, as: UTF8.self)
                @unknown default: return ""
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ReceiveTimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ReceiveTimedOut() }
            return first
        }
    }

    @Test func subscribesAndReceivesOverARealSocket() async throws {
        try await withServer { port, token in
            let task = socket(port: port, token: token)
            defer { task.cancel(with: .goingAway, reason: nil) }

            try await task.send(.string(#"{"op":"subscribe","id":1,"topic":"devices"}"#))

            let ack = try await receiveText(task)
            #expect(ack.contains(#""event":"subscribed""#))
            let batch = try await receiveText(task)
            #expect(batch.contains(#""event":"batch""#))
            #expect(batch.contains("emulator-5554"))
        }
    }

    @Test func refusesTheUpgradeWithoutAToken() async throws {
        // The handshake itself must fail. Accepting the upgrade and only then
        // checking would leave an authenticated-looking socket open to anything
        // that can reach the port.
        try await withServer { port, _ in
            let task = socket(port: port, token: nil)
            defer { task.cancel(with: .goingAway, reason: nil) }

            // Only the bounded receive: `send` on a task whose upgrade was
            // refused can block forever, before any receive deadline applies.
            await #expect(throws: (any Error).self) {
                _ = try await self.receiveText(task, timeout: .seconds(5))
            }
        }
    }

    @Test func refusesTheUpgradeWithAWrongToken() async throws {
        try await withServer { port, _ in
            let task = socket(port: port, token: DaemonToken.generate())
            defer { task.cancel(with: .goingAway, reason: nil) }

            await #expect(throws: (any Error).self) {
                _ = try await self.receiveText(task, timeout: .seconds(5))
            }
        }
    }

    @Test func aMalformedCommandIsAnsweredAndTheSocketSurvives() async throws {
        try await withServer { port, token in
            let task = socket(port: port, token: token)
            defer { task.cancel(with: .goingAway, reason: nil) }

            try await task.send(.string("this is not json"))
            let failure = try await receiveText(task)
            #expect(failure.contains(#""event":"failed""#))

            // Still usable — a buggy client must not wedge its own connection.
            try await task.send(.string(#"{"op":"subscribe","id":2,"topic":"devices"}"#))
            let ack = try await receiveText(task)
            #expect(ack.contains(#""event":"subscribed""#))
        }
    }

    @Test func theRoutesStillWorkAlongsideTheSocket() async throws {
        // One listener serves both; adding the upgrader must not break POST.
        try await withServer { port, token in
            var request = URLRequest(
                url: URL(string: "http://127.0.0.1:\(port)/v1/devices/list")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        }
    }
}
