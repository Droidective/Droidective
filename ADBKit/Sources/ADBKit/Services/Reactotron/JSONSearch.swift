import Foundation

/// Find inside a `JSONValue` tree (Reactotron payloads, the store browser).
/// Returns `TreeMatch`es whose ordinal paths follow the tree view's render
/// order — object children sorted by key, array items in order — so the view
/// can expand straight to a clicked result.
public enum JSONSearch {
    /// Every node whose own key or scalar value contains `query`
    /// (case-insensitive), in render order. Bounded by `limit` results and
    /// `maxVisited` visited nodes so a pathological payload can't stall a
    /// keystroke.
    public static func matches(
        in root: JSONValue, query: String, limit: Int = 200, maxVisited: Int = 40_000
    ) -> [TreeMatch] {
        let query = query.lowercased()
        guard !query.isEmpty else { return [] }
        var out: [TreeMatch] = []
        var visited = 0

        func matchesSelf(_ value: JSONValue, key: String) -> Bool {
            if key.lowercased().contains(query) { return true }
            switch value {
            case let .string(text): return text.lowercased().contains(query)
            case let .number(number): return preview(.number(number)).contains(query)
            case let .bool(flag): return (flag ? "true" : "false").contains(query)
            case .null, .object, .array: return false
            }
        }

        func walk(_ value: JSONValue, key: String, path: [Int], displayPath: String) {
            guard out.count < limit, visited < maxVisited else { return }
            visited += 1
            if !path.isEmpty, matchesSelf(value, key: key) {
                let isContainer = value.objectValue != nil || value.arrayValue != nil
                out.append(TreeMatch(
                    path: path, displayPath: displayPath,
                    preview: preview(value), isContainer: isContainer
                ))
            }
            switch value {
            case let .object(dict):
                // Sorted by key — the same order the tree view renders, so the
                // ordinal path lands on the right row.
                for (index, entry) in dict.sorted(by: { $0.key < $1.key }).enumerated() {
                    let child = displayPath.isEmpty ? entry.key : "\(displayPath).\(entry.key)"
                    walk(entry.value, key: entry.key, path: path + [index], displayPath: child)
                }
            case let .array(items):
                for (index, item) in items.enumerated() {
                    walk(item, key: "[\(index)]", path: path + [index], displayPath: "\(displayPath)[\(index)]")
                }
            case .null, .bool, .number, .string:
                break
            }
        }

        walk(root, key: "", path: [], displayPath: "")
        return out
    }

    /// One-line value preview matching the tree rows: containers summarize,
    /// strings quote, whole numbers drop the decimal point.
    public static func preview(_ value: JSONValue) -> String {
        switch value {
        case let .object(dict): return "{ \(dict.count) }"
        case let .array(items): return "[ \(items.count) ]"
        case let .string(text): return "\"\(text)\""
        case let .number(number):
            return number.truncatingRemainder(dividingBy: 1) == 0 && abs(number) < 9e15
                ? String(Int(number)) : String(number)
        case let .bool(flag): return flag ? "true" : "false"
        case .null: return "null"
        }
    }
}
