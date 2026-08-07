import Foundation
import Testing
@testable import ADBKit

@Suite struct SnapNodeTests {
    @Test func parsesOrderedObjectArrayAndPrimitives() {
        // Shape emitted by boundedSnapshotFunction: object entries stay ordered.
        let json = """
        {"type":"object","ctor":"Object","truncated":false,"entries":[
          {"name":"userId","node":{"type":"number","text":"1"}},
          {"name":"title","node":{"type":"string","text":"hi"}},
          {"name":"tags","node":{"type":"array","length":2,"truncated":false,"items":[
            {"type":"string","text":"a"},{"type":"string","text":"b"}]}}
        ]}
        """
        let node = SnapNode.parse(json)
        #expect(node?.type == "object")
        #expect(node?.entries?.map(\.name) == ["userId", "title", "tags"])   // order preserved
        #expect(node?.entries?[2].node.type == "array")
        #expect(node?.entries?[2].node.items?.count == 2)
        #expect(node?.entries?[2].node.isContainer == true)
    }

    @Test func reportsHiddenCountForTruncatedArray() {
        let json = """
        {"type":"array","length":200,"truncated":true,"items":[{"type":"number","text":"0"}]}
        """
        let node = SnapNode.parse(json)
        #expect(node?.length == 200)
        #expect(node?.hiddenCount == 199)
    }

    @Test func malformedJSONReturnsNil() {
        #expect(SnapNode.parse("not json") == nil)
    }
}

/// Pure tests for the CDP framing: request shapes and decoding of the replies
/// and events a console relies on.
@Suite struct CDPProtocolTests {
    // MARK: - Requests

    @Test func evaluateRequestUsesReplDefaults() {
        let request = CDP.request(id: 7, method: "Runtime.evaluate", params: CDP.evaluateParams(expression: "1 + 1"))
        #expect(request["id"]?.intValue == 7)
        #expect(request["method"]?.stringValue == "Runtime.evaluate")
        let params = request["params"]
        #expect(params?["expression"]?.stringValue == "1 + 1")
        #expect(params?["replMode"]?.boolValue == true)
        #expect(params?["includeCommandLineAPI"]?.boolValue == true)
        #expect(params?["generatePreview"]?.boolValue == true)
        #expect(params?["awaitPromise"]?.boolValue == true)
        #expect(params?["objectGroup"]?.stringValue == "console")
        // The result must stay a handle so it can be expanded and released.
        #expect(params?["returnByValue"]?.boolValue == false)
    }

