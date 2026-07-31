import Foundation

// MARK: - HTTP method

public enum HttpMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"

    public var id: String { rawValue }

    /// Methods where a request body is conventional. A body on the others is
    /// legal but unusual, so the UI warns instead of silently dropping it.
    public var conventionallyHasBody: Bool {
        switch self {
        case .post, .put, .patch: return true
        case .get, .delete, .head, .options: return false
        }
    }
}

// MARK: - Key/value pair (headers, query, form fields, variables)

public struct ApiKeyValue: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var key: String
    public var value: String
    public var enabled: Bool
    /// Free-text note. Maps to Postman's `description`, named differently so it
    /// doesn't shadow `CustomStringConvertible.description`.
    public var note: String

    public init(
        id: String = UUID().uuidString,
        key: String,
        value: String,
        enabled: Bool = true,
        note: String = ""
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.enabled = enabled
        self.note = note
    }

    private enum CodingKeys: String, CodingKey { case id, key, value, enabled, note }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

extension [ApiKeyValue] {
    /// Enabled pairs with a non-empty key, in order. Duplicate keys are kept —
    /// repeated headers and repeated query params are both legal.
    public var activePairs: [(key: String, value: String)] {
        compactMap { $0.enabled && !$0.key.isEmpty ? (key: $0.key, value: $0.value) : nil }
    }

    /// Last-wins map of enabled pairs, for variable lookup.
    public var activeMap: [String: String] {
        var map: [String: String] = [:]
        for pair in self where pair.enabled && !pair.key.isEmpty {
            map[pair.key] = pair.value
        }
        return map
    }

    /// Case-insensitive lookup, for header checks.
    public func firstValue(forKeyIgnoringCase key: String) -> String? {
        let wanted = key.lowercased()
        return first { $0.enabled && $0.key.lowercased() == wanted }?.value
    }
}

// MARK: - Multipart form field

public enum FormFieldKind: String, Codable, Sendable, CaseIterable {
    case text
    case file
}

public struct ApiFormField: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var key: String
    /// Text value for `.text`, an absolute file path for `.file`.
    public var value: String
    public var kind: FormFieldKind
    /// Explicit part Content-Type. Empty means "let the builder decide".
    public var contentType: String
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString,
        key: String,
        value: String,
        kind: FormFieldKind = .text,
        contentType: String = "",
        enabled: Bool = true
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.kind = kind
        self.contentType = contentType
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey { case id, key, value, kind, contentType, enabled }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        kind = try c.decodeIfPresent(FormFieldKind.self, forKey: .kind) ?? .text
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

// MARK: - Request body

public enum BodyType: String, Codable, Sendable, CaseIterable {
    case none
    case json
    case formUrlEncoded
    case multipart
    case raw
    case graphql
    case binary
}

/// Syntax of a `.raw` body. Drives the editor's highlighting and the default
/// Content-Type; mirrors Postman's `options.raw.language`.
public enum RawLanguage: String, Codable, Sendable, CaseIterable {
    case text
    case json
    case xml
    case html
    case javascript

    public var contentType: String {
        switch self {
        case .text: return "text/plain"
        case .json: return "application/json"
        case .xml: return "application/xml"
        case .html: return "text/html"
        case .javascript: return "application/javascript"
        }
    }
}

public struct RequestBodySpec: Codable, Sendable, Equatable {
    public var type: BodyType
    public var jsonText: String
    public var rawText: String
    public var rawLanguage: RawLanguage
    /// Overrides the language's default Content-Type when non-empty.
    public var rawContentType: String
    public var formFields: [ApiKeyValue]
    public var multipartFields: [ApiFormField]
    public var graphqlQuery: String
    public var graphqlVariables: String
    public var binaryFilePath: String

