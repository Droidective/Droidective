import Foundation

/// A fully type-erased JSON value — the Swift stand-in for Reactotron's
/// arbitrary `payload: any`. Lets the protocol layer decode any command frame
/// without knowing every payload shape, then pick fields out per command type.
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

public extension JSONValue {
    var stringValue: String? { if case let .string(value) = self { return value }; return nil }
    var doubleValue: Double? { if case let .number(value) = self { return value }; return nil }
    var intValue: Int? { if case let .number(value) = self { return Int(value) }; return nil }
    var boolValue: Bool? { if case let .bool(value) = self { return value }; return nil }
    var arrayValue: [JSONValue]? { if case let .array(value) = self { return value }; return nil }
    var objectValue: [String: JSONValue]? { if case let .object(value) = self { return value }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }

    subscript(key: String) -> JSONValue? { objectValue?[key] }

    /// Compact JSON for the timeline (sorted keys, unescaped slashes). Reactotron
    /// serializes functions and some special values as `"~~~ … ~~~"` string
    /// markers; unwrap them so the display reads like Reactotron's desktop —
    /// e.g. `register()`, `null`, `false` instead of quoted marker strings.
    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text.replacing(/"~~~ (.+?) ~~~"/) { match in String(match.1) }
    }

    /// Pretty-printed (indented) JSON for the expandable object preview, with the
    /// same `~~~ … ~~~` marker repair as `jsonString`.
    var prettyJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text.replacing(/"~~~ (.+?) ~~~"/) { match in String(match.1) }
    }

    /// A bounded compact-JSON preview: reads like `jsonString` (sorted keys,
    /// `~~~ … ~~~` markers unwrapped) but STOPS serializing once `maxLength`
    /// characters are produced, so previewing a row costs O(maxLength) no
    /// matter how big the payload is — `jsonString` walks the whole value,
    /// which stalls the parse thread on a multi-megabyte `console.log`. The
    /// result may cut off mid-token; it's a preview, not valid JSON.
    func compactPreview(maxLength: Int) -> String {
        var out = ""
        out.reserveCapacity(min(maxLength, 512))
        var remaining = maxLength
        appendCompact(to: &out, remaining: &remaining)
        return out
    }

    private func appendCompact(to out: inout String, remaining: inout Int) {
        guard remaining > 0 else { return }
        func emit(_ chunk: String) {
            let piece = chunk.count <= remaining ? chunk : String(chunk.prefix(remaining))
            out += piece
            remaining -= piece.count
        }
        switch self {
        case .null:
            emit("null")
        case let .bool(flag):
            emit(flag ? "true" : "false")
        case let .number(number):
            emit(number.truncatingRemainder(dividingBy: 1) == 0 && abs(number) < 9e15
                ? String(Int(number)) : String(number))
        case let .string(text):
            // The prefix/suffix guard keeps the anchored regex off megabyte
            // strings — markers are short serialized functions/values.
            if text.count < 2048, text.hasPrefix("~~~ "), text.hasSuffix(" ~~~"),
               let marker = text.wholeMatch(of: /~~~ (.+) ~~~/) {
                emit(String(marker.1))
            } else {
                emit("\"")
                emit(Self.escapeForPreview(text, maxLength: remaining))
                emit("\"")
            }
        case let .array(items):
            emit("[")
            for (index, item) in items.enumerated() {
                guard remaining > 0 else { return }
                if index > 0 { emit(",") }
                item.appendCompact(to: &out, remaining: &remaining)
            }
            emit("]")
        case let .object(dict):
            emit("{")
            // Sorted keys match `jsonString` for stable previews, but sorting
            // a pathological 100k-key object isn't worth it — dictionary
            // order is fine once nothing human is reading every key anyway.
            let keys = dict.count <= 128 ? dict.keys.sorted() : Array(dict.keys)
            for (index, key) in keys.enumerated() {
                guard remaining > 0 else { return }
                if index > 0 { emit(",") }
                emit("\"")
                emit(Self.escapeForPreview(key, maxLength: remaining))
                emit("\":")
                dict[key]?.appendCompact(to: &out, remaining: &remaining)
            }
            emit("}")
        }
    }

    /// Minimal JSON string escaping over at most `maxLength` characters of
    /// input — never walks a megabyte string to preview its head.
    private static func escapeForPreview(_ text: String, maxLength: Int) -> String {
        var out = ""
        for character in text.prefix(maxLength) {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        return out
    }
}
