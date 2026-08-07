import Foundation

/// One row of a `console.table`.
public struct ConsoleTableRow: Sendable, Equatable {
    /// The array index or object key that names the row.
    public let index: String
    /// Cell text per column, empty where the row has no such key.
    public let cells: [String]
    /// Set when the row itself is a primitive — Chrome files those under a
    /// single `Value` column rather than inventing keys for them.
    public let value: String?

    public init(index: String, cells: [String], value: String?) {
        self.index = index
        self.cells = cells
        self.value = value
    }
}

/// The grid `console.table(data)` prints — Chrome renders one, and a log that
/// shows only `(3) [{…}, {…}, {…}]` is the shape of the data without any of it.
///
/// Built from the same bounded snapshot the expandable rows use, so it costs no
/// extra device round-trip. Chrome's rules: a row per element (or per key, for
/// an object), a column per key in first-seen order across the rows, and a
/// `Value` column for any element that isn't an object.
public struct ConsoleTable: Sendable, Equatable {
    public let columns: [String]
    public let rows: [ConsoleTableRow]
    /// Whether any row was a primitive, so the view draws the `Value` column.
    public let hasValueColumn: Bool
    /// Rows beyond `rowLimit` that aren't drawn.
    public let hiddenRows: Int

    public init(columns: [String], rows: [ConsoleTableRow], hasValueColumn: Bool, hiddenRows: Int) {
        self.columns = columns
        self.rows = rows
        self.hasValueColumn = hasValueColumn
        self.hiddenRows = hiddenRows
    }

    /// The table for a snapshotted `console.table` argument, or nil when the
    /// value isn't tabular (a primitive — Chrome falls back to a plain log).
    public static func from(_ node: SnapNode, columnLimit: Int = 20, rowLimit: Int = 200) -> ConsoleTable? {
        guard node.isContainer else { return nil }
        let entries: [(String, SnapNode)] = if node.type == "array" {
            (node.items ?? []).enumerated().map { (String($0.offset), $0.element) }
        } else {
            (node.entries ?? []).map { ($0.name, $0.node) }
        }
        guard !entries.isEmpty else { return nil }

        var columns: [String] = []
        var seen: Set<String> = []
        for (_, child) in entries.prefix(rowLimit) where child.type == "object" {
            for entry in child.entries ?? [] where !seen.contains(entry.name) {
                guard columns.count < columnLimit else { break }
                seen.insert(entry.name)
                columns.append(entry.name)
            }
        }

        var hasValueColumn = false
        var rows: [ConsoleTableRow] = []
        for (index, child) in entries.prefix(rowLimit) {
            if child.type == "object" {
                let byName = Dictionary(
                    (child.entries ?? []).map { ($0.name, $0.node) }, uniquingKeysWith: { first, _ in first }
                )
                let cells = columns.map { byName[$0].map(cellText) ?? "" }
                rows.append(ConsoleTableRow(index: index, cells: cells, value: nil))
            } else {
                hasValueColumn = true
                rows.append(ConsoleTableRow(
                    index: index, cells: Array(repeating: "", count: columns.count), value: cellText(child)
                ))
            }
        }
        return ConsoleTable(
            columns: columns,
            rows: rows,
            hasValueColumn: hasValueColumn,
            hiddenRows: max(0, entries.count - rows.count)
        )
    }

    /// A cell is one line: nested containers collapse the way Chrome collapses
    /// them inside a table, since the row below the table is where you open one.
    private static func cellText(_ node: SnapNode) -> String {
        switch node.type {
        case "array": "Array(\(node.length ?? node.items?.count ?? 0))"
        case "object": (node.ctor ?? "Object") == "Object" ? "{…}" : (node.ctor ?? "Object")
        default: node.primitivePreview
        }
    }
}