    public init(
        type: BodyType = .none,
        jsonText: String = "",
        rawText: String = "",
        rawLanguage: RawLanguage = .text,
        rawContentType: String = "",
        formFields: [ApiKeyValue] = [],
        multipartFields: [ApiFormField] = [],
        graphqlQuery: String = "",
        graphqlVariables: String = "",
        binaryFilePath: String = ""
    ) {
        self.type = type
        self.jsonText = jsonText
        self.rawText = rawText
        self.rawLanguage = rawLanguage
        self.rawContentType = rawContentType
        self.formFields = formFields
        self.multipartFields = multipartFields
        self.graphqlQuery = graphqlQuery
        self.graphqlVariables = graphqlVariables
        self.binaryFilePath = binaryFilePath
    }

    /// Content-Type this body implies, or nil when the body carries none.
    public var impliedContentType: String? {
        switch type {
        case .none: return nil
        case .json, .graphql: return "application/json"
        case .formUrlEncoded: return "application/x-www-form-urlencoded"
        case .multipart: return nil  // built with the generated boundary
        case .raw: return rawContentType.isEmpty ? rawLanguage.contentType : rawContentType
        case .binary: return "application/octet-stream"
        }
    }

    /// Whether this body would put bytes on the wire.
    public var isEmpty: Bool {
        switch type {
        case .none: return true
        case .json: return jsonText.isEmpty
        case .raw: return rawText.isEmpty
        case .formUrlEncoded: return formFields.activePairs.isEmpty
        case .multipart: return multipartFields.filter(\.enabled).isEmpty
        case .graphql: return graphqlQuery.isEmpty && graphqlVariables.isEmpty
        case .binary: return binaryFilePath.isEmpty
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, jsonText, rawText, rawLanguage, rawContentType
        case formFields, multipartFields, graphqlQuery, graphqlVariables, binaryFilePath
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(BodyType.self, forKey: .type) ?? .none
        jsonText = try c.decodeIfPresent(String.self, forKey: .jsonText) ?? ""
        rawText = try c.decodeIfPresent(String.self, forKey: .rawText) ?? ""
        rawLanguage = try c.decodeIfPresent(RawLanguage.self, forKey: .rawLanguage) ?? .text
        rawContentType = try c.decodeIfPresent(String.self, forKey: .rawContentType) ?? ""
        formFields = try c.decodeIfPresent([ApiKeyValue].self, forKey: .formFields) ?? []
        multipartFields = try c.decodeIfPresent([ApiFormField].self, forKey: .multipartFields) ?? []
        graphqlQuery = try c.decodeIfPresent(String.self, forKey: .graphqlQuery) ?? ""
        graphqlVariables = try c.decodeIfPresent(String.self, forKey: .graphqlVariables) ?? ""
        binaryFilePath = try c.decodeIfPresent(String.self, forKey: .binaryFilePath) ?? ""
    }
}

// MARK: - Auth

public enum AuthType: String, Codable, Sendable, CaseIterable {
    case none
    case bearer
    case basic
    case apiKey
    case oauth2
}

/// Where an API key rides. Postman's "Add to: Header / Query Params".
public enum ApiKeyLocation: String, Codable, Sendable, CaseIterable {
    case header
    case query
}

public struct AuthSpec: Codable, Sendable, Equatable {
    public var type: AuthType
    public var bearerToken: String
    public var basicUsername: String
    public var basicPassword: String
    public var apiKeyName: String
    public var apiKeyValue: String
    public var apiKeyLocation: ApiKeyLocation
    /// An already-obtained OAuth 2 access token. Droidective does not run the
    /// grant flows; paste a token from wherever you obtained it.
    public var oauth2Token: String
    public var oauth2HeaderPrefix: String

