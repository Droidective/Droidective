// ReactotronMCP serves the Reactotron relay's data, and that relay is
// `Network.framework`-based, so this whole target is Apple-only until the
// listener moves to NIO or raw sockets (a port follow-up). Gated rather than
// stubbed: off-Apple the module simply exposes nothing.
#if canImport(Network)

import ADBKit
import Foundation

/// Redaction rule set — the Swift form of upstream's `McpRedactionRules`
/// (`reactotron-core-contract/src/mcpRedaction.ts`).
public struct McpRedactionRules: Sendable, Equatable, Codable {
    public var sensitiveKeys: [String]
    public var statePathPatterns: [String]
    public var valuePatterns: [String]

    public init(
        sensitiveKeys: [String] = [],
        statePathPatterns: [String] = [],
        valuePatterns: [String] = []
    ) {
        self.sensitiveKeys = sensitiveKeys
        self.statePathPatterns = statePathPatterns
        self.valuePatterns = valuePatterns
    }
}

/// A client's redaction wishes, sent as `mcpRedaction` inside `client.intro` —
/// upstream's `McpRedactionConfig`. `removeRules`/`disableRedaction` only take
/// effect when the matching server-side permission is on (the two-key model).
public struct McpRedactionConfig: Sendable, Equatable {
    public var disableRedaction: Bool
    public var additionalRules: McpRedactionRules?
    public var removeRules: McpRedactionRules?

    public init(
        disableRedaction: Bool = false,
        additionalRules: McpRedactionRules? = nil,
        removeRules: McpRedactionRules? = nil
    ) {
        self.disableRedaction = disableRedaction
        self.additionalRules = additionalRules
        self.removeRules = removeRules
    }

    /// Lenient parse from the `client.intro` payload's `mcpRedaction` field.
    /// Nil when the field is absent or not an object — never fails the intro.
    public init?(json: JSONValue?) {
        guard let object = json?.objectValue else { return nil }
        disableRedaction = object["disableRedaction"]?.boolValue ?? false
        additionalRules = Self.rules(from: object["additionalRules"])
        removeRules = Self.rules(from: object["removeRules"])
    }

    private static func rules(from json: JSONValue?) -> McpRedactionRules? {
        guard let object = json?.objectValue else { return nil }
        func strings(_ key: String) -> [String] {
            object[key]?.arrayValue?.compactMap(\.stringValue) ?? []
        }
        return McpRedactionRules(
            sensitiveKeys: strings("sensitiveKeys"),
            statePathPatterns: strings("statePathPatterns"),
            valuePatterns: strings("valuePatterns")
        )
    }
}

/// Server-side redaction posture — upstream's `McpRedactionServerConfig`.
public struct McpRedactionServerConfig: Sendable, Equatable, Codable {
    public var defaults: McpRedactionRules
    public var allowClientDisable: Bool
    public var allowClientRemoveRules: Bool

    public init(
        defaults: McpRedactionRules = McpRedaction.defaultRules,
        allowClientDisable: Bool = false,
        allowClientRemoveRules: Bool = false
    ) {
        self.defaults = defaults
        self.allowClientDisable = allowClientDisable
        self.allowClientRemoveRules = allowClientRemoveRules
    }

    /// Upstream `DEFAULT_SERVER_CONFIG`: default rules on, both opt-out
    /// permissions off.
    public static let standard = McpRedactionServerConfig()
}

/// Rules compiled for repeated application. `NSRegularExpression` is immutable
/// and documented thread-safe, hence the unchecked conformance.
public struct McpParsedRules: @unchecked Sendable {
    let sensitiveKeysLower: Set<String>
    /// All valid `valuePatterns` folded into one alternation (upstream
    /// `compileCombinedValueRegex`); nil when none compile.
    let combinedValueRegex: NSRegularExpression?
    let statePathPatterns: [String]
    /// Gates path-string allocation — only pay for it when patterns exist.
    let trackPaths: Bool
}

/// The redaction engine — a pure port of upstream `redaction.ts`, applied at
/// the MCP boundary only (the Droidective UI stays unredacted, like the
/// Reactotron desktop). Everything operates on `JSONValue`, so there are no
/// circular references to defend against (upstream's `seen` set has no
/// equivalent here by construction).
public enum McpRedaction {
    public static let redactedMarker = "[REDACTED]"

