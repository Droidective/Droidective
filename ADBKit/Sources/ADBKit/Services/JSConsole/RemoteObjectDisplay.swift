import Foundation

/// A syntax-colorable span of a rendered value. `kind` is semantic (UI-free);
/// the App maps it to a color, so ADBKit stays free of SwiftUI.
public enum JSTokenKind: Sendable, Equatable {
    case string, number, boolean, null, undefined, function, symbol
    case key, className, punctuation, plain
}

public struct JSToken: Sendable, Equatable {
    public let text: String
    public let kind: JSTokenKind

    public init(_ text: String, _ kind: JSTokenKind) {
        self.text = text
        self.kind = kind
    }
}

/// Where a value is being rendered, which is what decides whether a string is
/// quoted. Chrome prints a *top-level* `console.log` string argument bare
/// (`console.log('hi')` → `hi`, newlines and all) and quotes strings
/// everywhere else — nested in a preview, or returned from the prompt.
public enum JSRenderStyle: Sendable, Equatable {
    case value
    case consoleArgument
}

/// Pure value→tokens rendering for the console, tuned to how **Hermes** (not V8)
/// serializes over CDP: `bigint` arrives as `type: ""`, `-0`/`Infinity`/`NaN` as
/// `unserializableValue` with no `value`, and `Date`/`Map`/`Set`/`RegExp` as
/// plain `"Object"` (Hermes doesn't tag those subtypes). Kept here so it's
/// unit-tested against recorded payloads.
public extension RemoteObject {
    /// The compact one-line rendering as colorable tokens, quoting strings.
    var tokens: [JSToken] { tokens(style: .value) }

    /// The compact one-line rendering as colorable tokens.
    func tokens(style: JSRenderStyle) -> [JSToken] {
        switch type {
        case "string":
            let text = ConsoleANSI.strip(value?.stringValue ?? description ?? "")
            return style == .consoleArgument
                ? [JSToken(text, .plain)]
                : [JSToken(Self.quoted(text), .string)]
        case "boolean":
            return [JSToken(description ?? value.map(CDP.displayString) ?? "false", .boolean)]
        case "number":
            return [JSToken(numberString, .number)]
        case "undefined":
            return [JSToken("undefined", .undefined)]
        case "symbol":
            return [JSToken(description ?? "Symbol()", .symbol)]
        case "function":
            return [JSToken(Self.functionSummary(description), .function)]
        case "object":
            return objectTokens
        default:
            // Hermes reports bigint as `type: ""` — value is in description.
            return [JSToken(description ?? unserializableValue ?? value.map(CDP.displayString) ?? type, .number)]
        }
    }

    /// The plain one-line summary — the tokens joined. Used for search, find,
    /// and copy, so they never diverge from what's shown.
    var inlineSummary: String { inlineSummary(style: .value) }

    func inlineSummary(style: JSRenderStyle) -> String {
        tokens(style: style).map(\.text).joined()
    }

    /// `inlineSummary` bounded to roughly `limit` characters. String values
    /// take a prefix without materializing the full value — a multi-megabyte
    /// `console.log` string must not be copied whole just to index its head
    /// (that copy, once per replayed entry, was the reload CPU spike).
    /// Non-string values are already small (object previews are truncated on
    /// the device).
    func inlineSummary(limit: Int, style: JSRenderStyle = .value) -> String {
        if type == "string", let text = value?.stringValue, text.utf8.count > limit {
            // Strip the prefix, not the whole value — the point of this path is
            // never to walk a multi-megabyte string.
            let head = ConsoleANSI.strip(String(text.prefix(limit)))
            return style == .consoleArgument ? head : "\"\(head)"
        }
        let full = inlineSummary(style: style)
        return full.utf8.count <= limit ? full : String(full.prefix(limit))
    }

    /// A rough retained-size estimate in bytes — the string payloads dominate;
    /// O(1) on native strings. Drives the console buffer's byte budget.
    var approximateBytes: Int {
        (value?.stringValue?.utf8.count ?? 0) + (description?.utf8.count ?? 0) + 512
    }

    private var numberString: String {
        // -0 / Infinity / NaN come back via description/unserializableValue.
        description ?? value.map(CDP.displayString) ?? unserializableValue ?? "0"
    }

    private var objectTokens: [JSToken] {
        if subtype == "null" { return [JSToken("null", .null)] }
        if subtype == "error" {
            let message = description?.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "Error"
            return [JSToken(message, .plain)]
        }
        if let preview { return Self.previewTokens(preview) }
        // No preview: Hermes replays its buffered console history without one,
        // so the whole pre-connect backlog lands here. `Array(2)` or a class
        // name still says something; the bare word "Object" says less than
        // Chrome's `{…}`, which reads as "open me".
        if let description, description != "Object" { return [JSToken(description, .className)] }
        if let className, className != "Object" { return [JSToken(className, .className)] }
        return [JSToken("{…}", .punctuation)]
    }

