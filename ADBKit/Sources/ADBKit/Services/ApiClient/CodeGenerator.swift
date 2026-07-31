import Foundation

// MARK: - Targets

public enum CodeTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    case curl
    case httpie
    case fetch
    case axios
    case pythonRequests
    case swiftURLSession

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .curl: return "cURL"
        case .httpie: return "HTTPie"
        case .fetch: return "JavaScript · fetch"
        case .axios: return "Node · axios"
        case .pythonRequests: return "Python · requests"
        case .swiftURLSession: return "Swift · URLSession"
        }
    }

    /// For the editor's syntax highlighting.
    public var language: RawLanguage {
        switch self {
        case .curl, .httpie: return .text
        case .fetch, .axios: return .javascript
        case .pythonRequests, .swiftURLSession: return .text
        }
    }
}

/// Stands in for the disk while generating code — a snippet references the file
/// by path, so its contents are never needed.
struct PlaceholderFileReader: ApiFileReading {
    func data(at path: String) throws -> Data { Data() }
    func fileName(at path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }
}

// MARK: - Generator

public enum CodeGenerator: Sendable {

    /// Renders `request` as runnable code for `target`.
    ///
    /// Variables are resolved with `.fixed()` dynamic values so a preview pane
    /// doesn't churn on every redraw; a real send generates fresh ones.
    public static func generate(
        _ target: CodeTarget,
        for request: SavedRequest,
        scope: VariableScope = .empty,
        dynamic: DynamicVariables = .fixed()
    ) -> String {
        let resolved = ApiVariables.resolveRequest(request, scope: scope, dynamic: dynamic)
        guard let prepared = try? HttpRequestBuilder.prepare(
            resolved, files: PlaceholderFileReader(), boundary: "----DroidectiveBoundary"
        ) else {
            return "# Enter a valid URL to see the generated code."
        }
        switch target {
        case .curl: return curl(resolved, prepared)
        case .httpie: return httpie(resolved, prepared)
        case .fetch: return fetch(resolved, prepared)
        case .axios: return axios(resolved, prepared)
        case .pythonRequests: return python(resolved, prepared)
        case .swiftURLSession: return swift(resolved, prepared)
        }
    }

    /// Headers minus the ones the target's own body helper will set.
    static func headers(
        _ prepared: PreparedRequest, droppingContentTypeFor request: SavedRequest
    ) -> [(key: String, value: String)] {
        guard request.body.type == .multipart else { return prepared.headers }
        return prepared.headers.filter { $0.key.lowercased() != "content-type" }
    }

    // MARK: - cURL

    static func curl(_ request: SavedRequest, _ prepared: PreparedRequest) -> String {
        var parts: [String] = ["curl"]

        if request.method != .get || prepared.body != nil {
            parts.append("-X \(request.method.rawValue)")
        }
        parts.append(shellQuote(prepared.url))

        // Basic auth reads better as `-u`, and it round-trips back into the Auth
        // tab on re-import instead of arriving as a base64 header.
        let usesUserFlag = request.auth.type == .basic
        for header in prepared.headers {
            if usesUserFlag, header.key.lowercased() == "authorization" { continue }
            parts.append("-H \(shellQuote("\(header.key): \(header.value)"))")
        }
        if usesUserFlag {
            parts.append(
                "-u \(shellQuote("\(request.auth.basicUsername):\(request.auth.basicPassword)"))"
            )
        }

        switch request.body.type {
        case .none:
            break
        case .json, .raw, .graphql:
            if let text = prepared.bodyText, !text.isEmpty {
                parts.append("--data-raw \(shellQuote(text))")
            }
        case .formUrlEncoded:
            if let text = prepared.bodyText, !text.isEmpty {
                parts.append("--data \(shellQuote(text))")
            }
        case .multipart:
            for field in request.body.multipartFields where field.enabled && !field.key.isEmpty {
                let value = field.kind == .file ? "@\(field.value)" : field.value
                let suffix = field.contentType.isEmpty ? "" : ";type=\(field.contentType)"
                parts.append("-F \(shellQuote("\(field.key)=\(value)\(suffix)"))")
            }
        case .binary:
            if !request.body.binaryFilePath.isEmpty {
                parts.append("--data-binary \(shellQuote("@\(request.body.binaryFilePath)"))")
            }
        }

        if request.settings.followRedirects { parts.append("-L") }
        if !request.settings.validateTLS { parts.append("-k") }
        if request.settings.timeoutSeconds > 0, request.settings.timeoutSeconds != 60 {
            parts.append("--max-time \(Int(request.settings.timeoutSeconds))")
        }
        if request.settings.followRedirects, request.settings.maxRedirects != 10 {
            parts.append("--max-redirs \(request.settings.maxRedirects)")
        }
        return parts.joined(separator: " \\\n  ")
    }

    // MARK: - HTTPie

