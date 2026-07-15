import Foundation

/// Builds a copy-pasteable `curl` command that reproduces a Reactotron-captured
/// API request. Lives in ADBKit (not the view) so it stays pure, `Sendable`,
/// and unit-testable without the UI.
public enum ReactotronCurl {
    /// Render `method`/`url`/`request` as a multi-line `curl` invocation.
    ///
    /// - Parameters:
    ///   - method: the HTTP verb as captured (any case).
    ///   - url: the request URL.
    ///   - request: the Reactotron `request` payload, read for `headers`,
    ///     `data`, and `params`.
    public static func command(method: String, url: String, request: JSONValue?) -> String {
        let verb = method.uppercased()
        let fullURL = urlMergingParams(url, params: request?["params"])
        let form = formParts(request?["data"])
        let body = form == nil ? requestBody(request) : nil
        var parts: [String] = ["curl"]
        // `curl` switches to POST the moment a body is present, so the verb must
        // be stated explicitly whenever it isn't a plain body-less GET —
        // otherwise copying a GET that carries a body silently produces a POST.
        if verb != "GET" || body != nil || form != nil {
            parts.append("-X \(verb)")
        }
        parts.append(shellQuote(fullURL))
        if let headers = request?["headers"]?.objectValue {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                // A multipart body is rebuilt as -F fields below, so the captured
                // content-type's boundary is stale — curl must mint its own.
                if form != nil, key.lowercased() == "content-type" { continue }
                let rendered = value.stringValue ?? value.jsonString
                parts.append("-H \(shellQuote("\(key): \(rendered)"))")
            }
        }
        if let form {
            for (name, value) in form {
                // --form-string, not -F: a value starting with "@" or "<"
                // would otherwise be read as a local file/stdin reference.
                parts.append("--form-string \(shellQuote("\(name)=\(value)"))")
            }
        }
        if let body {
            parts.append("--data \(shellQuote(body))")
        }
        return parts.joined(separator: " \\\n  ")
    }

    /// The body to send, or `nil` when the request carries nothing meaningful —
    /// JSON null, an empty string, or an empty `{}` / `[]`. Keeps a body-less GET
    /// body-less (and therefore a GET, not a POST inferred by `curl`).
    private static func requestBody(_ request: JSONValue?) -> String? {
        guard let data = request?["data"], !data.isNull else { return nil }
        let rendered = data.stringValue ?? data.jsonString
        switch rendered {
        case "", "{}", "[]", "null": return nil
        default: return rendered
        }
    }

    // MARK: - Query params

    /// The networking plugin reports `url` from `xhr.responseURL` — the *final*
    /// URL after any redirect or gateway rewrite, which can arrive without the
    /// query string the app actually sent — while the original query params ride
    /// separately in the payload's `params` object. Append every param the URL
    /// doesn't already carry so the copied command reproduces the request; when
    /// the URL kept its query, this is a no-op.
    static func urlMergingParams(_ url: String, params: JSONValue?) -> String {
        guard let params = params?.objectValue, !params.isEmpty else { return url }
        let existing = existingQueryKeys(url)
        var merged = url
        for (key, value) in params.sorted(by: { $0.key < $1.key }) {
            guard !existing.contains(key) else { continue }
            // query-string yields an array for a repeated key (?tag=a&tag=b).
            let values = value.arrayValue ?? [value]
            for item in values {
                let separator = merged.contains("?") ? "&" : "?"
                // A bare flag (?debug) parses to null — reproduce it value-less.
                if item.isNull {
                    merged += "\(separator)\(queryEscape(key))"
                } else {
                    let rendered = item.stringValue ?? item.jsonString
                    merged += "\(separator)\(queryEscape(key))=\(queryEscape(rendered))"
                }
            }
        }
        return merged
    }

    /// The query keys already present in `url`, in both their raw and
    /// percent-decoded spellings — the client decodes some param keys and not
    /// others depending on its version, so match either form.
    private static func existingQueryKeys(_ url: String) -> Set<String> {
        guard let questionMark = url.firstIndex(of: "?") else { return [] }
        var keys: Set<String> = []
        let query = url[url.index(after: questionMark)...]
        for pair in query.split(separator: "&") {
            // A degenerate pair like "=" splits to nothing — skip it.
            guard let rawKey = pair.split(separator: "=", maxSplits: 1).first else { continue }
            let key = String(rawKey)
            keys.insert(key)
            if let decoded = key.removingPercentEncoding { keys.insert(decoded) }
        }
        return keys
    }

    /// RFC 3986 unreserved characters — everything else is percent-encoded so a
    /// param value carrying `&`, `=`, or spaces survives the round trip.
    private static let queryAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func queryEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? value
    }

    // MARK: - Multipart bodies

    /// React Native's `FormData` reaches the wire as `{"_parts": [[name, value],
    /// …]}` — attaching that JSON as `--data` reproduces nothing. Rebuild it as
    /// `-F` fields instead: string values pass through; a file part (an object
    /// with `uri`/`name`/`type`) renders as its JSON, since the file itself
    /// lives on the device and can't ride a copied command.
    static func formParts(_ data: JSONValue?) -> [(name: String, value: String)]? {
        guard let object = data?.objectValue,
              object.count == 1,
              let parts = object["_parts"]?.arrayValue,
              !parts.isEmpty else { return nil }
        var fields: [(name: String, value: String)] = []
        for part in parts {
            guard let pair = part.arrayValue, pair.count >= 2 else { return nil }
            let name = pair[0].stringValue ?? pair[0].jsonString
            let value = pair[1].stringValue ?? pair[1].jsonString
            fields.append((name: name, value: value))
        }
        return fields
    }
}
