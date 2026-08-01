import Foundation
import Testing

@testable import ADBKit

// MARK: - Tokenizer

@Suite struct CurlTokenizerTests {

    @Test func splitsQuotedAndBareTokens() {
        let tokens = CurlParser.tokenize(#"curl -H "Content-Type: application/json" 'https://api.com'"#)
        #expect(tokens == ["curl", "-H", "Content-Type: application/json", "https://api.com"])
    }

    @Test func joinsLineContinuations() {
        let tokens = CurlParser.tokenize("curl \\\n-X POST \\\nhttps://api.com")
        #expect(tokens == ["curl", "-X", "POST", "https://api.com"])
    }

    @Test func joinsWindowsCaretContinuations() {
        let tokens = CurlParser.tokenize("curl ^\n-X POST ^\nhttps://api.com")
        #expect(tokens == ["curl", "-X", "POST", "https://api.com"])
    }

    @Test func keepsAnEmptyQuotedArgument() {
        #expect(CurlParser.tokenize("curl -d '' https://api.com") == ["curl", "-d", "", "https://api.com"])
    }

    @Test func adjacentQuotedRunsAreOneToken() {
        #expect(CurlParser.tokenize(#"curl 'https://api.com'"/path""#) == ["curl", "https://api.com/path"])
    }

    @Test func decodesAnsiCQuoting() {
        // Chrome emits $'…' when a header or URL holds non-ASCII or escapes.
        let tokens = CurlParser.tokenize(#"curl -H $'X-Name: caf\xc3\xa9' https://api.com"#)
        #expect(tokens == ["curl", "-H", "X-Name: café", "https://api.com"])
    }

    @Test func decodesAnsiCUnicodeEscape() {
        let tokens = CurlParser.tokenize(#"curl -d $'aAb' https://api.com"#)
        #expect(tokens == ["curl", "-d", "aAb", "https://api.com"])
    }

    @Test func backslashInsideDoubleQuotesStaysLiteralExceptBeforeQuote() {
        let tokens = CurlParser.tokenize(#"curl -d "a\\b \"q\"" https://api.com"#)
        #expect(tokens == ["curl", "-d", #"a\b "q""#, "https://api.com"])
    }

    @Test func singleQuotesProtectBackslashes() {
        let tokens = CurlParser.tokenize(#"curl -d '{"re":"\d+"}' https://api.com"#)
        #expect(tokens == ["curl", "-d", #"{"re":"\d+"}"#, "https://api.com"])
    }

    @Test func newlineInsideDoubleQuotesIsKept() {
        let tokens = CurlParser.tokenize("curl -d \"line1\nline2\" https://api.com")
        #expect(tokens == ["curl", "-d", "line1\nline2", "https://api.com"])
    }
}

// MARK: - Flags that must never be mistaken for the URL

@Suite struct CurlFlagIsolationTests {

    /// Each of these has a value that looks like a positional argument. Before
    /// the flag table existed, the value became the request URL and the real
    /// URL was silently dropped.
    @Test(arguments: [
        "curl --data-urlencode 'q=hello world' https://api.example.com/search",
        "curl -x http://127.0.0.1:8888 https://api.example.com/search",
        "curl --proxy http://127.0.0.1:8888 https://api.example.com/search",
        "curl -T local.txt https://api.example.com/search",
        "curl --upload-file local.txt https://api.example.com/search",
        "curl -o out.json https://api.example.com/search",
        "curl -b 'session=abc123' https://api.example.com/search",
        "curl --cookie-jar jar.txt https://api.example.com/search",
        "curl -E client.pem https://api.example.com/search",
        "curl --cacert ca.pem https://api.example.com/search",
        "curl -w '%{http_code}' https://api.example.com/search",
        "curl --connect-timeout 5 https://api.example.com/search",
        "curl --retry 3 https://api.example.com/search",
        "curl --resolve example.com:443:127.0.0.1 https://api.example.com/search",
        "curl -r 0-1024 https://api.example.com/search",
        "curl --limit-rate 100k https://api.example.com/search",
        "curl --aws-sigv4 aws:amz:eu-west-1:s3 https://api.example.com/search",
    ])
    func flagValuesNeverBecomeTheURL(command: String) throws {
        let request = try #require(CurlParser.parse(command))
        #expect(request.url == "https://api.example.com/search")
    }

    @Test func unknownFlagDoesNotSwallowTheURL() throws {
        let request = try #require(
            CurlParser.parse("curl --some-future-flag https://api.example.com/v1/items")
        )
        #expect(request.url == "https://api.example.com/v1/items")
    }

    @Test func aNonURLPositionalIsReportedRatherThanUsedSilently() throws {
        let result = try #require(
            CurlParser.parseWithWarnings("curl https://api.example.com/x leftover-token")
        )
        #expect(result.request.url == "https://api.example.com/x")
        #expect(result.warnings.contains { $0.contains("leftover-token") })
    }

    @Test func withNoURLLikeTokenTheFirstPositionalIsStillUsed() throws {
        // Better to attempt something than to reject the paste outright.
        let request = try #require(CurlParser.parse("curl myhost/api"))
        #expect(request.url == "myhost/api")
    }

    @Test func returnsNilWithoutAnyPositional() {
        #expect(CurlParser.parse("curl -X POST") == nil)
    }
}

// MARK: - Method, URL, query

@Suite struct CurlBasicsTests {

    @Test func parsesSimpleGET() throws {
        let request = try #require(CurlParser.parse("curl https://api.example.com/users"))
        #expect(request.method == .get)
        #expect(request.url == "https://api.example.com/users")
        #expect(request.body.type == BodyType.none)
    }

    @Test func parsesExplicitMethod() {
        #expect(CurlParser.parse("curl -X DELETE https://api.example.com/users/1")?.method == .delete)
    }

    @Test func parsesAttachedShortFlagValue() {
        #expect(CurlParser.parse("curl -XPOST https://api.example.com/x")?.method == .post)
    }

    @Test func parsesBundledBooleanShortFlags() throws {
        let request = try #require(CurlParser.parse("curl -sSL https://api.example.com/x"))
        #expect(request.url == "https://api.example.com/x")
        #expect(request.settings.followRedirects)
    }

    @Test func parsesLongFlagWithEqualsForm() {
        #expect(CurlParser.parse("curl --request=PATCH https://api.example.com/x")?.method == .patch)
    }

    @Test func headFlagImpliesHEAD() {
        #expect(CurlParser.parse("curl -I https://api.example.com/x")?.method == .head)
    }

    @Test func uploadFileImpliesPUTAndABinaryBody() throws {
        let request = try #require(CurlParser.parse("curl -T /tmp/a.bin https://api.example.com/x"))
        #expect(request.method == .put)
        #expect(request.body.type == .binary)
        #expect(request.body.binaryFilePath == "/tmp/a.bin")
    }

    @Test func unknownMethodWarnsAndFallsBackToGET() throws {
        let result = try #require(CurlParser.parseWithWarnings("curl -X PURGE https://api.example.com/x"))
        #expect(result.request.method == .get)
        #expect(result.warnings.contains { $0.contains("PURGE") })
    }

    @Test func splitsQueryStringIntoParams() throws {
        let request = try #require(CurlParser.parse("curl 'https://api.example.com/search?q=swift&page=1'"))
        #expect(request.url == "https://api.example.com/search")
        #expect(request.queryParams.map(\.key) == ["q", "page"])
        #expect(request.queryParams.map(\.value) == ["swift", "1"])
    }

    @Test func decodesPercentAndPlusInQueryValues() throws {
        let request = try #require(
            CurlParser.parse("curl 'https://api.example.com/s?q=a%20b&r=c+d&t=100%25'")
        )
        #expect(request.queryParams.map(\.value) == ["a b", "c d", "100%"])
    }

    @Test func keepsValuelessQueryKeys() throws {
        let request = try #require(CurlParser.parse("curl 'https://api.example.com/s?flag&q=1'"))
        #expect(request.queryParams.map(\.key) == ["flag", "q"])
        #expect(request.queryParams[0].value == "")
    }

    @Test func keepsTheFragmentOnTheURL() throws {
        let request = try #require(CurlParser.parse("curl 'https://api.example.com/s?q=1#top'"))
        #expect(request.url == "https://api.example.com/s#top")
    }

    @Test func urlQueryFlagAddsParams() throws {
        let request = try #require(
            CurlParser.parse("curl --url-query 'q=swift' https://api.example.com/s")
        )
        #expect(request.queryParams.contains { $0.key == "q" && $0.value == "swift" })
    }

    @Test func explicitUrlFlagWins() throws {
        let request = try #require(CurlParser.parse("curl --url https://api.example.com/from-flag"))
        #expect(request.url == "https://api.example.com/from-flag")
    }

    @Test func rejectsNonCurlInput() {
        #expect(CurlParser.parse("wget https://example.com") == nil)
        #expect(CurlParser.parse("") == nil)
        #expect(CurlParser.parse("   ") == nil)
        #expect(CurlParser.parse("http https://example.com") == nil)
    }

    @Test func acceptsAPastedPromptAndAnAbsolutePath() {
        #expect(CurlParser.parse("$ curl https://api.example.com/x")?.url == "https://api.example.com/x")
        #expect(CurlParser.parse("/usr/bin/curl https://api.example.com/x")?.url == "https://api.example.com/x")
    }

    @Test func nameComesFromTheLastPathSegment() {
        #expect(CurlParser.nameFromURL("https://api.example.com/v1/users") == "users")
        #expect(CurlParser.nameFromURL("https://api.example.com") == "api.example.com")
        #expect(CurlParser.nameFromURL("https://api.example.com/") == "api.example.com")
        #expect(CurlParser.nameFromURL("https://api.example.com/v1/users?q=1") == "users")
    }
}

// MARK: - Headers

@Suite struct CurlHeaderTests {

