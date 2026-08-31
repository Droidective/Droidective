import ADBKit
import Foundation

/// The wire shapes for API Testing.
///
/// The persisted document travels as ADBKit's own `ApiClientData` — it is
/// `Codable` already, and a parallel DTO for a 780-line model would be 780
/// lines of drift. Only the *answers* need shapes of their own, because
/// `ApiResponse` and `PreparedRequest` are not `Codable`: one carries `Data`,
/// both carry `[(key:value:)]` tuples.
///
/// The collection *runner* is deliberately absent. On the Mac `ApiRunner` runs
/// in-process and reports each row as it lands; here the client already holds
/// the collection, so it walks the tree itself and sends one request at a time
/// through `/v1/api/send`. That is the same sequential order with the same
/// scope, and it keeps the progress live and the cancel instant — a run route
/// would have to grow a stream topic to say as much.
public enum ApiClientProtocol {

    /// The four variable layers, as `VariableScope` holds them.
    ///
    /// A DTO because `VariableScope` is `Sendable` but not `Codable`, and the
    /// client is the side that knows which collection a request was opened
    /// from — so it resolves the layers and sends them, rather than naming an
    /// id the daemon would have to look up in a document the client owns.
    public struct Scope: Codable, Equatable, Sendable {
        public var globals: [String: String]
        public var environment: [String: String]
        public var collection: [String: String]
        public var local: [String: String]

        public init(
            globals: [String: String] = [:],
            environment: [String: String] = [:],
            collection: [String: String] = [:],
            local: [String: String] = [:]
        ) {
            self.globals = globals
            self.environment = environment
            self.collection = collection
            self.local = local
        }

        public var model: VariableScope {
            VariableScope(
                globals: globals, environment: environment,
                collection: collection, local: local)
        }
    }

    public struct ReadResponse: Codable, Equatable, Sendable {
        public let data: ApiClientData
        public init(data: ApiClientData) { self.data = data }
    }

    /// The whole document, not a patch — the same reasoning the deep links and
    /// the custom commands follow: the client holds what it is showing.
    public struct WriteRequest: Codable, Equatable, Sendable {
        public let data: ApiClientData
        public init(data: ApiClientData) { self.data = data }
    }

    public struct SendRequest: Codable, Equatable, Sendable {
        public let request: SavedRequest
        public let scope: Scope
        /// The collection's auth, applied when the request's own is `.none`.
        public let inheritedAuth: AuthSpec?
        /// A handle for `/v1/api/cancel`.
        ///
        /// The client's own id rather than the request's: two concurrent sends
        /// of the same saved request are two different things to cancel, which
        /// is the reason `HttpClientService` keeps no registry of its own.
        /// Absent means "nothing will ask me to stop", which is what the
        /// collection runner sends.
        public let sendId: String?

        public init(
            request: SavedRequest, scope: Scope = Scope(),
            inheritedAuth: AuthSpec? = nil, sendId: String? = nil
        ) {
            self.request = request
            self.scope = scope
            self.inheritedAuth = inheritedAuth
            self.sendId = sendId
        }
    }

    public struct CancelRequest: Codable, Equatable, Sendable {
        public let sendId: String
        public init(sendId: String) { self.sendId = sendId }
    }

    /// Whether there was still something to stop.
    ///
    /// False is not a failure: a send that finished a moment before Cancel was
    /// pressed is the ordinary race, and reporting it as an error would put a
    /// red banner over a response that arrived correctly.
    public struct CancelResponse: Codable, Equatable, Sendable {
        public let cancelled: Bool
        public init(cancelled: Bool) { self.cancelled = cancelled }
    }

    public struct Header: Codable, Equatable, Sendable {
        public let key: String
        public let value: String
        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public struct Cookie: Codable, Equatable, Sendable {
        public let name: String
        public let value: String
        public let domain: String
        public let path: String
        public let expires: String
        public let maxAge: String
        public let httpOnly: Bool
        public let secure: Bool
        public let sameSite: String

        public init(_ cookie: ApiCookie) {
            name = cookie.name
            value = cookie.value
            domain = cookie.domain
            path = cookie.path
            expires = cookie.expires
            maxAge = cookie.maxAge
            httpOnly = cookie.httpOnly
            secure = cookie.secure
            sameSite = cookie.sameSite
        }
    }

