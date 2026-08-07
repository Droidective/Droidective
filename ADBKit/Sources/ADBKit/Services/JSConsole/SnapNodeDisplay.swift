import Foundation

/// How a snapshot node reads on one line — the collapsed rows of an expanded
/// value tree. Chrome previews a collapsed object by its first few properties
/// (`{at: '2026-…', session: {…}, tags: Array(3), …}`) rather than by a count,
/// and the snapshot already holds every child, so the preview is built here
/// instead of costing another device round-trip.
public extension SnapNode {
    /// Display text for a primitive node — strings quoted the way the console's
    /// value previews quote them, so the tree and the collapsed row agree.
    var primitivePreview: String {
        let text = text ?? "—"
        return type == "string" ? RemoteObject.quoted(ConsoleANSI.strip(text)) : text
    }

    /// Collapsed one-liner for a container node, e.g. `Array(200)`, `{3}`,
    /// `Map {2}` — the location line of a find result, where the node's own
    /// contents would be noise.
    var containerSummary: String {
        if type == "array" {
            return "Array(\(length ?? items?.count ?? 0))"
        }
        let count = entries?.count ?? 0
        let ctor = ctor ?? "Object"
        return ctor == "Object" ? "{\(count)}" : "\(ctor) {\(count)}"
    }

    /// Chrome's inline preview of this node: primitives render as themselves,
    /// containers as their first few children. Nested containers stop at
    /// `{…}` / `Array(n)`, so the preview is always one shallow line.
    func previewTokens(objectLimit: Int = 5, arrayLimit: Int = 10) -> [JSToken] {
        guard isContainer else { return [JSToken(primitivePreview, Self.tokenKind(type))] }
        if type == "array" {
            let items = items ?? []
            var tokens: [JSToken] = []
            let count = length ?? items.count
            if count > 1 { tokens.append(JSToken("(\(count)) ", .className)) }
            tokens.append(JSToken("[", .punctuation))
            for (index, item) in items.prefix(arrayLimit).enumerated() {
                if index > 0 { tokens.append(JSToken(", ", .punctuation)) }
                tokens.append(item.childToken)
            }
            if items.count > arrayLimit || truncated == true { tokens.append(JSToken(", …", .punctuation)) }
            tokens.append(JSToken("]", .punctuation))
            return tokens
        }
        let entries = entries ?? []
        var tokens: [JSToken] = []
        if let ctor, ctor != "Object" { tokens.append(JSToken("\(ctor) ", .className)) }
        tokens.append(JSToken("{", .punctuation))
        for (index, entry) in entries.prefix(objectLimit).enumerated() {
            if index > 0 { tokens.append(JSToken(", ", .punctuation)) }
            tokens.append(JSToken(entry.name, .key))
            tokens.append(JSToken(": ", .punctuation))
            tokens.append(entry.node.childToken)
        }
        if entries.count > objectLimit || truncated == true { tokens.append(JSToken(", …", .punctuation)) }
        tokens.append(JSToken("}", .punctuation))
        return tokens
    }

    /// How this node appears *inside* another node's preview: never recursive.
    private var childToken: JSToken {
        switch type {
        case "array": JSToken("Array(\(length ?? items?.count ?? 0))", .className)
        case "object":
            (ctor ?? "Object") == "Object"
                ? JSToken("{…}", .punctuation)
                : JSToken(ctor ?? "Object", .className)
        default: JSToken(primitivePreview, Self.tokenKind(type))
        }
    }

    /// Total nodes in the subtree, bounded — the tree view uses it to decide
    /// whether a value is big enough to deserve its own find field, so it stops
    /// counting the moment the answer can't change.
    func nodeCount(limit: Int = 1000) -> Int {
        var total = 0
        func walk(_ node: SnapNode) {
            guard total < limit else { return }
            total += 1
            for entry in node.entries ?? [] { walk(entry.node) }
            for item in node.items ?? [] { walk(item) }
        }
        walk(self)
        return total
    }

    /// The token kind for a snapshot node's `type` string.
    static func tokenKind(_ type: String) -> JSTokenKind {
        switch type {
        case "string": .string
        case "number", "bigint": .number
        case "boolean": .boolean
        case "null": .null
        case "undefined": .undefined
        case "function": .function
        case "symbol": .symbol
        default: .plain
        }
    }
}
