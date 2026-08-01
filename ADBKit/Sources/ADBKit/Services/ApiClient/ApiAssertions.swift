import Foundation

// MARK: - Target

/// What an assertion looks at. Postman expresses tests as JavaScript; this is
/// the declarative subset that covers what those scripts almost always do,
/// without shipping a JS engine.
public enum AssertionTarget: Sendable, Equatable, Hashable {
    case statusCode
    case responseTimeMs
    case bodySize
    case bodyText
    case header(String)
    /// Dotted path with array indices — `data.items[0].id`, `$.ok`, `["a.b"]`.
    case jsonPath(String)

    public var label: String {
        switch self {
        case .statusCode: return "status code"
        case .responseTimeMs: return "response time (ms)"
        case .bodySize: return "body size (bytes)"
        case .bodyText: return "body text"
        case .header(let name): return "header \(name.isEmpty ? "—" : name)"
        case .jsonPath(let path): return "json \(path.isEmpty ? "—" : path)"
        }
    }

    /// Argument-carrying targets keep their argument when the UI switches kind.
    public var argument: String {
        switch self {
        case .header(let name): return name
        case .jsonPath(let path): return path
        default: return ""
        }
    }
}

extension AssertionTarget: Codable {
    private enum CodingKeys: String, CodingKey { case kind, argument }
    private enum Kind: String, Codable {
        case statusCode, responseTimeMs, bodySize, bodyText, header, jsonPath
    }

    public var kindName: String {
        switch self {
        case .statusCode: return Kind.statusCode.rawValue
        case .responseTimeMs: return Kind.responseTimeMs.rawValue
        case .bodySize: return Kind.bodySize.rawValue
        case .bodyText: return Kind.bodyText.rawValue
        case .header: return Kind.header.rawValue
        case .jsonPath: return Kind.jsonPath.rawValue
        }
    }

    /// Rebuilds a target from the UI's kind picker plus its argument field.
    public static func make(kindName: String, argument: String) -> AssertionTarget {
        switch Kind(rawValue: kindName) {
        case .responseTimeMs: return .responseTimeMs
        case .bodySize: return .bodySize
        case .bodyText: return .bodyText
        case .header: return .header(argument)
        case .jsonPath: return .jsonPath(argument)
        case .statusCode, nil: return .statusCode
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? Kind.statusCode.rawValue
        let argument = try c.decodeIfPresent(String.self, forKey: .argument) ?? ""
        self = .make(kindName: kind, argument: argument)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kindName, forKey: .kind)
        let argument = self.argument
        if !argument.isEmpty { try c.encode(argument, forKey: .argument) }
    }
}

// MARK: - Operator

public enum AssertionOperator: String, Codable, Sendable, CaseIterable {
    case equals
    case notEquals
    case contains
    case notContains
    case matchesRegex
    case lessThan
    case greaterThan
    case exists
    case notExists
    case isEmpty
    case isNotEmpty

    public var label: String {
        switch self {
        case .equals: return "equals"
        case .notEquals: return "does not equal"
        case .contains: return "contains"
        case .notContains: return "does not contain"
        case .matchesRegex: return "matches regex"
        case .lessThan: return "is less than"
        case .greaterThan: return "is greater than"
        case .exists: return "exists"
        case .notExists: return "does not exist"
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        }
    }

    /// Operators that ignore the expected-value field.
    public var isUnary: Bool {
        switch self {
        case .exists, .notExists, .isEmpty, .isNotEmpty: return true
        default: return false
        }
    }
}

// MARK: - Assertion

public struct ApiAssertion: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var enabled: Bool
    public var target: AssertionTarget
    public var op: AssertionOperator
    public var expected: String

    public init(
        id: String = UUID().uuidString,
        enabled: Bool = true,
        target: AssertionTarget = .statusCode,
        op: AssertionOperator = .equals,
        expected: String = "200"
    ) {
        self.id = id
        self.enabled = enabled
        self.target = target
        self.op = op
        self.expected = expected
    }

    public var label: String {
        op.isUnary
            ? "\(target.label) \(op.label)"
            : "\(target.label) \(op.label) \(expected)"
    }

    private enum CodingKeys: String, CodingKey { case id, enabled, target, op, expected }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        target = try c.decodeIfPresent(AssertionTarget.self, forKey: .target) ?? .statusCode
        op = try c.decodeIfPresent(AssertionOperator.self, forKey: .op) ?? .equals
        expected = try c.decodeIfPresent(String.self, forKey: .expected) ?? ""
    }
}

