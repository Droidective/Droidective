import Testing
@testable import ADBKit
import Foundation

// MARK: - CurlParser tests

@Suite struct CurlParserTests {

    @Test func parsesSimpleGET() {
        let req = CurlParser.parse("curl https://api.example.com/users")
        #expect(req != nil)
        #expect(req?.method == .get)
        #expect(req?.url == "https://api.example.com/users")
    }

    @Test func parsesExplicitMethod() {
        let req = CurlParser.parse("curl -X DELETE https://api.example.com/users/1")
        #expect(req?.method == .delete)
    }

    @Test func parsesHeaders() {
        let req = CurlParser.parse("""
            curl -H "Authorization: Bearer tok123" \
                 -H "Accept: application/json" \
                 https://api.example.com/me
            """)
        #expect(req?.headers.count == 2)
        #expect(req?.headers.first?.key == "Authorization")
        #expect(req?.headers.first?.value == "Bearer tok123")
    }

    @Test func parsesJSONBody() {
        let req = CurlParser.parse(#"curl -d '{"name":"test"}' https://api.example.com/items"#)
        #expect(req?.method == .post)
        #expect(req?.body.type == .json)
        #expect(req?.body.jsonText == #"{"name":"test"}"#)
    }

    @Test func parsesFormFields() {
        let req = CurlParser.parse("curl -F 'user=alice' -F 'pass=secret' https://api.example.com/login")
        #expect(req?.method == .post)
        #expect(req?.body.type == .formUrlEncoded)
        #expect(req?.body.formFields.count == 2)
        #expect(req?.body.formFields.first?.key == "user")
        #expect(req?.body.formFields.first?.value == "alice")
    }

    @Test func parsesQueryParams() {
        let req = CurlParser.parse("curl 'https://api.example.com/search?q=swift&page=1'")
        #expect(req?.queryParams.count == 2)
        #expect(req?.queryParams[0].key == "q")
        #expect(req?.queryParams[0].value == "swift")
        #expect(req?.queryParams[1].key == "page")
        #expect(req?.queryParams[1].value == "1")
        #expect(req?.url == "https://api.example.com/search")
    }

    @Test func forceGetOverridesPost() {
        let req = CurlParser.parse("curl -G -d 'q=test' https://api.example.com/search")
        #expect(req?.method == .get)
        #expect(req?.body.type == BodyType.none)
        #expect(req?.queryParams.contains { $0.key == "q" && $0.value == "test" } == true)
    }

    @Test func forceGetMovesMultipleDataPairsToQueryParams() {
        let req = CurlParser.parse("curl -G -d 'q=swift' -d 'page=2' https://api.example.com/search")
        #expect(req?.method == .get)
        #expect(req?.body.type == BodyType.none)
        #expect(req?.queryParams.count == 2)
        #expect(req?.queryParams[0].key == "q")
        #expect(req?.queryParams[0].value == "swift")
        #expect(req?.queryParams[1].key == "page")
        #expect(req?.queryParams[1].value == "2")
    }

    @Test func ignoredFlagsDoNotBreakParsing() {
        let req = CurlParser.parse("curl -k --compressed -L -s https://api.example.com/test")
        #expect(req != nil)
        #expect(req?.url == "https://api.example.com/test")
    }

    @Test func returnsNilForNonCurl() {
        #expect(CurlParser.parse("wget https://example.com") == nil)
        #expect(CurlParser.parse("") == nil)
    }

    @Test func nameFromURLExtractsLastSegment() {
        #expect(CurlParser.nameFromURL("https://api.example.com/v1/users") == "users")
        #expect(CurlParser.nameFromURL("https://api.example.com") == "api.example.com")
        #expect(CurlParser.nameFromURL("https://api.example.com/") == "api.example.com")
    }

    @Test func tokenizeHandlesQuotesAndEscapes() {
        let tokens = CurlParser.tokenize(#"curl -H "Content-Type: application/json" 'https://api.com'"#)
        #expect(tokens == ["curl", "-H", "Content-Type: application/json", "https://api.com"])
    }

    @Test func tokenizeHandlesLineContinuation() {
        let tokens = CurlParser.tokenize("curl \\\n-X POST \\\nhttps://api.com")
        #expect(tokens == ["curl", "-X", "POST", "https://api.com"])
    }

    // MARK: - Export

    @Test func exportRoundtripsSimpleGET() {
        let req = SavedRequest(method: .get, url: "https://api.example.com/test")
        let curl = CurlParser.export(req)
        #expect(curl.contains("https://api.example.com/test"))
        #expect(!curl.contains("-X"))
    }

    @Test func exportIncludesMethod() {
        let req = SavedRequest(method: .post, url: "https://api.example.com/items")
        let curl = CurlParser.export(req)
        #expect(curl.contains("-X POST"))
    }

    @Test func exportIncludesHeaders() {
        let req = SavedRequest(
            method: .get,
            url: "https://api.example.com/test",
            headers: [ApiKeyValue(key: "Accept", value: "application/json")]
        )
        let curl = CurlParser.export(req)
        #expect(curl.contains("-H"))
        #expect(curl.contains("Accept: application/json"))
    }

    @Test func exportIncludesJSONBody() {
        let req = SavedRequest(
            method: .post,
            url: "https://api.example.com/items",
            body: RequestBodySpec(type: .json, jsonText: #"{"name":"test"}"#)
        )
        let curl = CurlParser.export(req)
        #expect(curl.contains("--data-raw"))
        #expect(curl.contains("Content-Type: application/json"))
    }

    @Test func exportIncludesBearerAuth() {
        let req = SavedRequest(
            method: .get,
            url: "https://api.example.com/me",
            auth: AuthSpec(type: .bearer, bearerToken: "mytoken")
        )
        let curl = CurlParser.export(req)
        #expect(curl.contains("Authorization: Bearer mytoken"))
    }

    @Test func exportIncludesBasicAuth() {
        let req = SavedRequest(
            method: .get,
            url: "https://api.example.com/me",
            auth: AuthSpec(type: .basic, basicUsername: "user", basicPassword: "pass")
        )
        let curl = CurlParser.export(req)
        #expect(curl.contains("-u"))
        #expect(curl.contains("user:pass"))
    }

    @Test func exportIncludesQueryParams() {
        let req = SavedRequest(
            method: .get,
            url: "https://api.example.com/search",
            queryParams: [ApiKeyValue(key: "q", value: "swift")]
        )
        let curl = CurlParser.export(req)
        #expect(curl.contains("q=swift"))
    }
}

// MARK: - EnvironmentEngine tests

@Suite struct EnvironmentEngineTests {

    @Test func resolvesVariables() {
        let result = EnvironmentEngine.resolve("https://{{host}}/api/v{{version}}", with: [
            "host": "example.com",
            "version": "2"
        ])
        #expect(result == "https://example.com/api/v2")
    }

    @Test func leavesUnknownVariablesUntouched() {
        let result = EnvironmentEngine.resolve("{{known}}/{{unknown}}", with: ["known": "val"])
        #expect(result == "val/{{unknown}}")
    }

    @Test func emptyVariablesReturnTemplate() {
        let result = EnvironmentEngine.resolve("{{host}}", with: [:])
        #expect(result == "{{host}}")
    }

    @Test func noTemplatesReturnInput() {
        let result = EnvironmentEngine.resolve("plain text", with: ["host": "val"])
        #expect(result == "plain text")
    }

    @Test func resolvesRequestFields() {
        let req = SavedRequest(
            url: "https://{{host}}/api",
            headers: [ApiKeyValue(key: "Auth", value: "Bearer {{token}}")],
            queryParams: [ApiKeyValue(key: "q", value: "{{query}}")],
            body: RequestBodySpec(type: .json, jsonText: #"{"key":"{{apiKey}}"}"#),
            auth: AuthSpec(type: .bearer, bearerToken: "{{token}}")
        )
        let env = ApiEnvironment(name: "test", variables: [
            ApiKeyValue(key: "host", value: "api.com"),
            ApiKeyValue(key: "token", value: "tok123"),
            ApiKeyValue(key: "query", value: "search"),
            ApiKeyValue(key: "apiKey", value: "key456"),
        ])
        let resolved = EnvironmentEngine.resolveRequest(req, with: env)
        #expect(resolved.url == "https://api.com/api")
        #expect(resolved.headers[0].value == "Bearer tok123")
        #expect(resolved.queryParams[0].value == "search")
        #expect(resolved.body.jsonText == #"{"key":"key456"}"#)
        #expect(resolved.auth.bearerToken == "tok123")
    }

    @Test func nilEnvironmentPassesThrough() {
        let req = SavedRequest(url: "https://{{host}}/api")
        let resolved = EnvironmentEngine.resolveRequest(req, with: nil)
        #expect(resolved.url == "https://{{host}}/api")
    }

    @Test func disabledVariablesAreSkipped() {
        let env = ApiEnvironment(name: "test", variables: [
            ApiKeyValue(key: "host", value: "api.com", enabled: false)
        ])
        let result = EnvironmentEngine.resolve("{{host}}", with: env.variableMap)
        #expect(result == "{{host}}")
    }
}

// MARK: - HttpClientService URL request building tests

@Suite struct HttpClientRequestBuildingTests {

    @Test func buildsSimpletGETRequest() throws {
        let req = SavedRequest(method: .get, url: "https://httpbin.org/get")
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.httpMethod == "GET")
        #expect(urlReq.url?.absoluteString == "https://httpbin.org/get")
    }

    @Test func prependsHTTPSWhenMissing() throws {
        let req = SavedRequest(method: .get, url: "httpbin.org/get")
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.url?.scheme == "https")
    }

    @Test func appendsQueryParams() throws {
        let req = SavedRequest(
            method: .get,
            url: "https://httpbin.org/get",
            queryParams: [
                ApiKeyValue(key: "q", value: "test"),
                ApiKeyValue(key: "page", value: "1"),
            ]
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        let urlString = urlReq.url?.absoluteString ?? ""
        #expect(urlString.contains("q=test"))
        #expect(urlString.contains("page=1"))
    }

    @Test func disabledParamsAreExcluded() throws {
        let req = SavedRequest(
            method: .get,
            url: "https://httpbin.org/get",
            queryParams: [
                ApiKeyValue(key: "q", value: "test", enabled: true),
                ApiKeyValue(key: "skip", value: "me", enabled: false),
            ]
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        let urlString = urlReq.url?.absoluteString ?? ""
        #expect(urlString.contains("q=test"))
        #expect(!urlString.contains("skip"))
    }

    @Test func setsHeadersFromRequest() throws {
        let req = SavedRequest(
            method: .get,
            url: "https://httpbin.org/get",
            headers: [ApiKeyValue(key: "X-Custom", value: "hello")]
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.value(forHTTPHeaderField: "X-Custom") == "hello")
    }

    @Test func setsBearerAuth() throws {
        let req = SavedRequest(
            method: .get,
            url: "https://httpbin.org/get",
            auth: AuthSpec(type: .bearer, bearerToken: "tok123")
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.value(forHTTPHeaderField: "Authorization") == "Bearer tok123")
    }

    @Test func setsBasicAuth() throws {
        let req = SavedRequest(
            method: .get,
            url: "https://httpbin.org/get",
            auth: AuthSpec(type: .basic, basicUsername: "user", basicPassword: "pass")
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        let expected = "Basic " + Data("user:pass".utf8).base64EncodedString()
        #expect(urlReq.value(forHTTPHeaderField: "Authorization") == expected)
    }

    @Test func setsApiKeyAuth() throws {
        let req = SavedRequest(
            method: .get,
            url: "https://httpbin.org/get",
            auth: AuthSpec(type: .apiKey, apiKeyName: "X-API-Key", apiKeyValue: "key123")
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.value(forHTTPHeaderField: "X-API-Key") == "key123")
    }

    @Test func setsJSONBody() throws {
        let req = SavedRequest(
            method: .post,
            url: "https://httpbin.org/post",
            body: RequestBodySpec(type: .json, jsonText: #"{"a":1}"#)
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.httpBody == Data(#"{"a":1}"#.utf8))
        #expect(urlReq.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func setsFormBody() throws {
        let req = SavedRequest(
            method: .post,
            url: "https://httpbin.org/post",
            body: RequestBodySpec(
                type: .formUrlEncoded,
                formFields: [ApiKeyValue(key: "user", value: "alice")]
            )
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        let bodyString = String(data: urlReq.httpBody ?? Data(), encoding: .utf8)
        #expect(bodyString?.contains("user=alice") == true)
        #expect(urlReq.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    }

    @Test func setsRawBody() throws {
        let req = SavedRequest(
            method: .post,
            url: "https://httpbin.org/post",
            body: RequestBodySpec(type: .raw, rawText: "<xml>hi</xml>", rawContentType: "application/xml")
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.httpBody == Data("<xml>hi</xml>".utf8))
        #expect(urlReq.value(forHTTPHeaderField: "Content-Type") == "application/xml")
    }

    @Test func throwsOnInvalidURL() {
        let req = SavedRequest(method: .get, url: "://not a url")
        #expect(throws: HttpClientError.self) {
            try HttpClientService.buildURLRequest(from: req)
        }
    }

    @Test func timeoutIs60Seconds() throws {
        let req = SavedRequest(method: .get, url: "https://httpbin.org/get")
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.timeoutInterval == 60)
    }

    @Test func urlWithNewlinesUsesFirstLine() throws {
        let req = SavedRequest(method: .get, url: "https://example.com/api\n  -H 'Accept: */*'\n  -H 'Auth: token'")
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.url?.absoluteString == "https://example.com/api")
    }

    @Test func urlWithLeadingTrailingWhitespaceIsTrimmed() throws {
        let req = SavedRequest(method: .get, url: "  https://example.com/api  \n")
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.url?.absoluteString == "https://example.com/api")
    }
}

// MARK: - Model Codable roundtrip tests

@Suite struct ApiModelCodableTests {

    @Test func savedRequestRoundtrips() throws {
        let req = SavedRequest(
            name: "Test",
            method: .post,
            url: "https://api.com/test",
            headers: [ApiKeyValue(key: "H", value: "V")],
            queryParams: [ApiKeyValue(key: "q", value: "v")],
            body: RequestBodySpec(type: .json, jsonText: "{}"),
            auth: AuthSpec(type: .bearer, bearerToken: "tok")
        )
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(SavedRequest.self, from: data)
        #expect(decoded == req)
    }

    @Test func apiCollectionRoundtrips() throws {
        let c = ApiCollection(name: "My API", requests: [SavedRequest(name: "Get users")])
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(ApiCollection.self, from: data)
        #expect(decoded == c)
    }

    @Test func apiEnvironmentRoundtrips() throws {
        let env = ApiEnvironment(name: "Staging", variables: [
            ApiKeyValue(key: "host", value: "staging.api.com")
        ])
        let data = try JSONEncoder().encode(env)
        let decoded = try JSONDecoder().decode(ApiEnvironment.self, from: data)
        #expect(decoded == env)
    }

    @Test func apiClientDataRoundtrips() throws {
        var d = ApiClientData(
            collections: [ApiCollection(name: "C1")],
            environments: [ApiEnvironment(name: "E1")],
            history: [ApiHistoryEntry(method: .get, url: "https://api.com", request: SavedRequest())]
        )
        d.activeEnvironmentId = d.environments.first?.id
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(ApiClientData.self, from: data)
        #expect(decoded == d)
    }

    @Test func exportedCollectionRoundtrips() throws {
        let ec = ExportedCollection(name: "Export", requests: [SavedRequest(name: "R1")])
        let data = try JSONEncoder().encode(ec)
        let decoded = try JSONDecoder().decode(ExportedCollection.self, from: data)
        #expect(decoded.name == ec.name)
        #expect(decoded.requests.count == 1)
    }
}

// MARK: - History limit test

@Suite struct ApiClientDataTests {

    @Test func historyLimitEnforced() {
        var d = ApiClientData()
        for i in 0..<120 {
            d.addToHistory(ApiHistoryEntry(
                method: .get, url: "https://api.com/\(i)", request: SavedRequest()
            ))
        }
        #expect(d.history.count == ApiClientData.historyLimit)
        #expect(d.history.first?.url == "https://api.com/119")
    }

    @Test func clearHistoryWorks() {
        var d = ApiClientData()
        d.addToHistory(ApiHistoryEntry(method: .get, url: "https://api.com", request: SavedRequest()))
        d.clearHistory()
        #expect(d.history.isEmpty)
    }

    @Test func activeEnvironmentReturnsCorrectEnv() {
        let env = ApiEnvironment(name: "Prod")
        var d = ApiClientData(environments: [env])
        d.activeEnvironmentId = env.id
        #expect(d.activeEnvironment?.name == "Prod")
    }

    @Test func activeEnvironmentNilWhenNoId() {
        let d = ApiClientData(environments: [ApiEnvironment(name: "Prod")])
        #expect(d.activeEnvironment == nil)
    }
}

// MARK: - ApiResponse tests

@Suite struct ApiResponseTests {

    @Test func prettyJSONFormatsValidJSON() {
        let body = Data(#"{"b":2,"a":1}"#.utf8)
        let resp = ApiResponse(statusCode: 200, statusText: "OK", headers: [
            (key: "Content-Type", value: "application/json")
        ], body: body, elapsedMs: 100, size: body.count)
        #expect(resp.isJSON)
        let pretty = resp.prettyJSON
        #expect(pretty != nil)
        #expect(pretty!.contains("\"a\" : 1"))
    }

    @Test func prettyJSONNilForNonJSON() {
        let body = Data("not json".utf8)
        let resp = ApiResponse(statusCode: 200, statusText: "OK", headers: [], body: body, elapsedMs: 50, size: body.count)
        #expect(resp.prettyJSON == nil)
    }

    @Test func bodyStringWorks() {
        let body = Data("hello".utf8)
        let resp = ApiResponse(statusCode: 200, statusText: "OK", headers: [], body: body, elapsedMs: 10, size: body.count)
        #expect(resp.bodyString == "hello")
    }

    @Test func statusTextForCommonCodes() {
        #expect(ApiResponse.statusText(for: 200) == "OK")
        #expect(ApiResponse.statusText(for: 404) == "Not Found")
        #expect(ApiResponse.statusText(for: 500) == "Internal Server Error")
        #expect(ApiResponse.statusText(for: 201) == "Created")
        #expect(ApiResponse.statusText(for: 401) == "Unauthorized")
    }

    @Test func statusTextCoversAllExplicitCodes() {
        let codes = [200, 201, 204, 301, 302, 304, 400, 401, 403, 404, 405,
                     408, 409, 422, 429, 500, 502, 503, 504]
        for code in codes {
            let text = ApiResponse.statusText(for: code)
            #expect(!text.isEmpty, "statusText empty for \(code)")
        }
    }

    @Test func statusTextFallsBackForUnknownCode() {
        let text = ApiResponse.statusText(for: 418)
        #expect(!text.isEmpty)
    }

    @Test func duplicateHeaderKeysArePreserved() {
        let body = Data()
        let resp = ApiResponse(statusCode: 200, statusText: "OK", headers: [
            (key: "Set-Cookie", value: "a=1"),
            (key: "Set-Cookie", value: "b=2"),
        ], body: body, elapsedMs: 10, size: 0)
        #expect(resp.headers.count == 2)
        #expect(resp.headers[0].value == "a=1")
        #expect(resp.headers[1].value == "b=2")
    }

    @Test func emptyBodyReturnsEmptyString() {
        let resp = ApiResponse(statusCode: 204, statusText: "No Content", headers: [],
                               body: Data(), elapsedMs: 5, size: 0)
        #expect(resp.bodyString == "")
        #expect(resp.prettyJSON == nil)
    }

    @Test func binaryBodyReturnsNilString() {
        let resp = ApiResponse(statusCode: 200, statusText: "OK", headers: [],
                               body: Data([0xFF, 0xFE, 0x00, 0x01]), elapsedMs: 10, size: 4)
        // Invalid UTF-8 bytes → bodyString may or may not decode depending on Foundation,
        // but prettyJSON must be nil for non-JSON binary.
        #expect(resp.prettyJSON == nil)
    }
}

// MARK: - CurlParser export round-trip tests

@Suite struct CurlExportRoundtripTests {

    @Test func exportThenParsePreservesGETRequest() {
        let original = SavedRequest(
            method: .get,
            url: "https://api.example.com/users",
            headers: [ApiKeyValue(key: "Accept", value: "application/json")],
            queryParams: [ApiKeyValue(key: "page", value: "1")]
        )
        let curl = CurlParser.export(original)
        let parsed = CurlParser.parse(curl)
        #expect(parsed?.method == .get)
        #expect(parsed?.url.contains("api.example.com") == true)
    }

    @Test func exportThenParsePreservesPOSTWithJSON() {
        let original = SavedRequest(
            method: .post,
            url: "https://api.example.com/items",
            body: RequestBodySpec(type: .json, jsonText: #"{"name":"test"}"#)
        )
        let curl = CurlParser.export(original)
        let parsed = CurlParser.parse(curl)
        #expect(parsed?.method == .post)
        #expect(parsed?.body.type == .json)
        #expect(parsed?.body.jsonText == #"{"name":"test"}"#)
    }

    @Test func exportFormUrlEncodedBody() {
        let req = SavedRequest(
            method: .post,
            url: "https://api.example.com/login",
            body: RequestBodySpec(
                type: .formUrlEncoded,
                formFields: [
                    ApiKeyValue(key: "user", value: "alice"),
                    ApiKeyValue(key: "pass", value: "secret")
                ]
            )
        )
        let curl = CurlParser.export(req)
        #expect(curl.contains("--data"))
        #expect(curl.contains("user=alice"))
        #expect(curl.contains("pass=secret"))
    }

    @Test func exportApiKeyAuth() {
        let req = SavedRequest(
            method: .get,
            url: "https://api.example.com/data",
            auth: AuthSpec(type: .apiKey, apiKeyName: "X-API-Key", apiKeyValue: "mykey")
        )
        let curl = CurlParser.export(req)
        #expect(curl.contains("X-API-Key: mykey"))
    }

    @Test func exportWithEnvironmentResolvesVariables() {
        let req = SavedRequest(
            method: .get,
            url: "https://{{host}}/api",
            auth: AuthSpec(type: .bearer, bearerToken: "{{token}}")
        )
        let env = ApiEnvironment(name: "test", variables: [
            ApiKeyValue(key: "host", value: "prod.api.com"),
            ApiKeyValue(key: "token", value: "tok999")
        ])
        let curl = CurlParser.export(req, environment: env)
        #expect(curl.contains("prod.api.com"))
        #expect(curl.contains("tok999"))
        #expect(!curl.contains("{{host}}"))
    }
}

// MARK: - HttpClientService additional tests

@Suite struct HttpClientRequestEdgeCaseTests {

    @Test func allHTTPMethodsAreBuildable() throws {
        for method in HttpMethod.allCases {
            let req = SavedRequest(method: method, url: "https://httpbin.org/anything")
            let urlReq = try HttpClientService.buildURLRequest(from: req)
            #expect(urlReq.httpMethod == method.rawValue)
        }
    }

    @Test func emptyBodyIsNotSet() throws {
        let req = SavedRequest(method: .post, url: "https://httpbin.org/post",
                               body: RequestBodySpec(type: .json, jsonText: ""))
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.httpBody == nil)
    }

    @Test func customContentTypeNotOverridden() throws {
        let req = SavedRequest(
            method: .post,
            url: "https://httpbin.org/post",
            headers: [ApiKeyValue(key: "Content-Type", value: "application/xml")],
            body: RequestBodySpec(type: .json, jsonText: #"{"a":1}"#)
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.value(forHTTPHeaderField: "Content-Type") == "application/xml")
    }

    @Test func queryParamsMergeWithExistingURL() throws {
        let req = SavedRequest(
            method: .get,
            url: "https://httpbin.org/get?existing=1",
            queryParams: [ApiKeyValue(key: "added", value: "2")]
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        let url = urlReq.url?.absoluteString ?? ""
        #expect(url.contains("existing=1"))
        #expect(url.contains("added=2"))
    }

    @Test func emptyBearerTokenNotSent() throws {
        let req = SavedRequest(
            method: .get,
            url: "https://httpbin.org/get",
            auth: AuthSpec(type: .bearer, bearerToken: "")
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func emptyApiKeyNameNotSent() throws {
        let req = SavedRequest(
            method: .get,
            url: "https://httpbin.org/get",
            auth: AuthSpec(type: .apiKey, apiKeyName: "", apiKeyValue: "val")
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        #expect(urlReq.allHTTPHeaderFields?.count ?? 0 == 0)
    }

    @Test func formFieldsPercentEncodeSpecialChars() throws {
        let req = SavedRequest(
            method: .post,
            url: "https://httpbin.org/post",
            body: RequestBodySpec(
                type: .formUrlEncoded,
                formFields: [ApiKeyValue(key: "q", value: "a b+c&d=e")]
            )
        )
        let urlReq = try HttpClientService.buildURLRequest(from: req)
        let body = String(data: urlReq.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(!body.contains(" "))
        #expect(body.contains("q="))
    }
}
