import ADBKit
import Foundation

/// The wire shapes. Bodies reuse ADBKit's own `Sendable` models — `Device` is
/// already `Codable` — so there is no parallel hierarchy to drift out of sync.
public enum DaemonProtocol {
    /// Every route the daemon answers. A table rather than a switch buried in
    /// the listener, so a completeness test can iterate it — the same reason
    /// `McpToolRegistry` and `FeatureRegistry` are tables.
    public enum Route: String, CaseIterable, Sendable {
        case devicesList = "/v1/devices/list"
        case featuresList = "/v1/features/list"
        case actionsRun = "/v1/actions/run"
        case appsList = "/v1/apps/list"
        case appsControl = "/v1/apps/control"
        case deviceProps = "/v1/device/props"
        case deviceRoot = "/v1/device/root"
        case filesList = "/v1/files/list"
        /// Every mutation behind one route, with the verb in the body — the
        /// shape `/v1/apps/control` already uses, for the same reason: the
        /// daemon owns the list of what may be done, and four near-identical
        /// routes would only be four places for it to drift.
        case filesOp = "/v1/files/op"
        case filesInfo = "/v1/files/info"
        case filesPull = "/v1/files/pull"
        case crashesList = "/v1/crashes/list"
        case crashesClear = "/v1/crashes/clear"
    }

    /// The multiplexed stream socket. Not a `Route`: it is a WebSocket upgrade
    /// rather than a POST, and folding it into the route table would make
    /// `everyRouteIsReachable` assert something untrue about it.
    public static let streamPath = "/v1/stream"

    /// A route's answer before it meets NIO.
    ///
    /// The route groups that live outside `DaemonServer` deal in a plain status
    /// code rather than an `HTTPResponseStatus`, which is what lets them be
    /// tested without standing up a socket.
    public typealias Answer = (status: Int, body: Data)

    public struct DevicesResponse: Codable, Equatable, Sendable {
        public let devices: [Device]
        public init(devices: [Device]) { self.devices = devices }
    }

    public struct DeviceRequest: Codable, Equatable, Sendable {
        public let serial: String
        public init(serial: String) { self.serial = serial }
    }

    /// Everything `getprop` printed, unparsed.
    ///
    /// The dictionary is passed through rather than reshaped into named
    /// fields: which properties matter is the reader's question, and a daemon
    /// that picked a subset would be deciding it for them — the Mac's Device
    /// Info screen is a search box over the same raw set.
    public struct DevicePropsResponse: Codable, Equatable, Sendable {
        public let properties: [String: String]
        public init(properties: [String: String]) { self.properties = properties }
    }

    /// The root probe behind the File Explorer's Root toggle.
    ///
    /// Every signal travels, not just the verdict: the verdict is a summary of
    /// them, and a client that only received it could say *whether* a device is
    /// rooted but never *why* — which is the whole content of the Mac's Root
    /// Status screen.
    public struct RootStatusResponse: Codable, Equatable, Sendable {
        public struct Signal: Codable, Equatable, Sendable {
            public let name: String
            public let detail: String
            public let indicatesRoot: Bool
        }

        /// `su -c id` really answered uid 0 — the only definitive proof, and
        /// the one thing root-gated browsing needs.
        public let hasRootShell: Bool
        public let likelyRooted: Bool
        public let summary: String
        public let signals: [Signal]

        public init(_ status: RootStatus) {
            hasRootShell = status.hasRootShell
            likelyRooted = status.likelyRooted
            summary = status.summary
            signals = status.signals.map {
                Signal(name: $0.name, detail: $0.detail, indicatesRoot: $0.indicatesRoot)
            }
        }
    }

    /// One error shape everywhere, so the UI has exactly one error path.
    ///
    /// `code` is a stable machine string, `message` is user-facing, `detail`
    /// carries raw tool output when there is any.
    public struct ErrorBody: Codable, Equatable, Sendable {
        public struct Payload: Codable, Equatable, Sendable {
            public let code: String
            public let message: String
            public let detail: String?
        }
        public let error: Payload

        public init(code: String, message: String, detail: String? = nil) {
            error = Payload(code: code, message: message, detail: detail)
        }
    }

    /// HTTP status per failure class. The split matters most for adb: a
    /// non-zero adb exit is the device's answer, not a daemon fault, so it must
    /// never surface as a 500 — `AdbClient` models that distinction and the
    /// wire has to preserve it.
    public static func status(for refusal: DaemonGuards.Refusal) -> Int {
        switch refusal {
        case .missingToken, .badToken: return 401
        case .badHost, .badOrigin: return 403
        }
    }

    public static func errorBody(for refusal: DaemonGuards.Refusal) -> ErrorBody {
        switch refusal {
        case .missingToken:
            return ErrorBody(code: refusal.rawValue, message: "Missing bearer token.")
        case .badToken:
            return ErrorBody(code: refusal.rawValue, message: "Invalid bearer token.")
        case .badHost:
            return ErrorBody(code: refusal.rawValue, message: "Host is not loopback.")
        case .badOrigin:
            return ErrorBody(code: refusal.rawValue, message: "Origin is not loopback.")
        }
    }

    public static let notFound = ErrorBody(
        code: "unknown_route", message: "No such endpoint.")
    public static let badRequest = ErrorBody(
        code: "bad_request", message: "The request body could not be read.")
    public static let unknownFeature = ErrorBody(
        code: "unknown_feature", message: "No such feature, or it has no runner.")
    public static let unknownPlatform = ErrorBody(
        code: "unknown_platform", message: "platform must be android or iosSimulator.")

    public static let methodNotAllowed = ErrorBody(
        code: "method_not_allowed", message: "Endpoints are POST.")

    /// Stable key ordering so a response diff in a test is a real change rather
    /// than dictionary iteration order.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    /// `encode` for a route handler, which has no useful answer to a body it
    /// cannot encode. Every wire type here is a plain struct of scalars, so the
    /// throwing path is unreachable in practice — but a route must still return
    /// bytes rather than trap.
    public static func encoded(_ value: some Encodable) -> Data {
        (try? encode(value)) ?? Data("{}".utf8)
    }
}