    public struct Timing: Codable, Equatable, Sendable {
        public let dns: Double?
        public let connect: Double?
        public let tls: Double?
        public let firstByte: Double?
        public let total: Double

        public init(_ timing: ApiTiming) {
            dns = timing.dns
            connect = timing.connect
            tls = timing.tls
            firstByte = timing.firstByte
            total = timing.total
        }
    }

    public struct Redirect: Codable, Equatable, Sendable {
        public let statusCode: Int
        public let from: String
        public let to: String

        public init(_ hop: RedirectHop) {
            statusCode = hop.statusCode
            from = hop.from
            to = hop.to
        }
    }

    public struct Assertion: Codable, Equatable, Sendable {
        public let id: String
        public let label: String
        public let passed: Bool
        public let detail: String

        public init(_ result: AssertionResult) {
            id = result.id
            label = result.label
            passed = result.passed
            detail = result.detail
        }
    }

    /// Bytes the daemon will inline as base64 for a body it cannot send as
    /// text. An image preview and a Save need the bytes themselves; a 32 MB
    /// download does not need to cross the IPC boundary a third larger than it
    /// arrived, so past this the response says the bytes were left behind
    /// rather than pretending the body was empty.
    public static let maxInlineBodyBytes = 8 << 20

    /// One send's answer.
    ///
    /// The body travels in whichever form the client can use: `bodyText` and
    /// `prettyBody` for anything textual — those are exactly the pane's Raw and
    /// Pretty, so nothing is duplicated — and `bodyBase64` only for an image or
    /// a binary, which is the one case where the bytes themselves are the
    /// content.
    public struct SendResponse: Codable, Equatable, Sendable {
        public let statusCode: Int
        public let statusText: String
        public let headers: [Header]
        public let cookies: [Cookie]
        public let bodyText: String?
        public let prettyBody: String?
        public let bodyBase64: String?
        /// True when the body was binary and larger than `maxInlineBodyBytes`,
        /// so the pane can say why there is nothing to show.
        public let bodyOmitted: Bool
        public let format: String
        public let mediaType: String
        public let elapsedMs: Double
        public let size: Int
        public let sizeText: String
        public let truncated: Bool
        public let redirects: [Redirect]
        public let timing: Timing?
        public let finalURL: String
        /// What actually went on the wire, for the Timing tab's two rows.
        public let sentBytes: Int
        public let preparedURL: String
        public let assertions: [Assertion]
        public let warnings: [String]

        public init(_ outcome: ApiSendOutcome) {
            let response = outcome.response
            statusCode = response.statusCode
            statusText = response.statusText
            headers = response.headers.map { Header(key: $0.key, value: $0.value) }
            cookies = response.cookies.map(Cookie.init)
            let textual = response.format.isTextual
            bodyText = textual ? response.bodyString : nil
            prettyBody = textual ? response.prettyBody : nil
            let inlineable = !textual && response.body.count <= maxInlineBodyBytes
            bodyBase64 = inlineable ? response.body.base64EncodedString() : nil
            bodyOmitted = !textual && !inlineable && !response.body.isEmpty
            format = response.format.rawValue
            mediaType = response.mediaType
            elapsedMs = response.elapsedMs
            size = response.size
            sizeText = response.sizeText
            truncated = response.truncated
            redirects = response.redirects.map(Redirect.init)
            timing = response.timing.map(Timing.init)
            finalURL = response.finalURL
            sentBytes = outcome.prepared.body?.count ?? 0
            preparedURL = outcome.prepared.url
            assertions = outcome.assertions.map(Assertion.init)
            warnings = outcome.warnings
        }
    }

    public struct CodeRequest: Codable, Equatable, Sendable {
        public let request: SavedRequest
        public let scope: Scope
        public let inheritedAuth: AuthSpec?
        /// A `CodeTarget` raw value. An unknown one is a 400 rather than a
        /// silent fall back to cURL, which would look like a broken picker.
        public let target: String

        public init(
            request: SavedRequest, scope: Scope = Scope(),
            inheritedAuth: AuthSpec? = nil, target: String
        ) {
            self.request = request
            self.scope = scope
            self.inheritedAuth = inheritedAuth
            self.target = target
        }
    }

    public struct CodeResponse: Codable, Equatable, Sendable {
        public let code: String
        public init(code: String) { self.code = code }
    }

