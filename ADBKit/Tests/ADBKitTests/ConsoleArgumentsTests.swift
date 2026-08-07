@testable import ADBKit
import Foundation
import Testing

/// `ConsoleArguments` — how a console call's arguments split into the chunks the
/// row renders and the clipboard carries.
struct ConsoleArgumentsTests {
    private func remote(_ json: String) -> RemoteObject {
        RemoteObject(json: (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .null)
    }

    private var text: RemoteObject { remote(#"{"type":"string","value":"[app] loaded"}"#) }
    private var number: RemoteObject { remote(#"{"type":"number","value":42}"#) }
    private var object: RemoteObject {
        remote(#"""
        {"type":"object","className":"Object","description":"Object","objectId":"7","preview":{"type":"object",
         "description":"Object","overflow":false,"properties":[{"name":"id","type":"number","value":"1"}]}}
        """#)
    }

    private var array: RemoteObject {
        remote(#"""
        {"type":"object","subtype":"array","description":"Array(2)","objectId":"8","preview":{"type":"object",
         "subtype":"array","description":"Array(2)","overflow":false,
         "properties":[{"name":"0","type":"string","value":"a"},{"name":"1","type":"string","value":"b"}]}}
        """#)
    }

    @Test func consecutiveScalarsRunTogetherAndObjectsStandAlone() {
        let chunks = ConsoleArguments.chunks([text, number, object])
        #expect(chunks.count == 2)
        guard case let .scalars(tokens) = chunks[0] else {
            Issue.record("expected a scalar run first")
            return
        }
        // The separating space is already in the tokens.
        #expect(tokens.map(\.text).joined() == "[app] loaded 42")
        guard case .object = chunks[1] else {
            Issue.record("expected the object to stand alone")
            return
        }
    }

    /// Argument order is preserved — an object logged first stays first.
    @Test func chunksKeepArgumentOrder() {
        let chunks = ConsoleArguments.chunks([object, text, array])
        #expect(chunks.count == 3)
        if case .object = chunks[0] {} else { Issue.record("object should lead") }
        if case .scalars = chunks[1] {} else { Issue.record("scalars should follow") }
        if case .object = chunks[2] {} else { Issue.record("array should trail") }
    }

    @Test func scalarOnlyAndEmptyCallsAreOneChunkOrNone() {
        #expect(ConsoleArguments.chunks([]).isEmpty)
        #expect(ConsoleArguments.chunks([text, number]).count == 1)
        #expect(ConsoleArguments.chunks([object]).count == 1)
    }

    /// A copied log carries the data it was logged with: the message, then each
    /// object's JSON. A pasted `{…}` is the one part of the row nobody can act on.
    @Test func copyTextPutsTheMessageFirstAndEachObjectsJSONBelow() {
        let chunks = ConsoleArguments.chunks([text, number, object])
        let copied = ConsoleArguments.copyText(chunks, json: [1: #"{\#n  "id": 1\#n}"#])
        #expect(copied == "[app] loaded 42\n{\n  \"id\": 1\n}")
    }

    @Test func copyTextKeepsEveryObjectOnItsOwnLine() {
        let chunks = ConsoleArguments.chunks([text, array, object])
        let copied = ConsoleArguments.copyText(chunks, json: [1: #"["a","b"]"#, 2: #"{"id":1}"#])
        #expect(copied == "[app] loaded\n[\"a\",\"b\"]\n{\"id\":1}")
    }

    /// A value the runtime couldn't stringify still copies as something —
    /// the preview beats an empty line.
    @Test func copyTextFallsBackToThePreviewWhenAValueWontStringify() {
        let chunks = ConsoleArguments.chunks([text, object])
        #expect(ConsoleArguments.copyText(chunks, json: [:]) == "[app] loaded\n{id: 1}")
    }

    @Test func copyTextOfAScalarOnlyCallIsJustItsText() {
        #expect(ConsoleArguments.copyText(ConsoleArguments.chunks([text, number]), json: [:]) == "[app] loaded 42")
        #expect(ConsoleArguments.copyText([], json: [:]).isEmpty)
    }
}