    public init(
        type: AuthType = .none,
        bearerToken: String = "",
        basicUsername: String = "",
        basicPassword: String = "",
        apiKeyName: String = "",
        apiKeyValue: String = "",
        apiKeyLocation: ApiKeyLocation = .header,
        oauth2Token: String = "",
        oauth2HeaderPrefix: String = "Bearer"
    ) {
        self.type = type
        self.bearerToken = bearerToken
        self.basicUsername = basicUsername
        self.basicPassword = basicPassword
        self.apiKeyName = apiKeyName
        self.apiKeyValue = apiKeyValue
        self.apiKeyLocation = apiKeyLocation
        self.oauth2Token = oauth2Token
        self.oauth2HeaderPrefix = oauth2HeaderPrefix
    }

    /// The same auth with every secret blanked. Used for history and export so
    /// tokens never reach disk in a shareable file.
    public func withoutSecrets() -> AuthSpec {
        var copy = self
        copy.bearerToken = ""
        copy.basicPassword = ""
        copy.apiKeyValue = ""
        copy.oauth2Token = ""
        return copy
    }

    public var hasSecret: Bool {
        !bearerToken.isEmpty || !basicPassword.isEmpty || !apiKeyValue.isEmpty || !oauth2Token.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case type, bearerToken, basicUsername, basicPassword
        case apiKeyName, apiKeyValue, apiKeyLocation, oauth2Token, oauth2HeaderPrefix
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(AuthType.self, forKey: .type) ?? .none
        bearerToken = try c.decodeIfPresent(String.self, forKey: .bearerToken) ?? ""
        basicUsername = try c.decodeIfPresent(String.self, forKey: .basicUsername) ?? ""
        basicPassword = try c.decodeIfPresent(String.self, forKey: .basicPassword) ?? ""
        apiKeyName = try c.decodeIfPresent(String.self, forKey: .apiKeyName) ?? ""
        apiKeyValue = try c.decodeIfPresent(String.self, forKey: .apiKeyValue) ?? ""
        apiKeyLocation = try c.decodeIfPresent(ApiKeyLocation.self, forKey: .apiKeyLocation) ?? .header
        oauth2Token = try c.decodeIfPresent(String.self, forKey: .oauth2Token) ?? ""
        oauth2HeaderPrefix = try c.decodeIfPresent(String.self, forKey: .oauth2HeaderPrefix) ?? "Bearer"
    }
}

// MARK: - Per-request settings

public struct RequestSettings: Codable, Sendable, Equatable {
    /// Seconds. 0 means "no client-side deadline" (capped at `maxTimeout`).
    public var timeoutSeconds: Double
    public var followRedirects: Bool
    public var maxRedirects: Int
    /// False skips TLS chain and hostname validation. Off-by-default, and the
    /// UI marks it, because it turns MITM protection off for that request.
    public var validateTLS: Bool
    public var sendCookies: Bool
    /// Response bytes kept in memory. Larger responses are truncated and
    /// flagged rather than growing the heap without bound.
    public var maxResponseBytes: Int

    public static let maxTimeout: Double = 600
    public static let defaultMaxResponseBytes = 32 * 1024 * 1024

    public init(
        timeoutSeconds: Double = 60,
        followRedirects: Bool = true,
        maxRedirects: Int = 10,
        validateTLS: Bool = true,
        sendCookies: Bool = true,
        maxResponseBytes: Int = RequestSettings.defaultMaxResponseBytes
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.followRedirects = followRedirects
        self.maxRedirects = maxRedirects
        self.validateTLS = validateTLS
        self.sendCookies = sendCookies
        self.maxResponseBytes = maxResponseBytes
    }

    /// Timeout clamped into a sane range for the transport.
    public var effectiveTimeout: Double {
        if timeoutSeconds <= 0 { return Self.maxTimeout }
        return min(timeoutSeconds, Self.maxTimeout)
    }

    public var effectiveMaxRedirects: Int { max(0, min(maxRedirects, 50)) }

    public var effectiveMaxResponseBytes: Int {
        maxResponseBytes > 0 ? maxResponseBytes : Self.defaultMaxResponseBytes
    }

