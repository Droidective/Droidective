import ADBKit
import Foundation

/// Wire shapes for wireless adb: the USB→Wi-Fi bootstrap, Android 11+ pairing,
/// connect, and disconnect.
///
/// The endpoint parsing stays on **this** side. `ConnectionService.parseEndpoint`
/// is what decides whether "10.0.0.5:37199" is a plausible target, and it
/// already handles the cases a hand-written client check gets wrong — IPv6 with
/// and without brackets, a truncated IPv4 like "1.1.1", a port out of range. A
/// client re-implementing it would be a second opinion about what adb accepts,
/// and the two would drift.
public enum ConnectionProtocol {
    /// What the wireless sheet can ask for.
    ///
    /// A closed set resolved before anything runs, the shape `EmulatorProtocol`
    /// uses: an unknown verb is a 400 rather than an unhandled case downstream.
    public enum Action: String, Codable, CaseIterable, Sendable {
        /// Android 11+ pairing, with the code and the *pairing* port.
        case pair
        /// `adb connect host:port`. A bare host defaults to adb's own 5555.
        case connect
        /// `adb disconnect` — one target, or every wireless device.
        case disconnect
        /// `adb tcpip 5555` on a USB device, then connect to its Wi-Fi address.
        case tcpip
    }

    public struct ActionRequest: Codable, Equatable, Sendable {
        public let action: String
        /// The pasted endpoint, exactly as the phone displays it. Parsed here.
        public let endpoint: String?
        /// Pairing only.
        public let code: String?
        /// `tcpip` names the USB device to bootstrap; `disconnect` names the
        /// device to drop, and omitting it drops every wireless one — which is
        /// the Mac's "Disconnect all wireless".
        public let serial: String?

        public init(
            action: String, endpoint: String? = nil, code: String? = nil, serial: String? = nil
        ) {
            self.action = action
            self.endpoint = endpoint
            self.code = code
            self.serial = serial
        }

        public var resolvedAction: Action? { Action(rawValue: action) }
    }

    /// A request's arguments once they are known to be usable.
    enum Resolved {
        case pair(host: String, port: String, code: String)
        case connect(host: String, port: String)
        case disconnect(target: String?)
        case tcpip(serial: String)
    }

    /// What a request actually asks for, or nil when it cannot be honoured.
    ///
    /// Pairing insists on an explicit port: the Android 11+ pairing port is
    /// random per session, so defaulting it would silently target the wrong one
    /// — which is exactly why `ConnectionService` has two parse entry points.
    static func resolve(_ request: ActionRequest) -> Resolved? {
        switch request.resolvedAction {
        case .pair:
            guard let endpoint = ConnectionService.parseEndpoint(request.endpoint ?? ""),
                  let port = endpoint.port,
                  let code = request.code, !code.isEmpty
            else { return nil }
            return .pair(host: endpoint.host, port: port, code: code)
        case .connect:
            guard let endpoint = ConnectionService.parseConnectEndpoint(request.endpoint ?? ""),
                  let port = endpoint.port
            else { return nil }
            return .connect(host: endpoint.host, port: port)
        case .disconnect:
            // An empty string is "everything", not a device named "". Sending
            // `adb disconnect ""` would be a request adb cannot answer.
            let target = request.serial?.isEmpty == false ? request.serial : nil
            return .disconnect(target: target)
        case .tcpip:
            guard let serial = request.serial, !serial.isEmpty else { return nil }
            return .tcpip(serial: serial)
        case nil:
            return nil
        }
    }

    /// One `_adb-tls-connect._tcp` advertisement, for the sheet's
    /// after-pairing step.
    public struct Discovered: Codable, Equatable, Sendable {
        public let name: String
        public let host: String
        public let port: String
    }

    /// What pairing answered, plus the endpoint the device then advertised.
    ///
    /// The Mac's sheet auto-connects after a successful pair by looking the
    /// device up over mDNS, so the port travels with the result: without it the
    /// client would have to ask for a port the phone never showed.
    public struct PairResponse: Codable, Equatable, Sendable {
        public let result: ActionProtocol.RunResponse
        /// Absent when this adb has mDNS off, or nothing matching turned up in
        /// time. The sheet then asks for the connection port, as it must.
        public let discovered: Discovered?
    }

    public static let badConnectionRequest = DaemonProtocol.ErrorBody(
        code: "bad_connection_request",
        message: "Unknown action, or the request did not carry a usable endpoint, code or serial.")
}

/// The one wireless route. Every verb behind a single path with the verb in the
/// body, the shape `/v1/apps/control` and `/v1/files/op` already use: the
/// daemon owns the list of what may be done, and four near-identical routes
/// would only be four places for it to drift.
enum ConnectionRoutes {
    static func action(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ConnectionProtocol.ActionRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        guard let resolved = ConnectionProtocol.resolve(request) else {
            return (400, DaemonProtocol.encoded(ConnectionProtocol.badConnectionRequest))
        }
        do {
            return try await run(resolved, backend: backend)
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "The wireless command failed.",
                detail: "\(error)")))
        }
    }

    private static func run(
        _ resolved: ConnectionProtocol.Resolved, backend: any DaemonBackend
    ) async throws -> DaemonProtocol.Answer {
        switch resolved {
        case .pair(let host, let port, let code):
            let result = try await backend.pairWireless(host: host, port: port, code: code)
            // Only worth a lookup once pairing actually worked; a failed pair
            // has nothing to advertise.
            let endpoint = result.ok ? await backend.discoverConnectEndpoint(host: host) : nil
            return (200, DaemonProtocol.encoded(ConnectionProtocol.PairResponse(
                result: ActionProtocol.RunResponse(result),
                discovered: endpoint.flatMap { found in
                    found.port.map {
                        ConnectionProtocol.Discovered(name: host, host: found.host, port: $0)
                    }
                })))
        case .connect(let host, let port):
            return answer(try await backend.connectWireless(host: host, port: port))
        case .disconnect(let target):
            return answer(try await backend.disconnectWireless(target: target))
        case .tcpip(let serial):
            return answer(try await backend.enableTcpip(serial: serial))
        }
    }

    private static func answer(_ result: FeatureResult) -> DaemonProtocol.Answer {
        (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(result)))
    }
}