    @Test func parsesRepeatedHeaders() throws {
        let request = try #require(
            CurlParser.parse("""
                curl -H "Authorization: Bearer tok123" \
                     -H "Accept: application/json" \
                     https://api.example.com/me
                """)
        )
        #expect(request.headers.count == 2)
        #expect(request.headers[0].key == "Authorization")
        #expect(request.headers[0].value == "Bearer tok123")
        #expect(request.headers[1].key == "Accept")
    }

    @Test func keepsTwoHeadersWithTheSameName() throws {
        let request = try #require(CurlParser.parse("curl -H 'X-A: 1' -H 'X-A: 2' https://api.example.com/x"))
        #expect(request.headers.count == 2)
        #expect(request.headers.map(\.value) == ["1", "2"])
    }

    @Test func headerWithEmptyValueRemovesIt() throws {
        // `-H "Accept:"` is curl's way of suppressing a header.
        let request = try #require(
            CurlParser.parse("curl -H 'Accept: application/json' -H 'Accept:' https://api.example.com/x")
        )
        #expect(request.headers.isEmpty)
    }

    @Test func semicolonFormSendsAnEmptyHeader() throws {
        let request = try #require(CurlParser.parse("curl -H 'X-Empty;' https://api.example.com/x"))
        #expect(request.headers.count == 1)
        #expect(request.headers[0].key == "X-Empty")
        #expect(request.headers[0].value == "")
    }

    @Test func headerValueKeepsInternalColons() throws {
        let request = try #require(
            CurlParser.parse("curl -H 'X-Time: 12:30:00' https://api.example.com/x")
        )
        #expect(request.headers[0].value == "12:30:00")
    }

    @Test func cookieUserAgentAndRefererBecomeHeaders() throws {
        let request = try #require(
            CurlParser.parse(
                "curl -b 'a=1; b=2' -A 'MyAgent/1.0' -e 'https://ref.example' https://api.example.com/x"
            )
        )
        #expect(request.headers.firstValue(forKeyIgnoringCase: "cookie") == "a=1; b=2")
        #expect(request.headers.firstValue(forKeyIgnoringCase: "user-agent") == "MyAgent/1.0")
        #expect(request.headers.firstValue(forKeyIgnoringCase: "referer") == "https://ref.example")
    }

    @Test func cookieFileIsReportedNotGuessed() throws {
        let result = try #require(CurlParser.parseWithWarnings("curl -b cookies.txt https://api.example.com/x"))
        #expect(result.request.headers.isEmpty)
        #expect(result.warnings.contains { $0.contains("cookies.txt") })
    }
}