public struct AssertionResult: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var passed: Bool
    /// What was actually found, for the failure row.
    public var detail: String

    public init(id: String, label: String, passed: Bool, detail: String) {
        self.id = id
        self.label = label
        self.passed = passed
        self.detail = detail
    }
}

// MARK: - Evaluation

public enum ApiAssertions: Sendable {

    public static func evaluate(
        _ assertions: [ApiAssertion], against response: ApiResponse
    ) -> [AssertionResult] {
        assertions.filter(\.enabled).map { evaluate($0, against: response) }
    }

    public static func evaluate(
        _ assertion: ApiAssertion, against response: ApiResponse
    ) -> AssertionResult {
        let actual = actualValue(for: assertion.target, in: response)
        let outcome = compare(actual: actual, op: assertion.op, expected: assertion.expected)
        return AssertionResult(
            id: assertion.id,
            label: assertion.label,
            passed: outcome.passed,
            detail: outcome.detail
        )
    }

    public static func summary(_ results: [AssertionResult]) -> (passed: Int, failed: Int) {
        let passed = results.filter(\.passed).count
        return (passed: passed, failed: results.count - passed)
    }

    // MARK: - Actual values

    /// nil means "not present" — a missing header or an absent JSON path, which
    /// is different from present-but-empty.
    static func actualValue(for target: AssertionTarget, in response: ApiResponse) -> String? {
        switch target {
        case .statusCode:
            return String(response.statusCode)
        case .responseTimeMs:
            return String(format: "%.0f", response.elapsedMs)
        case .bodySize:
            return String(response.size)
        case .bodyText:
            return response.bodyString ?? ""
        case .header(let name):
            guard !name.isEmpty else { return nil }
            return response.headerValue(name)
        case .jsonPath(let path):
            guard !path.isEmpty else { return nil }
            return JSONProbe.probe(path, in: response.body)?.stringValue
        }
    }

    static func compare(
        actual: String?, op: AssertionOperator, expected: String
    ) -> (passed: Bool, detail: String) {
        let found = actual.map { "\"\($0.truncatedForDetail())\"" } ?? "not present"

        switch op {
        case .exists:
            return (actual != nil, found)
        case .notExists:
            return (actual == nil, found)
        case .isEmpty:
            return ((actual ?? "").isEmpty, found)
        case .isNotEmpty:
            return (!(actual ?? "").isEmpty, found)
        case .equals, .notEquals:
            guard let actual else { return (op == .notEquals, found) }
            let same = numericEqualOrStringEqual(actual, expected)
            return (op == .equals ? same : !same, found)
        case .contains, .notContains:
            guard let actual else { return (op == .notContains, found) }
            let has = actual.contains(expected)
            return (op == .contains ? has : !has, found)
        case .matchesRegex:
            guard let actual else { return (false, found) }
            guard let regex = try? NSRegularExpression(pattern: expected) else {
                return (false, "invalid regex")
            }
            let range = NSRange(actual.startIndex..., in: actual)
            return (regex.firstMatch(in: actual, range: range) != nil, found)
        case .lessThan, .greaterThan:
            guard let actual, let lhs = Double(actual.trimmingCharacters(in: .whitespaces)) else {
                return (false, actual == nil ? found : "\(found) is not a number")
            }
            guard let rhs = Double(expected.trimmingCharacters(in: .whitespaces)) else {
                return (false, "expected value is not a number")
            }
            return (op == .lessThan ? lhs < rhs : lhs > rhs, found)
        }
    }

    /// `200` should match `200`, and `1.0` should match `1`, but `abc` still
    /// compares as text.
    private static func numericEqualOrStringEqual(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let left = lhs.trimmingCharacters(in: .whitespaces)
        let right = rhs.trimmingCharacters(in: .whitespaces)
        if let a = Double(left), let b = Double(right) { return a == b }
        return false
    }
}

