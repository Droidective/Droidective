import Testing
@testable import ADBKit

/// Searching a payload whose value is a *stringified* JSON body — the tree view
/// renders it as its object, so the find has to agree with what is on screen.
@Suite struct JSONSearchStringifiedTests {
    /// An API request the way `reactotron-react-native` reports one: `data` is
    /// the raw string handed to `xhr.send`.
    private var request: JSONValue {
        let body = #"{"id":"graphData_v1.3","params":{"storeId":"8052321","interval":"hour"}}"#
        return .object([
            "data": .string(body),
            "method": .string("POST"),
            "url": .string("https://example.test/stats"),
        ])
    }

    @Test func withoutExpansionOnlyTheBlobMatches() {
        let matches = JSONSearch.matches(in: request, query: "storeId")
        #expect(matches.count == 1)
        // The escaped body, as one line — the old behavior, kept for callers
        // that render the string as a string.
        #expect(matches.first?.displayPath == "data")
        #expect(matches.first?.preview.contains("graphData_v1.3") == true)
    }

    @Test func expansionFindsTheLeafInsideTheStringifiedBody() {
        let matches = JSONSearch.matches(in: request, query: "storeId", expandingStringifiedJSON: true)
        #expect(matches.map(\.displayPath) == ["data.params.storeId"])
        #expect(matches.first?.preview == "\"8052321\"")
    }

    @Test func anExpandedPayloadPreviewsAsItsObject() {
        // `data` matches by key, and `graphData_v1.3` by value — the point here
        // is the first: its preview is the object the reader sees, not the
        // escaped text it arrived as.
        let matches = JSONSearch.matches(in: request, query: "data", expandingStringifiedJSON: true)
        #expect(matches.map(\.displayPath) == ["data", "data.id"])
        #expect(matches.first?.preview == "{ 2 }")
        #expect(matches.first?.isContainer == true)
    }

    @Test func ordinalPathsStayAlignedWithTheTreesRows() {
        // The view grafts a parse's rows in the string's place, so the path to a
        // leaf is the string's own path plus the parse's ordinals (keys sorted:
        // id, params → params is 1; interval, storeId → storeId is 1).
        let matches = JSONSearch.matches(in: request, query: "8052321", expandingStringifiedJSON: true)
        #expect(matches.map(\.path) == [[0, 1, 1]])
    }

    @Test func nestedStringifiedPayloadsExpandTheirWholeChain() {
        let inner = #"{"deep":{"flag":true}}"#
        let outer = #"{"payload":"\#(inner.replacingOccurrences(of: "\"", with: "\\\""))"}"#
        let root = JSONValue.object(["body": .string(outer)])
        let matches = JSONSearch.matches(in: root, query: "flag", expandingStringifiedJSON: true)
        #expect(matches.map(\.displayPath) == ["body.payload.deep.flag"])
    }

    @Test func aStringThatIsNotJSONStillMatchesAsText() {
        let root = JSONValue.object(["note": .string("storeId was missing")])
        let matches = JSONSearch.matches(in: root, query: "storeId", expandingStringifiedJSON: true)
        #expect(matches.map(\.displayPath) == ["note"])
    }

    @Test func aPayloadPastTheSearchCapIsSearchedAsText() {
        let huge = "{\"pad\":\"" + String(repeating: "x", count: JSONSearch.maxStringifiedBytes) + "\",\"k\":1}"
        let root = JSONValue.object(["data": .string(huge)])
        let matches = JSONSearch.matches(in: root, query: "pad", expandingStringifiedJSON: true)
        // Found, but as the string it is — the parse is skipped at this size.
        #expect(matches.count == 1)
        #expect(matches.first?.isContainer == false)
    }
}