// MARK: - Auth

@Suite struct CurlAuthTests {

    @Test func userFlagBecomesBasicAuth() throws {
        let request = try #require(CurlParser.parse("curl -u alice:s3cret https://api.example.com/private"))
        #expect(request.auth.type == .basic)
        #expect(request.auth.basicUsername == "alice")
        #expect(request.auth.basicPassword == "s3cret")
    }

    @Test func userFlagWithoutPassword() throws {
        let request = try #require(CurlParser.parse("curl -u alice https://api.example.com/private"))
        #expect(request.auth.type == .basic)
        #expect(request.auth.basicUsername == "alice")
        #expect(request.auth.basicPassword == "")
    }

    @Test func passwordKeepsLaterColons() throws {
        let request = try #require(CurlParser.parse("curl -u 'alice:a:b:c' https://api.example.com/x"))
        #expect(request.auth.basicPassword == "a:b:c")
    }

    @Test func oauth2BearerFlagBecomesBearerAuth() throws {
        let request = try #require(
            CurlParser.parse("curl --oauth2-bearer tok999 https://api.example.com/me")
        )
        #expect(request.auth.type == .bearer)
        #expect(request.auth.bearerToken == "tok999")
    }
}

// MARK: - Bodies

@Suite struct CurlBodyTests {

