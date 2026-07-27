import Foundation

// MARK: - HTTP Method

public enum HttpMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"

    public var id: String { rawValue }
}

// MARK: - Key-value pair (headers, params, form fields)

public struct ApiKeyValue: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var key: String
    public var value: String
    public var enabled: Bool

    public init(id: String = UUID().uuidString, key: String, value: String, enabled: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.enabled = enabled
    }
}

// MARK: - Request body

public enum BodyType: String, Codable, Sendable, CaseIterable {
    case none
    case json
    case formUrlEncoded
    case raw
}

public struct RequestBodySpec: Codable, Sendable, Equatable {
    public var type: BodyType
    public var jsonText: String
    public var rawText: String
    public var rawContentType: String
    public var formFields: [ApiKeyValue]

    public init(
        type: BodyType = .none,
        jsonText: String = "",
        rawText: String = "",
        rawContentType: String = "text/plain",
        formFields: [ApiKeyValue] = []
    ) {
        self.type = type
        self.jsonText = jsonText
        self.rawText = rawText
        self.rawContentType = rawContentType
        self.formFields = formFields
    }
}

// MARK: - Auth

public enum AuthType: String, Codable, Sendable, CaseIterable {
    case none
    case bearer
    case basic
    case apiKey
}

public struct AuthSpec: Codable, Sendable, Equatable {
    public var type: AuthType
    public var bearerToken: String
    public var basicUsername: String
    public var basicPassword: String
    public var apiKeyName: String
    public var apiKeyValue: String

    public init(
        type: AuthType = .none,
        bearerToken: String = "",
        basicUsername: String = "",
        basicPassword: String = "",
        apiKeyName: String = "",
        apiKeyValue: String = ""
    ) {
        self.type = type
        self.bearerToken = bearerToken
        self.basicUsername = basicUsername
        self.basicPassword = basicPassword
        self.apiKeyName = apiKeyName
        self.apiKeyValue = apiKeyValue
    }
}

// MARK: - Saved request

public struct SavedRequest: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var method: HttpMethod
    public var url: String
    public var headers: [ApiKeyValue]
    public var queryParams: [ApiKeyValue]
    public var body: RequestBodySpec
    public var auth: AuthSpec
    public var createdAt: Double
    public var modifiedAt: Double

    public init(
        id: String = UUID().uuidString,
        name: String = "Untitled Request",
        method: HttpMethod = .get,
        url: String = "",
        headers: [ApiKeyValue] = [],
        queryParams: [ApiKeyValue] = [],
        body: RequestBodySpec = RequestBodySpec(),
        auth: AuthSpec = AuthSpec(),
        createdAt: Double = Date().timeIntervalSince1970,
        modifiedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.method = method
        self.url = url
        self.headers = headers
        self.queryParams = queryParams
        self.body = body
        self.auth = auth
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

// MARK: - Collection

public struct ApiCollection: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var requests: [SavedRequest]
    public var createdAt: Double

    public init(
        id: String = UUID().uuidString,
        name: String = "New Collection",
        requests: [SavedRequest] = [],
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name
        self.requests = requests
        self.createdAt = createdAt
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

    public var variableMap: [String: String] {
        var map: [String: String] = [:]
        for v in variables where v.enabled {
            map[v.key] = v.value
        }
        return map
    }
}

// MARK: - History entry

public struct ApiHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var method: HttpMethod
    public var url: String
    public var statusCode: Int?
    public var timestamp: Double
    public var request: SavedRequest

    public init(
        id: String = UUID().uuidString,
        method: HttpMethod,
        url: String,
        statusCode: Int? = nil,
        timestamp: Double = Date().timeIntervalSince1970,
        request: SavedRequest
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.timestamp = timestamp
        self.request = request
    }
}

// MARK: - Response

public struct ApiResponse: Sendable {
    public let statusCode: Int
    public let statusText: String
    public let headers: [(key: String, value: String)]
    public let body: Data
    public let elapsedMs: Double
    public let size: Int

    public init(
        statusCode: Int, statusText: String,
        headers: [(key: String, value: String)],
        body: Data, elapsedMs: Double, size: Int
    ) {
        self.statusCode = statusCode
        self.statusText = statusText
        self.headers = headers
        self.body = body
        self.elapsedMs = elapsedMs
        self.size = size
    }

    public var bodyString: String? { String(data: body, encoding: .utf8) }

    public var isJSON: Bool {
        headers.contains { $0.key.lowercased() == "content-type" && $0.value.lowercased().contains("json") }
    }

    public var prettyJSON: String? {
        guard let obj = try? JSONSerialization.jsonObject(with: body),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else { return nil }
        return str
    }

    public static func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return HTTPURLResponse.localizedString(forStatusCode: code).capitalized
        }
    }
}

// MARK: - Top-level persistence shape

public struct ApiClientData: Codable, Sendable, Equatable {
    public var collections: [ApiCollection]
    public var environments: [ApiEnvironment]
    public var activeEnvironmentId: String?
    public var history: [ApiHistoryEntry]
    public static let historyLimit = 100

    public init(
        collections: [ApiCollection] = [],
        environments: [ApiEnvironment] = [],
        activeEnvironmentId: String? = nil,
        history: [ApiHistoryEntry] = []
    ) {
        self.collections = collections
        self.environments = environments
        self.activeEnvironmentId = activeEnvironmentId
        self.history = history
    }

    public var activeEnvironment: ApiEnvironment? {
        guard let id = activeEnvironmentId else { return nil }
        return environments.first { $0.id == id }
    }

    public mutating func addToHistory(_ entry: ApiHistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit {
            history = Array(history.prefix(Self.historyLimit))
        }
    }

    public mutating func clearHistory() { history.removeAll() }
}

// MARK: - Export/import shape

public struct ExportedCollection: Codable, Sendable {
    public var name: String
    public var requests: [SavedRequest]

    public init(name: String, requests: [SavedRequest]) {
        self.name = name
        self.requests = requests
    }
}
