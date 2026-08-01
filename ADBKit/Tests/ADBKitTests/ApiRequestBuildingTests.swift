import Foundation
import Testing

@testable import ADBKit

// MARK: - URL assembly

@Suite struct ApiURLBuildingTests {

    private func url(_ request: SavedRequest) throws -> String {
        try HttpRequestBuilder.prepare(request).url
    }

    @Test func keepsAFullyQualifiedURL() throws {
        #expect(try url(SavedRequest(url: "https://httpbin.org/get")) == "https://httpbin.org/get")
    }

    @Test func defaultsToHTTPSForAPublicHost() throws {
        #expect(try url(SavedRequest(url: "httpbin.org/get")) == "https://httpbin.org/get")
    }

    /// A dev server on the machine or an emulator's host alias almost never
    /// speaks TLS; forcing https there fails with a confusing handshake error.
    @Test(arguments: [
        "localhost:3000/api",
        "127.0.0.1:8080/health",
        "10.0.2.2:3000/api",
        "192.168.1.50:8000/x",
        "172.16.4.4/x",
        "169.254.10.1/x",
        "my-mac.local/api",
        "backend.test/api",
    ])
    func defaultsToHTTPForLocalAddresses(host: String) throws {
        #expect(try url(SavedRequest(url: host)).hasPrefix("http://"))
    }

    @Test(arguments: ["example.com/x", "8.8.8.8/x", "api.internal.example.com/x", "172.32.0.1/x"])
    func defaultsToHTTPSForEverythingElse(host: String) throws {
        #expect(try url(SavedRequest(url: host)).hasPrefix("https://"))
    }

    @Test func trimsWhitespaceAndUsesTheFirstLine() throws {
        let pasted = SavedRequest(url: "  https://example.com/api  \n  -H 'Accept: */*'\n")
        #expect(try url(pasted) == "https://example.com/api")
    }

