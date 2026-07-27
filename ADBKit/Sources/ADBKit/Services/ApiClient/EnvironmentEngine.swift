import Foundation

public enum EnvironmentEngine: Sendable {
    private static let pattern = try! NSRegularExpression(pattern: "\\{\\{([^}]+)\\}\\}")

    public static func resolve(_ template: String, with variables: [String: String]) -> String {
        guard !variables.isEmpty, template.contains("{{") else { return template }
        let range = NSRange(template.startIndex..., in: template)
        var result = template
        let matches = pattern.matches(in: template, range: range).reversed()
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: template) else { continue }
            let key = String(template[keyRange]).trimmingCharacters(in: .whitespaces)
            if let value = variables[key] {
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: value)
            }
        }
        return result
    }

    public static func resolveRequest(_ request: SavedRequest, with env: ApiEnvironment?) -> SavedRequest {
        guard let env else { return request }
        let vars = env.variableMap
        guard !vars.isEmpty else { return request }

        var resolved = request
        resolved.url = resolve(resolved.url, with: vars)

        resolved.headers = resolved.headers.map { h in
            var h = h
            h.value = resolve(h.value, with: vars)
            return h
        }
        resolved.queryParams = resolved.queryParams.map { p in
            var p = p
            p.key = resolve(p.key, with: vars)
            p.value = resolve(p.value, with: vars)
            return p
        }

        switch resolved.body.type {
        case .json:
            resolved.body.jsonText = resolve(resolved.body.jsonText, with: vars)
        case .raw:
            resolved.body.rawText = resolve(resolved.body.rawText, with: vars)
        case .formUrlEncoded:
            resolved.body.formFields = resolved.body.formFields.map { f in
                var f = f
                f.value = resolve(f.value, with: vars)
                return f
            }
        case .none:
            break
        }

        resolved.auth.bearerToken = resolve(resolved.auth.bearerToken, with: vars)
        resolved.auth.basicUsername = resolve(resolved.auth.basicUsername, with: vars)
        resolved.auth.basicPassword = resolve(resolved.auth.basicPassword, with: vars)
        resolved.auth.apiKeyValue = resolve(resolved.auth.apiKeyValue, with: vars)

        return resolved
    }
}