    static let maxJsonStringDepth = 5
    static let maxJsonParseLength = 1_000_000
    static let maxFormEncodedLength = 8192

    /// Upstream `DEFAULT_REDACTION_RULES`, verbatim.
    public static let defaultRules = McpRedactionRules(
        sensitiveKeys: [
            // Credentials
            "password", "passwd", "pwd",
            "secret", "client_secret", "clientsecret",
            "credentials", "ssn", "creditcard",
            "privatekey", "private_key",
            // API keys
            "apikey", "api_key", "x-api-key",
            // Auth tokens
            "accesstoken", "access_token",
            "refreshtoken", "refresh_token",
            "idtoken", "id_token",
            "token", "bearer", "jwt",
            // Session / CSRF
            "session", "sessionid", "session_id",
            "csrf", "xsrf", "csrf_token", "xsrf_token",
            // HTTP headers
            "authorization", "cookie", "set-cookie", "proxy-authorization",
            "x-auth-token", "x-csrf-token", "x-xsrf-token", "csrf-token",
            "x-forwarded-for", "x-real-ip",
        ],
        statePathPatterns: [],
        valuePatterns: [
            // Bearer tokens
            #"Bearer\s+[A-Za-z0-9\-._~+/]+=*"#,
            // JWTs (header.payload[.signature])
            #"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#,
            // OpenAI-style keys
            #"sk-[a-zA-Z0-9_-]{20,}"#,
            // Anthropic API keys
            #"sk-ant-[a-zA-Z0-9_-]{20,}"#,
            // GitHub PATs / fine-grained tokens
            #"gh[pousr]_[A-Za-z0-9]{30,}"#,
            // Slack tokens
            #"xox[bpoas]-[a-zA-Z0-9\-]{10,}"#,
            // AWS access key IDs
            #"AKIA[0-9A-Z]{16}"#,
            // Google API keys
            #"AIza[0-9A-Za-z\-_]{35}"#,
            // Stripe keys (live/test, secret/publishable/restricted)
            #"(?:sk|pk|rk)_(?:test|live)_[A-Za-z0-9]{24,}"#,
            // PEM-encoded private key blocks
            #"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----[\s\S]+?-----END (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----"#,
        ]
    )

    // MARK: - Rule resolution (the two-key model)

    /// Merge server defaults with a client's config. `additionalRules` apply
    /// unconditionally; `disableRedaction`/`removeRules` need the matching
    /// server permission. Nil result = redaction disabled for this client.
    public static func resolveEffectiveRules(
        server: McpRedactionServerConfig,
        client: McpRedactionConfig?
    ) -> McpRedactionRules? {
        guard let client else { return server.defaults }
        if client.disableRedaction, server.allowClientDisable { return nil }
        var rules = server.defaults
        if let remove = client.removeRules, server.allowClientRemoveRules {
            rules = subtract(rules, removing: remove)
        }
        if let additional = client.additionalRules {
            rules = merge(rules, adding: additional)
        }
        return rules
    }

    static func merge(_ base: McpRedactionRules, adding additional: McpRedactionRules) -> McpRedactionRules {
        McpRedactionRules(
            sensitiveKeys: dedupe(base.sensitiveKeys + additional.sensitiveKeys),
            statePathPatterns: dedupe(base.statePathPatterns + additional.statePathPatterns),
            valuePatterns: dedupe(base.valuePatterns + additional.valuePatterns)
        )
    }