extension String {
    func truncatedForDetail(limit: Int = 120) -> String {
        count <= limit ? self : String(prefix(limit)) + "…"
    }
}

// MARK: - JSON path probe

/// A leaf or container found at a JSON path.
public enum JSONProbeValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array(count: Int)
    case object(keys: Int)

    /// Text used for comparisons. Containers report their shape so an
    /// `exists`/`isNotEmpty` check on an array still reads sensibly.
    public var stringValue: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
            return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        case .array(let count): return "[\(count) items]"
        case .object(let keys): return "{\(keys) keys}"
        }
    }
}

public enum JSONProbe: Sendable {

    /// Value at `path`, or nil when the path doesn't exist. Accepts a leading
    /// `$.`, dotted keys, `[0]` / `[-1]` indices, and `["quoted.key"]`.
    public static func probe(_ path: String, in data: Data) -> JSONProbeValue? {
        guard !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(
                  with: data, options: [.fragmentsAllowed]
              )
        else { return nil }
        return probe(path, in: root)
    }

    static func probe(_ path: String, in root: Any) -> JSONProbeValue? {
        var current: Any? = root
        for segment in segments(of: path) {
            guard let node = current else { return nil }
            switch segment {
            case .key(let key):
                guard let dict = node as? [String: Any], let next = dict[key] else { return nil }
                current = next
            case .index(let index):
                guard let array = node as? [Any] else { return nil }
                let resolved = index < 0 ? array.count + index : index
                guard resolved >= 0, resolved < array.count else { return nil }
                current = array[resolved]
            }
        }
        return describe(current)
    }

    static func describe(_ node: Any?) -> JSONProbeValue? {
        guard let node else { return nil }
        if node is NSNull { return .null }
        if let number = node as? NSNumber {
            // JSON booleans arrive as NSNumber too. `objCType == "c"` is the
            // portable way to tell them apart — JSON has no 8-bit integer type,
            // so a char-typed number from a JSON parse is always a bool. (A
            // `as? Bool` cast succeeds for every number, and CFBooleanGetTypeID
            // isn't dependable off Apple.)
            if isJSONBoolean(number) { return .bool(number.boolValue) }
            return .number(number.doubleValue)
        }
        if let value = node as? Bool { return .bool(value) }
        if let value = node as? String { return .string(value) }
        if let value = node as? Double { return .number(value) }
        if let value = node as? Int { return .number(Double(value)) }
        if let value = node as? [Any] { return .array(count: value.count) }
        if let value = node as? [String: Any] { return .object(keys: value.count) }
        return nil
    }

    static func isJSONBoolean(_ number: NSNumber) -> Bool {
        String(cString: number.objCType) == "c"
    }

    enum Segment: Equatable {
        case key(String)
        case index(Int)
    }

    static func segments(of path: String) -> [Segment] {
        var trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("$") { trimmed.removeFirst() }
        if trimmed.hasPrefix(".") { trimmed.removeFirst() }

        var segments: [Segment] = []
        var current = ""
        var index = trimmed.startIndex

        func flush() {
            if !current.isEmpty {
                segments.append(.key(current))
                current = ""
            }
        }

        while index < trimmed.endIndex {
            let character = trimmed[index]
            switch character {
            case ".":
                flush()
                index = trimmed.index(after: index)
            case "[":
                flush()
                let afterBracket = trimmed.index(after: index)
                guard let close = trimmed[afterBracket...].firstIndex(of: "]") else {
                    return segments
                }
                var inner = String(trimmed[afterBracket..<close])
                if inner.hasPrefix("\"") && inner.hasSuffix("\"") && inner.count >= 2 {
                    inner.removeFirst()
                    inner.removeLast()
                    segments.append(.key(inner))
                } else if inner.hasPrefix("'") && inner.hasSuffix("'") && inner.count >= 2 {
                    inner.removeFirst()
                    inner.removeLast()
                    segments.append(.key(inner))
                } else if let number = Int(inner) {
                    segments.append(.index(number))
                } else if !inner.isEmpty {
                    segments.append(.key(inner))
                }
                index = trimmed.index(after: close)
            default:
                current.append(character)
                index = trimmed.index(after: index)
            }
        }
        flush()
        return segments
    }
}