    private enum CodingKeys: String, CodingKey {
        case timeoutSeconds, followRedirects, maxRedirects, validateTLS, sendCookies, maxResponseBytes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 60
        followRedirects = try c.decodeIfPresent(Bool.self, forKey: .followRedirects) ?? true
        maxRedirects = try c.decodeIfPresent(Int.self, forKey: .maxRedirects) ?? 10
        validateTLS = try c.decodeIfPresent(Bool.self, forKey: .validateTLS) ?? true
        sendCookies = try c.decodeIfPresent(Bool.self, forKey: .sendCookies) ?? true
        maxResponseBytes = try c.decodeIfPresent(Int.self, forKey: .maxResponseBytes)
            ?? Self.defaultMaxResponseBytes
    }
}

// MARK: - Saved request

public struct SavedRequest: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var note: String
    public var method: HttpMethod
    public var url: String
    public var headers: [ApiKeyValue]
    public var queryParams: [ApiKeyValue]
    /// Values for `:name` placeholders in the URL path.
    public var pathVariables: [ApiKeyValue]
    public var body: RequestBodySpec
    public var auth: AuthSpec
    public var settings: RequestSettings
    public var assertions: [ApiAssertion]
    public var createdAt: Double
    public var modifiedAt: Double

    public init(
        id: String = UUID().uuidString,
        name: String = "Untitled Request",
        note: String = "",
        method: HttpMethod = .get,
        url: String = "",
        headers: [ApiKeyValue] = [],
        queryParams: [ApiKeyValue] = [],
        pathVariables: [ApiKeyValue] = [],
        body: RequestBodySpec = RequestBodySpec(),
        auth: AuthSpec = AuthSpec(),
        settings: RequestSettings = RequestSettings(),
        assertions: [ApiAssertion] = [],
        createdAt: Double = Date().timeIntervalSince1970,
        modifiedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.method = method
        self.url = url
        self.headers = headers
        self.queryParams = queryParams
        self.pathVariables = pathVariables
        self.body = body
        self.auth = auth
        self.settings = settings
        self.assertions = assertions
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// A copy safe to persist in history or hand to an export file: auth
    /// secrets blanked and credential-bearing headers masked. The URL is left
    /// intact — it is what makes history navigable.
    public func withoutSecrets() -> SavedRequest {
        var copy = self
        copy.auth = auth.withoutSecrets()
        copy.headers = headers.map { header in
            guard SavedRequest.secretHeaderNames.contains(header.key.lowercased()) else { return header }
            var masked = header
            masked.value = masked.value.isEmpty ? "" : "•••"
            return masked
        }
        return copy
    }

    static let secretHeaderNames: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie",
        "x-api-key", "api-key", "apikey", "x-auth-token", "x-access-token",
        "x-csrf-token", "x-session-token",
    ]

    private enum CodingKeys: String, CodingKey {
        case id, name, note, method, url, headers, queryParams, pathVariables
        case body, auth, settings, assertions, createdAt, modifiedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date().timeIntervalSince1970
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Request"
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        method = try c.decodeIfPresent(HttpMethod.self, forKey: .method) ?? .get
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        headers = try c.decodeIfPresent([ApiKeyValue].self, forKey: .headers) ?? []
        queryParams = try c.decodeIfPresent([ApiKeyValue].self, forKey: .queryParams) ?? []
        pathVariables = try c.decodeIfPresent([ApiKeyValue].self, forKey: .pathVariables) ?? []
        body = try c.decodeIfPresent(RequestBodySpec.self, forKey: .body) ?? RequestBodySpec()
        auth = try c.decodeIfPresent(AuthSpec.self, forKey: .auth) ?? AuthSpec()
        settings = try c.decodeIfPresent(RequestSettings.self, forKey: .settings) ?? RequestSettings()
        assertions = try c.decodeIfPresent([ApiAssertion].self, forKey: .assertions) ?? []
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? now
        modifiedAt = try c.decodeIfPresent(Double.self, forKey: .modifiedAt) ?? now
    }
}

