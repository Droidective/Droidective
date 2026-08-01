import Foundation

// MARK: - Scope

/// The four variable layers, highest precedence first: request-local, then
/// collection, environment, and globals. Mirrors Postman's scoping so a
/// collection imported from Postman resolves the way its author expects.
public struct VariableScope: Sendable, Equatable {
    public var globals: [String: String]
    public var environment: [String: String]
    public var collection: [String: String]
    public var local: [String: String]

    public init(
        globals: [String: String] = [:],
        environment: [String: String] = [:],
        collection: [String: String] = [:],
        local: [String: String] = [:]
    ) {
        self.globals = globals
        self.environment = environment
        self.collection = collection
        self.local = local
    }

    public static let empty = VariableScope()

    /// Flattened lookup table with precedence applied.
    public var merged: [String: String] {
        var map = globals
        map.merge(environment) { _, new in new }
        map.merge(collection) { _, new in new }
        map.merge(local) { _, new in new }
        return map
    }

    public var isEmpty: Bool {
        globals.isEmpty && environment.isEmpty && collection.isEmpty && local.isEmpty
    }

    /// Which layer a name resolves from, for the UI's variable tooltip.
    public func origin(of name: String) -> String? {
        if local[name] != nil { return "request" }
        if collection[name] != nil { return "collection" }
        if environment[name] != nil { return "environment" }
        if globals[name] != nil { return "global" }
        return nil
    }
}

// MARK: - Dynamic values

/// Generators behind the `{{$…}}` variables. Injectable so tests can pin them.
public struct DynamicVariables: Sendable {
    public var uuid: @Sendable () -> String
    public var now: @Sendable () -> Date
    public var randomInt: @Sendable () -> Int

    public init(
        uuid: @escaping @Sendable () -> String,
        now: @escaping @Sendable () -> Date,
        randomInt: @escaping @Sendable () -> Int
    ) {
        self.uuid = uuid
        self.now = now
        self.randomInt = randomInt
    }

    public static let live = DynamicVariables(
        uuid: { UUID().uuidString.lowercased() },
        now: { Date() },
        randomInt: { Int.random(in: 0...1000) }
    )

    /// Deterministic generators for tests and for the cURL/code preview, where
    /// a value that changes on every keystroke would make the pane flicker.
    public static func fixed(
        uuid: String = "00000000-0000-0000-0000-000000000000",
        date: Date = Date(timeIntervalSince1970: 0),
        randomInt: Int = 42
    ) -> DynamicVariables {
        DynamicVariables(uuid: { uuid }, now: { date }, randomInt: { randomInt })
    }
}

// MARK: - Resolution

public enum ApiVariables: Sendable {

    /// Recursion cap. A variable whose value references another variable is
    /// expanded up to this many rounds; anything still unresolved is left as
    /// written, which is also how a reference cycle terminates.
    public static let maxDepth = 10

    /// Ceiling on an expanded string, so a variable that fans out (`a` = `{{b}}{{b}}`)
    /// can't grow the heap exponentially before the depth cap stops it.
    public static let maxExpandedBytes = 1 << 20

    static let dynamicNames = ["$guid", "$randomUUID", "$timestamp", "$isoTimestamp", "$randomInt"]

    public static func resolve(
        _ template: String,
        with variables: [String: String],
        dynamic: DynamicVariables = .live
    ) -> String {
        resolve(template, scope: VariableScope(globals: variables), dynamic: dynamic)
    }

    /// Substitutes `{{name}}` from `scope`, then re-expands any references the
    /// substituted values themselves contain.
    public static func resolve(
        _ template: String,
        scope: VariableScope,
        dynamic: DynamicVariables = .live
    ) -> String {
        guard template.contains("{{") else { return template }
        var current = expandDynamics(template, dynamic: dynamic)
        let map = scope.merged
        guard !map.isEmpty else { return current }
        for _ in 0..<maxDepth {
            let next = expandOnce(current) { map[$0] }
            if next == current { break }
            if next.utf8.count > maxExpandedBytes { return next }
            current = next
        }
        return current
    }

    /// Names still written as `{{name}}` after resolution — what the UI warns
    /// about before a send goes out with a literal `{{host}}` in the URL.
    public static func unresolvedNames(in template: String, scope: VariableScope) -> [String] {
        let resolved = resolve(template, scope: scope, dynamic: .fixed())
        var names: [String] = []
        _ = expandOnce(resolved) { name in
            if !names.contains(name) { names.append(name) }
            return nil
        }
        return names
    }

    // MARK: - Request-wide resolution

