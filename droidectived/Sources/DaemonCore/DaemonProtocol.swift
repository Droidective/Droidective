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
        case featuresRoles = "/v1/features/roles"
        case actionsRun = "/v1/actions/run"
        case appsList = "/v1/apps/list"
        case appsControl = "/v1/apps/control"
        /// Which package is in front, for a caller that has to guess at one.
        case appsForeground = "/v1/apps/foreground"
        /// One app's process id, so a log client can narrow to it. See
        /// `LogcatProtocol`.
        case logcatPid = "/v1/logcat/pid"
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
        /// Developer Options and the dev-time restrictions. Read and write are
        /// split — unlike the filesystem's one `op` route — because a read
        /// answers with a whole table and a write names one row, so folding
        /// them together would mean a response type that is two shapes.
        case devSettingsRead = "/v1/devsettings/read"
        case devSettingsWrite = "/v1/devsettings/write"
        case restrictionsRead = "/v1/restrictions/read"
        case restrictionsWrite = "/v1/restrictions/write"
        case wifiRead = "/v1/wifi/read"
        case wifiWrite = "/v1/wifi/write"
        case dnsRead = "/v1/dns/read"
        case dnsWrite = "/v1/dns/write"
        /// The per-app screens. All four hang off a package id already chosen
        /// in Apps, so they take one shape: serial + packageId.
        case appInfo = "/v1/app/info"
        case appPermissions = "/v1/app/permissions"
        case appSetPermission = "/v1/app/permission"
        case appMeminfo = "/v1/app/meminfo"
        case appSandboxList = "/v1/app/sandbox/list"
        case appSandboxPull = "/v1/app/sandbox/pull"
        case appPullApk = "/v1/app/apk/pull"
        case emulatorsList = "/v1/emulators/list"
        case emulatorsAction = "/v1/emulators/action"
        case installFormats = "/v1/install/formats"
        case installRun = "/v1/install/run"
        /// Wireless adb — pair, connect, disconnect, and the USB→Wi-Fi
        /// bootstrap — with the verb in the body.
        case wirelessAction = "/v1/wireless/action"
        /// The saved deep links: read one app's list, replace it, launch one.
        /// The write takes the whole list rather than an add/edit/delete verb —
        /// the client holds what it is showing, and three routes would each
        /// have to re-derive it.
        case deepLinksRead = "/v1/deeplinks/read"
        case deepLinksWrite = "/v1/deeplinks/write"
        case deepLinksLaunch = "/v1/deeplinks/launch"
        case bugReportCreate = "/v1/bugreport/create"
        /// The saved custom commands: read the list, replace it, run one. The
        /// write takes the whole list for the reason the deep links do — the
        /// client holds what it is showing.
        /// The APK tools — inspect, sign, and convert a bundle. `apkToolchain`
        /// is asked first: the SDK build-tools are detected rather than
        /// downloadable, so a screen can say what is missing before someone
        /// picks a file.
        case apkToolchain = "/v1/apk/toolchain"
        case apkInspect = "/v1/apk/inspect"
        case apkSign = "/v1/apk/sign"
        case aabConvert = "/v1/apk/convert"
        /// Decompile: run jadx or apktool, then read and search what it wrote.
        /// The last three carry the output root back so the daemon can confine
        /// them to it — a path from a client is otherwise a read of any file
        /// the developer can read.
        case apkDecompile = "/v1/apk/decompile"
        case apkDecompileFile = "/v1/apk/decompile/file"
        case apkDecompileSearch = "/v1/apk/decompile/search"
        case apkRebuild = "/v1/apk/rebuild"
        /// The downloadable half of the APK toolchain. Asked before a run so a
        /// screen can offer the download rather than failing into it.
        case apkTools = "/v1/apk/tools"
        case apkToolInstall = "/v1/apk/tools/install"
        case customCommandsRead = "/v1/customcommands/read"
        case customCommandsWrite = "/v1/customcommands/write"
        case customCommandsRun = "/v1/customcommands/run"
        /// Which external tools are on this machine, for Settings ▸ Doctor and
        /// the device bar's adb warning.
        case toolsDetect = "/v1/tools/detect"
        case reactotronReverse = "/v1/reactotron/reverse"
        case reactotronUnreverse = "/v1/reactotron/unreverse"
        /// API Testing. The workspace read/write pair takes the whole document
        /// for the reason the deep links and custom commands do — the client
        /// holds what it is showing — and the rest are the four things a
        /// browser-side client cannot do for itself: send a request without a
        /// CORS opinion, generate code, parse a cURL line, and read or write a
        /// Postman file. There is deliberately no runner route: see
        /// `ApiClientProtocol`.
        case apiRead = "/v1/api/read"
        case apiWrite = "/v1/api/write"
        case apiSend = "/v1/api/send"
        case apiCancel = "/v1/api/cancel"
        case apiCode = "/v1/api/code"
        case apiCurl = "/v1/api/curl"
        case apiImport = "/v1/api/import"
        case apiExport = "/v1/api/export"
        /// Screen recording. Four verbs plus a read rather than a stream: the
        /// session lives in the daemon, and the only thing that changes second
        /// to second is an elapsed time the client can count itself.
        case recordStatus = "/v1/record/status"
        case recordStart = "/v1/record/start"
        case recordPause = "/v1/record/pause"
        case recordResume = "/v1/record/resume"
        case recordStop = "/v1/record/stop"
        /// The managed-tool store behind Settings ▸ Tools. Separate from
        /// `/v1/apk/tools`, which exists for the decompiler's two and says so:
        /// this one lists whatever the *host* can fetch, which is why ffmpeg
        /// appears on Windows and Linux and not on macOS.
        case managedToolsList = "/v1/tools/managed"
        case managedToolsInstall = "/v1/tools/managed/install"
        case managedToolsRemove = "/v1/tools/managed/remove"
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