    @Test func jsonBodyIsDetectedWithoutAContentTypeHeader() throws {
        let request = try #require(
            CurlParser.parse(#"curl -d '{"name":"test"}' https://api.example.com/items"#)
        )
        #expect(request.method == .post)
        #expect(request.body.type == .json)
        #expect(request.body.jsonText == #"{"name":"test"}"#)
    }

    @Test func formPairsBecomeUrlEncodedFields() throws {
        // curl defaults -d to application/x-www-form-urlencoded.
        let request = try #require(CurlParser.parse("curl -d 'user=alice&pass=secret' https://api.example.com/login"))
        #expect(request.body.type == .formUrlEncoded)
        #expect(request.body.formFields.map(\.key) == ["user", "pass"])
        #expect(request.body.formFields.map(\.value) == ["alice", "secret"])
    }

    @Test func repeatedDataFlagsAreJoinedWithAmpersand() throws {
        let request = try #require(
            CurlParser.parse("curl -d 'a=1' -d 'b=2' https://api.example.com/x")
        )
        #expect(request.body.type == .formUrlEncoded)
        #expect(request.body.formFields.map(\.key) == ["a", "b"])
    }

    @Test func plainTextBodyStaysRaw() throws {
        let request = try #require(CurlParser.parse("curl -d 'just some text' https://api.example.com/x"))
        #expect(request.body.type == .raw)
        #expect(request.body.rawText == "just some text")
    }

    @Test func contentTypeDrivesTheBodyKind() throws {
        let xml = try #require(
            CurlParser.parse("curl -H 'Content-Type: application/xml' -d '<a/>' https://api.example.com/x")
        )
        #expect(xml.body.type == .raw)
        #expect(xml.body.rawLanguage == .xml)

        let json = try #require(
            CurlParser.parse("curl -H 'Content-Type: application/json' -d 'not-json' https://api.example.com/x")
        )
        #expect(json.body.type == .json)
    }

    @Test func dataUrlencodeEncodesTheValue() throws {
        let request = try #require(
            CurlParser.parse("curl --data-urlencode 'q=hello world' https://api.example.com/s")
        )
        #expect(request.body.type == .formUrlEncoded)
        #expect(request.body.formFields.first?.value == "hello world")
    }

    @Test func dataUrlencodeFileFormIsSkippedWithAWarning() throws {
        let result = try #require(
            CurlParser.parseWithWarnings("curl --data-urlencode 'q@payload.txt' https://api.example.com/s")
        )
        #expect(result.request.body.type == BodyType.none)
        #expect(result.warnings.contains { $0.contains("payload.txt") })
    }

    @Test func dataBinaryFileBecomesABinaryBody() throws {
        let result = try #require(
            CurlParser.parseWithWarnings("curl --data-binary @/tmp/photo.png https://api.example.com/up")
        )
        #expect(result.request.body.type == .binary)
        #expect(result.request.body.binaryFilePath == "/tmp/photo.png")
        #expect(result.warnings.contains { $0.contains("/tmp/photo.png") })
    }

    @Test func dataFileFormKeepsTheTextAndWarns() throws {
        let result = try #require(
            CurlParser.parseWithWarnings("curl -d @payload.json https://api.example.com/x")
        )
        #expect(result.warnings.contains { $0.contains("payload.json") })
    }

    @Test func jsonShorthandSetsBothHeaders() throws {
        let request = try #require(
            CurlParser.parse(#"curl --json '{"a":1}' https://api.example.com/x"#)
        )
        #expect(request.body.type == .json)
        #expect(request.headers.firstValue(forKeyIgnoringCase: "content-type") == "application/json")
        #expect(request.headers.firstValue(forKeyIgnoringCase: "accept") == "application/json")
    }

    @Test func formFlagsBecomeMultipart() throws {
        let request = try #require(
            CurlParser.parse("curl -F 'user=alice' -F 'pass=secret' https://api.example.com/login")
        )
        #expect(request.method == .post)
        #expect(request.body.type == .multipart)
        #expect(request.body.multipartFields.map(\.key) == ["user", "pass"])
        #expect(request.body.multipartFields.allSatisfy { $0.kind == .text })
    }

    @Test func formFileAndExplicitTypeAreParsed() throws {
        let request = try #require(
            CurlParser.parse("curl -F 'photo=@/tmp/a.png;type=image/png' https://api.example.com/up")
        )
        let field = try #require(request.body.multipartFields.first)
        #expect(field.kind == .file)
        #expect(field.value == "/tmp/a.png")
        #expect(field.contentType == "image/png")
    }

    @Test func formStringKeepsAnAtSignLiteral() throws {
        let request = try #require(
            CurlParser.parse("curl --form-string 'note=@notafile' https://api.example.com/x")
        )
        let field = try #require(request.body.multipartFields.first)
        #expect(field.kind == .text)
        #expect(field.value == "@notafile")
    }

    @Test func getFlagMovesDataIntoTheQuery() throws {
        let request = try #require(CurlParser.parse("curl -G -d 'q=test' https://api.example.com/search"))
        #expect(request.method == .get)
        #expect(request.body.type == BodyType.none)
        #expect(request.queryParams.contains { $0.key == "q" && $0.value == "test" })
    }

    @Test func getFlagMovesEveryDataPairIntoTheQuery() throws {
        let request = try #require(
            CurlParser.parse("curl -G -d 'q=swift' -d 'page=2' https://api.example.com/search")
        )
        #expect(request.queryParams.map(\.key) == ["q", "page"])
        #expect(request.queryParams.map(\.value) == ["swift", "2"])
    }

    @Test func getFlagWithUrlencodedDataDecodesBackToPlainValues() throws {
        let request = try #require(
            CurlParser.parse("curl -G --data-urlencode 'q=hello world' https://api.example.com/s")
        )
        #expect(request.queryParams.first?.value == "hello world")
    }
}