    @Test func rejectsAnEmptyURL() {
        #expect(throws: ApiRequestError.emptyURL) {
            try HttpRequestBuilder.prepare(SavedRequest(url: "   "))
        }
    }

    @Test func rejectsANonHTTPScheme() {
        #expect(throws: ApiRequestError.unsupportedScheme("ftp")) {
            try HttpRequestBuilder.prepare(SavedRequest(url: "ftp://example.com/x"))
        }
        #expect(throws: ApiRequestError.unsupportedScheme("file")) {
            try HttpRequestBuilder.prepare(SavedRequest(url: "file:///etc/passwd"))
        }
    }

    @Test func escapesASpaceTypedIntoThePath() throws {
        let prepared = try HttpRequestBuilder.prepare(SavedRequest(url: "https://example.com/a b"))
        #expect(prepared.url == "https://example.com/a%20b")
    }

    /// The repair pass exists for corelibs-foundation, which doesn't escape
    /// these itself the way Apple's `URL(string:)` does.
    @Test func theRepairPassLeavesTheAuthorityAlone() {
        #expect(
            HttpRequestBuilder.percentEncodeAfterAuthority("https://ex ample.com/a b")
                == "https://ex ample.com/a%20b"
        )
    }

    @Test func aSpaceInTheHostIsAnErrorNotASilentEncode() {
        #expect(throws: ApiRequestError.invalidURL("https://exa mple.com/x")) {
            try HttpRequestBuilder.prepare(SavedRequest(url: "https://exa mple.com/x"))
        }
    }

    @Test func doesNotDoubleEncodeAnAlreadyEncodedPath() throws {
        #expect(try url(SavedRequest(url: "https://example.com/a%20b")) == "https://example.com/a%20b")
    }

    // MARK: Query

    @Test func appendsEnabledParamsAndSkipsDisabledOnes() throws {
        let request = SavedRequest(
            url: "https://httpbin.org/get",
            queryParams: [
                ApiKeyValue(key: "q", value: "test"),
                ApiKeyValue(key: "skip", value: "me", enabled: false),
                ApiKeyValue(key: "page", value: "1"),
            ]
        )
        #expect(try url(request) == "https://httpbin.org/get?q=test&page=1")
    }

    @Test func mergesWithAQueryAlreadyInTheURL() throws {
        let request = SavedRequest(
            url: "https://httpbin.org/get?existing=1",
            queryParams: [ApiKeyValue(key: "added", value: "2")]
        )
        #expect(try url(request) == "https://httpbin.org/get?existing=1&added=2")
    }

    /// Under-encoding here is what lets a value containing `&` or `=` forge
    /// extra parameters, so everything outside RFC 3986 unreserved is escaped.
    @Test func percentEncodesEveryReservedCharacterInAValue() throws {
        let request = SavedRequest(
            url: "https://api.co/s",
            queryParams: [ApiKeyValue(key: "q", value: "a b&c=d+e/f?g#h")]
        )
        #expect(try url(request) == "https://api.co/s?q=a%20b%26c%3Dd%2Be%2Ff%3Fg%23h")
    }

    @Test func encodesTheKeyToo() throws {
        let request = SavedRequest(
            url: "https://api.co/s",
            queryParams: [ApiKeyValue(key: "a key", value: "1")]
        )
        #expect(try url(request) == "https://api.co/s?a%20key=1")
    }

    @Test func encodesUnicodeValues() throws {
        let request = SavedRequest(
            url: "https://api.co/s",
            queryParams: [ApiKeyValue(key: "q", value: "café")]
        )
        #expect(try url(request) == "https://api.co/s?q=caf%C3%A9")
    }

    @Test func keepsRepeatedParamsAndEmptyValues() throws {
        let request = SavedRequest(
            url: "https://api.co/s",
            queryParams: [
                ApiKeyValue(key: "tag", value: "a"),
                ApiKeyValue(key: "tag", value: "b"),
                ApiKeyValue(key: "flag", value: ""),
            ]
        )
        #expect(try url(request) == "https://api.co/s?tag=a&tag=b&flag=")
    }

    @Test func ignoresParamsWithNoKey() throws {
        let request = SavedRequest(
            url: "https://api.co/s",
            queryParams: [ApiKeyValue(key: "", value: "orphan"), ApiKeyValue(key: "q", value: "1")]
        )
        #expect(try url(request) == "https://api.co/s?q=1")
    }

    @Test func preservesTheFragmentAfterTheQuery() throws {
        let request = SavedRequest(
            url: "https://api.co/page#section",
            queryParams: [ApiKeyValue(key: "q", value: "1")]
        )
        #expect(try url(request) == "https://api.co/page?q=1#section")
    }

    // MARK: Path variables

    @Test func substitutesPathVariables() throws {
        let request = SavedRequest(
            url: "https://api.co/v1/users/:id/posts/:postId",
            pathVariables: [
                ApiKeyValue(key: "id", value: "42"),
                ApiKeyValue(key: "postId", value: "7"),
            ]
        )
        #expect(try url(request) == "https://api.co/v1/users/42/posts/7")
    }

    @Test func encodesASubstitutedPathValue() throws {
        let request = SavedRequest(
            url: "https://api.co/files/:name",
            pathVariables: [ApiKeyValue(key: "name", value: "a b/c")]
        )
        #expect(try url(request) == "https://api.co/files/a%20b%2Fc")
    }

    @Test func warnsWhenAPathVariableHasNoValue() throws {
        let prepared = try HttpRequestBuilder.prepare(SavedRequest(url: "https://api.co/users/:id"))
        #expect(prepared.url == "https://api.co/users/:id")
        #expect(prepared.warnings.contains { $0.contains(":id") })
    }

    @Test func aPortIsNotMistakenForAPathVariable() throws {
        let request = SavedRequest(
            url: "http://localhost:3000/users/:id",
            pathVariables: [ApiKeyValue(key: "id", value: "9")]
        )
        #expect(try url(request) == "http://localhost:3000/users/9")
    }
}

// MARK: - Headers

@Suite struct ApiHeaderBuildingTests {

