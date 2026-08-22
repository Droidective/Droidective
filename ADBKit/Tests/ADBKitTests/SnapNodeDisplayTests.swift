@testable import ADBKit
import Testing

/// `SnapNode` display — the one-line previews of an expanded value's collapsed
/// rows, which Chrome fills with the node's own first few children rather than a
/// count.
struct SnapNodeDisplayTests {
    private func node(_ json: String) -> SnapNode {
        guard let node = SnapNode.parse(json) else {
            Issue.record("fixture failed to parse")
            return SnapNode.parse(#"{"type":"object","entries":[]}"#)!
        }
        return node
    }

    private func text(_ node: SnapNode) -> String {
        node.previewTokens().map(\.text).joined()
    }

    @Test func objectPreviewShowsItsFirstProperties() {
        let root = node("""
        {"type":"object","ctor":"Object","entries":[
          {"name":"at","node":{"type":"string","text":"2026-08-07"}},
          {"name":"session","node":{"type":"object","ctor":"Object","entries":[
            {"name":"id","node":{"type":"string","text":"s1"}}]}},
          {"name":"tags","node":{"type":"array","length":3,"items":[
            {"type":"string","text":"a"},{"type":"string","text":"b"},{"type":"string","text":"c"}]}},
          {"name":"ok","node":{"type":"boolean","text":"true"}}
        ]}
        """)
        // Nested containers stop at one level so the preview stays a single line.
        #expect(text(root) == "{at: '2026-08-07', session: {…}, tags: Array(3), ok: true}")
    }

    @Test func objectPreviewCapsItsPropertiesAndMarksTheRest() {
        let entries = (0 ..< 8).map { #"{"name":"k\#($0)","node":{"type":"number","text":"\#($0)"}}"# }
        let root = node(#"{"type":"object","ctor":"Object","entries":[\#(entries.joined(separator: ","))]}"#)
        #expect(text(root) == "{k0: 0, k1: 1, k2: 2, k3: 3, k4: 4, …}")
        // A level the device already cut is marked even when it fits.
        let cut = node(#"""
        {"type":"object","ctor":"Object","truncated":true,"entries":[
          {"name":"a","node":{"type":"number","text":"1"}}]}
        """#)
        #expect(text(cut) == "{a: 1, …}")
    }

    @Test func arrayPreviewLeadsWithItsLength() {
        let two = node(#"""
        {"type":"array","length":2,"items":[{"type":"number","text":"1"},{"type":"string","text":"two"}]}
        """#)
        #expect(text(two) == "(2) [1, 'two']")
        #expect(text(node(#"{"type":"array","length":1,"items":[{"type":"number","text":"1"}]}"#)) == "[1]")
        #expect(text(node(#"{"type":"array","length":0,"items":[]}"#)) == "[]")
        // The reported length wins over the items actually sent.
        let capped = node(#"""
        {"type":"array","length":500,"truncated":true,"items":[{"type":"number","text":"1"}]}
        """#)
        #expect(text(capped) == "(500) [1, …]")
    }

    @Test func classInstancesKeepTheirConstructorName() {
        let root = node(#"""
        {"type":"object","ctor":"Widget","entries":[{"name":"id","node":{"type":"number","text":"1"}}]}
        """#)
        #expect(text(root) == "Widget {id: 1}")
        let nested = node(#"""
        {"type":"object","ctor":"Object","entries":[
          {"name":"w","node":{"type":"object","ctor":"Widget","entries":[]}}]}
        """#)
        #expect(text(nested) == "{w: Widget}")
    }

    @Test func primitivesPreviewAsThemselvesWithTheirKind() {
        #expect(text(node(#"{"type":"string","text":"hi"}"#)) == "'hi'")
        #expect(text(node(#"{"type":"number","text":"42"}"#)) == "42")
        #expect(node(#"{"type":"number","text":"42"}"#).previewTokens().first?.kind == .number)
        #expect(node(#"{"type":"string","text":"hi"}"#).previewTokens().first?.kind == .string)
        #expect(node(#"{"type":"null","text":"null"}"#).previewTokens().first?.kind == .null)
    }

    /// Quoting matches the collapsed row's, so an expanded value doesn't
    /// suddenly render its strings a different way.
    @Test func treeStringsQuoteLikeTheConsoleRows() {
        #expect(node(#"{"type":"string","text":"hi"}"#).primitivePreview == "'hi'")
        #expect(node(#"{"type":"string","text":"it's"}"#).primitivePreview == "\"it's\"")
        #expect(node(#"{"type":"number","text":"7"}"#).primitivePreview == "7")
    }

    @Test func nodeCountMeasuresTheSubtreeAndStopsAtItsLimit() {
        let flat = node(#"""
        {"type":"object","ctor":"Object","entries":[
          {"name":"a","node":{"type":"number","text":"1"}},
          {"name":"b","node":{"type":"number","text":"2"}}]}
        """#)
        #expect(flat.nodeCount() == 3)
        #expect(node(#"{"type":"number","text":"1"}"#).nodeCount() == 1)

        let items = (0 ..< 50).map { #"{"type":"number","text":"\#($0)"}"# }.joined(separator: ",")
        let wide = node(#"{"type":"array","length":50,"items":[\#(items)]}"#)
        #expect(wide.nodeCount() == 51)
        #expect(wide.nodeCount(limit: 10) == 10)
    }
}