    static func subtract(_ base: McpRedactionRules, removing remove: McpRedactionRules) -> McpRedactionRules {
        let removeKeys = Set(remove.sensitiveKeys.map { $0.lowercased() })
        let removePaths = Set(remove.statePathPatterns)
        let removePatterns = Set(remove.valuePatterns)
        return McpRedactionRules(
            sensitiveKeys: base.sensitiveKeys.filter { !removeKeys.contains($0.lowercased()) },
            statePathPatterns: base.statePathPatterns.filter { !removePaths.contains($0) },
            valuePatterns: base.valuePatterns.filter { !removePatterns.contains($0) }
        )
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: - Compilation

    /// Validate each pattern individually so one bad regex doesn't kill the
    /// rest, then fold survivors into a single alternation.
    public static func parse(_ rules: McpRedactionRules) -> McpParsedRules {
        let valid = rules.valuePatterns.filter {
            (try? NSRegularExpression(pattern: $0)) != nil
        }
        let combined = valid.isEmpty
            ? nil
            : try? NSRegularExpression(pattern: valid.map { "(?:\($0))" }.joined(separator: "|"))
        return McpParsedRules(
            sensitiveKeysLower: Set(rules.sensitiveKeys.map { $0.lowercased() }),
            combinedValueRegex: combined,
            statePathPatterns: rules.statePathPatterns,
            trackPaths: !rules.statePathPatterns.isEmpty
        )
    }

    // MARK: - Redaction

    /// Deep-redact a generic payload (network entry, log event, action…).
    public static func redact(_ value: JSONValue, parsed: McpParsedRules) -> JSONValue {
        redactValue(value, parsed: parsed, currentPath: "", jsonStringDepth: 0)
    }

    /// Redact a state payload anchored at `statePath` ("" for the full tree),
    /// so `statePathPatterns` written against the whole tree still line up
    /// when the app returned a subtree.
    public static func redactState(
        _ value: JSONValue, parsed: McpParsedRules, statePath: String
    ) -> JSONValue {
        redactValue(value, parsed: parsed, currentPath: statePath, jsonStringDepth: 0)
    }

    /// Redact an AsyncStorage mutation payload: the *storage key* carries the
    /// sensitive name (`auth:password`), so match keys by substring first,
    /// then deep-walk whatever remains.
    public static func redactAsyncStorage(_ value: JSONValue, parsed: McpParsedRules) -> JSONValue {
        guard !parsed.sensitiveKeysLower.isEmpty else { return value }
        return redact(redactAsyncStorageItem(value, parsed: parsed), parsed: parsed)
    }

    private static func redactValue(
        _ value: JSONValue, parsed: McpParsedRules, currentPath: String, jsonStringDepth: Int
    ) -> JSONValue {
        switch value {
        case .null, .bool, .number:
            return value
        case let .string(text):
            return .string(redactString(text, parsed: parsed, jsonStringDepth: jsonStringDepth))
        case let .array(items):
            if !parsed.trackPaths {
                return .array(items.map {
                    redactValue($0, parsed: parsed, currentPath: "", jsonStringDepth: jsonStringDepth)
                })
            }
            return .array(items.enumerated().map { index, item in
                let childPath = currentPath.isEmpty ? String(index) : "\(currentPath).\(index)"
                return redactValue(
                    item, parsed: parsed, currentPath: childPath, jsonStringDepth: jsonStringDepth)
            })
        case let .object(dict):
            var result: [String: JSONValue] = [:]
            result.reserveCapacity(dict.count)
            for (key, child) in dict {
                if parsed.sensitiveKeysLower.contains(key.lowercased()) {
                    result[key] = .string(redactedMarker)
                    continue
                }
                if parsed.trackPaths {
                    let childPath = currentPath.isEmpty ? key : "\(currentPath).\(key)"
                    if matchesStatePath(childPath, patterns: parsed.statePathPatterns) {
                        result[key] = .string(redactedMarker)
                        continue
                    }
                    result[key] = redactValue(
                        child, parsed: parsed, currentPath: childPath, jsonStringDepth: jsonStringDepth)
                } else {
                    result[key] = redactValue(
                        child, parsed: parsed, currentPath: "", jsonStringDepth: jsonStringDepth)
                }
            }
            return .object(result)
        }
    }

    static func redactString(
        _ value: String, parsed: McpParsedRules, jsonStringDepth: Int
    ) -> String {
        var result = value

        // JSON embedded in a string: parse → redact → re-stringify, guarded by
        // depth (nested stringify layers) and size (don't parse huge strings).
        if jsonStringDepth < maxJsonStringDepth, result.count <= maxJsonParseLength {
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            let looksLikeJson = (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
                || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
            if looksLikeJson,
               let inner = try? JSONDecoder().decode(JSONValue.self, from: Data(result.utf8)),
               inner.objectValue != nil || inner.arrayValue != nil {
                let redacted = redactValue(
                    inner, parsed: parsed, currentPath: "", jsonStringDepth: jsonStringDepth + 1)
                return redacted.jsonString
            }
        }

        if !parsed.sensitiveKeysLower.isEmpty {
            if result.contains("?") {
                result = redactUrlQueryParams(result, sensitiveKeysLower: parsed.sensitiveKeysLower)
            } else if looksLikeFormEncoded(result) {
                result = redactFormEncodedParams(result, sensitiveKeysLower: parsed.sensitiveKeysLower)
            }
        }

        if let regex = parsed.combinedValueRegex {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: redactedMarker
            )
        }
        return result
    }

    /// Detect a form-urlencoded body ("user=alice&password=x"). The strict
    /// `^k=v(&k=v)*$` anchor avoids false positives on prose like "x=5".
    private static let formEncodedRegex = try? NSRegularExpression(
        pattern: #"^[\w.\-+~*\[\]%]+=[^&]*(?:&[\w.\-+~*\[\]%]+=[^&]*)*$"#
    )

    static func looksLikeFormEncoded(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= maxFormEncodedLength,
              let regex = formEncodedRegex else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    static func redactFormEncodedParams(_ value: String, sensitiveKeysLower: Set<String>) -> String {
        value.components(separatedBy: "&").map { param in
            redactParam(param, sensitiveKeysLower: sensitiveKeysLower)
        }.joined(separator: "&")
    }

    static func redactUrlQueryParams(_ value: String, sensitiveKeysLower: Set<String>) -> String {
        guard let questionIndex = value.firstIndex(of: "?") else { return value }
        let base = String(value[...questionIndex])
        let queryString = String(value[value.index(after: questionIndex)...])

        let query: String
        let fragment: String
        if let hashIndex = queryString.firstIndex(of: "#") {
            query = String(queryString[..<hashIndex])
            fragment = String(queryString[hashIndex...])
        } else {
            query = queryString
            fragment = ""
        }

        let redacted = query.components(separatedBy: "&").map { param in
            redactParam(param, sensitiveKeysLower: sensitiveKeysLower)
        }.joined(separator: "&")
        return base + redacted + fragment
    }

    private static func redactParam(_ param: String, sensitiveKeysLower: Set<String>) -> String {
        guard let equalsIndex = param.firstIndex(of: "=") else { return param }
        let name = String(param[..<equalsIndex])
        guard sensitiveKeysLower.contains(name.lowercased()) else { return param }
        return "\(name)=\(redactedMarker)"
    }

    static func matchesStatePath(_ currentPath: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if pattern.hasSuffix(".*") {
                let prefix = String(pattern.dropLast(2))
                // "auth.tokens.*" matches "auth.tokens.access" but NOT
                // "auth.tokens" itself.
                if currentPath.hasPrefix(prefix + "."), currentPath.count > prefix.count + 1 {
                    return true
                }
            } else if currentPath == pattern {
                return true
            }
        }
        return false
    }

    // MARK: - AsyncStorage shapes

    static func storageKeyIsSensitive(_ storageKey: String, sensitiveKeysLower: Set<String>) -> Bool {
        let keyLower = storageKey.lowercased()
        return sensitiveKeysLower.contains { keyLower.contains($0) }
    }

    private static func redactAsyncStorageItem(_ value: JSONValue, parsed: McpParsedRules) -> JSONValue {
        // [key, value] tuple from a multiSet/multiMerge `pairs` entry.
        if let pair = value.arrayValue, pair.count == 2, let key = pair[0].stringValue {
            if storageKeyIsSensitive(key, sensitiveKeysLower: parsed.sensitiveKeysLower) {
                return .array([.string(key), .string(redactedMarker)])
            }
            if let text = pair[1].stringValue {
                return .array([
                    .string(key),
                    .string(redactString(text, parsed: parsed, jsonStringDepth: 0)),
                ])
            }
            return value
        }

        guard var object = value.objectValue else { return value }

        // multiSet / multiMerge: { pairs: [[key, value], ...] }
        if let pairs = object["pairs"]?.arrayValue {
            object["pairs"] = .array(pairs.map { redactAsyncStorageItem($0, parsed: parsed) })
            return .object(object)
        }

        // setItem / mergeItem: { key, value }
        if let key = object["key"]?.stringValue {
            if storageKeyIsSensitive(key, sensitiveKeysLower: parsed.sensitiveKeysLower),
               object["value"] != nil {
                object["value"] = .string(redactedMarker)
            } else if let text = object["value"]?.stringValue {
                object["value"] = .string(redactString(text, parsed: parsed, jsonStringDepth: 0))
            }
            return .object(object)
        }

        return value
    }
}

#endif
