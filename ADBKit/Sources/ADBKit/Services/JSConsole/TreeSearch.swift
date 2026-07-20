import Foundation

/// One hit from a find inside an expanded value tree (the JS console's object
/// snapshots and Reactotron's JSON payloads). The view renders these as a
/// clickable result list; clicking one expands the tree along `path` and
/// highlights the node.
public struct TreeMatch: Sendable, Equatable {
    /// Ordinal child indices from the root to the matched node, in the exact
    /// order the tree view renders children — the view derives its expansion
    /// keys from these.
    public let path: [Int]
    /// Human-readable location, e.g. `user.addresses[0].city`.
    public let displayPath: String
    /// The matched node's value text, or a container summary like `Array(3)`.
    public let preview: String
    public let isContainer: Bool

    public init(path: [Int], displayPath: String, preview: String, isContainer: Bool) {
        self.path = path
        self.displayPath = displayPath
        self.preview = preview
        self.isContainer = isContainer
    }
}

public extension SnapNode {
    /// Collapsed one-liner for a container node, e.g. `Array(200)`, `{3}`,
    /// `Map {2}` — shared by the tree rows and the find-result previews.
    var containerSummary: String {
        if type == "array" {
            return "Array(\(length ?? items?.count ?? 0))"
        }
        let count = entries?.count ?? 0
        let ctor = ctor ?? "Object"
        return ctor == "Object" ? "{\(count)}" : "\(ctor) {\(count)}"
    }

    /// Display text for a primitive node (strings quoted, like the tree rows).
    var primitivePreview: String {
        let text = text ?? "—"
        return type == "string" ? "\"\(text)\"" : text
    }

    /// Every descendant whose own key or primitive value contains `query`
    /// (case-insensitive), in render order, capped at `limit`. The root itself
    /// is never a match — it has no key of its own.
    func findMatches(query: String, limit: Int = 200) -> [TreeMatch] {
        let query = query.lowercased()
        guard !query.isEmpty else { return [] }
        var out: [TreeMatch] = []

        func matchesSelf(_ node: SnapNode, key: String?) -> Bool {
            if let key, key.lowercased().contains(query) { return true }
            if let text = node.text, text.lowercased().contains(query) { return true }
            return false
        }

        func walk(_ node: SnapNode, key: String?, path: [Int], displayPath: String) {
            guard out.count < limit else { return }
            if !path.isEmpty, matchesSelf(node, key: key) {
                out.append(TreeMatch(
                    path: path,
                    displayPath: displayPath,
                    preview: node.isContainer ? node.containerSummary : node.primitivePreview,
                    isContainer: node.isContainer
                ))
            }
            if let entries = node.entries {
                for (index, entry) in entries.enumerated() {
                    let child = displayPath.isEmpty ? entry.name : "\(displayPath).\(entry.name)"
                    walk(entry.node, key: entry.name, path: path + [index], displayPath: child)
                }
            } else if let items = node.items {
                for (index, item) in items.enumerated() {
                    walk(item, key: nil, path: path + [index], displayPath: "\(displayPath)[\(index)]")
                }
            }
        }

        walk(self, key: nil, path: [], displayPath: "")
        return out
    }
}
