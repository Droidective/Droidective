import Foundation

// MARK: - Results

public enum PostmanFileKind: Sendable, Equatable {
    /// Collection Format v2 / v2.1 — what Postman exports today.
    case collectionV2
    /// Collection Format v1 — older exports still in circulation.
    case collectionV1
    case environment
    /// A whole Droidective workspace written by `exportWorkspace`.
    case workspace
    case unknown
}

public struct PostmanImport: Sendable {
    public var collections: [ApiCollection]
    public var environments: [ApiEnvironment]
    /// Everything the file carried that this app can't represent — scripts,
    /// unsupported auth schemes, saved example responses.
    public var warnings: [String]

    public init(
        collections: [ApiCollection] = [],
        environments: [ApiEnvironment] = [],
        warnings: [String] = []
    ) {
        self.collections = collections
        self.environments = environments
        self.warnings = warnings
    }

    public var isEmpty: Bool { collections.isEmpty && environments.isEmpty }

    public var summary: String {
        var parts: [String] = []
        let requests = collections.reduce(0) { $0 + ApiCollectionTree.requestCount(in: $1.items) }
        if !collections.isEmpty {
            parts.append("\(collections.count) collection\(collections.count == 1 ? "" : "s")")
            parts.append("\(requests) request\(requests == 1 ? "" : "s")")
        }
        if !environments.isEmpty {
            parts.append("\(environments.count) environment\(environments.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Nothing to import" : "Imported " + parts.joined(separator: ", ")
    }
}

public enum PostmanFormatError: Error, LocalizedError, Sendable, Equatable {
    case notJSON
    case unrecognisedShape

    public var errorDescription: String? {
        switch self {
        case .notJSON:
            return "That file isn't valid JSON."
        case .unrecognisedShape:
            return "That JSON isn't a Postman collection, a Postman environment, or a Droidective export."
        }
    }
}

// MARK: - Import / export

public enum PostmanFormat: Sendable {

    public static let schemaV21 = "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"

    // MARK: Detection

    public static func detect(_ data: Data) -> PostmanFileKind {
        guard let root = json(data) else { return .unknown }
        if let info = root["info"] as? [String: Any] {
            let schema = (info["schema"] as? String ?? "").lowercased()
            if schema.contains("v1") { return .collectionV1 }
            if root["item"] != nil || schema.contains("collection") { return .collectionV2 }
        }
        if root["item"] != nil { return .collectionV2 }
        if (root["_postman_variable_scope"] as? String) == "environment" { return .environment }
        if root["values"] is [Any], root["name"] is String { return .environment }
        if root["collections"] is [Any] || root["environments"] is [Any] { return .workspace }
        if root["requests"] is [Any] { return .collectionV1 }
        return .unknown
    }

    /// Reads any of the four shapes above. Throws only when the file isn't JSON
    /// or isn't one of them — a partially-broken collection imports what it can
    /// and reports the rest through `warnings`.
    public static func importFile(_ data: Data) throws -> PostmanImport {
        guard let root = json(data) else { throw PostmanFormatError.notJSON }
        switch detect(data) {
        case .collectionV2:
            var warnings: [String] = []
            let collection = importCollectionV2(root, warnings: &warnings)
            return PostmanImport(collections: [collection], warnings: warnings)
        case .collectionV1:
            var warnings: [String] = []
            let collection = importCollectionV1(root, warnings: &warnings)
            return PostmanImport(collections: [collection], warnings: warnings)
        case .environment:
            return PostmanImport(environments: [importEnvironment(root)])
        case .workspace:
            return try importWorkspace(data)
        case .unknown:
            throw PostmanFormatError.unrecognisedShape
        }
    }

    static func importWorkspace(_ data: Data) throws -> PostmanImport {
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(ApiClientData.self, from: data) else {
            throw PostmanFormatError.unrecognisedShape
        }
        return PostmanImport(
            collections: payload.collections,
            environments: payload.environments
        )
    }

    static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Collection v2 / v2.1

    static func importCollectionV2(_ root: [String: Any], warnings: inout [String]) -> ApiCollection {
        let info = root["info"] as? [String: Any] ?? [:]
        let name = info["name"] as? String ?? root["name"] as? String ?? "Imported Collection"
        let items = (root["item"] as? [Any]) ?? []

        var collection = ApiCollection(
            name: name,
            note: description(info["description"]) ?? "",
            items: items.compactMap { node($0, warnings: &warnings) },
            variables: variables(root["variable"])
        )
        if let auth = root["auth"] as? [String: Any] {
            collection.auth = authSpec(auth, warnings: &warnings)
        }
        return collection
    }

    static func node(_ raw: Any, warnings: inout [String]) -> ApiItem? {
        guard let node = raw as? [String: Any] else { return nil }
        let name = node["name"] as? String ?? "Untitled"

        if let children = node["item"] as? [Any] {
            return .folder(
                ApiFolder(
                    name: name,
                    note: description(node["description"]) ?? "",
                    items: children.compactMap { self.node($0, warnings: &warnings) }
                )
            )
        }

        guard node["request"] != nil else { return nil }
        noteScripts(node, name: name, warnings: &warnings)
        if let examples = node["response"] as? [Any], !examples.isEmpty {
            warnings.append("\"\(name)\": \(examples.count) saved example response(s) weren't imported.")
        }
        var request = self.request(node["request"], name: name, warnings: &warnings)
        applyProfileBehaviour(node["protocolProfileBehavior"], to: &request.settings)
        return .request(request)
    }

    static func noteScripts(_ node: [String: Any], name: String, warnings: inout [String]) {
        guard let events = node["event"] as? [Any] else { return }
        var kinds: [String] = []
        for case let event as [String: Any] in events {
            guard let listen = event["listen"] as? String else { continue }
            let script = event["script"] as? [String: Any]
            let lines = script?["exec"] as? [Any]
            guard (lines?.isEmpty == false) else { continue }
            kinds.append(listen == "test" ? "test" : "pre-request")
        }
        guard !kinds.isEmpty else { return }
        warnings.append(
            "\"\(name)\": \(kinds.joined(separator: " and ")) script(s) weren't imported — "
                + "rebuild them as assertions in the Tests tab."
        )
    }

    static func request(_ raw: Any?, name: String, warnings: inout [String]) -> SavedRequest {
        // Postman allows the shorthand `"request": "https://example.com"`.
        if let url = raw as? String {
            return SavedRequest(name: name, method: .get, url: url)
        }
        guard let dict = raw as? [String: Any] else { return SavedRequest(name: name) }

        let rawMethod = (dict["method"] as? String ?? "GET").uppercased()
        var method = HttpMethod(rawValue: rawMethod) ?? .get
        if HttpMethod(rawValue: rawMethod) == nil {
            warnings.append("\"\(name)\": method \(rawMethod) isn't supported; imported as GET.")
            method = .get
        }

        let url = self.url(dict["url"])
        var request = SavedRequest(
            name: name,
            note: description(dict["description"]) ?? "",
            method: method,
            url: url.base,
            headers: headers(dict["header"]),
            queryParams: url.query,
            pathVariables: url.pathVariables,
            body: body(dict["body"], name: name, warnings: &warnings)
        )
        if let auth = dict["auth"] as? [String: Any] {
            request.auth = authSpec(auth, warnings: &warnings)
        }
        return request
    }

    static func applyProfileBehaviour(_ raw: Any?, to settings: inout RequestSettings) {
        guard let behaviour = raw as? [String: Any] else { return }
        if let follow = behaviour["followRedirects"] as? Bool { settings.followRedirects = follow }
        if let strict = behaviour["strictSSL"] as? Bool { settings.validateTLS = strict }
        if let maxRedirects = behaviour["maxRedirects"] as? Int { settings.maxRedirects = maxRedirects }
    }

    // MARK: URL

    static func url(_ raw: Any?) -> (base: String, query: [ApiKeyValue], pathVariables: [ApiKeyValue]) {
        if let text = raw as? String {
            let split = splitQuery(text)
            return (split.base, split.query, [])
        }
        guard let dict = raw as? [String: Any] else { return ("", [], []) }

        let queryList = pairs(dict["query"])
        var base = dict["raw"] as? String ?? assembleURL(dict)
        if !queryList.isEmpty {
            // `raw` already contains the query string; the table owns it now.
            base = splitQuery(base).base
        } else {
            let split = splitQuery(base)
            return (split.base, split.query, pairs(dict["variable"]))
        }
        return (base, queryList, pairs(dict["variable"]))
    }

    /// Rebuilds a URL from Postman's decomposed form when `raw` is absent.
    static func assembleURL(_ dict: [String: Any]) -> String {
        let scheme = dict["protocol"] as? String ?? "https"
        let host: String
        if let parts = dict["host"] as? [Any] {
            host = parts.compactMap { $0 as? String }.joined(separator: ".")
        } else {
            host = dict["host"] as? String ?? ""
        }
        var out = host.isEmpty ? "" : "\(scheme)://\(host)"
        if let port = dict["port"] as? String, !port.isEmpty { out += ":\(port)" }
        if let port = dict["port"] as? Int { out += ":\(port)" }
        if let segments = dict["path"] as? [Any] {
            let path = segments.compactMap { segment -> String? in
                if let text = segment as? String { return text }
                if let variable = segment as? [String: Any] {
                    return (variable["value"] as? String).map { ":\($0)" }
                }
                return nil
            }
            if !path.isEmpty { out += "/" + path.joined(separator: "/") }
        } else if let path = dict["path"] as? String {
            out += path.hasPrefix("/") ? path : "/" + path
        }
        if let hash = dict["hash"] as? String, !hash.isEmpty { out += "#\(hash)" }
        return out
    }

    static func splitQuery(_ url: String) -> (base: String, query: [ApiKeyValue]) {
        guard let mark = url.firstIndex(of: "?") else { return (url, []) }
        let queryString = String(url[url.index(after: mark)...])
        let parsed = CurlParser.parseQueryString(queryString)
        var base = String(url[url.startIndex..<mark])
        if !parsed.fragment.isEmpty { base += "#" + parsed.fragment }
        return (base, parsed.pairs)
    }

    // MARK: Headers, pairs, variables

    static func headers(_ raw: Any?) -> [ApiKeyValue] {
        // Older exports store headers as one `A: b\nC: d` blob.
        if let text = raw as? String {
            return text.components(separatedBy: .newlines).compactMap { line in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { return nil }
                return ApiKeyValue(
                    key: key,
                    value: String(line[line.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                )
            }
        }
        return pairs(raw)
    }

    static func pairs(_ raw: Any?) -> [ApiKeyValue] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { element in
            guard let dict = element as? [String: Any] else { return nil }
            guard let key = dict["key"] as? String ?? dict["name"] as? String else { return nil }
            let disabled = dict["disabled"] as? Bool ?? false
            let enabled = dict["enabled"] as? Bool ?? !disabled
            return ApiKeyValue(
                key: key,
                value: stringValue(dict["value"]),
                enabled: enabled,
                note: description(dict["description"]) ?? ""
            )
        }
    }

    static func variables(_ raw: Any?) -> [ApiKeyValue] { pairs(raw) }

    /// Postman writes numbers and booleans unquoted in variable values.
    static func stringValue(_ raw: Any?) -> String {
        switch raw {
        case let text as String: return text
        case let number as NSNumber:
            if JSONProbe.isJSONBoolean(number) { return number.boolValue ? "true" : "false" }
            if number.doubleValue == number.doubleValue.rounded(),
               abs(number.doubleValue) < 1e15 {
                return String(number.intValue)
            }
            return number.stringValue
        case let flag as Bool: return flag ? "true" : "false"
        case nil: return ""
        default: return ""
        }
    }

    /// `description` is either a string or `{content, type}`.
    static func description(_ raw: Any?) -> String? {
        if let text = raw as? String { return text }
        if let dict = raw as? [String: Any] { return dict["content"] as? String }
        return nil
    }

    // MARK: Body

    static func body(_ raw: Any?, name: String, warnings: inout [String]) -> RequestBodySpec {
        guard let dict = raw as? [String: Any] else { return RequestBodySpec() }
        if (dict["disabled"] as? Bool) == true { return RequestBodySpec() }
        let mode = dict["mode"] as? String ?? ""

        switch mode {
        case "raw":
            let text = dict["raw"] as? String ?? ""
            let language = rawLanguage(dict["options"])
            if language == .json || (language == .text && JSONFormatter.isValidJSON(text)) {
                return RequestBodySpec(type: .json, jsonText: text)
            }
            return RequestBodySpec(type: .raw, rawText: text, rawLanguage: language)

        case "urlencoded":
            return RequestBodySpec(type: .formUrlEncoded, formFields: pairs(dict["urlencoded"]))

        case "formdata":
            return RequestBodySpec(type: .multipart, multipartFields: formData(dict["formdata"]))

        case "graphql":
            let graphql = dict["graphql"] as? [String: Any] ?? [:]
            let variables = graphql["variables"]
            return RequestBodySpec(
                type: .graphql,
                graphqlQuery: graphql["query"] as? String ?? "",
                graphqlVariables: variablesText(variables)
            )

        case "file":
            let file = dict["file"] as? [String: Any] ?? [:]
            let source = file["src"] as? String ?? ""
            if source.isEmpty {
                warnings.append("\"\(name)\": binary body has no file path saved in the export.")
            }
            return RequestBodySpec(type: .binary, binaryFilePath: source)

        case "", "none":
            return RequestBodySpec()

        default:
            warnings.append("\"\(name)\": body mode \"\(mode)\" isn't supported and was dropped.")
            return RequestBodySpec()
        }
    }

    static func rawLanguage(_ raw: Any?) -> RawLanguage {
        guard let options = raw as? [String: Any],
              let rawOptions = options["raw"] as? [String: Any],
              let language = rawOptions["language"] as? String
        else { return .text }
        return RawLanguage(rawValue: language.lowercased()) ?? .text
    }

    static func formData(_ raw: Any?) -> [ApiFormField] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { element in
            guard let dict = element as? [String: Any], let key = dict["key"] as? String else {
                return nil
            }
            let disabled = dict["disabled"] as? Bool ?? false
            let isFile = (dict["type"] as? String) == "file"
            let value: String
            if isFile {
                if let source = dict["src"] as? String {
                    value = source
                } else if let sources = dict["src"] as? [Any] {
                    value = sources.compactMap { $0 as? String }.first ?? ""
                } else {
                    value = ""
                }
            } else {
                value = stringValue(dict["value"])
            }
            return ApiFormField(
                key: key,
                value: value,
                kind: isFile ? .file : .text,
                contentType: dict["contentType"] as? String ?? "",
                enabled: !disabled
            )
        }
    }

    /// GraphQL variables arrive as either a JSON string or a nested object.
    static func variablesText(_ raw: Any?) -> String {
        if let text = raw as? String { return text }
        guard let object = raw,
              let data = try? JSONSerialization.data(
                  withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
              ),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    // MARK: Auth

    static func authSpec(_ dict: [String: Any], warnings: inout [String]) -> AuthSpec {
        let type = (dict["type"] as? String ?? "noauth").lowercased()

        func field(_ key: String) -> String {
            if let list = dict[type] as? [Any] {
                for case let entry as [String: Any] in list {
                    if entry["key"] as? String == key { return stringValue(entry["value"]) }
                }
            }
            if let nested = dict[type] as? [String: Any] { return stringValue(nested[key]) }
            return ""
        }

        switch type {
        case "bearer":
            return AuthSpec(type: .bearer, bearerToken: field("token"))
        case "basic":
            return AuthSpec(
                type: .basic,
                basicUsername: field("username"),
                basicPassword: field("password")
            )
        case "apikey":
            let location = field("in").lowercased()
            return AuthSpec(
                type: .apiKey,
                apiKeyName: field("key"),
                apiKeyValue: field("value"),
                apiKeyLocation: location.contains("quer") ? .query : .header
            )
        case "oauth2":
            let prefix = field("headerPrefix")
            return AuthSpec(
                type: .oauth2,
                oauth2Token: field("accessToken"),
                oauth2HeaderPrefix: prefix.isEmpty ? "Bearer" : prefix
            )
        case "noauth", "":
            return AuthSpec()
        default:
            warnings.append(
                "\(type) auth isn't supported — set credentials manually on the Auth tab."
            )
            return AuthSpec()
        }
    }

    // MARK: - Environment

    static func importEnvironment(_ root: [String: Any]) -> ApiEnvironment {
        let values = (root["values"] as? [Any]) ?? []
        return ApiEnvironment(
            name: root["name"] as? String ?? "Imported Environment",
            variables: values.compactMap { element in
                guard let dict = element as? [String: Any],
                      let key = dict["key"] as? String
                else { return nil }
                return ApiKeyValue(
                    key: key,
                    value: stringValue(dict["value"]),
                    enabled: dict["enabled"] as? Bool ?? true
                )
            }
        )
    }

    // MARK: - Export

    /// Postman Collection v2.1. `includeSecrets` defaults to false so a shared
    /// file can't leak a bearer token or password.
    public static func exportCollection(
        _ collection: ApiCollection,
        includeSecrets: Bool = false,
        id: String = UUID().uuidString
    ) throws -> Data {
        let source = includeSecrets
            ? collection
            : {
                var copy = collection
                copy.items = ApiCollectionTree.withoutSecrets(copy.items)
                copy.auth = copy.auth.withoutSecrets()
                return copy
            }()

        var payload: [String: Any] = [
            "info": [
                "_postman_id": id,
                "name": source.name,
                "description": source.note,
                "schema": schemaV21,
            ],
            "item": source.items.map(exportItem),
        ]
        if !source.variables.isEmpty {
            payload["variable"] = source.variables.map(exportPair)
        }
        if source.auth.type != .none {
            payload["auth"] = exportAuth(source.auth)
        }
        return try JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        )
    }

    public static func exportEnvironment(
        _ environment: ApiEnvironment, id: String = UUID().uuidString
    ) throws -> Data {
        let payload: [String: Any] = [
            "id": id,
            "name": environment.name,
            "values": environment.variables.map { variable in
                [
                    "key": variable.key,
                    "value": variable.value,
                    "enabled": variable.enabled,
                    "type": "default",
                ] as [String: Any]
            },
            "_postman_variable_scope": "environment",
            "_postman_exported_using": "Droidective",
        ]
        return try JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        )
    }

    /// Everything, for a backup that round-trips through `importFile`.
    public static func exportWorkspace(_ data: ApiClientData, includeSecrets: Bool = false) throws -> Data {
        var payload = data
        payload.history = []
        if !includeSecrets {
            payload.collections = payload.collections.map { collection in
                var copy = collection
                copy.items = ApiCollectionTree.withoutSecrets(copy.items)
                copy.auth = copy.auth.withoutSecrets()
                return copy
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func exportItem(_ item: ApiItem) -> [String: Any] {
        switch item {
        case .folder(let folder):
            var out: [String: Any] = [
                "name": folder.name,
                "item": folder.items.map(exportItem),
            ]
            if !folder.note.isEmpty { out["description"] = folder.note }
            return out
        case .request(let request):
            var out: [String: Any] = [
                "name": request.name,
                "request": exportRequest(request),
                "response": [],
            ]
            if request.settings.followRedirects == false || request.settings.validateTLS == false {
                out["protocolProfileBehavior"] = [
                    "followRedirects": request.settings.followRedirects,
                    "strictSSL": request.settings.validateTLS,
                ]
            }
            return out
        }
    }

    static func exportRequest(_ request: SavedRequest) -> [String: Any] {
        var out: [String: Any] = [
            "method": request.method.rawValue,
            "header": request.headers.map(exportPair),
            "url": exportURL(request),
        ]
        if !request.note.isEmpty { out["description"] = request.note }
        if request.auth.type != .none { out["auth"] = exportAuth(request.auth) }
        if let body = exportBody(request.body) { out["body"] = body }
        return out
    }

    static func exportURL(_ request: SavedRequest) -> [String: Any] {
        let query = request.queryParams.filter { !$0.key.isEmpty }
        var raw = request.url
        if !query.isEmpty {
            let encoded = query
                .filter(\.enabled)
                .map {
                    "\(HttpRequestBuilder.encodeQueryComponent($0.key))="
                        + HttpRequestBuilder.encodeQueryComponent($0.value)
                }
                .joined(separator: "&")
            if !encoded.isEmpty { raw += (raw.contains("?") ? "&" : "?") + encoded }
        }
        var out: [String: Any] = ["raw": raw]
        if !query.isEmpty { out["query"] = query.map(exportPair) }
        if !request.pathVariables.isEmpty {
            out["variable"] = request.pathVariables.map(exportPair)
        }
        return out
    }

    static func exportPair(_ pair: ApiKeyValue) -> [String: Any] {
        var out: [String: Any] = ["key": pair.key, "value": pair.value]
        if !pair.enabled { out["disabled"] = true }
        if !pair.note.isEmpty { out["description"] = pair.note }
        return out
    }

    static func exportBody(_ body: RequestBodySpec) -> [String: Any]? {
        switch body.type {
        case .none:
            return nil
        case .json:
            return [
                "mode": "raw",
                "raw": body.jsonText,
                "options": ["raw": ["language": "json"]],
            ]
        case .raw:
            return [
                "mode": "raw",
                "raw": body.rawText,
                "options": ["raw": ["language": body.rawLanguage.rawValue]],
            ]
        case .formUrlEncoded:
            return ["mode": "urlencoded", "urlencoded": body.formFields.map(exportPair)]
        case .multipart:
            return [
                "mode": "formdata",
                "formdata": body.multipartFields.map { field -> [String: Any] in
                    var out: [String: Any] = ["key": field.key, "type": field.kind.rawValue]
                    if field.kind == .file {
                        out["src"] = field.value
                    } else {
                        out["value"] = field.value
                    }
                    if !field.contentType.isEmpty { out["contentType"] = field.contentType }
                    if !field.enabled { out["disabled"] = true }
                    return out
                },
            ]
        case .graphql:
            return [
                "mode": "graphql",
                "graphql": ["query": body.graphqlQuery, "variables": body.graphqlVariables],
            ]
        case .binary:
            return ["mode": "file", "file": ["src": body.binaryFilePath]]
        }
    }

    static func exportAuth(_ auth: AuthSpec) -> [String: Any] {
        switch auth.type {
        case .none:
            return ["type": "noauth"]
        case .bearer:
            return [
                "type": "bearer",
                "bearer": [["key": "token", "value": auth.bearerToken, "type": "string"]],
            ]
        case .basic:
            return [
                "type": "basic",
                "basic": [
                    ["key": "username", "value": auth.basicUsername, "type": "string"],
                    ["key": "password", "value": auth.basicPassword, "type": "string"],
                ],
            ]
        case .apiKey:
            return [
                "type": "apikey",
                "apikey": [
                    ["key": "key", "value": auth.apiKeyName, "type": "string"],
                    ["key": "value", "value": auth.apiKeyValue, "type": "string"],
                    [
                        "key": "in",
                        "value": auth.apiKeyLocation == .query ? "query" : "header",
                        "type": "string",
                    ],
                ],
            ]
        case .oauth2:
            return [
                "type": "oauth2",
                "oauth2": [
                    ["key": "accessToken", "value": auth.oauth2Token, "type": "string"],
                    ["key": "headerPrefix", "value": auth.oauth2HeaderPrefix, "type": "string"],
                    ["key": "addTokenTo", "value": "header", "type": "string"],
                ],
            ]
        }
    }

    // MARK: - Collection v1

    static func importCollectionV1(_ root: [String: Any], warnings: inout [String]) -> ApiCollection {
        let requests = (root["requests"] as? [Any]) ?? []
        var items: [ApiItem] = []

        for case let dict as [String: Any] in requests {
            let name = dict["name"] as? String ?? "Untitled"
            let method = HttpMethod(rawValue: (dict["method"] as? String ?? "GET").uppercased()) ?? .get
            let split = splitQuery(dict["url"] as? String ?? "")
            var request = SavedRequest(
                name: name,
                note: dict["description"] as? String ?? "",
                method: method,
                url: split.base,
                headers: headers(dict["headers"]),
                queryParams: split.query
            )
            switch dict["dataMode"] as? String {
            case "raw":
                let text = dict["rawModeData"] as? String ?? ""
                request.body = JSONFormatter.isValidJSON(text)
                    ? RequestBodySpec(type: .json, jsonText: text)
                    : RequestBodySpec(type: .raw, rawText: text)
            case "urlencoded":
                request.body = RequestBodySpec(type: .formUrlEncoded, formFields: pairs(dict["data"]))
            case "params":
                request.body = RequestBodySpec(type: .multipart, multipartFields: formData(dict["data"]))
            default:
                break
            }
            items.append(.request(request))
        }
        warnings.append("Imported a v1 collection — folders and auth aren't part of that format.")
        return ApiCollection(name: root["name"] as? String ?? "Imported Collection", items: items)
    }
}