    static func httpie(_ request: SavedRequest, _ prepared: PreparedRequest) -> String {
        var parts: [String] = ["http"]
        if !request.settings.validateTLS { parts.append("--verify=no") }
        if request.settings.followRedirects { parts.append("--follow") }
        parts.append(request.method.rawValue)
        parts.append(shellQuote(prepared.url))

        for header in headers(prepared, droppingContentTypeFor: request) {
            parts.append(shellQuote("\(header.key):\(header.value)"))
        }

        switch request.body.type {
        case .multipart:
            parts.append("--multipart")
            for field in request.body.multipartFields where field.enabled && !field.key.isEmpty {
                let separator = field.kind == .file ? "@" : "="
                parts.append(shellQuote("\(field.key)\(separator)\(field.value)"))
            }
            return parts.joined(separator: " \\\n  ")
        case .binary:
            return parts.joined(separator: " \\\n  ") + " \\\n  < \(shellQuote(request.body.binaryFilePath))"
        case .none:
            return parts.joined(separator: " \\\n  ")
        case .json, .raw, .graphql, .formUrlEncoded:
            let command = parts.joined(separator: " \\\n  ")
            guard let text = prepared.bodyText, !text.isEmpty else { return command }
            return "\(command) \\\n  --raw \(shellQuote(text))"
        }
    }

    // MARK: - JavaScript

    static func fetch(_ request: SavedRequest, _ prepared: PreparedRequest) -> String {
        var lines: [String] = []
        let active = headers(prepared, droppingContentTypeFor: request)

        if request.body.type == .multipart {
            lines.append("const form = new FormData()")
            for field in request.body.multipartFields where field.enabled && !field.key.isEmpty {
                if field.kind == .file {
                    lines.append(
                        "form.append(\(js(field.key)), fileInput.files[0])  // \(field.value)"
                    )
                } else {
                    lines.append("form.append(\(js(field.key)), \(js(field.value)))")
                }
            }
            lines.append("")
        }

        lines.append("const response = await fetch(\(js(prepared.url)), {")
        lines.append("  method: \(js(request.method.rawValue)),")
        if !active.isEmpty {
            lines.append("  headers: {")
            for header in active {
                lines.append("    \(js(header.key)): \(js(header.value)),")
            }
            lines.append("  },")
        }
        if let body = jsBodyLiteral(request, prepared) {
            lines.append("  body: \(body),")
        }
        if !request.settings.followRedirects {
            lines.append("  redirect: \"manual\",")
        }
        lines.append("})")
        lines.append("")
        lines.append("const data = await response.json()")
        lines.append("console.log(response.status, data)")
        return lines.joined(separator: "\n")
    }

    static func axios(_ request: SavedRequest, _ prepared: PreparedRequest) -> String {
        var lines: [String] = ["import axios from \"axios\"", ""]
        let active = headers(prepared, droppingContentTypeFor: request)

        if request.body.type == .multipart {
            lines.append("const form = new FormData()")
            for field in request.body.multipartFields where field.enabled && !field.key.isEmpty {
                if field.kind == .file {
                    lines.append(
                        "form.append(\(js(field.key)), fs.createReadStream(\(js(field.value))))"
                    )
                } else {
                    lines.append("form.append(\(js(field.key)), \(js(field.value)))")
                }
            }
            lines.append("")
        }

        lines.append("const response = await axios({")
        lines.append("  method: \(js(request.method.rawValue.lowercased())),")
        lines.append("  url: \(js(prepared.url)),")
        if !active.isEmpty {
            lines.append("  headers: {")
            for header in active {
                lines.append("    \(js(header.key)): \(js(header.value)),")
            }
            lines.append("  },")
        }
        if let body = jsBodyLiteral(request, prepared) {
            lines.append("  data: \(body),")
        }
        lines.append("  timeout: \(Int(request.settings.effectiveTimeout * 1000)),")
        lines.append("  maxRedirects: \(request.settings.followRedirects ? request.settings.maxRedirects : 0),")
        lines.append("})")
        lines.append("")
        lines.append("console.log(response.status, response.data)")
        return lines.joined(separator: "\n")
    }

    static func jsBodyLiteral(_ request: SavedRequest, _ prepared: PreparedRequest) -> String? {
        switch request.body.type {
        case .none:
            return nil
        case .multipart:
            return "form"
        case .binary:
            return "fs.readFileSync(\(js(request.body.binaryFilePath)))"
        case .json, .graphql:
            guard let text = prepared.bodyText, !text.isEmpty else { return nil }
            if let minified = JSONFormatter.minify(text) { return minified }
            return js(text)
        case .raw, .formUrlEncoded:
            guard let text = prepared.bodyText, !text.isEmpty else { return nil }
            return js(text)
        }
    }

    // MARK: - Python

