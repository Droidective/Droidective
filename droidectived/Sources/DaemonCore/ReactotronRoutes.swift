import ADBKit
import Foundation

/// Wire shapes for the Reactotron relay's device side.
///
/// The *listener* is a stream topic (`reactotron`) because it produces a feed.
/// This is the other half, and it is request/response: opening the `adb reverse`
/// tunnel that makes the device's `localhost:9090` reach the relay. Without it
/// the relay listens and no app ever arrives, which is the failure that looks
/// like the feature being broken.
public enum ReactotronProtocolRoutes {
    public struct ReverseRequest: Codable, Equatable, Sendable {
        /// Which devices to tunnel. Empty is not an error: a UI that offers the
        /// button with nothing connected gets an empty result rather than a 400.
        public let serials: [String]
        /// The relay's port. Defaults to upstream's 9090, and travels because
        /// the daemon may have bound something else.
        public let port: Int?

        public init(serials: [String], port: Int? = nil) {
            self.serials = serials
            self.port = port
        }
    }

    /// One device's outcome. The adb error travels rather than a bare false:
    /// "device offline" and "more than one device" want different things done
    /// about them.
    public struct ReverseResult: Codable, Equatable, Sendable {
        public let serial: String
        public let ok: Bool
        public let detail: String

        public init(serial: String, ok: Bool, detail: String) {
            self.serial = serial
            self.ok = ok
            self.detail = detail
        }
    }

    public struct ReverseResponse: Codable, Equatable, Sendable {
        public let results: [ReverseResult]
        /// The exact command run, for the UI to show — the Mac surfaces it in
        /// the Commands tab and the timeline's guidance, so both apps name it
        /// the same way.
        public let command: String

        public init(results: [ReverseResult], command: String) {
            self.results = results
            self.command = command
        }
    }
}

/// `POST /v1/reactotron/reverse` and its removal.
public enum ReactotronRoutes {
    /// How many times to try one device.
    ///
    /// A freshly attached or just-booted device rejects `reverse` for a moment,
    /// and the Mac retries three times for the same reason — a single attempt
    /// makes "plug in and open Reactotron" fail about as often as it works.
    static let attempts = 3
    static let retryDelay = Duration.milliseconds(500)

    public static func reverse(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ReactotronProtocolRoutes.ReverseRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }

        let port = request.port ?? ReactotronRelay.defaultPort
        var results: [ReactotronProtocolRoutes.ReverseResult] = []
        for serial in request.serials {
            results.append(await one(serial: serial, port: port, backend: backend))
        }
        return (200, DaemonProtocol.encoded(
            ReactotronProtocolRoutes.ReverseResponse(
                results: results, command: "adb reverse tcp:\(port) tcp:\(port)")))
    }

    /// Removes the tunnels. Best-effort per device: a device that has already
    /// gone is not a failure to report, it is the outcome asked for.
    public static func unreverse(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ReactotronProtocolRoutes.ReverseRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }

        let port = request.port ?? ReactotronRelay.defaultPort
        var results: [ReactotronProtocolRoutes.ReverseResult] = []
        for serial in request.serials {
            let result = await backend.reverseTcp(serial: serial, port: port, remove: true)
            results.append(
                ReactotronProtocolRoutes.ReverseResult(
                    serial: serial, ok: result.succeeded, detail: detail(of: result)))
        }
        return (200, DaemonProtocol.encoded(
            ReactotronProtocolRoutes.ReverseResponse(
                results: results, command: "adb reverse --remove tcp:\(port)")))
    }

    private static func one(
        serial: String, port: Int, backend: any DaemonBackend
    ) async -> ReactotronProtocolRoutes.ReverseResult {
        var last = "no attempt"
        for attempt in 0 ..< attempts {
            let result = await backend.reverseTcp(serial: serial, port: port, remove: false)
            if result.succeeded {
                return ReactotronProtocolRoutes.ReverseResult(serial: serial, ok: true, detail: "")
            }
            last = detail(of: result)
            if attempt < attempts - 1 { try? await Task.sleep(for: retryDelay) }
        }
        return ReactotronProtocolRoutes.ReverseResult(serial: serial, ok: false, detail: last)
    }

    /// adb says *why* on stderr and says nothing useful in its exit code, so the
    /// message is what travels — with the exit code behind it for the cases
    /// where stderr is empty.
    private static func detail(of result: AdbResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty { return stdout }
        return "exit \(result.exitCode.map(String.init) ?? "nil")"
    }
}
