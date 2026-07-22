import ADBKit
import Foundation

/// Scoped redactor caching resolved rules per clientId — create one per MCP
/// request so an aggregated read resolves each distinct app's rules once
/// (upstream `createRedactor`). A nil parsed entry means that client is
/// allowed to run unredacted (two-key opt-out granted).
struct McpRedactor {
    private let config: McpRedactionServerConfig
    private let clients: [McpClientRecord]
    private var cache: [String: McpParsedRules?] = [:]

    private static let noClientKey = "\0__no_client__"

    init(config: McpRedactionServerConfig, clients: [McpClientRecord]) {
        self.config = config
        self.clients = clients
    }

    private mutating func parsedRules(for clientId: String?) -> McpParsedRules? {
        let key = clientId ?? Self.noClientKey
        if let cached = cache[key] { return cached }

        let clientConfig: McpRedactionConfig? = if let clientId {
            clients.first { $0.clientId == clientId }?.redaction
        } else if clients.count == 1 {
            clients.first?.redaction
        } else {
            nil
        }
        let rules = McpRedaction.resolveEffectiveRules(server: config, client: clientConfig)
        let parsed = rules.map(McpRedaction.parse)
        cache[key] = parsed
        return parsed
    }

    mutating func redact(_ value: JSONValue, clientId: String?) -> JSONValue {
        guard let parsed = parsedRules(for: clientId) else { return value }
        return McpRedaction.redact(value, parsed: parsed)
    }

    mutating func redactState(_ value: JSONValue, clientId: String?, statePath: String) -> JSONValue {
        guard let parsed = parsedRules(for: clientId) else { return value }
        return McpRedaction.redactState(value, parsed: parsed, statePath: statePath)
    }

    mutating func redactAsyncStorage(_ value: JSONValue, clientId: String?) -> JSONValue {
        guard let parsed = parsedRules(for: clientId) else { return value }
        return McpRedaction.redactAsyncStorage(value, parsed: parsed)
    }
}