    @Test func evaluateRequestPreservesExpressionVerbatim() {
        // An expression must round-trip exactly — no quoting/escaping mangling.
        let expression = #"({ a: "x", re: /~~~ y ~~~/ })"#
        let params = CDP.evaluateParams(expression: expression)
        #expect(params["expression"]?.stringValue == expression)
        let data = try? JSONEncoder().encode(CDP.request(id: 1, method: "Runtime.evaluate", params: params))
        let decoded = data.flatMap { CDP.parseIncoming($0) }
        // It decodes back as a (request-shaped) response with our id.
        if case let .response(id, _, _) = decoded { #expect(id == 1) } else { Issue.record("expected id round-trip") }
    }

    // MARK: - Incoming classification

    @Test func classifiesResponseAndEvent() {
        let response = CDP.parseIncoming(Data(#"{"id":3,"result":{"x":1}}"#.utf8))
        guard case let .response(id, result, error) = response else { Issue.record("expected response"); return }
        #expect(id == 3)
        #expect(result?["x"]?.intValue == 1)
        #expect(error == nil)

        let event = CDP.parseIncoming(Data(#"{"method":"Runtime.consoleAPICalled","params":{"type":"log"}}"#.utf8))
        guard case let .event(method, params) = event else { Issue.record("expected event"); return }
        #expect(method == "Runtime.consoleAPICalled")
        #expect(params["type"]?.stringValue == "log")
    }

    @Test func decodesProtocolError() {
        let response = CDP.parseIncoming(Data(#"{"id":4,"error":{"code":-32000,"message":"boom"}}"#.utf8))
        guard case let .response(_, _, error) = response else { Issue.record("expected response"); return }
        #expect(error?.code == -32000)
        #expect(error?.message == "boom")
    }

    // MARK: - Evaluate outcomes

    @Test func evaluateValueDecodesPrimitive() {
        let result = try? JSONDecoder().decode(
            JSONValue.self, from: Data(#"{"result":{"type":"number","value":4,"description":"4"}}"#.utf8))
        guard case let .value(object) = EvalOutcome.from(result: result) else { Issue.record("expected value"); return }
        #expect(object.type == "number")
        #expect(object.description == "4")
        #expect(object.value?.doubleValue == 4)
    }

    @Test func evaluateExceptionIsNotATransportError() {
        // A thrown JS error rides in the successful reply as exceptionDetails.
        let json = #"""
        {"result":{"type":"object","subtype":"error"},
         "exceptionDetails":{"text":"Uncaught","exception":{"type":"object","subtype":"error",
           "description":"ReferenceError: foo is not defined\n  at <anonymous>:1:1"},
           "lineNumber":0,"columnNumber":0}}
        """#
        let result = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        guard case let .error(details) = EvalOutcome.from(result: result) else { Issue.record("expected error"); return }
        #expect(details.message.contains("ReferenceError"))
    }

    @Test func evaluateMissingResultIsUndefined() {
        guard case let .value(object) = EvalOutcome.from(result: .object([:])) else {
            Issue.record("expected value"); return
        }
        #expect(object.type == "undefined")
    }

    // MARK: - RemoteObject + preview

    @Test func remoteObjectExposesExpandabilityAndPreview() {
        let json = #"""
        {"type":"object","className":"Object","description":"Object","objectId":"{\"id\":2}",
         "preview":{"type":"object","description":"Object","overflow":false,
           "properties":[{"name":"id","type":"number","value":"1"},{"name":"name","type":"string","value":"x"}]}}
        """#
        let value = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let object = RemoteObject(json: value ?? .null)
        #expect(object.isExpandable)
        #expect(object.objectId == "{\"id\":2}")
        #expect(object.preview?.properties.count == 2)
        #expect(object.preview?.properties.first?.name == "id")
    }

    @Test func nullIsNotExpandable() {
        let object = RemoteObject(json: .object(["type": .string("object"), "subtype": .string("null")]))
        #expect(!object.isExpandable)
    }

    @Test func primitiveStringIsNotExpandable() {
        let object = RemoteObject(json: .object(["type": .string("string"), "value": .string("hi")]))
        #expect(!object.isExpandable)
        #expect(object.value?.stringValue == "hi")
    }

    // MARK: - Console event

    @Test func consoleEventDecodesTypeAndArgs() {
        let json = #"""
        {"type":"warning","args":[{"type":"string","value":"watch out"},
          {"type":"number","value":42,"description":"42"}],"timestamp":1700000000000}
        """#
        let params = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let call = ConsoleAPICall(params: params ?? .null)
        #expect(call.type == "warning")
        #expect(call.args.count == 2)
        #expect(call.args.first?.value?.stringValue == "watch out")
        #expect(call.timestamp == 1_700_000_000_000)
    }

    // MARK: - inlineSummary across all data types (real Hermes shapes)

    private func remote(_ json: String) -> RemoteObject {
        RemoteObject(json: (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .null)
    }

    @Test func boundedInlineSummaryTakesAPrefixOfHugeStrings() {
        // A multi-megabyte logged string must not be materialized whole to
        // index its head — the bounded summary takes a prefix directly.
        let huge = RemoteObject(json: .object([
            "type": .string("string"), "value": .string(String(repeating: "x", count: 1_000_000)),
        ]))
        let summary = huge.inlineSummary(limit: 100)
        #expect(summary == "\"" + String(repeating: "x", count: 100))
        // A console argument's bounded head skips the opening quote too, so the
        // filter matches the same text the bare row shows.
        #expect(huge.inlineSummary(limit: 100, style: .consoleArgument)
            == String(repeating: "x", count: 100))
        // Small values render exactly like the unbounded summary.
        let small = remote(#"{"type":"string","value":"hi"}"#)
        #expect(small.inlineSummary(limit: 100) == small.inlineSummary)
        let number = remote(#"{"type":"number","value":42}"#)
        #expect(number.inlineSummary(limit: 100) == "42")
    }

    @Test func approximateBytesTracksStringPayloadSize() {
        let huge = RemoteObject(json: .object([
            "type": .string("string"), "value": .string(String(repeating: "x", count: 5000)),
        ]))
        #expect(huge.approximateBytes >= 5000)
        #expect(remote(#"{"type":"number","value":42}"#).approximateBytes < 1024)
    }

    @Test func inlineSummaryRendersPrimitives() {
        #expect(remote(#"{"type":"string","value":"hi"}"#).inlineSummary == "'hi'")
        #expect(remote(#"{"type":"number","value":42}"#).inlineSummary == "42")
        #expect(remote(#"{"type":"number","value":3.5}"#).inlineSummary == "3.5")
        #expect(remote(#"{"type":"boolean","value":true}"#).inlineSummary == "true")
        #expect(remote(#"{"type":"undefined"}"#).inlineSummary == "undefined")
        #expect(remote(#"{"type":"object","subtype":"null","value":null}"#).inlineSummary == "null")
        #expect(remote(#"{"type":"symbol","description":"Symbol(sym)"}"#).inlineSummary == "Symbol(sym)")
    }

    @Test func inlineSummaryRendersHermesUnserializablesAndBigInt() {
        // Hermes: -0 / Infinity / NaN have description + unserializableValue, no value.
        #expect(remote(#"{"type":"number","description":"-0","unserializableValue":"-0"}"#).inlineSummary == "-0")
        #expect(remote(#"{"type":"number","description":"Infinity","unserializableValue":"Infinity"}"#).inlineSummary == "Infinity")
        #expect(remote(#"{"type":"number","description":"NaN","unserializableValue":"NaN"}"#).inlineSummary == "NaN")
        // Hermes reports bigint as type "".
        #expect(remote(#"{"type":"","description":"123n","unserializableValue":"123n"}"#).inlineSummary == "123n")
    }

    @Test func inlineSummaryRendersFunctionsAndErrors() {
        #expect(remote(#"{"type":"function","description":"function adder(a0, a1) { [bytecode] }"}"#).inlineSummary == "ƒ adder(a0, a1)")
        #expect(remote(#"{"type":"object","subtype":"error","description":"Error: boom\n   at x:1:1"}"#).inlineSummary == "Error: boom")
    }

    @Test func inlineSummaryRendersArraysAndObjectsFromPreview() {
        let array = #"""
        {"type":"object","subtype":"array","description":"Array(3)","preview":{"type":"object","subtype":"array",
         "description":"Array(3)","overflow":false,"properties":[{"name":"0","type":"number","value":"1"},
         {"name":"1","type":"string","value":"two"},{"name":"2","type":"object","value":"Array(2)"}]}}
        """#
        // Chrome leads a multi-element array with its length.
        #expect(remote(array).inlineSummary == "(3) [1, 'two', Array(2)]")

        let object = #"""
        {"type":"object","className":"Object","description":"Object","preview":{"type":"object","description":"Object",
         "overflow":true,"properties":[{"name":"id","type":"number","value":"1"},{"name":"name","type":"string","value":"x"}]}}
        """#
        #expect(remote(object).inlineSummary == "{id: 1, name: 'x', …}")
    }

    /// Chrome's array length prefix appears only where it says something: an
    /// empty or single-element array reads fine without it.
    @Test func arrayLengthPrefixOnlyForMultipleElements() {
        func array(_ length: Int, _ properties: String) -> String {
            #"""
            {"type":"object","subtype":"array","description":"Array(\#(length))","preview":{"type":"object",
             "subtype":"array","description":"Array(\#(length))","overflow":false,"properties":[\#(properties)]}}
            """#
        }
        #expect(remote(array(0, "")).inlineSummary == "[]")
        #expect(remote(array(1, #"{"name":"0","type":"number","value":"7"}"#)).inlineSummary == "[7]")
        #expect(remote(array(2, #"{"name":"0","type":"number","value":"7"},{"name":"1","type":"number","value":"8"}"#))
            .inlineSummary == "(2) [7, 8]")
    }

    /// A nested plain object is Chrome's `{…}`; a nested array or class instance
    /// keeps the name Hermes reports.
    @Test func nestedObjectsRenderAsChromeEllipsis() {
        let object = #"""
        {"type":"object","description":"Object","preview":{"type":"object","description":"Object","overflow":false,
         "properties":[{"name":"meta","type":"object","value":"Object"},
         {"name":"list","subtype":"array","type":"object","value":"Array(3)"},
         {"name":"widget","type":"object","value":"Widget"},
         {"name":"none","type":"object","subtype":"null","value":"null"}]}}
        """#
        #expect(remote(object).inlineSummary == "{meta: {…}, list: Array(3), widget: Widget, none: null}")
    }

    /// A top-level `console.log` string argument prints bare, the way Chrome
    /// prints it; the same value quoted anywhere else.
    @Test func consoleArgumentStringsPrintBare() {
        let text = remote(#"{"type":"string","value":"[StreamLab] hello"}"#)
        #expect(text.inlineSummary(style: .consoleArgument) == "[StreamLab] hello")
        #expect(text.tokens(style: .consoleArgument).first?.kind == .plain)
        #expect(text.inlineSummary(style: .value) == "'[StreamLab] hello'")
        // Newlines survive a bare argument (Chrome prints a multi-line log
        // across lines) and are escaped in the quoted form so a preview stays
        // on one row.
        let multiline = remote(#"{"type":"string","value":"a\nb"}"#)
        #expect(multiline.inlineSummary(style: .consoleArgument) == "a\nb")
        #expect(multiline.inlineSummary(style: .value) == "'a\\nb'")
        // Only strings differ between the styles.
        let number = remote(#"{"type":"number","value":42}"#)
        #expect(number.inlineSummary(style: .consoleArgument) == number.inlineSummary)
    }

    /// The quoting rule: single quotes, switching to double when the text has
    /// one of its own, and escapes so a value can't break its row.
    @Test func stringQuotingFollowsChrome() {
        #expect(RemoteObject.quoted("plain") == "'plain'")
        #expect(RemoteObject.quoted("it's") == "\"it's\"")
        #expect(RemoteObject.quoted("it's \"both\"") == #"'it\'s "both"'"#)
        #expect(RemoteObject.quoted("tab\there") == #"'tab\there'"#)
        #expect(RemoteObject.quoted(#"back\slash"#) == #"'back\\slash'"#)
    }

    /// Hermes replays its buffered console history without previews, so the
    /// whole pre-connect backlog renders from the fallbacks alone.
    @Test func objectsWithoutAPreviewFallBackTheWayChromeDoes() {
        #expect(remote(#"{"type":"object","className":"Object","description":"Object","objectId":"1"}"#)
            .inlineSummary == "{…}")
        #expect(remote(#"{"type":"object","objectId":"1"}"#).inlineSummary == "{…}")
        // An array or a class instance still names itself.
        #expect(remote(#"{"type":"object","subtype":"array","description":"Array(2)","objectId":"1"}"#)
            .inlineSummary == "Array(2)")
        #expect(remote(#"{"type":"object","className":"Widget","description":"Object","objectId":"1"}"#)
            .inlineSummary == "Widget")
    }

    @Test func tokensCarrySemanticKindsForColoring() {
        let object = remote(#"""
        {"type":"object","description":"Object","preview":{"type":"object","description":"Object","overflow":false,
         "properties":[{"name":"id","type":"number","value":"1"},{"name":"name","type":"string","value":"x"}]}}
        """#)
        let tokens = object.tokens
        #expect(tokens.contains { $0.text == "id" && $0.kind == .key })
        #expect(tokens.contains { $0.text == "1" && $0.kind == .number })
        #expect(tokens.contains { $0.text == "'x'" && $0.kind == .string })
        #expect(remote(#"{"type":"string","value":"hi"}"#).tokens.first?.kind == .string)
        #expect(remote(#"{"type":"boolean","value":true}"#).tokens.first?.kind == .boolean)
        #expect(remote(#"{"type":"object","subtype":"null","value":null}"#).tokens.first?.kind == .null)
    }

    /// Metro's bundle URL carries a query string longer than the frame itself;
    /// eight of those turn an unsymbolicated stack into a wall of parameters.
    @Test func stackFrameDisplayNamesTheScriptNotItsURL() {
        let bundle = "http://localhost:8081/index.bundle//&platform=android&dev=true&app=com.streamlab"
        #expect(CDPCallFrame.scriptName(bundle) == "index.bundle")
        #expect(CDPCallFrame.scriptName("http://h/a/b/main.js?v=2#frag") == "main.js")
        #expect(CDPCallFrame.scriptName("plain.js") == "plain.js")
        #expect(CDPCallFrame.scriptName("http://h/dir/") == "dir")
        let frame = CDPCallFrame(json: .object([
            "functionName": .string("emitLog"),
            "url": .string(bundle),
            "lineNumber": .number(87_065),
            "columnNumber": .number(28),
        ]))
        #expect(frame.display == "emitLog  index.bundle:87066")
    }

    @Test func stackFrameDisplayIsOneBasedWithFile() {
        let frame = CDPCallFrame(json: .object([
            "functionName": .string("render"),
            "url": .string("index.bundle"),
            "lineNumber": .number(41),
            "columnNumber": .number(2),
        ]))
        #expect(frame.display == "render  index.bundle:42")
    }
}