    public struct CurlRequest: Codable, Equatable, Sendable {
        public let text: String
        public init(text: String) { self.text = text }
    }

    public struct CurlResponse: Codable, Equatable, Sendable {
        public let request: SavedRequest
        public let warnings: [String]

        public init(_ result: CurlImport) {
            request = result.request
            warnings = result.warnings
        }
    }

    public struct ImportRequest: Codable, Equatable, Sendable {
        public let path: String
        public init(path: String) { self.path = path }
    }

    /// What a Postman file contained, with fresh ids already applied.
    ///
    /// The reidentifying happens here rather than on the client because the
    /// same walk already exists in ADBKit and importing the same file twice
    /// must not produce two collections that share every id.
    public struct ImportResponse: Codable, Equatable, Sendable {
        public let collections: [ApiCollection]
        public let environments: [ApiEnvironment]
        public let summary: String
        public let warnings: [String]

        public init(
            collections: [ApiCollection], environments: [ApiEnvironment],
            summary: String, warnings: [String]
        ) {
            self.collections = collections
            self.environments = environments
            self.summary = summary
            self.warnings = warnings
        }
    }

    /// What to turn into a Postman file. The payload travels rather than an id:
    /// the client owns the document, so an id would make the daemon export
    /// whatever it last had on disk instead of what is on screen.
    public enum ExportPayload: Codable, Equatable, Sendable {
        case collection(ApiCollection)
        case environment(ApiEnvironment)
        case workspace(ApiClientData)

        private enum CodingKeys: String, CodingKey { case kind, collection, environment, workspace }
        private enum Kind: String, Codable { case collection, environment, workspace }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .collection:
                self = .collection(try container.decode(ApiCollection.self, forKey: .collection))
            case .environment:
                self = .environment(try container.decode(ApiEnvironment.self, forKey: .environment))
            case .workspace:
                self = .workspace(try container.decode(ApiClientData.self, forKey: .workspace))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .collection(let value):
                try container.encode(Kind.collection, forKey: .kind)
                try container.encode(value, forKey: .collection)
            case .environment(let value):
                try container.encode(Kind.environment, forKey: .kind)
                try container.encode(value, forKey: .environment)
            case .workspace(let value):
                try container.encode(Kind.workspace, forKey: .kind)
                try container.encode(value, forKey: .workspace)
            }
        }
    }

    public struct ExportRequest: Codable, Equatable, Sendable {
        public let payload: ExportPayload
        public let includeSecrets: Bool

        public init(payload: ExportPayload, includeSecrets: Bool = false) {
            self.payload = payload
            self.includeSecrets = includeSecrets
        }
    }

    /// The file's text and the name to offer for it.
    ///
    /// Text rather than a written file: every other export in this app goes
    /// through the host's own `export_text` into `~/Downloads/Droidective`, and
    /// two places deciding where a file lands is how a Show in folder button
    /// ends up pointing at the wrong one.
    public struct ExportResponse: Codable, Equatable, Sendable {
        public let json: String
        public let suggestedName: String

        public init(json: String, suggestedName: String) {
            self.json = json
            self.suggestedName = suggestedName
        }
    }

    static let badRequest = DaemonProtocol.ErrorBody(
        code: "bad_request", message: "That is not an API Testing request.", detail: nil)

    static let unknownTarget = DaemonProtocol.ErrorBody(
        code: "unknown_target", message: "No code generator by that name.", detail: nil)

    static let notCurl = DaemonProtocol.ErrorBody(
        code: "not_curl",
        message: "Couldn't parse that. It needs to start with \"curl\" and contain a URL.",
        detail: nil)

    /// A send that never reached a response.
    ///
    /// 200 with a non-2xx status is the server's answer and belongs in the
    /// pane; *this* is the transport failing, which is the pane's error state.
    /// The distinction is the one `AdbClient` draws for adb, for the same
    /// reason: a UI cannot tell them apart from a status code alone.
    static func sendFailure(_ error: any Error) -> DaemonProtocol.ErrorBody {
        if error is CancellationError {
            return DaemonProtocol.ErrorBody(
                code: "cancelled", message: "Request cancelled.", detail: nil)
        }
        let described = (error as? any LocalizedError)?.errorDescription
        return DaemonProtocol.ErrorBody(
            code: "send_failed",
            message: described ?? "The request could not be sent.",
            detail: described == nil ? "\(error)" : nil)
    }
}