    @Test func setsHeadersInOrderKeepingDuplicates() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                url: "https://api.co/x",
                headers: [
                    ApiKeyValue(key: "X-A", value: "1"),
                    ApiKeyValue(key: "X-A", value: "2"),
                    ApiKeyValue(key: "X-B", value: "3", enabled: false),
                ]
            )
        )
        #expect(prepared.headers.map(\.key) == ["X-A", "X-A"])
        #expect(prepared.headers.map(\.value) == ["1", "2"])
    }

    /// A variable expanding to `value\r\nX-Injected: 1` must not be able to
    /// append a header of its own.
    @Test func stripsCRLFFromAHeaderValue() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                url: "https://api.co/x",
                headers: [ApiKeyValue(key: "X-Note", value: "ok\r\nX-Injected: yes")]
            )
        )
        #expect(prepared.headers.count == 1)
        #expect(prepared.headers[0].value == "okX-Injected: yes")
        #expect(prepared.warnings.contains { $0.contains("line break") })
    }

    @Test(arguments: ["Bad Name", "Bad:Name", "Bad\nName", "Bad(Name)", "", "  "])
    func rejectsAnUnusableHeaderName(name: String) throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(url: "https://api.co/x", headers: [ApiKeyValue(key: name, value: "v")])
        )
        #expect(prepared.headers.isEmpty)
    }

    @Test func trimsSurroundingWhitespace() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                url: "https://api.co/x",
                headers: [ApiKeyValue(key: "  X-A  ", value: "  v  ")]
            )
        )
        #expect(prepared.headers[0].key == "X-A")
        #expect(prepared.headers[0].value == "v")
    }
}

// MARK: - Auth

@Suite struct ApiAuthBuildingTests {

    private func authorization(_ auth: AuthSpec) throws -> String? {
        try HttpRequestBuilder.prepare(SavedRequest(url: "https://api.co/x", auth: auth))
            .headerValue("Authorization")
    }

    @Test func bearer() throws {
        #expect(try authorization(AuthSpec(type: .bearer, bearerToken: "tok123")) == "Bearer tok123")
    }

    @Test func bearerTrimsWhitespaceAroundAPastedToken() throws {
        #expect(try authorization(AuthSpec(type: .bearer, bearerToken: "  tok  \n")) == "Bearer tok")
    }

    @Test func basicIsBase64OfUserColonPassword() throws {
        let header = try authorization(
            AuthSpec(type: .basic, basicUsername: "user", basicPassword: "pass")
        )
        #expect(header == "Basic " + Data("user:pass".utf8).base64EncodedString())
    }

    @Test func basicHandlesNonASCIICredentials() throws {
        let header = try authorization(
            AuthSpec(type: .basic, basicUsername: "usér", basicPassword: "pä55")
        )
        #expect(header == "Basic " + Data("usér:pä55".utf8).base64EncodedString())
    }

    @Test func basicWithOnlyAUsernameStillSends() throws {
        #expect(try authorization(AuthSpec(type: .basic, basicUsername: "u")) != nil)
    }