// MARK: - Collection tree

public struct ApiFolder: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var note: String
    public var items: [ApiItem]

    public init(
        id: String = UUID().uuidString,
        name: String = "New Folder",
        note: String = "",
        items: [ApiItem] = []
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case id, name, note, items }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "New Folder"
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        items = try c.decodeIfPresent([ApiItem].self, forKey: .items) ?? []
    }
}

/// One node of a collection: a request, or a folder of further nodes. Encoded
/// with an explicit `kind` tag so the on-disk shape stays readable and stable.
public enum ApiItem: Codable, Sendable, Equatable, Identifiable {
    case request(SavedRequest)
    case folder(ApiFolder)

    public var id: String {
        switch self {
        case .request(let request): return request.id
        case .folder(let folder): return folder.id
        }
    }

    public var name: String {
        switch self {
        case .request(let request): return request.name
        case .folder(let folder): return folder.name
        }
    }

    public var asRequest: SavedRequest? {
        if case .request(let request) = self { return request }
        return nil
    }

    public var asFolder: ApiFolder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }

    private enum CodingKeys: String, CodingKey { case kind, request, folder }
    private enum Kind: String, Codable { case request, folder }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decodeIfPresent(Kind.self, forKey: .kind) {
        case .folder:
            self = .folder(try c.decode(ApiFolder.self, forKey: .folder))
        case .request:
            self = .request(try c.decode(SavedRequest.self, forKey: .request))
        case nil:
            // Tolerate a tag-less node by sniffing which payload is present.
            if let folder = try c.decodeIfPresent(ApiFolder.self, forKey: .folder) {
                self = .folder(folder)
            } else {
                self = .request(try c.decode(SavedRequest.self, forKey: .request))
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .request(let request):
            try c.encode(Kind.request, forKey: .kind)
            try c.encode(request, forKey: .request)
        case .folder(let folder):
            try c.encode(Kind.folder, forKey: .kind)
            try c.encode(folder, forKey: .folder)
        }
    }
}

public struct ApiCollection: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var note: String
    public var items: [ApiItem]
    /// Collection-scoped variables. Beat the environment, lose to request-local.
    public var variables: [ApiKeyValue]
    /// Applied to requests whose own auth is `.none`, like Postman's
    /// collection-level auth with per-request "Inherit".
    public var auth: AuthSpec
    public var createdAt: Double

    public init(
        id: String = UUID().uuidString,
        name: String = "New Collection",
        note: String = "",
        items: [ApiItem] = [],
        variables: [ApiKeyValue] = [],
        auth: AuthSpec = AuthSpec(),
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.items = items
        self.variables = variables
        self.auth = auth
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, items, variables, auth, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "New Collection"
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        items = try c.decodeIfPresent([ApiItem].self, forKey: .items) ?? []
        variables = try c.decodeIfPresent([ApiKeyValue].self, forKey: .variables) ?? []
        auth = try c.decodeIfPresent(AuthSpec.self, forKey: .auth) ?? AuthSpec()
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt)
            ?? Date().timeIntervalSince1970
    }
}

// MARK: - Environment

public struct ApiEnvironment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var variables: [ApiKeyValue]

    public init(
        id: String = UUID().uuidString,
        name: String = "New Environment",
        variables: [ApiKeyValue] = []
    ) {
        self.id = id
        self.name = name
        self.variables = variables
    }

    public var variableMap: [String: String] { variables.activeMap }

    private enum CodingKeys: String, CodingKey { case id, name, variables }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "New Environment"
        variables = try c.decodeIfPresent([ApiKeyValue].self, forKey: .variables) ?? []
    }
}

// MARK: - History

