@testable import ADBKit
import Foundation
import Testing

/// `SnapNode.findMatches` — the JS console's find-in-object result list.
struct SnapNodeFindMatchesTests {
    /// { user: { name: "Ada", tags: ["math", "code"] }, count: 2 }
    private var root: SnapNode {
        let json = """
        {"type":"object","entries":[
          {"name":"user","node":{"type":"object","entries":[
            {"name":"name","node":{"type":"string","text":"Ada"}},
            {"name":"tags","node":{"type":"array","length":2,"items":[
              {"type":"string","text":"math"},
              {"type":"string","text":"code"}
            ]}}
          ]}},
          {"name":"count","node":{"type":"number","text":"2"}}
        ]}
        """
        guard let node = SnapNode.parse(json) else {
            Issue.record("fixture failed to parse")
            return SnapNode.parse(#"{"type":"object","entries":[]}"#)!
        }
        return node
    }

    @Test func matchesValueWithOrdinalPathAndDisplayPath() {
        let matches = root.findMatches(query: "ada")
        #expect(matches.count == 1)
        #expect(matches[0].path == [0, 0])
        #expect(matches[0].displayPath == "user.name")
        #expect(matches[0].preview == "\"Ada\"")
        #expect(matches[0].isContainer == false)
    }

    @Test func matchesKeysAndArrayItems() {
        let byKey = root.findMatches(query: "tags")
        #expect(byKey.map(\.path) == [[0, 1]])
        #expect(byKey[0].isContainer == true)
        #expect(byKey[0].preview == "Array(2)")

        let inArray = root.findMatches(query: "code")
        #expect(inArray.map(\.path) == [[0, 1, 1]])
        #expect(inArray[0].displayPath == "user.tags[1]")
    }

    @Test func matchingIsCaseInsensitiveAndEmptyQueryReturnsNothing() {
        #expect(root.findMatches(query: "ADA").count == 1)
        #expect(root.findMatches(query: "").isEmpty)
    }

    @Test func limitCapsResults() {
        let matches = root.findMatches(query: "a", limit: 1)
        #expect(matches.count == 1)
    }

    @Test func rootItselfNeverMatches() {
        // A query matching only container summaries/ctor text finds nothing —
        // matches come from keys and primitive values.
        #expect(root.findMatches(query: "object").isEmpty)
    }
}

/// `JSONSearch` — Reactotron's find-in-payload result list.
struct JSONSearchTests {
    /// Object keys deliberately unsorted in source: render order is sorted.
    private var root: JSONValue {
        .object([
            "zeta": .string("last"),
            "alpha": .object([
                "flag": .bool(true),
                "count": .number(42),
            ]),
            "items": .array([.string("one"), .number(2.5)]),
        ])
    }

    @Test func ordinalPathsFollowSortedKeyOrder() {
        // Sorted top-level order: alpha(0), items(1), zeta(2).
        let matches = JSONSearch.matches(in: root, query: "last")
        #expect(matches.map(\.path) == [[2]])
        #expect(matches[0].displayPath == "zeta")
        #expect(matches[0].preview == "\"last\"")
    }

    @Test func nestedKeysAndValuesMatch() {
        // "count" the key and 42 the value under alpha (sorted: count=0, flag=1).
        let byKey = JSONSearch.matches(in: root, query: "count")
        #expect(byKey.map(\.path) == [[0, 0]])
        #expect(byKey[0].displayPath == "alpha.count")
        #expect(byKey[0].preview == "42")

        let byBool = JSONSearch.matches(in: root, query: "true")
        #expect(byBool.map(\.path) == [[0, 1]])
    }

    @Test func arrayItemsMatchWithBracketPaths() {
        let matches = JSONSearch.matches(in: root, query: "2.5")
        #expect(matches.map(\.path) == [[1, 1]])
        #expect(matches[0].displayPath == "items[1]")
        #expect(matches[0].preview == "2.5")
    }

    @Test func containerMatchesByKeyOnly() {
        let matches = JSONSearch.matches(in: root, query: "alpha")
        #expect(matches.count == 1)
        #expect(matches[0].isContainer == true)
        #expect(matches[0].preview == "{ 2 }")
    }

    @Test func capsResultsAndVisits() {
        let wide = JSONValue.array((0 ..< 500).map { .string("hit\($0)") })
        #expect(JSONSearch.matches(in: wide, query: "hit", limit: 10).count == 10)
        // A visit cap smaller than the tree still returns what it saw.
        let capped = JSONSearch.matches(in: wide, query: "hit", maxVisited: 50)
        #expect(capped.count < 500)
        #expect(!capped.isEmpty)
    }

    @Test func emptyQueryReturnsNothing() {
        #expect(JSONSearch.matches(in: root, query: "").isEmpty)
    }
}