    @Test func apiKeyInAHeader() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                url: "https://api.co/x",
                auth: AuthSpec(type: .apiKey, apiKeyName: "X-API-Key", apiKeyValue: "key123")
            )
        )
        #expect(prepared.headerValue("X-API-Key") == "key123")
    }

    @Test func apiKeyInTheQuery() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                url: "https://api.co/x",
                queryParams: [ApiKeyValue(key: "q", value: "1")],
                auth: AuthSpec(
                    type: .apiKey, apiKeyName: "api_key", apiKeyValue: "k e y",
                    apiKeyLocation: .query
                )
            )
        )
        #expect(prepared.url == "https://api.co/x?q=1&api_key=k%20e%20y")
        #expect(prepared.headerValue("api_key") == nil)
    }

    @Test func oauth2UsesItsHeaderPrefix() throws {
        #expect(
            try authorization(AuthSpec(type: .oauth2, oauth2Token: "tok", oauth2HeaderPrefix: "Token"))
                == "Token tok"
        )
    }

    @Test func oauth2WithNoPrefixSendsTheBareToken() throws {
        #expect(
            try authorization(AuthSpec(type: .oauth2, oauth2Token: "tok", oauth2HeaderPrefix: ""))
                == "tok"
        )
    }

    @Test func authReplacesAManualAuthorizationHeaderAndSaysSo() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                url: "https://api.co/x",
                headers: [ApiKeyValue(key: "Authorization", value: "Bearer stale")],
                auth: AuthSpec(type: .bearer, bearerToken: "fresh")
            )
        )
        #expect(prepared.headerValue("Authorization") == "Bearer fresh")
        #expect(prepared.headers.filter { $0.key.lowercased() == "authorization" }.count == 1)
        #expect(prepared.warnings.contains { $0.contains("replaced") })
    }

    @Test(arguments: [
        AuthSpec(type: .bearer),
        AuthSpec(type: .basic),
        AuthSpec(type: .apiKey),
        AuthSpec(type: .oauth2),
    ])
    func anIncompleteCredentialWarnsInsteadOfSendingNothing(auth: AuthSpec) throws {
        let prepared = try HttpRequestBuilder.prepare(SavedRequest(url: "https://api.co/x", auth: auth))
        #expect(prepared.headerValue("Authorization") == nil)
        #expect(!prepared.warnings.isEmpty)
    }

    @Test func noAuthAddsNothing() throws {
        let prepared = try HttpRequestBuilder.prepare(SavedRequest(url: "https://api.co/x"))
        #expect(prepared.headers.isEmpty)
        #expect(prepared.warnings.isEmpty)
    }
}

// MARK: - Bodies

@Suite struct ApiBodyBuildingTests {

