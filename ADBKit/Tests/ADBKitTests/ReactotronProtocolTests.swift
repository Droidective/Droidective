import Foundation
import Testing
@testable import ADBKit

@Suite struct ReactotronProtocolTests {
    // MARK: - JSONValue

    @Test func jsonValueDecodesNestedShapes() throws {
        let value = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(#"{"a":1,"b":["x",true,null],"c":{"d":2.5}}"#.utf8)
        )
        #expect(value["a"]?.intValue == 1)
        #expect(value["b"]?.arrayValue?.count == 3)
        #expect(value["b"]?.arrayValue?[0].stringValue == "x")
        #expect(value["b"]?.arrayValue?[1].boolValue == true)
        #expect(value["b"]?.arrayValue?[2].isNull == true)
        #expect(value["c"]?["d"]?.doubleValue == 2.5)
    }

    /// The "Copy as JSON" buttons on the State tab copy `prettyJSON` — sorted
    /// keys, pretty-printed, slashes unescaped — so the output must be stable,
    /// valid JSON.
    @Test func prettyJSONEmitsSortedReadableJSON() throws {
        let value = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(#"{"b":{"url":"https://x.dev/a"},"a":[1,true,null]}"#.utf8)
        )
        let pretty = value.prettyJSON
        #expect(pretty.contains("\"a\" : [") || pretty.contains("\"a\": ["))
        #expect(pretty.contains("https://x.dev/a"))
        #expect(!pretty.contains("\\/"))
        // Keys come out sorted, so "a" precedes "b" regardless of input order.
        let aIndex = try #require(pretty.range(of: "\"a\""))
        let bIndex = try #require(pretty.range(of: "\"b\""))
        #expect(aIndex.lowerBound < bIndex.lowerBound)
        // Round-trips as valid JSON.
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(pretty.utf8))
        #expect(decoded["a"]?.arrayValue?.count == 3)
        #expect(decoded["b"]?["url"]?.stringValue == "https://x.dev/a")
    }

    // MARK: - Envelope

    @Test func decodesEnvelopeFields() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"log","important":true,"date":"2024-01-02T03:04:05.000Z","deltaTime":12,"payload":{"level":"debug","message":"hi"}}"#
        )
        #expect(command.type == "log")
        #expect(command.commandType == .log)
        #expect(command.isImportant == true)
        #expect(command.date == "2024-01-02T03:04:05.000Z")
        #expect(command.deltaTime == 12)
    }

    @Test func decodesClearWithoutPayload() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"clear","important":false,"date":"d","deltaTime":0}"#
        )
        #expect(command.payload == nil)
        #expect(ReactotronEvent(command: command) == .clear)
    }

    // MARK: - Events

    @Test func parsesErrorLogWithStack() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"log","important":false,"date":"d","deltaTime":1,"payload":{"level":"error","message":"Boom","stack":[{"fileName":"App.js","functionName":"render","lineNumber":42,"columnNumber":7}]}}"#
        )
        guard case let .log(level, message, stack) = ReactotronEvent(command: command) else {
            Issue.record("expected .log"); return
        }
        #expect(level == .error)
        #expect(message == "Boom")
        #expect(stack.count == 1)
        #expect(stack.first?.fileName == "App.js")
        #expect(stack.first?.lineNumber == 42)
        #expect(stack.first?.columnNumber == 7)
    }

    @Test func logObjectAndArrayMessagesPreviewTheirContent() throws {
        // `console.log({user})` and multi-arg logs must show the values on the
        // collapsed row, not an opaque "{ 1 }" / "[ 2 ]" element count.
        let object = try ReactotronCommand.decode(
            #"{"type":"log","important":false,"date":"d","deltaTime":1,"payload":{"level":"debug","message":{"user":"Sam"}}}"#
        )
        guard case let .log(_, objectMessage, _) = ReactotronEvent(command: object) else {
            Issue.record("expected .log"); return
        }
        #expect(objectMessage == #"{"user":"Sam"}"#)

        let array = try ReactotronCommand.decode(
            #"{"type":"log","important":false,"date":"d","deltaTime":1,"payload":{"level":"debug","message":["cart",{"count":2}]}}"#
        )
        guard case let .log(_, arrayMessage, _) = ReactotronEvent(command: array) else {
            Issue.record("expected .log"); return
        }
        #expect(arrayMessage == #"["cart",{"count":2}]"#)
    }

    @Test func compactPreviewMatchesCompactJSONForSmallValues() {
        // Sentinel markers are repaired at decode time, so by the time a value
        // is previewed a function marker is already the plain string.
        let value = JSONValue.object([
            "b": .array([.number(1), .bool(true), .null]),
            "a": .string("hi \"there\"\n"),
            "fn": .string("register()"),
        ])
        #expect(value.compactPreview(maxLength: 500) == #"{"a":"hi \"there\"\n","b":[1,true,null],"fn":"register()"}"#)
    }

    @Test func compactPreviewStopsAtTheBudgetOnHugeValues() {
        // A megabyte string and a 50k-element array must cost O(budget) to
        // preview — the old full-serialize-then-prefix stalled the parse path.
        let huge = JSONValue.object([
            "blob": .string(String(repeating: "x", count: 1_000_000)),
            "list": .array(Array(repeating: JSONValue.number(7), count: 50_000)),
        ])
        let preview = huge.compactPreview(maxLength: 500)
        #expect(preview.count == 500)   // emit clamps every chunk to the budget
        #expect(preview.hasPrefix(#"{"blob":"xxx"#))
    }

    @Test func logMessagePreviewIsCappedAt500Characters() throws {
        let long = String(repeating: "x", count: 600)
        let command = try ReactotronCommand.decode(
            #"{"type":"log","important":false,"date":"d","deltaTime":1,"payload":{"level":"debug","message":{"blob":"\#(long)"}}}"#
        )
        guard case let .log(_, message, _) = ReactotronEvent(command: command) else {
            Issue.record("expected .log"); return
        }
        #expect(message.count == 500)
    }

    @Test func parsesDisplay() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"display","important":false,"date":"d","deltaTime":1,"payload":{"name":"User","value":{"id":7,"name":"Sam"},"preview":"Sam"}}"#
        )
        guard case let .display(name, value, preview, _) = ReactotronEvent(command: command) else {
            Issue.record("expected .display"); return
        }
        #expect(name == "User")
        #expect(preview == "Sam")
        #expect(value?["id"]?.intValue == 7)
        #expect(value?["name"]?.stringValue == "Sam")
    }

    @Test func parsesApiResponse() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"api.response","important":false,"date":"d","deltaTime":1,"payload":{"duration":134,"request":{"method":"get","url":"https://api.example.com/users","headers":{},"params":null,"data":null},"response":{"status":200,"headers":{},"body":"[]"}}}"#
        )
        guard case let .apiResponse(method, url, status, duration, _, _) = ReactotronEvent(command: command) else {
            Issue.record("expected .apiResponse"); return
        }
        #expect(method == "GET")
        #expect(url == "https://api.example.com/users")
        #expect(status == 200)
        #expect(duration == 134)
    }

    @Test func parsesBenchmark() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"benchmark.report","important":false,"date":"d","deltaTime":1,"payload":{"title":"startup","steps":[{"title":"a","time":10,"delta":10},{"title":"b","time":25,"delta":15}]}}"#
        )
        guard case let .benchmark(title, steps) = ReactotronEvent(command: command) else {
            Issue.record("expected .benchmark"); return
        }
        #expect(title == "startup")
        #expect(steps.count == 2)
        #expect(steps[1].delta == 15)
    }

    @Test func parsesStateAction() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"state.action.complete","important":false,"date":"d","deltaTime":1,"payload":{"name":"INCREMENT","action":{"type":"INCREMENT","payload":1},"ms":3}}"#
        )
        guard case let .stateAction(name, action, ms) = ReactotronEvent(command: command) else {
            Issue.record("expected .stateAction"); return
        }
        #expect(name == "INCREMENT")
        #expect(action?["type"]?.stringValue == "INCREMENT")
        #expect(ms == 3)
    }

    @Test func parsesClientIntro() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"client.intro","important":false,"date":"d","deltaTime":0,"payload":{"name":"MyApp","environment":"development","platform":"android","reactotronCoreClientVersion":"2.17.1"}}"#
        )
        guard case let .clientIntro(name, environment, platform, clientVersion) = ReactotronEvent(command: command) else {
            Issue.record("expected .clientIntro"); return
        }
        #expect(name == "MyApp")
        #expect(environment == "development")
        #expect(platform == "android")
        #expect(clientVersion == "2.17.1")
    }

    @Test func parsesAsyncStorageMutation() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"asyncStorage.mutation","important":false,"date":"d","deltaTime":1,"payload":{"action":"setItem","data":{"key":"token","value":"abc"}}}"#
        )
        guard case let .asyncStorage(action, data) = ReactotronEvent(command: command) else {
            Issue.record("expected .asyncStorage"); return
        }
        #expect(action == "setItem")
        #expect(data?["key"]?.stringValue == "token")
    }

    @Test func parsesStateValuesChange() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"state.values.change","important":false,"date":"d","deltaTime":1,"payload":{"changes":[{"path":"user.name","value":"Sam"},{"path":"count","value":3}]}}"#
        )
        guard case let .stateValuesChange(changes) = ReactotronEvent(command: command) else {
            Issue.record("expected .stateValuesChange"); return
        }
        #expect(changes.count == 2)
        #expect(changes.first?.path == "user.name")
        #expect(changes.first?.value.stringValue == "Sam")
        #expect(changes.last?.value.intValue == 3)
    }

    @Test func parsesStateValuesResponse() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"state.values.response","important":false,"date":"d","deltaTime":1,"payload":{"path":"user.name","value":"Sam","valid":true}}"#
        )
        guard case let .stateValuesResponse(path, value) = ReactotronEvent(command: command) else {
            Issue.record("expected .stateValuesResponse"); return
        }
        #expect(path == "user.name")
        #expect(value?.stringValue == "Sam")
    }

    @Test func parsesStateBackupResponse() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"state.backup.response","important":false,"date":"d","deltaTime":1,"payload":{"state":{"count":5}}}"#
        )
        guard case let .stateBackup(snapshot) = ReactotronEvent(command: command) else {
            Issue.record("expected .stateBackup"); return
        }
        #expect(snapshot?["count"]?.intValue == 5)
    }

    @Test func parsesStateValuesResponseWithWholeStateFromMST() throws {
        // reactotron-mst answers `state.values.request` (no path) with the whole
        // store in a `state.values.response` whose path is null.
        let command = try ReactotronCommand.decode(
            #"{"type":"state.values.response","important":false,"date":"d","deltaTime":1,"payload":{"path":null,"value":{"user":{"name":"Sam"},"count":3},"valid":true}}"#
        )
        guard case let .stateValuesResponse(path, value) = ReactotronEvent(command: command) else {
            Issue.record("expected .stateValuesResponse"); return
        }
        #expect(path == nil)
        #expect(value?["user"]?["name"]?.stringValue == "Sam")
        #expect(value?["count"]?.intValue == 3)
    }

    @Test func parsesStateKeysResponseWithWholeState() throws {
        // `state.values.request` with no path makes the client return the whole
        // cleaned store inside a `state.keys.response` whose path is null.
        let command = try ReactotronCommand.decode(
            #"{"type":"state.keys.response","important":false,"date":"d","deltaTime":1,"payload":{"path":null,"keys":{"user":{"name":"Sam"},"count":3},"valid":true}}"#
        )
        guard case let .stateKeysResponse(path, keys) = ReactotronEvent(command: command) else {
            Issue.record("expected .stateKeysResponse"); return
        }
        #expect(path == nil)
        #expect(keys?["user"]?["name"]?.stringValue == "Sam")
        #expect(keys?["count"]?.intValue == 3)
    }

    @Test func parsesReplResponses() throws {
        let ls = try ReactotronCommand.decode(
            #"{"type":"repl.ls.response","important":false,"date":"d","deltaTime":1,"payload":["store","nav"]}"#
        )
        guard case let .replKeys(names) = ReactotronEvent(command: ls) else {
            Issue.record("expected .replKeys"); return
        }
        #expect(names == ["store", "nav"])

        let exec = try ReactotronCommand.decode(
            #"{"type":"repl.execute.response","important":false,"date":"d","deltaTime":1,"payload":42}"#
        )
        guard case let .replResult(value) = ReactotronEvent(command: exec) else {
            Issue.record("expected .replResult"); return
        }
        #expect(value?.intValue == 42)
    }

    @Test func parsesCustomCommandRegister() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"customCommand.register","important":false,"date":"d","deltaTime":1,"payload":{"id":3,"command":"navigate","title":"Go to screen","args":[{"name":"route","type":"string"}]}}"#
        )
        guard case let .customCommandRegister(id, name, title, _, args) = ReactotronEvent(command: command) else {
            Issue.record("expected .customCommandRegister"); return
        }
        #expect(id == 3)
        #expect(name == "navigate")
        #expect(title == "Go to screen")
        #expect(args.count == 1)
        #expect(args.first?.name == "route")
    }

    @Test func decodesEnvelopeWithReactotronMarkers() throws {
        // reactotron serializes booleans/functions as "~~~ … ~~~" markers, so the
        // envelope's `important` arrives as a String, not a Bool. The frame must
        // still decode, and payload markers are repaired on the way in — the
        // function marker loses its tildes.
        let command = try ReactotronCommand.decode(
            #"{"type":"state.action.complete","important":"~~~ false ~~~","date":"2026-06-26","payload":{"name":"PING","action":{"type":"PING","cb":"~~~ fn() ~~~"},"ms":0.4}}"#
        )
        #expect(command.type == "state.action.complete")
        #expect(command.isImportant == false)
        guard case let .stateAction(name, action, ms) = ReactotronEvent(command: command) else {
            Issue.record("expected .stateAction"); return
        }
        #expect(name == "PING")
        #expect(ms == 0.4)
        #expect(action?["cb"]?.stringValue == "fn()")
    }

    // MARK: - Sentinel repair

    @Test func repairsNamedSentinelsIntoRealValues() throws {
        // The mirror of reactotron-core-server's repair-serialization: the
        // client encodes JSON-hostile values as markers; decode restores them.
        let command = try ReactotronCommand.decode(
            #"""
            {"type":"log","important":false,"date":"d","deltaTime":1,"payload":{
                "isNull":"~~~ null ~~~",
                "isUndefined":"~~~ undefined ~~~",
                "isFalse":"~~~ false ~~~",
                "isZero":"~~~ zero ~~~",
                "isEmpty":"~~~ empty string ~~~"
            }}
            """#
        )
        let payload = try #require(command.payload)
        #expect(payload["isNull"]?.isNull == true)
        #expect(payload["isUndefined"]?.isNull == true)
        #expect(payload["isFalse"]?.boolValue == false)
        #expect(payload["isZero"]?.doubleValue == 0)
        #expect(payload["isEmpty"]?.stringValue == "")
    }

    @Test func repairsSentinelsCaseInsensitivelyAndInNestedShapes() throws {
        // The official repair matches markers case-insensitively, and payloads
        // nest them arbitrarily deep (state trees, api bodies).
        let command = try ReactotronCommand.decode(
            #"{"type":"log","important":false,"date":"d","deltaTime":1,"payload":{"list":[{"flag":"~~~ FALSE ~~~"},"~~~ Empty String ~~~"],"fn":"~~~ register() ~~~"}}"#
        )
        let payload = try #require(command.payload)
        #expect(payload["list"]?.arrayValue?[0]["flag"]?.boolValue == false)
        #expect(payload["list"]?.arrayValue?[1].stringValue == "")
        // Unknown markers (functions, circular refs) drop their tildes but
        // stay strings.
        #expect(payload["fn"]?.stringValue == "register()")
    }

    @Test func repairLeavesOrdinaryStringsAndShortMarkersAlone() {
        // Below the length threshold (9), and plain text with tildes inside —
        // neither is a marker.
        let value = JSONValue.object([
            "short": .string("~~~ a ~~~"),
            "plain": .string("approx ~~~ tilde art ~~~ inline"),
            "text": .string("hello"),
        ])
        let repaired = value.repairingSentinels()
        #expect(repaired["short"]?.stringValue == "~~~ a ~~~")
        #expect(repaired["plain"]?.stringValue == "approx ~~~ tilde art ~~~ inline")
        #expect(repaired["text"]?.stringValue == "hello")
    }

    @Test func repairReturnsUntouchedSubtreesAsIs() {
        let clean = JSONValue.object([
            "a": .array([.number(1), .string("x")]),
            "b": .object(["c": .bool(true)]),
        ])
        #expect(clean.repairingSentinels() == clean)
    }

    @Test func unknownTypeFallsThrough() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"some.future.command","important":false,"date":"d","deltaTime":1,"payload":{"x":1}}"#
        )
        guard case let .unknown(type, _) = ReactotronEvent(command: command) else {
            Issue.record("expected .unknown"); return
        }
        #expect(type == "some.future.command")
    }

    // MARK: API filter accessors — back the timeline's method/status filters.

    @Test func apiAccessorsExposeMethodAndStatus() throws {
        let command = try ReactotronCommand.decode(
            #"{"type":"api.response","important":false,"date":"d","deltaTime":1,"payload":{"duration":10,"request":{"method":"post","url":"https://api.example.com/orders"},"response":{"status":404}}}"#
        )
        let event = ReactotronEvent(command: command)
        #expect(event.apiMethod == "POST")
        #expect(event.apiStatus == 404)
    }

    @Test func apiAccessorsAreNilForOtherEvents() {
        let event = ReactotronEvent.log(level: .debug, message: "GET /not-an-api", stack: [])
        #expect(event.apiMethod == nil)
        #expect(event.apiStatus == nil)
    }

    @Test func statusClassBucketsCodes() {
        #expect(HTTPStatusClass(status: 200) == .success)
        #expect(HTTPStatusClass(status: 204) == .success)
        #expect(HTTPStatusClass(status: 302) == .redirect)
        #expect(HTTPStatusClass(status: 404) == .clientError)
        #expect(HTTPStatusClass(status: 503) == .serverError)
    }

    @Test func statusZeroIsTheFailureBucket() {
        // A request that never got a response arrives with status 0.
        #expect(HTTPStatusClass(status: 0) == .failure)
        #expect(HTTPStatusClass.failure.label == "Failed")
    }

    @Test func statusClassRejectsOutOfRangeCodes() {
        #expect(HTTPStatusClass(status: 100) == nil)   // 1xx: not a filter bucket
        #expect(HTTPStatusClass(status: 601) == nil)
        #expect(HTTPStatusClass(status: -1) == nil)
    }

    // MARK: Disconnect reasons — the timeline's "why did streaming stop" row.

    @Test func goingAwayCloseMapsToTheQueueOverflowReason() {
        // OkHttp (RN Android) sends 1001 when its 16 MiB send queue overflows.
        #expect(ReactotronServer.closeReason(.protocolCode(.goingAway))
            == .clientClosed(goingAway: true))
    }

    @Test func normalCloseIsAPlainClientClose() {
        #expect(ReactotronServer.closeReason(.protocolCode(.normalClosure))
            == .clientClosed(goingAway: false))
    }
}