    public static func resolveRequest(
        _ request: SavedRequest,
        scope: VariableScope,
        dynamic: DynamicVariables = .live
    ) -> SavedRequest {
        guard !scope.isEmpty || requestMentionsVariables(request) else { return request }
        var out = request
        let apply: (String) -> String = { resolve($0, scope: scope, dynamic: dynamic) }

        out.url = apply(request.url)
        out.headers = request.headers.map { pair in
            var copy = pair
            copy.key = apply(pair.key)
            copy.value = apply(pair.value)
            return copy
        }
        out.queryParams = request.queryParams.map { pair in
            var copy = pair
            copy.key = apply(pair.key)
            copy.value = apply(pair.value)
            return copy
        }
        out.pathVariables = request.pathVariables.map { pair in
            var copy = pair
            copy.value = apply(pair.value)
            return copy
        }

        switch out.body.type {
        case .json:
            out.body.jsonText = apply(request.body.jsonText)
        case .raw:
            out.body.rawText = apply(request.body.rawText)
            out.body.rawContentType = apply(request.body.rawContentType)
        case .formUrlEncoded:
            out.body.formFields = request.body.formFields.map { field in
                var copy = field
                copy.key = apply(field.key)
                copy.value = apply(field.value)
                return copy
            }
        case .multipart:
            out.body.multipartFields = request.body.multipartFields.map { field in
                var copy = field
                copy.key = apply(field.key)
                copy.value = apply(field.value)
                return copy
            }
        case .graphql:
            out.body.graphqlQuery = apply(request.body.graphqlQuery)
            out.body.graphqlVariables = apply(request.body.graphqlVariables)
        case .binary:
            out.body.binaryFilePath = apply(request.body.binaryFilePath)
        case .none:
            break
        }

        out.auth.bearerToken = apply(request.auth.bearerToken)
        out.auth.basicUsername = apply(request.auth.basicUsername)
        out.auth.basicPassword = apply(request.auth.basicPassword)
        out.auth.apiKeyName = apply(request.auth.apiKeyName)
        out.auth.apiKeyValue = apply(request.auth.apiKeyValue)
        out.auth.oauth2Token = apply(request.auth.oauth2Token)
        return out
    }

    /// Every unresolved name across a request, for the pre-send warning.
    public static func unresolvedNames(in request: SavedRequest, scope: VariableScope) -> [String] {
        var names: [String] = []
        func scan(_ text: String) {
            for name in unresolvedNames(in: text, scope: scope) where !names.contains(name) {
                names.append(name)
            }
        }
        scan(request.url)
        for pair in request.headers where pair.enabled { scan(pair.key); scan(pair.value) }
        for pair in request.queryParams where pair.enabled { scan(pair.key); scan(pair.value) }
        for pair in request.pathVariables { scan(pair.value) }
        switch request.body.type {
        case .json: scan(request.body.jsonText)
        case .raw: scan(request.body.rawText)
        case .formUrlEncoded: for f in request.body.formFields where f.enabled { scan(f.key); scan(f.value) }
        case .multipart: for f in request.body.multipartFields where f.enabled { scan(f.key); scan(f.value) }
        case .graphql: scan(request.body.graphqlQuery); scan(request.body.graphqlVariables)
        case .binary: scan(request.body.binaryFilePath)
        case .none: break
        }
        scan(request.auth.bearerToken)
        scan(request.auth.basicUsername)
        scan(request.auth.basicPassword)
        scan(request.auth.apiKeyName)
        scan(request.auth.apiKeyValue)
        scan(request.auth.oauth2Token)
        return names
    }

    private static func requestMentionsVariables(_ request: SavedRequest) -> Bool {
        request.url.contains("{{")
    }

    // MARK: - Scanner

    private static func expandDynamics(_ template: String, dynamic: DynamicVariables) -> String {
        guard dynamicNames.contains(where: { template.contains($0) }) else { return template }
        return expandOnce(template) { name in dynamicValue(name, dynamic: dynamic) }
    }

    static func dynamicValue(_ name: String, dynamic: DynamicVariables) -> String? {
        switch name {
        case "$guid", "$randomUUID":
            return dynamic.uuid()
        case "$timestamp":
            return String(Int(dynamic.now().timeIntervalSince1970))
        case "$isoTimestamp":
            return iso8601(dynamic.now())
        case "$randomInt":
            return String(dynamic.randomInt())
        default:
            return nil
        }
    }

    /// `2026-07-31T12:34:56.000Z`, built by hand so it reads the same on Linux
    /// where `ISO8601DateFormatter`'s option set differs.
    static func iso8601(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else { return String(date.timeIntervalSince1970) }
        calendar.timeZone = utc
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.000Z",
            parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    /// One substitution pass. `lookup` returning nil leaves the reference
    /// written as-is, which is what makes an unknown variable visible instead
    /// of silently becoming an empty string.
    static func expandOnce(_ template: String, lookup: (String) -> String?) -> String {
        guard template.contains("{{") else { return template }
        var out = ""
        out.reserveCapacity(template.count)
        var rest = Substring(template)

        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: "}}") else {
                out += rest[open.lowerBound...]
                return out
            }
            let rawName = afterOpen[..<close.lowerBound]
            let name = rawName.trimmingCharacters(in: .whitespaces)
            if name.isEmpty || rawName.contains("{{") {
                out += "{{"
                rest = afterOpen
                continue
            }
            if let value = lookup(name) {
                out += value
            } else {
                out += "{{\(rawName)}}"
            }
            rest = afterOpen[close.upperBound...]
        }
        out += rest
        return out
    }
}
