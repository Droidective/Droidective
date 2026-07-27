import Foundation

public enum CurlParser: Sendable {

    // MARK: - Parse cURL → SavedRequest

    public static func parse(_ curl: String) -> SavedRequest? {
        let tokens = tokenize(curl)
        guard let first = tokens.first,
              first.lowercased().hasSuffix("curl") else { return nil }

        var method: HttpMethod = .get
        var url = ""
        var headers: [ApiKeyValue] = []
        var bodyParts: [String] = []
        var formFields: [(String, String)] = []
        var explicitMethod = false
        var forceGet = false

        var i = 1
        while i < tokens.count {
            let token = tokens[i]
            switch token {
            case "-X", "--request":
                i += 1
                if i < tokens.count, let m = HttpMethod(rawValue: tokens[i].uppercased()) {
                    method = m
                    explicitMethod = true
                }
            case "-G", "--get":
                forceGet = true
            case "-H", "--header":
                i += 1
                if i < tokens.count {
                    let header = tokens[i]
                    if let colon = header.firstIndex(of: ":") {
                        let key = String(header[..<colon]).trimmingCharacters(in: .whitespaces)
                        let value = String(header[header.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        headers.append(ApiKeyValue(key: key, value: value))
                    }
                }
            case "-d", "--data", "--data-raw", "--data-binary", "--data-ascii":
                i += 1
                if i < tokens.count {
                    bodyParts.append(tokens[i])
                    if !explicitMethod && !forceGet { method = .post }
                }
            case "-F", "--form", "--form-string":
                i += 1
                if i < tokens.count {
                    let field = tokens[i]
                    if let eq = field.firstIndex(of: "=") {
                        formFields.append((String(field[..<eq]), String(field[field.index(after: eq)...])))
                    }
                    if !explicitMethod && !forceGet { method = .post }
                }
            case "-u", "--user":
                i += 1
            case "--url":
                i += 1
                if i < tokens.count { url = tokens[i] }
            case "--compressed", "-s", "--silent", "-S", "--show-error",
                 "-k", "--insecure", "-L", "--location", "-i", "--include",
                 "-v", "--verbose", "--location-trusted":
                break
            case "-o", "--output", "-w", "--write-out", "--connect-timeout",
                 "--max-time", "-A", "--user-agent", "-e", "--referer":
                i += 1
            default:
                if !token.hasPrefix("-"), url.isEmpty {
                    url = token
                }
            }
            i += 1
        }

        if forceGet { method = .get }
        guard !url.isEmpty else { return nil }

        var queryParams: [ApiKeyValue] = []
        if let components = URLComponents(string: url) {
            for item in components.queryItems ?? [] {
                queryParams.append(ApiKeyValue(key: item.name, value: item.value ?? ""))
            }
            if !queryParams.isEmpty, let scheme = components.scheme, let host = components.host {
                var clean = "\(scheme)://\(host)"
                if let port = components.port { clean += ":\(port)" }
                clean += components.path
                url = clean
            }
        }

        let bodyRaw = bodyParts.isEmpty ? nil : bodyParts.joined(separator: "&")

        // curl -G moves -d content into query params instead of body
        if forceGet, let raw = bodyRaw, !raw.isEmpty {
            for pair in raw.split(separator: "&", omittingEmptySubsequences: false) {
                if let eq = pair.firstIndex(of: "=") {
                    queryParams.append(ApiKeyValue(
                        key: String(pair[..<eq]),
                        value: String(pair[pair.index(after: eq)...])
                    ))
                } else {
                    queryParams.append(ApiKeyValue(key: String(pair), value: ""))
                }
            }
        }

        let bodySpec: RequestBodySpec
        if !formFields.isEmpty {
            bodySpec = RequestBodySpec(
                type: .formUrlEncoded,
                formFields: formFields.map { ApiKeyValue(key: $0.0, value: $0.1) }
            )
        } else if !forceGet, let raw = bodyRaw, !raw.isEmpty {
            let isJSON = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) != nil
            if isJSON {
                bodySpec = RequestBodySpec(type: .json, jsonText: raw)
            } else {
                bodySpec = RequestBodySpec(type: .raw, rawText: raw)
            }
        } else {
            bodySpec = RequestBodySpec()
        }

        return SavedRequest(
            name: nameFromURL(url),
            method: method,
            url: url,
            headers: headers,
            queryParams: queryParams,
            body: bodySpec
        )
    }

    // MARK: - Export SavedRequest → cURL

    public static func export(_ request: SavedRequest, environment: ApiEnvironment? = nil) -> String {
        let env = environment?.variableMap ?? [:]
        var parts: [String] = ["curl"]

        if request.method != .get || hasBody(request.body) {
            parts.append("-X \(request.method.rawValue)")
        }

        var fullURL = EnvironmentEngine.resolve(request.url, with: env)
        let enabledParams = request.queryParams.filter(\.enabled)
        if !enabledParams.isEmpty {
            let joined = enabledParams
                .map { "\(queryEscape(EnvironmentEngine.resolve($0.key, with: env)))=\(queryEscape(EnvironmentEngine.resolve($0.value, with: env)))" }
                .joined(separator: "&")
            fullURL += (fullURL.contains("?") ? "&" : "?") + joined
        }
        parts.append(shellQuote(fullURL))

        for h in request.headers where h.enabled {
            let val = EnvironmentEngine.resolve(h.value, with: env)
            parts.append("-H \(shellQuote("\(h.key): \(val)"))")
        }

        switch request.auth.type {
        case .bearer:
            let tok = EnvironmentEngine.resolve(request.auth.bearerToken, with: env)
            parts.append("-H \(shellQuote("Authorization: Bearer \(tok)"))")
        case .basic:
            let u = EnvironmentEngine.resolve(request.auth.basicUsername, with: env)
            let p = EnvironmentEngine.resolve(request.auth.basicPassword, with: env)
            parts.append("-u \(shellQuote("\(u):\(p)"))")
        case .apiKey:
            let k = request.auth.apiKeyName
            let v = EnvironmentEngine.resolve(request.auth.apiKeyValue, with: env)
            parts.append("-H \(shellQuote("\(k): \(v)"))")
        case .none:
            break
        }

        switch request.body.type {
        case .json:
            let text = EnvironmentEngine.resolve(request.body.jsonText, with: env)
            if !text.isEmpty {
                if !request.headers.contains(where: { $0.enabled && $0.key.lowercased() == "content-type" }) {
                    parts.append("-H \(shellQuote("Content-Type: application/json"))")
                }
                parts.append("--data-raw \(shellQuote(text))")
            }
        case .formUrlEncoded:
            let fields = request.body.formFields.filter(\.enabled)
            if !fields.isEmpty {
                let encoded = fields
                    .map { "\(queryEscape($0.key))=\(queryEscape(EnvironmentEngine.resolve($0.value, with: env)))" }
                    .joined(separator: "&")
                parts.append("--data \(shellQuote(encoded))")
            }
        case .raw:
            let text = EnvironmentEngine.resolve(request.body.rawText, with: env)
            if !text.isEmpty {
                parts.append("--data-raw \(shellQuote(text))")
            }
        case .none:
            break
        }

        return parts.joined(separator: " \\\n  ")
    }

    // MARK: - Tokenizer

    static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var escaped = false
        let chars = Array(input)
        var i = 0

        while i < chars.count {
            let ch = chars[i]
            if escaped {
                if ch != "\n" { current.append(ch) }
                escaped = false
                i += 1
                continue
            }
            if ch == "\\" && !inSingle {
                escaped = true
                i += 1
                continue
            }
            if ch == "'" && !inDouble {
                inSingle.toggle()
                i += 1
                continue
            }
            if ch == "\"" && !inSingle {
                inDouble.toggle()
                i += 1
                continue
            }
            if (ch == " " || ch == "\t" || ch == "\n") && !inSingle && !inDouble {
                if !current.isEmpty { tokens.append(current); current = "" }
                i += 1
                continue
            }
            current.append(ch)
            i += 1
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Helpers

    public static func nameFromURL(_ url: String) -> String {
        guard let components = URLComponents(string: url) else { return "Request" }
        let segment = components.path.split(separator: "/").last.map(String.init) ?? ""
        if segment.isEmpty { return components.host ?? "Request" }
        return segment
    }

    private static func hasBody(_ body: RequestBodySpec) -> Bool {
        switch body.type {
        case .none: return false
        case .json: return !body.jsonText.isEmpty
        case .raw: return !body.rawText.isEmpty
        case .formUrlEncoded: return !body.formFields.filter(\.enabled).isEmpty
        }
    }

    private static let queryAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func queryEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? value
    }
}