    static func python(_ request: SavedRequest, _ prepared: PreparedRequest) -> String {
        var lines: [String] = ["import requests", ""]
        let active = headers(prepared, droppingContentTypeFor: request)

        if !active.isEmpty {
            lines.append("headers = {")
            for header in active {
                lines.append("    \(py(header.key)): \(py(header.value)),")
            }
            lines.append("}")
            lines.append("")
        }

        var arguments: [String] = [py(prepared.url)]
        if !active.isEmpty { arguments.append("headers=headers") }

        switch request.body.type {
        case .none:
            break
        case .json, .graphql:
            if let text = prepared.bodyText, !text.isEmpty {
                lines.append("payload = \(py(text))")
                lines.append("")
                arguments.append("data=payload")
            }
        case .raw:
            if let text = prepared.bodyText, !text.isEmpty {
                lines.append("payload = \(py(text))")
                lines.append("")
                arguments.append("data=payload")
            }
        case .formUrlEncoded:
            lines.append("data = {")
            for pair in request.body.formFields.activePairs {
                lines.append("    \(py(pair.key)): \(py(pair.value)),")
            }
            lines.append("}")
            lines.append("")
            arguments.append("data=data")
        case .multipart:
            lines.append("files = {")
            for field in request.body.multipartFields where field.enabled && !field.key.isEmpty {
                if field.kind == .file {
                    lines.append("    \(py(field.key)): open(\(py(field.value)), \"rb\"),")
                } else {
                    lines.append("    \(py(field.key)): (None, \(py(field.value))),")
                }
            }
            lines.append("}")
            lines.append("")
            arguments.append("files=files")
        case .binary:
            lines.append("with open(\(py(request.body.binaryFilePath)), \"rb\") as handle:")
            lines.append("    payload = handle.read()")
            lines.append("")
            arguments.append("data=payload")
        }

        arguments.append("timeout=\(Int(request.settings.effectiveTimeout))")
        if !request.settings.validateTLS { arguments.append("verify=False") }
        if !request.settings.followRedirects { arguments.append("allow_redirects=False") }

        let call = "response = requests.\(request.method.rawValue.lowercased())("
        lines.append(call)
        for argument in arguments {
            lines.append("    \(argument),")
        }
        lines.append(")")
        lines.append("")
        lines.append("print(response.status_code, response.text)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Swift

    static func swift(_ request: SavedRequest, _ prepared: PreparedRequest) -> String {
        var lines: [String] = ["import Foundation", ""]
        lines.append("var request = URLRequest(url: URL(string: \(sw(prepared.url)))!)")
        lines.append("request.httpMethod = \(sw(request.method.rawValue))")
        lines.append("request.timeoutInterval = \(Int(request.settings.effectiveTimeout))")

        for header in headers(prepared, droppingContentTypeFor: request) {
            lines.append(
                "request.setValue(\(sw(header.value)), forHTTPHeaderField: \(sw(header.key)))"
            )
        }

        switch request.body.type {
        case .none:
            break
        case .multipart:
            lines.append("// Build the multipart body with the boundary set above.")
        case .binary:
            lines.append(
                "request.httpBody = try Data(contentsOf: URL(fileURLWithPath: \(sw(request.body.binaryFilePath))))"
            )
        case .json, .raw, .graphql, .formUrlEncoded:
            if let text = prepared.bodyText, !text.isEmpty {
                lines.append("request.httpBody = Data(\(sw(text)).utf8)")
            }
        }

        lines.append("")
        lines.append("let (data, response) = try await URLSession.shared.data(for: request)")
        lines.append("print((response as? HTTPURLResponse)?.statusCode ?? 0)")
        lines.append("print(String(data: data, encoding: .utf8) ?? \"\")")
        return lines.joined(separator: "\n")
    }

    // MARK: - Literal escaping

    static func js(_ value: String) -> String {
        var out = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(character)
            }
        }
        return out + "\""
    }

    static func py(_ value: String) -> String {
        if value.contains("\n") {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
            return "\"\"\"\(escaped)\"\"\""
        }
        return js(value)
    }

    static func sw(_ value: String) -> String {
        if value.contains("\n") || value.contains("\"") {
            // Swift's raw string form avoids escaping quotes inside JSON bodies.
            let fence = value.contains("\"#") ? "##" : "#"
            return "\(fence)\"\(value)\"\(fence)"
        }
        return js(value)
    }
}

// MARK: - cURL export convenience

public enum CurlExporter: Sendable {
    /// The cURL tab's one-liner. Kept separate from `CodeGenerator` because the
    /// parser round-trips against it.
    public static func export(
        _ request: SavedRequest,
        scope: VariableScope = .empty,
        dynamic: DynamicVariables = .fixed()
    ) -> String {
        CodeGenerator.generate(.curl, for: request, scope: scope, dynamic: dynamic)
    }

    public static func export(_ request: SavedRequest, environment: ApiEnvironment?) -> String {
        export(request, scope: VariableScope(environment: environment?.variableMap ?? [:]))
    }
}