/// The sends a client may still ask to stop.
///
/// An actor keyed by the *client's* id rather than the request's, because two
/// concurrent sends of the same saved request are two different things to
/// cancel — the same reason `HttpClientService` deliberately keeps no registry
/// of its own. Entries are removed when the send finishes, so a long-lived
/// daemon does not accumulate one per request ever made.
actor InFlightSends {
    private var tasks: [String: Task<ApiSendOutcome, any Error>] = [:]

    func register(_ id: String, task: Task<ApiSendOutcome, any Error>) {
        tasks[id] = task
    }

    func finished(_ id: String) {
        tasks[id] = nil
    }

    /// False when there was nothing to stop — the ordinary race, not a fault.
    func cancel(_ id: String) -> Bool {
        guard let task = tasks.removeValue(forKey: id) else { return false }
        task.cancel()
        return true
    }
}

/// The API Testing routes: the workspace, one send, code, cURL, and the two
/// halves of Postman interchange.
enum ApiClientRoutes {
    static func read(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        (200, DaemonProtocol.encoded(
            ApiClientProtocol.ReadResponse(data: await backend.apiWorkspace())))
    }

    static func write(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ApiClientProtocol.WriteRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(ApiClientProtocol.badRequest)) }
        do {
            try await backend.writeApiWorkspace(request.data)
            return (200, DaemonProtocol.encoded(
                ApiClientProtocol.ReadResponse(data: request.data)))
        } catch {
            // The store, not the network: a disk that refuses the write is a
            // daemon-side fault, and the pane says so rather than losing
            // someone's collections at the next launch without a word.
            return (500, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "store_failed", message: "Couldn't save your API workspace.",
                detail: "\(error)")))
        }
    }

    static func send(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ApiClientProtocol.SendRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(ApiClientProtocol.badRequest)) }
        do {
            let outcome = try await backend.sendApiRequest(request)
            return (200, DaemonProtocol.encoded(ApiClientProtocol.SendResponse(outcome)))
        } catch {
            return (502, DaemonProtocol.encoded(ApiClientProtocol.sendFailure(error)))
        }
    }

    static func cancel(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ApiClientProtocol.CancelRequest.self, from: body), !request.sendId.isEmpty
        else { return (400, DaemonProtocol.encoded(ApiClientProtocol.badRequest)) }
        let stopped = await backend.cancelApiSend(sendId: request.sendId)
        return (200, DaemonProtocol.encoded(ApiClientProtocol.CancelResponse(cancelled: stopped)))
    }

    static func code(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ApiClientProtocol.CodeRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(ApiClientProtocol.badRequest)) }
        guard CodeTarget(rawValue: request.target) != nil else {
            return (400, DaemonProtocol.encoded(ApiClientProtocol.unknownTarget))
        }
        let generated = await backend.apiCode(request)
        return (200, DaemonProtocol.encoded(ApiClientProtocol.CodeResponse(code: generated)))
    }

    static func curl(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ApiClientProtocol.CurlRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(ApiClientProtocol.badRequest)) }
        guard let parsed = await backend.parseCurl(request.text) else {
            return (422, DaemonProtocol.encoded(ApiClientProtocol.notCurl))
        }
        return (200, DaemonProtocol.encoded(ApiClientProtocol.CurlResponse(parsed)))
    }

    static func importFile(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ApiClientProtocol.ImportRequest.self, from: body), !request.path.isEmpty
        else { return (400, DaemonProtocol.encoded(ApiClientProtocol.badRequest)) }
        do {
            return (200, DaemonProtocol.encoded(try await backend.importApiFile(path: request.path)))
        } catch {
            // The file's own reason: "not a Postman file" and "that path is not
            // readable" send someone to different places.
            return (422, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "import_failed",
                message: (error as? any LocalizedError)?.errorDescription
                    ?? "That file couldn't be imported.",
                detail: "\(error)")))
        }
    }

    static func export(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ApiClientProtocol.ExportRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(ApiClientProtocol.badRequest)) }
        do {
            return (200, DaemonProtocol.encoded(try await backend.exportApi(request)))
        } catch {
            return (422, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "export_failed", message: "Couldn't build that export.",
                detail: "\(error)")))
        }
    }
}