// MARK: - Settings

@Suite struct CurlSettingsTests {

    @Test func insecureTurnsOffValidation() throws {
        let request = try #require(CurlParser.parse("curl -k https://api.example.com/x"))
        #expect(request.settings.validateTLS == false)
    }

    @Test func maxTimeAndMaxRedirsAreCarriedOver() throws {
        let request = try #require(
            CurlParser.parse("curl -m 5 --max-redirs 3 -L https://api.example.com/x")
        )
        #expect(request.settings.timeoutSeconds == 5)
        #expect(request.settings.maxRedirects == 3)
        #expect(request.settings.followRedirects)
    }

    @Test func ignoredFlagsDoNotBreakParsing() throws {
        let request = try #require(
            CurlParser.parse("curl -k --compressed -L -s -i -v --http2 --fail https://api.example.com/test")
        )
        #expect(request.url == "https://api.example.com/test")
    }
}

// MARK: - Realistic pastes

@Suite struct CurlRealWorldTests {

    @Test func chromeCopyAsCurl() throws {
        let command = """
            curl 'https://api.example.com/v1/orders?status=open&limit=25' \
              -H 'accept: application/json, text/plain, */*' \
              -H 'accept-language: en-GB,en;q=0.9' \
              -H 'authorization: Bearer eyJhbGciOi' \
              -b 'session=abc123; theme=dark' \
              -H 'sec-fetch-mode: cors' \
              --compressed
            """
        let request = try #require(CurlParser.parse(command))
        #expect(request.url == "https://api.example.com/v1/orders")
        #expect(request.method == .get)
        #expect(request.queryParams.map(\.key) == ["status", "limit"])
        #expect(request.headers.firstValue(forKeyIgnoringCase: "authorization") == "Bearer eyJhbGciOi")
        #expect(request.headers.firstValue(forKeyIgnoringCase: "cookie") == "session=abc123; theme=dark")
    }