    /// Nested `#require` calls can't be expanded, so the body is unwrapped here.
    static func jsonBody(_ prepared: PreparedRequest) throws -> [String: Any] {
        let data = try #require(prepared.body)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test func jsonBodySetsTheDefaultContentType() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/x",
                body: RequestBodySpec(type: .json, jsonText: #"{"a":1}"#)
            )
        )
        #expect(prepared.body == Data(#"{"a":1}"#.utf8))
        #expect(prepared.headerValue("Content-Type") == "application/json")
    }

    @Test func anExplicitContentTypeIsNotOverridden() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/x",
                headers: [ApiKeyValue(key: "content-type", value: "application/vnd.api+json")],
                body: RequestBodySpec(type: .json, jsonText: "{}")
            )
        )
        #expect(prepared.headerValue("Content-Type") == "application/vnd.api+json")
        #expect(prepared.headers.filter { $0.key.lowercased() == "content-type" }.count == 1)
    }

    @Test func invalidJSONIsSentAsTypedWithAWarning() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/x",
                body: RequestBodySpec(type: .json, jsonText: "{oops")
            )
        )
        #expect(prepared.body == Data("{oops".utf8))
        #expect(prepared.warnings.contains { $0.contains("isn't valid JSON") })
    }

    @Test func emptyBodiesAreNotAttached() throws {
        for spec in [
            RequestBodySpec(type: .json, jsonText: ""),
            RequestBodySpec(type: .raw, rawText: ""),
            RequestBodySpec(type: .formUrlEncoded),
            RequestBodySpec(type: .multipart),
            RequestBodySpec(type: .graphql),
            RequestBodySpec(type: .binary),
            RequestBodySpec(type: BodyType.none),
        ] {
            let prepared = try HttpRequestBuilder.prepare(
                SavedRequest(method: .post, url: "https://api.co/x", body: spec)
            )
            #expect(prepared.body == nil, "\(spec.type) should not attach a body")
        }
    }

    @Test func rawBodyTakesItsContentTypeFromTheLanguage() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/x",
                body: RequestBodySpec(type: .raw, rawText: "<a/>", rawLanguage: .xml)
            )
        )
        #expect(prepared.headerValue("Content-Type") == "application/xml")
    }

    @Test func rawContentTypeOverridesTheLanguage() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/x",
                body: RequestBodySpec(
                    type: .raw, rawText: "a,b", rawLanguage: .text, rawContentType: "text/csv"
                )
            )
        )
        #expect(prepared.headerValue("Content-Type") == "text/csv")
    }

    @Test func formUrlEncodedEscapesReservedCharacters() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/x",
                body: RequestBodySpec(
                    type: .formUrlEncoded,
                    formFields: [
                        ApiKeyValue(key: "q", value: "a b+c&d=e"),
                        ApiKeyValue(key: "skip", value: "x", enabled: false),
                    ]
                )
            )
        )
        #expect(prepared.bodyText == "q=a%20b%2Bc%26d%3De")
        #expect(prepared.headerValue("Content-Type") == "application/x-www-form-urlencoded")
    }

    @Test func multipartBodyIsExactlyRFC7578Shaped() throws {
        let files = StubFileReader(files: ["/tmp/a.png": Data([0x89, 0x50, 0x4E, 0x47])])
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/up",
                body: RequestBodySpec(
                    type: .multipart,
                    multipartFields: [
                        ApiFormField(key: "note", value: "hi"),
                        ApiFormField(key: "photo", value: "/tmp/a.png", kind: .file),
                    ]
                )
            ),
            files: files,
            boundary: "BOUND"
        )
        #expect(prepared.headerValue("Content-Type") == "multipart/form-data; boundary=BOUND")

        var expected = Data()
        expected.append(Data("--BOUND\r\n".utf8))
        expected.append(Data("Content-Disposition: form-data; name=\"note\"\r\n\r\n".utf8))
        expected.append(Data("hi\r\n".utf8))
        expected.append(Data("--BOUND\r\n".utf8))
        expected.append(
            Data("Content-Disposition: form-data; name=\"photo\"; filename=\"a.png\"\r\n".utf8)
        )
        expected.append(Data("Content-Type: image/png\r\n\r\n".utf8))
        expected.append(Data([0x89, 0x50, 0x4E, 0x47]))
        expected.append(Data("\r\n--BOUND--\r\n".utf8))
        #expect(prepared.body == expected)
    }

    @Test func multipartUsesAnExplicitPartContentType() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/up",
                body: RequestBodySpec(
                    type: .multipart,
                    multipartFields: [
                        ApiFormField(key: "meta", value: "{}", contentType: "application/json")
                    ]
                )
            ),
            boundary: "B"
        )
        #expect(prepared.bodyText?.contains("Content-Type: application/json") == true)
    }

    @Test func multipartEscapesQuotesInNames() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/up",
                body: RequestBodySpec(
                    type: .multipart,
                    multipartFields: [ApiFormField(key: "a\"b", value: "v")]
                )
            ),
            boundary: "B"
        )
        #expect(prepared.bodyText?.contains(#"name="a%22b""#) == true)
    }

    @Test func multipartWithoutAFilePathIsAnError() {
        #expect(throws: ApiRequestError.missingFilePath(field: "photo")) {
            try HttpRequestBuilder.prepare(
                SavedRequest(
                    method: .post,
                    url: "https://api.co/up",
                    body: RequestBodySpec(
                        type: .multipart,
                        multipartFields: [ApiFormField(key: "photo", value: "  ", kind: .file)]
                    )
                )
            )
        }
    }

    @Test func anUnreadableFileReportsItsPath() {
        #expect(throws: ApiRequestError.fileUnreadable(path: "/nope.bin", reason: "No such file")) {
            try HttpRequestBuilder.prepare(
                SavedRequest(
                    method: .put,
                    url: "https://api.co/up",
                    body: RequestBodySpec(type: .binary, binaryFilePath: "/nope.bin")
                ),
                files: StubFileReader()
            )
        }
    }

    @Test func binaryBodyGuessesContentTypeFromTheExtension() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .put,
                url: "https://api.co/up",
                body: RequestBodySpec(type: .binary, binaryFilePath: "/tmp/report.pdf")
            ),
            files: StubFileReader(files: ["/tmp/report.pdf": Data([1, 2, 3])])
        )
        #expect(prepared.body == Data([1, 2, 3]))
        #expect(prepared.headerValue("Content-Type") == "application/pdf")
    }

    @Test func graphqlWrapsQueryAndVariables() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/graphql",
                body: RequestBodySpec(
                    type: .graphql,
                    graphqlQuery: "query Me { me { id } }",
                    graphqlVariables: #"{"first":10}"#
                )
            )
        )
        let json = try Self.jsonBody(prepared)
        #expect(json["query"] as? String == "query Me { me { id } }")
        #expect((json["variables"] as? [String: Any])?["first"] as? Int == 10)
        #expect(prepared.headerValue("Content-Type") == "application/json")
    }

    @Test func graphqlWithBrokenVariablesWarnsAndOmitsThem() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/graphql",
                body: RequestBodySpec(
                    type: .graphql, graphqlQuery: "{ me }", graphqlVariables: "{not json"
                )
            )
        )
        let json = try Self.jsonBody(prepared)
        #expect(json["variables"] == nil)
        #expect(prepared.warnings.contains { $0.contains("GraphQL variables") })
    }

    @Test func graphqlEscapesQuotesAndNewlinesInTheQuery() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/graphql",
                body: RequestBodySpec(
                    type: .graphql, graphqlQuery: "query {\n  find(q: \"a\\b\") { id }\n}"
                )
            )
        )
        let json = try Self.jsonBody(prepared)
        #expect(json["query"] as? String == "query {\n  find(q: \"a\\b\") { id }\n}")
    }

    @Test func aBodyOnAGETIsSentWithAWarning() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .get,
                url: "https://api.co/x",
                body: RequestBodySpec(type: .json, jsonText: "{}")
            )
        )
        #expect(prepared.body != nil)
        #expect(prepared.warnings.contains { $0.contains("don't normally carry a body") })
    }

    @Test func aBodyOnAPOSTIsUnremarkable() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(
                method: .post,
                url: "https://api.co/x",
                body: RequestBodySpec(type: .json, jsonText: "{}")
            )
        )
        #expect(!prepared.warnings.contains { $0.contains("don't normally carry a body") })
    }

    @Test func disablingTLSValidationIsAlwaysCalledOut() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(url: "https://api.co/x", settings: RequestSettings(validateTLS: false))
        )
        #expect(prepared.warnings.contains { $0.lowercased().contains("validation is disabled") })
    }
}

