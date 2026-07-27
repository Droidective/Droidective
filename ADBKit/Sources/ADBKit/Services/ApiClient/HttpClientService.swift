import Foundation

public actor HttpClientService {
    private var inFlight: [String: Task<ApiResponse, any Error>] = [:]

    public init() {}

    public func send(_ request: SavedRequest, environment: ApiEnvironment? = nil) async throws -> ApiResponse {
        let resolved = EnvironmentEngine.resolveRequest(request, with: environment)
        let urlRequest = try Self.buildURLRequest(from: resolved)
        let id = request.id
        let task = Task<ApiResponse, any Error> {
            let start = ContinuousClock.now
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let elapsed = start.duration(to: ContinuousClock.now)
            let ms = Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000

            guard let http = response as? HTTPURLResponse else {
                throw HttpClientError.notHTTP
            }

            let headers = http.allHeaderFields.compactMap { key, value -> (String, String)? in
                guard let k = key as? String, let v = value as? String else { return nil }
                return (k, v)
            }.sorted { $0.0.lowercased() < $1.0.lowercased() }

            return ApiResponse(
                statusCode: http.statusCode,
                statusText: ApiResponse.statusText(for: http.statusCode),
                headers: headers,
                body: data,
                elapsedMs: ms,
                size: data.count
            )
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        return try await task.value
    }

    public func cancel(id: String) {
        inFlight[id]?.cancel()
        inFlight[id] = nil
    }

    // MARK: - URLRequest builder

    public static func buildURLRequest(from request: SavedRequest) throws -> URLRequest {
        var urlString = request.url
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }

        let enabledParams = request.queryParams.filter(\.enabled)
        if !enabledParams.isEmpty, var components = URLComponents(string: urlString) {
            var items = components.queryItems ?? []
            for param in enabledParams {
                items.append(URLQueryItem(name: param.key, value: param.value))
            }
            components.queryItems = items
            if let built = components.url { urlString = built.absoluteString }
        }

        guard let url = URL(string: urlString) else {
            throw HttpClientError.invalidURL(urlString)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = 60

        for h in request.headers where h.enabled {
            urlRequest.setValue(h.value, forHTTPHeaderField: h.key)
        }

        switch request.auth.type {
        case .bearer:
            if !request.auth.bearerToken.isEmpty {
                urlRequest.setValue("Bearer \(request.auth.bearerToken)", forHTTPHeaderField: "Authorization")
            }
        case .basic:
            let cred = Data("\(request.auth.basicUsername):\(request.auth.basicPassword)".utf8).base64EncodedString()
            urlRequest.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        case .apiKey:
            if !request.auth.apiKeyName.isEmpty {
                urlRequest.setValue(request.auth.apiKeyValue, forHTTPHeaderField: request.auth.apiKeyName)
            }
        case .none:
            break
        }

        switch request.body.type {
        case .json:
            if !request.body.jsonText.isEmpty {
                urlRequest.httpBody = Data(request.body.jsonText.utf8)
                if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        case .formUrlEncoded:
            let enabled = request.body.formFields.filter(\.enabled)
            if !enabled.isEmpty {
                let encoded = enabled.map { "\(formEscape($0.key))=\(formEscape($0.value))" }.joined(separator: "&")
                urlRequest.httpBody = Data(encoded.utf8)
                if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                    urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }
            }
        case .raw:
            if !request.body.rawText.isEmpty {
                urlRequest.httpBody = Data(request.body.rawText.utf8)
                if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                    urlRequest.setValue(request.body.rawContentType, forHTTPHeaderField: "Content-Type")
                }
            }
        case .none:
            break
        }

        return urlRequest
    }

    private static func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+=&")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public enum HttpClientError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case notHTTP

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .notHTTP: return "Response is not HTTP"
        }
    }
}
