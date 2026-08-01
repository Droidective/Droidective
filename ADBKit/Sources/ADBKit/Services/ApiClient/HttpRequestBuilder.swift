import Foundation

// MARK: - File access seam

/// Reads the files a multipart or binary body references. Injected so body
/// building stays testable without touching the disk.
public protocol ApiFileReading: Sendable {
    func data(at path: String) throws -> Data
    func fileName(at path: String) -> String
}

public struct DiskFileReader: ApiFileReading {
    public init() {}

    public func data(at path: String) throws -> Data {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ApiRequestError.fileUnreadable(
                path: path, reason: (error as NSError).localizedDescription
            )
        }
    }

    public func fileName(at path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

/// In-memory stand-in for tests.
public struct StubFileReader: ApiFileReading {
    public var files: [String: Data]

    public init(files: [String: Data] = [:]) { self.files = files }

    public func data(at path: String) throws -> Data {
        guard let data = files[path] else {
            throw ApiRequestError.fileUnreadable(path: path, reason: "No such file")
        }
        return data
    }

    public func fileName(at path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

// MARK: - Errors

public enum ApiRequestError: Error, LocalizedError, Sendable, Equatable {
    case emptyURL
    case invalidURL(String)
    case unsupportedScheme(String)
    case fileUnreadable(path: String, reason: String)
    case missingFilePath(field: String)

    public var errorDescription: String? {
        switch self {
        case .emptyURL:
            return "Enter a URL first."
        case .invalidURL(let url):
            return "\"\(url)\" isn't a valid URL. Check for spaces or missing characters."
        case .unsupportedScheme(let scheme):
            return "\(scheme):// isn't supported — use http or https."
        case .fileUnreadable(let path, let reason):
            return "Can't read \(path): \(reason)"
        case .missingFilePath(let field):
            return "Form field \"\(field)\" is set to File but has no file selected."
        }
    }
}

// MARK: - Prepared request

/// A fully resolved request, one step short of the transport. Every decision —
/// scheme, encoding, auth, body bytes — is already made here, which is what
/// makes the whole pipeline testable without a network.
public struct PreparedRequest: Sendable, Equatable {
    public var url: String
    public var method: HttpMethod
    /// Wire order; duplicates preserved.
    public var headers: [(key: String, value: String)]
    public var body: Data?
    public var settings: RequestSettings
    /// Non-fatal notes for the UI (body on a GET, invalid JSON, and so on).
    public var warnings: [String]

    public init(
        url: String,
        method: HttpMethod,
        headers: [(key: String, value: String)],
        body: Data? = nil,
        settings: RequestSettings = RequestSettings(),
        warnings: [String] = []
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.settings = settings
        self.warnings = warnings
    }

    public func headerValue(_ name: String) -> String? {
        let wanted = name.lowercased()
        return headers.first { $0.key.lowercased() == wanted }?.value
    }

    public var bodyText: String? {
        guard let body else { return nil }
        return String(data: body, encoding: .utf8)
    }

    public static func == (lhs: PreparedRequest, rhs: PreparedRequest) -> Bool {
        lhs.url == rhs.url
            && lhs.method == rhs.method
            && lhs.body == rhs.body
            && lhs.settings == rhs.settings
            && lhs.headers.map { [$0.key, $0.value] } == rhs.headers.map { [$0.key, $0.value] }
    }
}

// MARK: - Builder

public enum HttpRequestBuilder: Sendable {

    /// Characters left literal when encoding a query component. RFC 3986
    /// unreserved only — encoding more than strictly necessary is always safe,
    /// under-encoding is what breaks values containing `&`, `=` or `+`.
    static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Turns a request into wire-ready form.
    ///
    /// - Parameters:
    ///   - request: Already variable-resolved (see `ApiVariables.resolveRequest`).
    ///   - files: Reader for multipart/binary file parts.
    ///   - boundary: Multipart boundary; pass a fixed one in tests.
    public static func prepare(
        _ request: SavedRequest,
        files: any ApiFileReading = DiskFileReader(),
        boundary: String = "Droidective-\(UUID().uuidString)"
    ) throws -> PreparedRequest {
        var warnings: [String] = []
        var extraQuery: [(key: String, value: String)] = []
        var headers: [(key: String, value: String)] = []

        // Headers the user typed, sanitised against header injection.
        for pair in request.headers.activePairs {
            guard let name = sanitizedHeaderName(pair.key) else {
                warnings.append("Skipped header \"\(pair.key)\" — a header name can't contain spaces, colons or newlines.")
                continue
            }
            let value = sanitizedHeaderValue(pair.value)
            if value != pair.value {
                warnings.append("Stripped a line break from the \(name) header.")
            }
            headers.append((key: name, value: value))
        }

        // Auth, which wins over a hand-typed Authorization header.
        let auth = applyAuth(request.auth, to: &headers, query: &extraQuery, warnings: &warnings)
        if auth, request.settings.validateTLS == false {
            warnings.append("TLS verification is off for this request — credentials would travel unverified.")
        }

        let body = try buildBody(
            request, files: files, boundary: boundary, headers: &headers, warnings: &warnings
        )
        if body != nil, !request.method.conventionallyHasBody {
            warnings.append("\(request.method.rawValue) requests don't normally carry a body; sending it anyway.")
        }

        let url = try buildURL(request, extraQuery: extraQuery, warnings: &warnings)

        if !request.settings.validateTLS {
            warnings.append("Certificate validation is disabled for this request.")
        }

        return PreparedRequest(
            url: url,
            method: request.method,
            headers: headers,
            body: body,
            settings: request.settings,
            warnings: warnings
        )
    }

    // MARK: - URL

    static func buildURL(
        _ request: SavedRequest,
        extraQuery: [(key: String, value: String)],
        warnings: inout [String]
    ) throws -> String {
        // Only the first line matters — pasting a multi-line curl into the URL
        // field is common enough that silently using line one beats erroring.
        var raw = request.url
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !raw.isEmpty else { throw ApiRequestError.emptyURL }

        raw = applySchemeIfMissing(to: raw)

        let scheme = raw.components(separatedBy: "://").first?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            throw ApiRequestError.unsupportedScheme(scheme)
        }

        var (base, existingQuery, fragment) = split(raw)
        base = substitutePathVariables(base, with: request.pathVariables, warnings: &warnings)

        let listQuery = request.queryParams.activePairs + extraQuery
        var query = existingQuery
        if !listQuery.isEmpty {
            let encoded = listQuery
                .map { "\(encodeQueryComponent($0.key))=\(encodeQueryComponent($0.value))" }
                .joined(separator: "&")
            query = query.isEmpty ? encoded : query + "&" + encoded
        }

        var assembled = base
        if !query.isEmpty { assembled += "?" + query }
        if !fragment.isEmpty { assembled += "#" + fragment }

        if let url = URL(string: assembled) { return url.absoluteString }

        // One repair pass over the path and query only. Apple's `URL(string:)`
        // escapes these itself; corelibs-foundation does not, so the same paste
        // has to work on both. The authority is deliberately left alone — a
        // space in the host is an error, not something to paper over.
        let repaired = percentEncodeAfterAuthority(assembled)
        if repaired != assembled, let url = URL(string: repaired) {
            warnings.append("Escaped characters in the URL that aren't legal unencoded.")
            return url.absoluteString
        }
        throw ApiRequestError.invalidURL(assembled)
    }

    /// Bare hosts get a scheme. Loopback, `.local` and RFC 1918 addresses get
    /// `http` — a dev server on your Mac or an emulator's host alias almost
    /// never speaks TLS, and defaulting those to https fails confusingly.
    static func applySchemeIfMissing(to raw: String) -> String {
        if raw.contains("://") { return raw }
        var candidate = raw
        if candidate.hasPrefix("//") { candidate.removeFirst(2) }
        let host = candidate
            .components(separatedBy: "/").first?
            .components(separatedBy: "?").first?
            .components(separatedBy: "@").last?
            .components(separatedBy: ":").first?
            .lowercased() ?? ""
        return (isLocalHost(host) ? "http://" : "https://") + candidate
    }

    static func isLocalHost(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if bare == "localhost" || bare.hasSuffix(".localhost") { return true }
        if bare == "::1" || bare == "0.0.0.0" { return true }
        if bare.hasSuffix(".local") || bare.hasSuffix(".internal") || bare.hasSuffix(".test") {
            return true
        }
        let octets = bare.components(separatedBy: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (192, 168), (169, 254):
            return true
        case (172, let second) where (16...31).contains(second):
            return true
        default:
            return false
        }
    }

    /// Splits into everything-before-`?`, the query, and the fragment. Hand-rolled
    /// because `URLComponents` refuses URLs the user is still typing.
    static func split(_ url: String) -> (base: String, query: String, fragment: String) {
        var rest = url
        var fragment = ""
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...])
            rest = String(rest[rest.startIndex..<hash])
        }
        var query = ""
        if let mark = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: mark)...])
            rest = String(rest[rest.startIndex..<mark])
        }
        return (base: rest, query: query, fragment: fragment)
    }

    /// Replaces `:name` segments in the path. The host is left alone so a port
    /// (`localhost:3000`) is never mistaken for a variable.
    static func substitutePathVariables(
        _ base: String, with variables: [ApiKeyValue], warnings: inout [String]
    ) -> String {
        guard base.contains(":") else { return base }
        let map = variables.activeMap
        guard let schemeEnd = base.range(of: "://") else { return base }
        let afterScheme = base[schemeEnd.upperBound...]
        guard let firstSlash = afterScheme.firstIndex(of: "/") else { return base }

        let prefix = String(base[base.startIndex..<firstSlash])
        let path = String(base[firstSlash...])
        var out = ""
        var unresolved: [String] = []

        for (index, segment) in path.components(separatedBy: "/").enumerated() {
            if index > 0 { out += "/" }
            guard segment.hasPrefix(":"), segment.count > 1 else {
                out += segment
                continue
            }
            let name = String(segment.dropFirst())
            if let value = map[name], !value.isEmpty {
                out += encodePathComponent(value)
            } else {
                unresolved.append(name)
                out += segment
            }
        }
        if !unresolved.isEmpty {
            warnings.append(
                "No value for path variable\(unresolved.count > 1 ? "s" : "") "
                    + unresolved.map { ":\($0)" }.joined(separator: ", ")
            )
        }
        return prefix + out
    }

    static func encodeQueryComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func encodePathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Escapes the path/query/fragment, keeping existing `%XX` sequences intact
    /// so an already-encoded URL isn't double-encoded. `scheme://authority` is
    /// returned untouched.
    static func percentEncodeAfterAuthority(_ url: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.formUnion(CharacterSet(charactersIn: "#[]%"))
        guard let schemeEnd = url.range(of: "://") else {
            return url.addingPercentEncoding(withAllowedCharacters: allowed) ?? url
        }
        let afterScheme = url[schemeEnd.upperBound...]
        guard let firstSlash = afterScheme.firstIndex(of: "/") else { return url }
        let authority = String(url[url.startIndex..<firstSlash])
        let rest = String(url[firstSlash...])
        return authority + (rest.addingPercentEncoding(withAllowedCharacters: allowed) ?? rest)
    }

    // MARK: - Headers

    /// nil for a name HTTP can't carry. Rejecting these is what stops a
    /// variable expanding to `X: y\r\nInjected: z` from forging headers.
    static func sanitizedHeaderName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let illegal = CharacterSet(charactersIn: ":\r\n\t ()<>@,;\\\"/[]?={}")
        guard trimmed.rangeOfCharacter(from: illegal) == nil else { return nil }
        return trimmed
    }

    static func sanitizedHeaderValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func setHeader(
        _ name: String, _ value: String, in headers: inout [(key: String, value: String)]
    ) {
        let wanted = name.lowercased()
        headers.removeAll { $0.key.lowercased() == wanted }
        headers.append((key: name, value: value))
    }

    static func hasHeader(_ name: String, in headers: [(key: String, value: String)]) -> Bool {
        let wanted = name.lowercased()
        return headers.contains { $0.key.lowercased() == wanted }
    }

    // MARK: - Auth

    /// Returns whether a credential was attached.
    static func applyAuth(
        _ auth: AuthSpec,
        to headers: inout [(key: String, value: String)],
        query: inout [(key: String, value: String)],
        warnings: inout [String]
    ) -> Bool {
        func noteOverride() {
            if hasHeader("Authorization", in: headers) {
                warnings.append("The Auth tab replaced your manual Authorization header.")
            }
        }

        switch auth.type {
        case .none:
            return false

        case .bearer:
            let token = auth.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                warnings.append("Bearer auth is selected but the token is empty.")
                return false
            }
            noteOverride()
            setHeader("Authorization", "Bearer \(token)", in: &headers)
            return true

        case .basic:
            guard !auth.basicUsername.isEmpty || !auth.basicPassword.isEmpty else {
                warnings.append("Basic auth is selected but username and password are both empty.")
                return false
            }
            noteOverride()
            let credential = Data("\(auth.basicUsername):\(auth.basicPassword)".utf8)
                .base64EncodedString()
            setHeader("Authorization", "Basic \(credential)", in: &headers)
            return true

        case .apiKey:
            let name = auth.apiKeyName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                warnings.append("API-key auth is selected but the key name is empty.")
                return false
            }
            switch auth.apiKeyLocation {
            case .header:
                guard let header = sanitizedHeaderName(name) else {
                    warnings.append("\"\(name)\" isn't a usable header name.")
                    return false
                }
                setHeader(header, sanitizedHeaderValue(auth.apiKeyValue), in: &headers)
            case .query:
                query.append((key: name, value: auth.apiKeyValue))
            }
            return true

        case .oauth2:
            let token = auth.oauth2Token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                warnings.append("OAuth 2 is selected but no access token is set.")
                return false
            }
            noteOverride()
            let prefix = auth.oauth2HeaderPrefix.trimmingCharacters(in: .whitespaces)
            setHeader(
                "Authorization", prefix.isEmpty ? token : "\(prefix) \(token)", in: &headers
            )
            return true
        }
    }

    // MARK: - Body

    static func buildBody(
        _ request: SavedRequest,
        files: any ApiFileReading,
        boundary: String,
        headers: inout [(key: String, value: String)],
        warnings: inout [String]
    ) throws -> Data? {
        let spec = request.body
        guard spec.type != .none else { return nil }

        func defaultContentType(_ value: String) {
            guard !hasHeader("Content-Type", in: headers) else { return }
            headers.append((key: "Content-Type", value: value))
        }

        switch spec.type {
        case .none:
            return nil

        case .json:
            guard !spec.jsonText.isEmpty else { return nil }
            if !JSONFormatter.isValidJSON(spec.jsonText) {
                warnings.append("The JSON body isn't valid JSON — sending it as typed.")
            }
            defaultContentType("application/json")
            return Data(spec.jsonText.utf8)

        case .raw:
            guard !spec.rawText.isEmpty else { return nil }
            defaultContentType(spec.impliedContentType ?? "text/plain")
            return Data(spec.rawText.utf8)

        case .formUrlEncoded:
            let pairs = spec.formFields.activePairs
            guard !pairs.isEmpty else { return nil }
            defaultContentType("application/x-www-form-urlencoded")
            let encoded = pairs
                .map { "\(encodeQueryComponent($0.key))=\(encodeQueryComponent($0.value))" }
                .joined(separator: "&")
            return Data(encoded.utf8)

        case .multipart:
            let fields = spec.multipartFields.filter { $0.enabled && !$0.key.isEmpty }
            guard !fields.isEmpty else { return nil }
            setHeader("Content-Type", "multipart/form-data; boundary=\(boundary)", in: &headers)
            return try multipartBody(fields, boundary: boundary, files: files)

        case .graphql:
            guard !spec.graphqlQuery.isEmpty || !spec.graphqlVariables.isEmpty else { return nil }
            defaultContentType("application/json")
            return graphqlBody(spec, warnings: &warnings)

        case .binary:
            let path = spec.binaryFilePath.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return nil }
            let data = try files.data(at: path)
            defaultContentType(contentType(forFileName: files.fileName(at: path)))
            return data
        }
    }

    static func multipartBody(
        _ fields: [ApiFormField], boundary: String, files: any ApiFileReading
    ) throws -> Data {
        var body = Data()
        let newline = Data("\r\n".utf8)

        for field in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            let name = quoteEscaped(field.key)
            switch field.kind {
            case .text:
                body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n".utf8))
                if !field.contentType.isEmpty {
                    body.append(Data("Content-Type: \(field.contentType)\r\n".utf8))
                }
                body.append(newline)
                body.append(Data(field.value.utf8))
            case .file:
                let path = field.value.trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty else { throw ApiRequestError.missingFilePath(field: field.key) }
                let data = try files.data(at: path)
                let filename = quoteEscaped(files.fileName(at: path))
                body.append(
                    Data(
                        "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8
                    )
                )
                let type = field.contentType.isEmpty
                    ? contentType(forFileName: filename)
                    : field.contentType
                body.append(Data("Content-Type: \(type)\r\n".utf8))
                body.append(newline)
                body.append(data)
            }
            body.append(newline)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    static func graphqlBody(_ spec: RequestBodySpec, warnings: inout [String]) -> Data {
        var payload: [String: Any] = ["query": spec.graphqlQuery]
        let variables = spec.graphqlVariables.trimmingCharacters(in: .whitespacesAndNewlines)
        if !variables.isEmpty {
            if let parsed = try? JSONSerialization.jsonObject(with: Data(variables.utf8)),
               let object = parsed as? [String: Any] {
                payload["variables"] = object
            } else {
                warnings.append("GraphQL variables aren't a valid JSON object — sending without them.")
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload) { return data }
        // Only reachable if the query holds unencodable scalars; fall back to a
        // hand-built envelope rather than dropping the body.
        let escaped = spec.graphqlQuery
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return Data("{\"query\":\"\(escaped)\"}".utf8)
    }

    static func quoteEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\"", with: "%22")
    }

    static func contentType(forFileName name: String) -> String {
        let extension_ = URL(fileURLWithPath: name).pathExtension.lowercased()
        switch extension_ {
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "txt", "log": return "text/plain"
        case "csv": return "text/csv"
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "zip": return "application/zip"
        case "gz", "tgz": return "application/gzip"
        case "apk": return "application/vnd.android.package-archive"
        case "aab": return "application/octet-stream"
        case "ipa": return "application/octet-stream"
        default: return "application/octet-stream"
        }
    }
}
