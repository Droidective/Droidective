// ReactotronMCP serves the Reactotron relay's data, and that relay is
// `Network.framework`-based, so this whole target is Apple-only until the
// listener moves to NIO or raw sockets (a port follow-up). Gated rather than
// stubbed: off-Apple the module simply exposes nothing.
#if canImport(Network)

import ADBKit
import Foundation

/// Result shaping — the Swift form of upstream `serialization.ts`: compact
/// JSON, hard truncation with LLM guidance, and the per-command summaries the
/// timeline/network reads return.
public enum McpSerialization {
    /// Compact JSON with sorted keys (deterministic for tests and fixtures).
    public static func compactJson(_ value: JSONValue) -> String {
        value.jsonString
    }

    /// Truncate to `limit` characters, appending guidance telling the LLM how
    /// to get a smaller answer (pass a path, filter by type, clear the buffer).
    public static func truncate(_ text: String, limit: Int, guidance: String? = nil) -> String {
        guard text.count > limit else { return text }
        let kilochars = Int((Double(text.count) / 1000).rounded())
        let suffix = if let guidance {
            "\n\n[TRUNCATED — response was ~\(kilochars)K chars. \(guidance)]"
        } else {
            "\n\n[TRUNCATED — response was ~\(kilochars)K chars.]"
        }
        return String(text.prefix(max(0, limit - suffix.count))) + suffix
    }

    /// Compact-serialize then truncate — every tool/resource result goes
    /// through this (upstream `safeSerialize`).
    public static func safeSerialize(
        _ value: JSONValue,
        limit: Int = McpConstants.maxResponseChars,
        guidance: String? = nil
    ) -> String {
        truncate(compactJson(value), limit: limit, guidance: guidance)
    }

    // MARK: - Summaries

    /// Timeline row: metadata + a short type-specific preview, payload
    /// stripped (upstream `summarizeCommand`).
    public static func summarizeCommand(_ buffered: McpBufferedCommand) -> JSONValue {
        let command = buffered.command
        let preview: String = switch command.commandType {
        case .apiResponse: apiResponsePreview(command.payload)
        case .log: logPreview(command.payload)
        case .stateValuesResponse: "path: \(command.payload?["path"]?.stringValue ?? "(root)")"
        case .stateValuesChange: "\(command.payload?["changes"]?.arrayValue?.count ?? 0) change(s)"
        case .stateActionComplete:
            command.payload?["type"]?.stringValue ?? genericPreview(command.payload)
        case .benchmark: command.payload?["title"]?.stringValue ?? "benchmark"
        default: genericPreview(command.payload)
        }

        var summary: [String: JSONValue] = [
            "type": .string(command.type),
            "messageId": .number(Double(buffered.messageId)),
            "important": .bool(command.isImportant),
            "payloadPreview": .string(preview),
        ]
        if let date = command.date { summary["date"] = .string(date) }
        if let deltaTime = command.deltaTime { summary["deltaTime"] = .number(deltaTime) }
        if let clientId = buffered.clientId { summary["clientId"] = .string(clientId) }
        return .object(summary)
    }

    /// Network row: method/url/status/duration/headers + body previews capped
    /// at `maxBodyPreviewChars` (upstream `summarizeNetworkEntry`).
    public static func summarizeNetworkEntry(_ buffered: McpBufferedCommand) -> JSONValue {
        let payload = buffered.command.payload
        let request = payload?["request"]
        let response = payload?["response"]

        var requestSummary: [String: JSONValue] = [:]
        if let method = request?["method"] { requestSummary["method"] = method }
        if let url = request?["url"] { requestSummary["url"] = url }
        if let headers = request?["headers"] { requestSummary["headers"] = headers }
        if let data = request?["data"], !data.isNull {
            requestSummary["data"] = .string(preview(of: data, limit: McpConstants.maxBodyPreviewChars))
        }

        var responseSummary: [String: JSONValue] = [:]
        if let status = response?["status"] { responseSummary["status"] = status }
        if let headers = response?["headers"] { responseSummary["headers"] = headers }
        if let body = response?["body"], !body.isNull {
            responseSummary["body"] = .string(preview(of: body, limit: McpConstants.maxBodyPreviewChars))
        }

        var entry: [String: JSONValue] = [
            "messageId": .number(Double(buffered.messageId)),
            "request": .object(requestSummary),
            "response": .object(responseSummary),
        ]
        if let clientId = buffered.clientId { entry["clientId"] = .string(clientId) }
        if let date = buffered.command.date { entry["date"] = .string(date) }
        if let duration = payload?["duration"] { entry["duration"] = duration }
        return .object(entry)
    }

    // MARK: - Previews

    private static func apiResponsePreview(_ payload: JSONValue?) -> String {
        let method = payload?["request"]?["method"]?.stringValue ?? "?"
        let url = payload?["request"]?["url"]?.stringValue ?? "?"
        let status = payload?["response"]?["status"]?.intValue.map(String.init) ?? "?"
        let duration = payload?["duration"]?.doubleValue.map { " (\(Self.milliseconds($0))ms)" } ?? ""
        return "\(method) \(url) -> \(status)\(duration)"
    }

    private static func milliseconds(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }

    private static func logPreview(_ payload: JSONValue?) -> String {
        let level = payload?["level"]?.stringValue ?? "log"
        let message: String = if let text = payload?["message"]?.stringValue {
            text
        } else if let value = payload?["message"] {
            value.compactPreview(maxLength: McpConstants.maxPayloadPreviewChars)
        } else {
            ""
        }
        let capped = message.count > McpConstants.maxPayloadPreviewChars
            ? String(message.prefix(McpConstants.maxPayloadPreviewChars)) + "..."
            : message
        return "[\(level)] \(capped)"
    }

    private static func genericPreview(_ payload: JSONValue?) -> String {
        guard let payload, !payload.isNull else { return "" }
        let text = payload.compactPreview(maxLength: McpConstants.maxPayloadPreviewChars + 1)
        return text.count > McpConstants.maxPayloadPreviewChars
            ? String(text.prefix(McpConstants.maxPayloadPreviewChars)) + "..."
            : text
    }

    /// A capped preview of any value: strings stay raw, everything else goes
    /// through compact JSON (upstream `truncateValue`).
    static func preview(of value: JSONValue, limit: Int) -> String {
        let text = value.stringValue ?? value.compactPreview(maxLength: limit + 1)
        return text.count > limit ? String(text.prefix(limit)) + "..." : text
    }
}

#endif