public struct ApiHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var method: HttpMethod
    /// The fully resolved URL that went on the wire.
    public var url: String
    public var statusCode: Int?
    /// Set when the send failed before a response arrived.
    public var errorText: String?
    public var elapsedMs: Double?
    public var responseSize: Int?
    public var timestamp: Double
    /// Secret-free copy — see `SavedRequest.withoutSecrets()`.
    public var request: SavedRequest

    public init(
        id: String = UUID().uuidString,
        method: HttpMethod,
        url: String,
        statusCode: Int? = nil,
        errorText: String? = nil,
        elapsedMs: Double? = nil,
        responseSize: Int? = nil,
        timestamp: Double = Date().timeIntervalSince1970,
        request: SavedRequest
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.errorText = errorText
        self.elapsedMs = elapsedMs
        self.responseSize = responseSize
        self.timestamp = timestamp
        self.request = request.withoutSecrets()
    }

    private enum CodingKeys: String, CodingKey {
        case id, method, url, statusCode, errorText, elapsedMs, responseSize, timestamp, request
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        method = try c.decodeIfPresent(HttpMethod.self, forKey: .method) ?? .get
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        statusCode = try c.decodeIfPresent(Int.self, forKey: .statusCode)
        errorText = try c.decodeIfPresent(String.self, forKey: .errorText)
        elapsedMs = try c.decodeIfPresent(Double.self, forKey: .elapsedMs)
        responseSize = try c.decodeIfPresent(Int.self, forKey: .responseSize)
        timestamp = try c.decodeIfPresent(Double.self, forKey: .timestamp)
            ?? Date().timeIntervalSince1970
        request = try c.decodeIfPresent(SavedRequest.self, forKey: .request) ?? SavedRequest()
    }
}

// MARK: - Top-level persisted shape

public struct ApiClientData: Codable, Sendable, Equatable {
    public var collections: [ApiCollection]
    public var environments: [ApiEnvironment]
    public var activeEnvironmentId: String?
    /// Variables available everywhere, below environment in precedence.
    public var globals: [ApiKeyValue]
    public var history: [ApiHistoryEntry]

    public static let historyLimit = 200

    public init(
        collections: [ApiCollection] = [],
        environments: [ApiEnvironment] = [],
        activeEnvironmentId: String? = nil,
        globals: [ApiKeyValue] = [],
        history: [ApiHistoryEntry] = []
    ) {
        self.collections = collections
        self.environments = environments
        self.activeEnvironmentId = activeEnvironmentId
        self.globals = globals
        self.history = history
    }

    public var activeEnvironment: ApiEnvironment? {
        guard let id = activeEnvironmentId else { return nil }
        return environments.first { $0.id == id }
    }

    /// Variable scope for a request run from `collection` (nil for an unsaved
    /// scratch request, which sees globals + environment only).
    public func scope(for collection: ApiCollection?) -> VariableScope {
        VariableScope(
            globals: globals.activeMap,
            environment: activeEnvironment?.variableMap ?? [:],
            collection: collection?.variables.activeMap ?? [:]
        )
    }

    public mutating func addToHistory(_ entry: ApiHistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit {
            history = Array(history.prefix(Self.historyLimit))
        }
    }

    public mutating func clearHistory() { history.removeAll() }

    /// The collection containing `requestId`, if any.
    public func collection(containing requestId: String) -> ApiCollection? {
        collections.first { ApiCollectionTree.find(requestId, in: $0.items) != nil }
    }

    private enum CodingKeys: String, CodingKey {
        case collections, environments, activeEnvironmentId, globals, history
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collections = try c.decodeIfPresent([ApiCollection].self, forKey: .collections) ?? []
        environments = try c.decodeIfPresent([ApiEnvironment].self, forKey: .environments) ?? []
        activeEnvironmentId = try c.decodeIfPresent(String.self, forKey: .activeEnvironmentId)
        globals = try c.decodeIfPresent([ApiKeyValue].self, forKey: .globals) ?? []
        history = try c.decodeIfPresent([ApiHistoryEntry].self, forKey: .history) ?? []
    }
}
