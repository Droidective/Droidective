import Foundation
import Testing
@testable import ADBKit

@Suite struct ReactotronCurlTests {
    @Test func getWithoutBodyHasNoMethodOrData() {
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test/items", request: nil)
        #expect(curl.contains("curl"))
        #expect(curl.contains("'https://x.test/items'"))
        #expect(!curl.contains("-X"))
        #expect(!curl.contains("--data"))
    }

    @Test func getWithEmptyObjectDataStaysBodylessGet() {
        // Reactotron often records `data: {}` for a GET — it must not gain a body
        // (and therefore must not flip to POST).
        let request = JSONValue.object(["data": .object([:])])
        let curl = ReactotronCurl.command(method: "get", url: "https://x.test", request: request)
        #expect(!curl.contains("--data"))
        #expect(!curl.contains("-X"))
    }

    @Test func getWithRealBodyKeepsGetMethod() {
        // The reported bug: a GET with a body must stay GET, not silently POST.
        let request = JSONValue.object(["data": .string("q=1")])
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test", request: request)
        #expect(curl.contains("-X GET"))
        #expect(curl.contains("--data 'q=1'"))
    }

    @Test func postWithBodySetsMethodAndData() {
        let request = JSONValue.object(["data": .string(#"{"a":1}"#)])
        let curl = ReactotronCurl.command(method: "POST", url: "https://x.test", request: request)
        #expect(curl.contains("-X POST"))
        #expect(curl.contains(#"--data '{"a":1}'"#))
    }

    @Test func putWithoutBodyStillSetsMethod() {
        let curl = ReactotronCurl.command(method: "PUT", url: "https://x.test", request: nil)
        #expect(curl.contains("-X PUT"))
        #expect(!curl.contains("--data"))
    }

    @Test func headersAreRenderedSortedAndQuoted() throws {
        let request = JSONValue.object([
            "headers": .object([
                "Authorization": .string("Bearer t"),
                "Accept": .string("application/json"),
            ]),
        ])
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test", request: request)
        #expect(curl.contains("-H 'Accept: application/json'"))
        #expect(curl.contains("-H 'Authorization: Bearer t'"))
        let accept = try #require(curl.range(of: "Accept"))
        let auth = try #require(curl.range(of: "Authorization"))
        #expect(accept.lowerBound < auth.lowerBound)
    }

    @Test func singleQuotesInValuesAreEscaped() {
        let request = JSONValue.object(["data": .string("it's")])
        let curl = ReactotronCurl.command(method: "POST", url: "https://x.test", request: request)
        #expect(curl.contains(#"--data 'it'\''s'"#))
    }

    @Test func objectBodyIsSerializedToJSON() {
        // Reactotron usually records the body as a JSON object, not a pre-encoded
        // string — it must be serialized back to JSON and attached.
        let request = JSONValue.object(["data": .object(["a": .number(1)])])
        let curl = ReactotronCurl.command(method: "POST", url: "https://x.test", request: request)
        #expect(curl.contains("-X POST"))
        #expect(curl.contains(#"--data '{"a":1}'"#))
    }

    @Test func nonEmptyArrayBodyIsAttached() {
        let request = JSONValue.object(["data": .array([.number(1), .number(2)])])
        let curl = ReactotronCurl.command(method: "POST", url: "https://x.test", request: request)
        #expect(curl.contains(#"--data '[1,2]'"#))
    }

    @Test func emptyArrayDataStaysBodyless() {
        let request = JSONValue.object(["data": .array([])])
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test", request: request)
        #expect(!curl.contains("--data"))
        #expect(!curl.contains("-X"))
    }

    @Test func nullAndEmptyStringDataStayBodyless() {
        for data: JSONValue in [.null, .string("")] {
            let request = JSONValue.object(["data": data])
            let curl = ReactotronCurl.command(method: "GET", url: "https://x.test", request: request)
            #expect(!curl.contains("--data"))
            #expect(!curl.contains("-X"))
        }
    }

    @Test func nonStringHeaderValueIsSerialized() {
        let request = JSONValue.object(["headers": .object(["X-Retry": .number(3)])])
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test", request: request)
        #expect(curl.contains("-H 'X-Retry: 3'"))
    }

    // MARK: - params merging

    @Test func paramsMissingFromURLAreAppended() {
        // The networking plugin reports the URL from xhr.responseURL, which can
        // lose the query string after a redirect/rewrite — the original params
        // ride separately and must be restored into the copied command.
        let request = JSONValue.object(["params": .object([
            "store_id": .string("42"),
            "postcode": .string("CB4 1AA"),
        ])])
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test/menu", request: request)
        #expect(curl.contains("'https://x.test/menu?postcode=CB4%201AA&store_id=42'"))
    }

    @Test func paramsAlreadyInURLAreNotDuplicated() {
        let request = JSONValue.object(["params": .object([
            "a": .string("1"),
            "b": .string("2"),
        ])])
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test/p?a=1", request: request)
        #expect(curl.contains("'https://x.test/p?a=1&b=2'"))
    }

    @Test func paramValueCarryingMetacharactersIsPercentEncoded() {
        let request = JSONValue.object(["params": .object(["q": .string("fish & chips=good")])])
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test/s", request: request)
        #expect(curl.contains("'https://x.test/s?q=fish%20%26%20chips%3Dgood'"))
    }

    @Test func repeatedParamKeyAppendsEveryValue() {
        // query-string parses ?tag=a&tag=b into an array value.
        let request = JSONValue.object(["params": .object([
            "tag": .array([.string("a"), .string("b")]),
        ])])
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test/t", request: request)
        #expect(curl.contains("'https://x.test/t?tag=a&tag=b'"))
    }

    @Test func bareFlagParamStaysValueless() {
        // ?debug with no "=" parses to a null value.
        let request = JSONValue.object(["params": .object(["debug": .null])])
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test/d", request: request)
        #expect(curl.contains("'https://x.test/d?debug'"))
    }

    @Test func nullParamsFieldLeavesURLUntouched() {
        let request = JSONValue.object(["params": .null, "data": .null])
        let curl = ReactotronCurl.command(method: "GET", url: "https://x.test/plain", request: request)
        #expect(curl.contains("'https://x.test/plain'"))
    }

    // MARK: - FormData bodies

    @Test func formDataBodyRendersAsFormFields() {
        // RN FormData reaches the wire as {"_parts": [[name, value], …]} —
        // reproduce it as -F fields, and drop the captured multipart
        // content-type so curl mints a fresh boundary.
        let request = JSONValue.object([
            "data": .object(["_parts": .array([
                .array([.string("field"), .string("value")]),
                .array([.string("photo"), .object(["uri": .string("file:///a.jpg"), "name": .string("a.jpg")])]),
            ])]),
            "headers": .object([
                "content-type": .string("multipart/form-data; boundary=xyz"),
                "accept": .string("application/json"),
            ]),
        ])
        let curl = ReactotronCurl.command(method: "POST", url: "https://x.test/upload", request: request)
        #expect(curl.contains("-X POST"))
        #expect(curl.contains("-F 'field=value'"))
        #expect(curl.contains(#"-F 'photo={"name":"a.jpg","uri":"file:///a.jpg"}'"#))
        #expect(curl.contains("-H 'accept: application/json'"))
        #expect(!curl.contains("content-type"))
        #expect(!curl.contains("--data"))
    }

    @Test func plainObjectBodyIsNotMistakenForFormData() {
        let request = JSONValue.object(["data": .object(["_parts": .string("just a field")])])
        let curl = ReactotronCurl.command(method: "POST", url: "https://x.test", request: request)
        #expect(curl.contains(#"--data '{"_parts":"just a field"}'"#))
    }

    // MARK: - Real wire frames (captured from reactotron-core-client 2.8.10)

    @Test func realPostWireFrameProducesFullCurl() throws {
        let frame = #"""
        {"type":"api.response","payload":{"request":{"url":"https://api.example.test/consumer/order","method":"POST","data":"{\"user_id\":0,\"token\":null,\"filters\":{\"active\":false,\"promo\":\"\"},\"qty\":2}","headers":{"content-type":"application/json","accept":"application/json","x-app":"~~~ empty string ~~~"},"params":"~~~ null ~~~"},"response":{"body":{"status":"ok","data":"~~~ null ~~~"},"status":200,"headers":{"content-type":"application/json"}},"duration":123},"important":"~~~ false ~~~","date":"2026-07-15T07:20:58.991Z","deltaTime":490}
        """#
        let event = try ReactotronEvent(command: ReactotronCommand.decode(frame))
        guard case let .apiResponse(method, url, _, _, request, _) = event else {
            Issue.record("expected apiResponse, got \(event)")
            return
        }
        let curl = ReactotronCurl.command(method: method, url: url, request: request)
        #expect(curl.contains("-X POST"))
        #expect(curl.contains("-H 'content-type: application/json'"))
        #expect(curl.contains(#"--data '{"user_id":0,"token":null,"filters":{"active":false,"promo":""},"qty":2}'"#))
    }

    @Test func realGetWireFrameKeepsQueryParams() throws {
        let frame = #"""
        {"type":"api.response","payload":{"request":{"url":"https://api.example.test/menu?store_id=42&postcode=CB4+1AA&empty=&flag=0","method":"GET","data":"~~~ null ~~~","headers":{"accept":"application/json"},"params":{"store_id":"42","postcode":"CB4 1AA","empty":"~~~ empty string ~~~","flag":"0"}},"response":{"body":"~~~ skipped ~~~","status":200,"headers":{}},"duration":45},"important":"~~~ false ~~~","date":"2026-07-15T07:20:59.482Z","deltaTime":1}
        """#
        let event = try ReactotronEvent(command: ReactotronCommand.decode(frame))
        guard case let .apiResponse(method, url, _, _, request, _) = event else {
            Issue.record("expected apiResponse, got \(event)")
            return
        }
        let curl = ReactotronCurl.command(method: method, url: url, request: request)
        #expect(curl.contains("'https://api.example.test/menu?store_id=42&postcode=CB4+1AA&empty=&flag=0'"))
        #expect(!curl.contains("--data"))
    }

    @Test func realFrameWhoseResponseURLLostTheQueryRegainsIt() throws {
        // The plugin's url is xhr.responseURL — after a gateway rewrite it can
        // arrive stripped of the query the app sent, while params keeps it.
        let frame = #"""
        {"type":"api.response","payload":{"request":{"url":"https://api.example.test/menu","method":"GET","data":"~~~ null ~~~","headers":{"accept":"application/json"},"params":{"store_id":"42","flag":"0"}},"response":{"body":"~~~ skipped ~~~","status":200,"headers":{}},"duration":45},"important":"~~~ false ~~~","date":"2026-07-15T07:20:59.482Z","deltaTime":1}
        """#
        let event = try ReactotronEvent(command: ReactotronCommand.decode(frame))
        guard case let .apiResponse(method, url, _, _, request, _) = event else {
            Issue.record("expected apiResponse, got \(event)")
            return
        }
        let curl = ReactotronCurl.command(method: method, url: url, request: request)
        #expect(curl.contains("'https://api.example.test/menu?flag=0&store_id=42'"))
    }
}