    @Test func chromeCopyAsCurlWithJSONPost() throws {
        let command = """
            curl 'https://api.example.com/graphql' \
              -X POST \
              -H 'content-type: application/json' \
              --data-raw '{"query":"{ me { id } }","variables":{}}' \
              --compressed
            """
        let request = try #require(CurlParser.parse(command))
        #expect(request.method == .post)
        #expect(request.body.type == .json)
        #expect(request.body.jsonText.contains("\"query\""))
    }

    @Test func multilineCommandWithTrailingBackslashes() throws {
        let command = #"""
        curl -X PUT \
          "https://api.example.com/v1/items/42" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer abc" \
          -d '{"name":"updated","tags":["a","b"]}'
        """#
        let request = try #require(CurlParser.parse(command))
        #expect(request.method == .put)
        #expect(request.url == "https://api.example.com/v1/items/42")
        #expect(request.headers.count == 2)
        #expect(request.body.type == .json)
    }
}

// MARK: - Export and round-trip

@Suite struct CurlExportTests {

    @Test func getWithoutABodyOmitsTheMethodFlag() {
        let curl = CurlExporter.export(SavedRequest(method: .get, url: "https://api.example.com/test"))
        #expect(curl.contains("https://api.example.com/test"))
        #expect(!curl.contains("-X"))
    }

    @Test func includesMethodHeadersAndBody() {
        let request = SavedRequest(
            method: .post,
            url: "https://api.example.com/items",
            headers: [ApiKeyValue(key: "Accept", value: "application/json")],
            body: RequestBodySpec(type: .json, jsonText: #"{"name":"test"}"#)
        )
        let curl = CurlExporter.export(request)
        #expect(curl.contains("-X POST"))
        #expect(curl.contains("Accept: application/json"))
        #expect(curl.contains("Content-Type: application/json"))
        #expect(curl.contains("--data-raw"))
    }

    @Test func exportsEachAuthKind() {
        let bearer = CurlExporter.export(
            SavedRequest(url: "https://a.co/x", auth: AuthSpec(type: .bearer, bearerToken: "tok"))
        )
        #expect(bearer.contains("Authorization: Bearer tok"))

        // Basic auth exports as `-u` rather than a base64 header so it comes
        // back as auth, not as an opaque header, when re-imported.
        let basic = CurlExporter.export(
            SavedRequest(
                url: "https://a.co/x",
                auth: AuthSpec(type: .basic, basicUsername: "u", basicPassword: "p")
            )
        )
        #expect(basic.contains("-u 'u:p'"))
        #expect(!basic.contains("Authorization"))

        let apiKey = CurlExporter.export(
            SavedRequest(
                url: "https://a.co/x",
                auth: AuthSpec(type: .apiKey, apiKeyName: "X-API-Key", apiKeyValue: "k")
            )
        )
        #expect(apiKey.contains("X-API-Key: k"))

        let queryKey = CurlExporter.export(
            SavedRequest(
                url: "https://a.co/x",
                auth: AuthSpec(
                    type: .apiKey, apiKeyName: "api_key", apiKeyValue: "k", apiKeyLocation: .query
                )
            )
        )
        #expect(queryKey.contains("api_key=k"))
    }

    @Test func exportsMultipartAndBinaryBodies() {
        let multipart = CurlExporter.export(
            SavedRequest(
                method: .post,
                url: "https://a.co/up",
                body: RequestBodySpec(
                    type: .multipart,
                    multipartFields: [
                        ApiFormField(key: "note", value: "hi"),
                        ApiFormField(key: "photo", value: "/tmp/a.png", kind: .file),
                    ]
                )
            )
        )
        #expect(multipart.contains("-F 'note=hi'"))
        #expect(multipart.contains("-F 'photo=@/tmp/a.png'"))

        let binary = CurlExporter.export(
            SavedRequest(
                method: .put,
                url: "https://a.co/up",
                body: RequestBodySpec(type: .binary, binaryFilePath: "/tmp/a.bin")
            )
        )
        #expect(binary.contains("--data-binary '@/tmp/a.bin'"))
    }

    @Test func exportsSettingsFlags() {
        let request = SavedRequest(
            url: "https://a.co/x",
            settings: RequestSettings(
                timeoutSeconds: 5, followRedirects: true, maxRedirects: 3, validateTLS: false
            )
        )
        let curl = CurlExporter.export(request)
        #expect(curl.contains("-k"))
        #expect(curl.contains("-L"))
        #expect(curl.contains("--max-time 5"))
        #expect(curl.contains("--max-redirs 3"))
    }

    @Test func resolvesVariablesOnExport() {
        let request = SavedRequest(
            url: "https://{{host}}/api",
            auth: AuthSpec(type: .bearer, bearerToken: "{{token}}")
        )
        let scope = VariableScope(environment: ["host": "prod.api.com", "token": "tok999"])
        let curl = CurlExporter.export(request, scope: scope)
        #expect(curl.contains("prod.api.com"))
        #expect(curl.contains("tok999"))
        #expect(!curl.contains("{{host}}"))
    }

    @Test func quotesValuesThatWouldOtherwiseSplit() {
        let request = SavedRequest(
            url: "https://a.co/x",
            headers: [ApiKeyValue(key: "X-Note", value: "a b; rm -rf /")]
        )
        let curl = CurlExporter.export(request)
        #expect(curl.contains("'X-Note: a b; rm -rf /'"))
    }
}

@Suite struct CurlRoundTripTests {

    /// Export then re-import must preserve the request, including the auth that
    /// used to be dropped on the way back in.
    @Test func basicAuthSurvivesARoundTrip() throws {
        let original = SavedRequest(
            method: .get,
            url: "https://api.example.com/private",
            auth: AuthSpec(type: .basic, basicUsername: "alice", basicPassword: "s3cret")
        )
        let reimported = try #require(CurlParser.parse(CurlExporter.export(original)))
        #expect(reimported.auth.type == .basic)
        #expect(reimported.auth.basicUsername == "alice")
        #expect(reimported.auth.basicPassword == "s3cret")
    }

    @Test func bearerAuthRoundTripsAsAHeader() throws {
        let original = SavedRequest(
            url: "https://api.example.com/me",
            auth: AuthSpec(type: .bearer, bearerToken: "tok123")
        )
        let reimported = try #require(CurlParser.parse(CurlExporter.export(original)))
        #expect(reimported.headers.firstValue(forKeyIgnoringCase: "authorization") == "Bearer tok123")
    }

    @Test func getWithQueryAndHeadersRoundTrips() throws {
        let original = SavedRequest(
            method: .get,
            url: "https://api.example.com/users",
            headers: [ApiKeyValue(key: "Accept", value: "application/json")],
            queryParams: [ApiKeyValue(key: "page", value: "1"), ApiKeyValue(key: "q", value: "a b")]
        )
        let reimported = try #require(CurlParser.parse(CurlExporter.export(original)))
        #expect(reimported.method == .get)
        #expect(reimported.url == "https://api.example.com/users")
        #expect(reimported.queryParams.map(\.key) == ["page", "q"])
        #expect(reimported.queryParams.map(\.value) == ["1", "a b"])
        #expect(reimported.headers.firstValue(forKeyIgnoringCase: "accept") == "application/json")
    }

    @Test func jsonPostRoundTrips() throws {
        let original = SavedRequest(
            method: .post,
            url: "https://api.example.com/items",
            body: RequestBodySpec(type: .json, jsonText: #"{"name":"test","n":1}"#)
        )
        let reimported = try #require(CurlParser.parse(CurlExporter.export(original)))
        #expect(reimported.method == .post)
        #expect(reimported.body.type == .json)
        #expect(reimported.body.jsonText == #"{"name":"test","n":1}"#)
    }

    @Test func multipartRoundTrips() throws {
        let original = SavedRequest(
            method: .post,
            url: "https://api.example.com/up",
            body: RequestBodySpec(
                type: .multipart,
                multipartFields: [
                    ApiFormField(key: "note", value: "hello"),
                    ApiFormField(key: "photo", value: "/tmp/a.png", kind: .file, contentType: "image/png"),
                ]
            )
        )
        let reimported = try #require(CurlParser.parse(CurlExporter.export(original)))
        #expect(reimported.body.type == .multipart)
        #expect(reimported.body.multipartFields.count == 2)
        let photo = try #require(reimported.body.multipartFields.last)
        #expect(photo.kind == .file)
        #expect(photo.value == "/tmp/a.png")
        #expect(photo.contentType == "image/png")
    }

    @Test func urlEncodedFormRoundTrips() throws {
        let original = SavedRequest(
            method: .post,
            url: "https://api.example.com/login",
            body: RequestBodySpec(
                type: .formUrlEncoded,
                formFields: [
                    ApiKeyValue(key: "user", value: "alice"),
                    ApiKeyValue(key: "pass", value: "p@ss word"),
                ]
            )
        )
        let reimported = try #require(CurlParser.parse(CurlExporter.export(original)))
        #expect(reimported.body.type == .formUrlEncoded)
        #expect(reimported.body.formFields.map(\.value) == ["alice", "p@ss word"])
    }

    @Test func settingsRoundTrip() throws {
        let original = SavedRequest(
            url: "https://api.example.com/x",
            settings: RequestSettings(timeoutSeconds: 12, maxRedirects: 4, validateTLS: false)
        )
        let reimported = try #require(CurlParser.parse(CurlExporter.export(original)))
        #expect(reimported.settings.timeoutSeconds == 12)
        #expect(reimported.settings.maxRedirects == 4)
        #expect(reimported.settings.validateTLS == false)
    }
}
