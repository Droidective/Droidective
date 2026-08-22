@testable import ADBKit
import Testing

/// `ConsoleTable` — the grid `console.table(data)` prints.
struct ConsoleTableTests {
    private func node(_ json: String) -> SnapNode {
        guard let node = SnapNode.parse(json) else {
            Issue.record("fixture failed to parse")
            return SnapNode.parse(#"{"type":"object","entries":[]}"#)!
        }
        return node
    }

    /// StreamLab's own call: `console.table([{endpoint, status, ms}, …])`.
    @Test func arrayOfObjectsBecomesIndexedRows() {
        let table = ConsoleTable.from(node("""
        {"type":"array","length":2,"items":[
          {"type":"object","ctor":"Object","entries":[
            {"name":"endpoint","node":{"type":"string","text":"/users"}},
            {"name":"status","node":{"type":"number","text":"200"}}]},
          {"type":"object","ctor":"Object","entries":[
            {"name":"endpoint","node":{"type":"string","text":"/broken"}},
            {"name":"status","node":{"type":"number","text":"404"}}]}
        ]}
        """))
        #expect(table?.columns == ["endpoint", "status"])
        #expect(table?.rows.map(\.index) == ["0", "1"])
        #expect(table?.rows[0].cells == ["'/users'", "200"])
        #expect(table?.rows[1].cells == ["'/broken'", "404"])
        #expect(table?.hasValueColumn == false)
        #expect(table?.hiddenRows == 0)
    }

    /// Columns are the union across rows, in first-seen order, and a row missing
    /// one leaves the cell blank rather than shifting the others.
    @Test func columnsUniteInFirstSeenOrder() {
        let table = ConsoleTable.from(node("""
        {"type":"array","length":2,"items":[
          {"type":"object","ctor":"Object","entries":[
            {"name":"a","node":{"type":"number","text":"1"}},
            {"name":"b","node":{"type":"number","text":"2"}}]},
          {"type":"object","ctor":"Object","entries":[
            {"name":"b","node":{"type":"number","text":"3"}},
            {"name":"c","node":{"type":"number","text":"4"}}]}
        ]}
        """))
        #expect(table?.columns == ["a", "b", "c"])
        #expect(table?.rows[0].cells == ["1", "2", ""])
        #expect(table?.rows[1].cells == ["", "3", "4"])
    }

    /// A primitive element gets Chrome's single `Value` column instead of
    /// inventing keys for it.
    @Test func primitiveRowsUseTheValueColumn() {
        let table = ConsoleTable.from(node("""
        {"type":"array","length":2,"items":[
          {"type":"object","ctor":"Object","entries":[{"name":"a","node":{"type":"number","text":"1"}}]},
          {"type":"string","text":"loose"}
        ]}
        """))
        #expect(table?.hasValueColumn == true)
        #expect(table?.rows[1].value == "'loose'")
        #expect(table?.rows[1].cells == [""])
        #expect(table?.rows[0].value == nil)
    }

    /// An object argument indexes by key, the way Chrome labels those rows.
    @Test func objectArgumentIndexesByKey() {
        let table = ConsoleTable.from(node("""
        {"type":"object","ctor":"Object","entries":[
          {"name":"first","node":{"type":"object","ctor":"Object","entries":[
            {"name":"ok","node":{"type":"boolean","text":"true"}}]}},
          {"name":"second","node":{"type":"object","ctor":"Object","entries":[
            {"name":"ok","node":{"type":"boolean","text":"false"}}]}}
        ]}
        """))
        #expect(table?.rows.map(\.index) == ["first", "second"])
        #expect(table?.columns == ["ok"])
        #expect(table?.rows.map(\.cells) == [["true"], ["false"]])
    }

    /// Nested values collapse to one line — the disclosure under the table is
    /// where you open one.
    @Test func nestedCellsCollapseToOneLine() {
        let table = ConsoleTable.from(node("""
        {"type":"array","length":1,"items":[
          {"type":"object","ctor":"Object","entries":[
            {"name":"nested","node":{"type":"object","ctor":"Object","entries":[]}},
            {"name":"list","node":{"type":"array","length":3,"items":[]}},
            {"name":"inst","node":{"type":"object","ctor":"Widget","entries":[]}}]}
        ]}
        """))
        #expect(table?.rows[0].cells == ["{…}", "Array(3)", "Widget"])
    }

    @Test func nonTabularAndEmptyValuesHaveNoTable() {
        #expect(ConsoleTable.from(node(#"{"type":"string","text":"hi"}"#)) == nil)
        #expect(ConsoleTable.from(node(#"{"type":"array","length":0,"items":[]}"#)) == nil)
        #expect(ConsoleTable.from(node(#"{"type":"object","ctor":"Object","entries":[]}"#)) == nil)
    }

    /// A `console.table` of a huge array must not build a thousand-column grid,
    /// and the rows it doesn't draw are counted so the view can say so.
    @Test func rowsAndColumnsAreCapped() {
        let keys = (0 ..< 8).map { #"{"name":"k\#($0)","node":{"type":"number","text":"1"}}"# }
        let row = #"{"type":"object","ctor":"Object","entries":[\#(keys.joined(separator: ","))]}"#
        let items = Array(repeating: row, count: 30).joined(separator: ",")
        let table = ConsoleTable.from(
            node(#"{"type":"array","length":30,"items":[\#(items)]}"#), columnLimit: 5, rowLimit: 4
        )
        #expect(table?.columns == ["k0", "k1", "k2", "k3", "k4"])
        #expect(table?.rows.count == 4)
        #expect(table?.rows[0].cells.count == 5)
        #expect(table?.hiddenRows == 26)
    }
}
