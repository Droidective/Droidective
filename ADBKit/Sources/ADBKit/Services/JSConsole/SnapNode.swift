import Foundation

/// One node of a bounded, ordered snapshot of a JS value, built in the device
/// runtime by `CDPProtocol.boundedSnapshotFunction` and returned as a JSON
/// string. Expanding a logged value renders this tree client-side, so it never
/// goes through Hermes's crash-prone `Runtime.getProperties` converter.
///
/// Object children are carried as an ordered `entries` array (not a JSON object)
/// so insertion order survives decoding.
public struct SnapNode: Sendable, Decodable, Equatable {
    public struct Entry: Sendable, Decodable, Equatable {
        public let name: String
        public let node: SnapNode
    }

    /// `string` · `number` · `boolean` · `null` · `undefined` · `bigint` ·
    /// `symbol` · `function` · `array` · `object`.
    public let type: String
    /// Display text for a primitive node.
    public let text: String?
    /// Constructor name for an object node (e.g. `Object`, `Map`).
    public let ctor: String?
    /// Reported element count for an array (may exceed `items.count` when truncated).
    public let length: Int?
    /// Whether this level was cut at the breadth cap.
    public let truncated: Bool?
    public let entries: [Entry]?
    public let items: [SnapNode]?

    public var isContainer: Bool { type == "array" || type == "object" }

    /// Number of children not shown because the level hit the breadth cap.
    public var hiddenCount: Int? {
        guard truncated == true else { return nil }
        if type == "array", let length { return max(0, length - (items?.count ?? 0)) }
        return nil
    }

    /// Decode the JSON string produced by `boundedSnapshotFunction`.
    public static func parse(_ json: String) -> SnapNode? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SnapNode.self, from: data)
    }

    /// Whether this node — or any descendant — matches `query` (already
    /// lowercased) in a key or a primitive value, so a search within an object
    /// can keep matching branches and prune the rest. `key` is this node's own
    /// key (nil for array items and the root). An empty query matches everything.
    public func matches(_ query: String, key: String? = nil) -> Bool {
        if query.isEmpty { return true }
        if let key, key.lowercased().contains(query) { return true }
        if let text, text.lowercased().contains(query) { return true }
        if let entries { return entries.contains { $0.node.matches(query, key: $0.name) } }
        if let items { return items.contains { $0.matches(query) } }
        return false
    }
}
