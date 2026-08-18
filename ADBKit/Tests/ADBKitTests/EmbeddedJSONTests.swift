import Testing
@testable import ADBKit

/// Recognizing and parsing a stringified payload — the `data: "{…}"` field an
/// RN app sends on an `api.response`. The recognition half runs per row render,
/// so it must answer without walking (or copying) the payload.
@Suite struct EmbeddedJSONTests {
    @Test func recognizesAnObjectString() {
        #expect(EmbeddedJSON.looksLikeJSON(#"{"id":"graphData_v1.3"}"#))
    }

    @Test func recognizesAnArrayString() {
        #expect(EmbeddedJSON.looksLikeJSON("[1,2,3]"))
    }

    @Test func toleratesSurroundingWhitespace() {
        #expect(EmbeddedJSON.looksLikeJSON("\n  {\"a\":1}\t\n"))
    }

    @Test func rejectsPlainText() {
        #expect(!EmbeddedJSON.looksLikeJSON("not json at all"))
        #expect(!EmbeddedJSON.looksLikeJSON(""))
        #expect(!EmbeddedJSON.looksLikeJSON("   "))
        #expect(!EmbeddedJSON.looksLikeJSON("42"))
        #expect(!EmbeddedJSON.looksLikeJSON("\"{\\\"a\\\":1}\""))
    }

    @Test func rejectsAnUnclosedShape() {
        #expect(!EmbeddedJSON.looksLikeJSON(#"{"a":1"#))
        #expect(!EmbeddedJSON.looksLikeJSON("[1,2"))
        // Opener and closer must match each other, not just be brackets.
        #expect(!EmbeddedJSON.looksLikeJSON("{1,2]"))
    }

    @Test func rejectsAPayloadPastTheParseCap() {
        let huge = "{\"a\":\"" + String(repeating: "x", count: EmbeddedJSON.maxBytes) + "\"}"
        #expect(!EmbeddedJSON.looksLikeJSON(huge))
        #expect(EmbeddedJSON.parse(huge) == nil)
    }

    @Test func parsesAStringifiedRequestBody() {
        let text = #"{"id":"graphData_v1.3","params":{"storeId":"8052321","interval":"hour"}}"#
        let parsed = EmbeddedJSON.parse(text)
        #expect(parsed?["id"]?.stringValue == "graphData_v1.3")
        #expect(parsed?["params"]?["storeId"]?.stringValue == "8052321")
    }

    @Test func parsesAnArrayBody() {
        #expect(EmbeddedJSON.parse("[1,2,3]")?.arrayValue?.count == 3)
    }

    @Test func parsesNestedStringifiedJSONOneLevelAtATime() {
        // The inner value stays a string — the row that opens it parses it in
        // turn, so a doubly-encoded payload isn't walked all at once.
        let inner = #"{\"deep\":true}"#
        let parsed = EmbeddedJSON.parse("{\"data\":\"\(inner)\"}")
        let nested = parsed?["data"]?.stringValue
        #expect(nested == #"{"deep":true}"#)
        #expect(EmbeddedJSON.parse(nested ?? "")?["deep"]?.boolValue == true)
    }

    @Test func malformedJSONIsNotParsed() {
        #expect(EmbeddedJSON.parse("{oops}") == nil)
        #expect(EmbeddedJSON.parse(#"{"a":}"#) == nil)
        #expect(EmbeddedJSON.parse("[1,2]]") == nil)
    }

    @Test func aScalarIsNeverAParsedTree() {
        // Shaped like neither an object nor an array: there is nothing to show
        // as a tree, so these must not offer the toggle.
        #expect(EmbeddedJSON.parse("42") == nil)
        #expect(EmbeddedJSON.parse("\"quoted\"") == nil)
        #expect(EmbeddedJSON.parse("null") == nil)
    }
}