    /// Chrome's string literal: single quotes, switching to double quotes when
    /// the text already contains one, with the escapes a one-line preview needs
    /// so a logged multi-line string can't break the row into several.
    static func quoted(_ text: String) -> String {
        var escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        if escaped.contains("'"), !escaped.contains("\"") { return "\"\(escaped)\"" }
        escaped = escaped.replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    /// "function adder(a0, a1) { [bytecode] }" → "ƒ adder(a0, a1)".
    static func functionSummary(_ description: String?) -> String {
        guard let description, !description.isEmpty else { return "ƒ ()" }
        let head = description.split(separator: "{", maxSplits: 1).first.map(String.init) ?? description
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        let body = trimmed.hasPrefix("function ") ? String(trimmed.dropFirst("function ".count)) : trimmed
        return body.isEmpty ? "ƒ ()" : "ƒ \(body)"
    }

    static func previewTokens(_ preview: ObjectPreview) -> [JSToken] {
        if preview.subtype == "array" || preview.description?.hasPrefix("Array(") == true {
            var tokens: [JSToken] = []
            // Chrome leads a multi-element array with its length — `(3) [1, 2, 3]`
            // — and leaves `[]` / `[x]` to speak for themselves.
            if let count = arrayLength(preview), count > 1 {
                tokens.append(JSToken("(\(count)) ", .className))
            }
            tokens.append(JSToken("[", .punctuation))
            for (index, property) in preview.properties.enumerated() {
                if index > 0 { tokens.append(JSToken(", ", .punctuation)) }
                tokens.append(elementToken(property))
            }
            if preview.overflow { tokens.append(JSToken(", …", .punctuation)) }
            tokens.append(JSToken("]", .punctuation))
            return tokens
        }
        if preview.subtype == "error" {
            return [JSToken(preview.description ?? "Error", .plain)]
        }
        var tokens: [JSToken] = []
        let className = preview.description ?? ""
        if !className.isEmpty, className != "Object" { tokens.append(JSToken("\(className) ", .className)) }
        tokens.append(JSToken("{", .punctuation))
        for (index, property) in preview.properties.enumerated() {
            if index > 0 { tokens.append(JSToken(", ", .punctuation)) }
            tokens.append(JSToken(property.name, .key))
            tokens.append(JSToken(": ", .punctuation))
            tokens.append(elementToken(property))
        }
        if preview.overflow { tokens.append(JSToken(", …", .punctuation)) }
        tokens.append(JSToken("}", .punctuation))
        return tokens
    }

    /// The element count out of an array preview's `Array(n)` description.
    private static func arrayLength(_ preview: ObjectPreview) -> Int? {
        guard let description = preview.description,
              description.hasPrefix("Array("), description.hasSuffix(")") else { return nil }
        return Int(description.dropFirst("Array(".count).dropLast())
    }

    private static func elementToken(_ property: PropertyPreview) -> JSToken {
        switch property.type {
        case "string": JSToken(quoted(ConsoleANSI.strip(property.value ?? "")), .string)
        case "number", "bigint": JSToken(property.value ?? "", .number)
        case "boolean": JSToken(property.value ?? "", .boolean)
        case "undefined": JSToken("undefined", .undefined)
        case "symbol": JSToken(property.value ?? "Symbol()", .symbol)
        case "function": JSToken("ƒ", .function)
        case "object":
            if property.subtype == "null" {
                JSToken("null", .null)
            } else if let value = property.value, value != "Object" {
                // `Array(3)`, or a class name — Chrome shows both verbatim.
                JSToken(value, .className)
            } else {
                // A plain nested object is Chrome's `{…}`, not the word "Object".
                JSToken("{…}", .punctuation)
            }
        default: JSToken(property.value ?? "", .plain)
        }
    }
}

public extension CDP {
    /// Plain rendering of a decoded JSON value (for primitives carried in
    /// `RemoteObject.value`). Guards against `Int(NaN/Infinity)`.
    static func displayString(_ value: JSONValue) -> String {
        switch value {
        case let .number(number):
            return (number.isFinite && number == number.rounded()) ? String(Int(number)) : String(number)
        case let .bool(flag): return String(flag)
        case let .string(text): return text
        case .null: return "null"
        default: return value.jsonString
        }
    }
}