// MARK: - Settings clamping

@Suite struct RequestSettingsTests {

    @Test func zeroTimeoutMeansTheCeilingNotZero() {
        #expect(RequestSettings(timeoutSeconds: 0).effectiveTimeout == RequestSettings.maxTimeout)
        #expect(RequestSettings(timeoutSeconds: -5).effectiveTimeout == RequestSettings.maxTimeout)
    }

    @Test func timeoutIsCappedAndOtherwisePassedThrough() {
        #expect(RequestSettings(timeoutSeconds: 30).effectiveTimeout == 30)
        #expect(RequestSettings(timeoutSeconds: 9999).effectiveTimeout == RequestSettings.maxTimeout)
    }

    @Test func redirectAndSizeLimitsAreClamped() {
        #expect(RequestSettings(maxRedirects: -1).effectiveMaxRedirects == 0)
        #expect(RequestSettings(maxRedirects: 500).effectiveMaxRedirects == 50)
        #expect(
            RequestSettings(maxResponseBytes: 0).effectiveMaxResponseBytes
                == RequestSettings.defaultMaxResponseBytes
        )
    }

    @Test func theTimeoutReachesTheWireRequest() throws {
        let prepared = try HttpRequestBuilder.prepare(
            SavedRequest(url: "https://api.co/x", settings: RequestSettings(timeoutSeconds: 12))
        )
        #expect(prepared.settings.effectiveTimeout == 12)
    }
}
