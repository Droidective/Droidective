import Foundation
import Testing

@testable import ADBKit

// MARK: - Helpers

private func response(
    status: Int = 200,
    headers: [(key: String, value: String)] = [],
    body: Data = Data(),
    elapsedMs: Double = 10,
    truncated: Bool = false
) -> ApiResponse {
    ApiResponse(
        statusCode: status, headers: headers, body: body, elapsedMs: elapsedMs, truncated: truncated
    )
}

private func jsonResponse(_ text: String, status: Int = 200) -> ApiResponse {
    response(
        status: status,
        headers: [(key: "Content-Type", value: "application/json")],
        body: Data(text.utf8)
    )
}

// MARK: - Status codes

@Suite struct HttpStatusTests {

    @Test func knownCodesUseTheirRegistryPhrase() {
        #expect(HttpStatus.text(for: 200) == "OK")
        #expect(HttpStatus.text(for: 201) == "Created")
        #expect(HttpStatus.text(for: 204) == "No Content")
        #expect(HttpStatus.text(for: 301) == "Moved Permanently")
        #expect(HttpStatus.text(for: 401) == "Unauthorized")
        #expect(HttpStatus.text(for: 404) == "Not Found")
        #expect(HttpStatus.text(for: 418) == "I'm a Teapot")
        #expect(HttpStatus.text(for: 422) == "Unprocessable Content")
        #expect(HttpStatus.text(for: 429) == "Too Many Requests")
        #expect(HttpStatus.text(for: 500) == "Internal Server Error")
        #expect(HttpStatus.text(for: 503) == "Service Unavailable")
    }

    /// A vendor-specific code still needs to read sensibly in the status pill.
    @Test func unknownCodesFallBackToTheirClass() {
        #expect(HttpStatus.text(for: 599) == "Server Error")
        #expect(HttpStatus.text(for: 499) == "Client Error")
        #expect(HttpStatus.text(for: 299) == "Success")
        #expect(HttpStatus.text(for: 399) == "Redirection")
        #expect(HttpStatus.text(for: 199) == "Informational")
        #expect(HttpStatus.text(for: 0) == "Unknown")
        #expect(HttpStatus.text(for: 700) == "Unknown")
    }

    @Test func everyPhraseIsNonEmpty() {
        for code in 100...599 {
            #expect(!HttpStatus.text(for: code).isEmpty, "empty phrase for \(code)")
        }
    }

    @Test func theResponseTakesItsPhraseFromTheCode() {
        #expect(response(status: 404).statusText == "Not Found")
        #expect(response(status: 200).isSuccess)
        #expect(!response(status: 302).isSuccess)
    }
}

// MARK: - Headers and cookies

@Suite struct ApiResponseHeaderTests {

    @Test func lookupIgnoresCase() {
        let subject = response(headers: [(key: "Content-Type", value: "application/json")])
        #expect(subject.headerValue("content-type") == "application/json")
        #expect(subject.headerValue("CONTENT-TYPE") == "application/json")
        #expect(subject.headerValue("missing") == nil)
    }

    @Test func repeatedHeadersAreKeptAndJoinedOnLookup() {
        let subject = response(headers: [
            (key: "Set-Cookie", value: "a=1"),
            (key: "Set-Cookie", value: "b=2"),
        ])
        #expect(subject.headers.count == 2)
        #expect(subject.headerValue("Set-Cookie") == "a=1, b=2")
    }

    @Test func readsTheMediaTypeAndCharsetSeparately() {
        let subject = response(headers: [
            (key: "Content-Type", value: "application/json; charset=UTF-8")
        ])
        #expect(subject.mediaType == "application/json")
        #expect(subject.charsetName == "utf-8")
    }

    @Test func toleratesAQuotedCharset() {
        let subject = response(headers: [
            (key: "Content-Type", value: "text/plain; charset=\"iso-8859-1\"")
        ])
        #expect(subject.charsetName == "iso-8859-1")
    }

    @Test func parsesEveryCookieAttribute() throws {
        let subject = response(headers: [
            (
                key: "Set-Cookie",
                value: "sid=abc123; Domain=.example.com; Path=/api; Expires=Wed, 09 Jun 2027 10:18:14 GMT; Max-Age=3600; HttpOnly; Secure; SameSite=Lax"
            )
        ])
        let cookie = try #require(subject.cookies.first)
        #expect(cookie.name == "sid")
        #expect(cookie.value == "abc123")
        #expect(cookie.domain == ".example.com")
        #expect(cookie.path == "/api")
        #expect(cookie.maxAge == "3600")
        #expect(cookie.httpOnly)
        #expect(cookie.secure)
        #expect(cookie.sameSite == "Lax")
        #expect(cookie.expires.contains("2027"))
    }

    @Test func collectsEveryCookie() {
        let subject = response(headers: [
            (key: "Set-Cookie", value: "a=1; Path=/"),
            (key: "Set-Cookie", value: "b=2; Secure"),
        ])
        #expect(subject.cookies.map(\.name) == ["a", "b"])
    }

    @Test func aCookieNeedsANameValuePair() {
        #expect(ApiCookie.parse("HttpOnly; Secure") == nil)
        #expect(ApiCookie.parse("") == nil)
        #expect(ApiCookie.parse("=novalue") == nil)
    }

    @Test func aCookieValueMayBeEmptyOrContainEquals() throws {
        #expect(ApiCookie.parse("a=")?.value == "")
        #expect(ApiCookie.parse("token=a=b=c")?.value == "a=b=c")
    }
}

// MARK: - Body decoding and format

@Suite struct ApiResponseBodyTests {

    @Test func decodesUTF8ByDefault() {
        #expect(response(body: Data("héllo".utf8)).bodyString == "héllo")
    }

    @Test func honoursADeclaredLatin1Charset() {
        let subject = response(
            headers: [(key: "Content-Type", value: "text/plain; charset=iso-8859-1")],
            body: Data([0x63, 0x61, 0x66, 0xE9])
        )
        #expect(subject.bodyString == "café")
    }

    @Test func honoursADeclaredUTF16Charset() throws {
        let payload = try #require("hello".data(using: .utf16))
        let subject = response(
            headers: [(key: "Content-Type", value: "text/plain; charset=utf-16")], body: payload
        )
        #expect(subject.bodyString == "hello")
    }

    @Test func fallsBackWhenTheCharsetLabelIsWrong() {
        let subject = response(
            headers: [(key: "Content-Type", value: "text/plain; charset=x-made-up")],
            body: Data("plain".utf8)
        )
        #expect(subject.bodyString == "plain")
    }

    @Test func anEmptyBodyDecodesToAnEmptyString() {
        let subject = response(status: 204)
        #expect(subject.bodyString == "")
        #expect(subject.prettyBody == nil)
        #expect(subject.format == .text)
    }

    @Test func detectsFormatFromTheContentType() {
        #expect(jsonResponse("{}").format == .json)
        #expect(
            response(headers: [(key: "Content-Type", value: "application/xml")], body: Data("<a/>".utf8))
                .format == .xml
        )
        #expect(
            response(headers: [(key: "Content-Type", value: "text/html")], body: Data("<p>".utf8))
                .format == .html
        )
        #expect(
            response(headers: [(key: "Content-Type", value: "image/png")], body: Data([0x89]))
                .format == .image
        )
        #expect(
            response(headers: [(key: "Content-Type", value: "application/pdf")], body: Data([0x25]))
                .format == .binary
        )
    }

    /// Plenty of APIs answer with JSON labelled `text/plain`.
    @Test func sniffsJSONMislabelledAsText() {
        let subject = response(
            headers: [(key: "Content-Type", value: "text/plain")],
            body: Data(#"{"a":1}"#.utf8)
        )
        #expect(subject.format == .json)
        #expect(subject.isJSON)
    }

    @Test func sniffsMarkupWithNoContentType() {
        #expect(response(body: Data("<!DOCTYPE html><p>hi".utf8)).format == .html)
        #expect(response(body: Data("<?xml version=\"1.0\"?><a/>".utf8)).format == .xml)
        #expect(response(body: Data("<html><body>".utf8)).format == .html)
        #expect(response(body: Data("<root><a/></root>".utf8)).format == .xml)
        #expect(response(body: Data("[1,2,3]".utf8)).format == .json)
        #expect(response(body: Data("hello".utf8)).format == .text)
    }

    @Test func treatsNULBytesAsBinary() {
        let subject = response(body: Data([0xFF, 0xFE, 0x00, 0x01]))
        #expect(subject.format == .binary)
        #expect(subject.bodyString == nil)
        #expect(subject.prettyBody == nil)
    }

    @Test func reportsSizeAndTruncation() {
        let subject = ApiResponse(
            statusCode: 200, headers: [], body: Data(count: 100), elapsedMs: 5,
            size: 5000, truncated: true
        )
        #expect(subject.size == 5000)
        #expect(subject.truncated)
        #expect(subject.sizeText == "4.9 KB")
    }

    @Test func formatsByteCountsAcrossUnits() {
        #expect(ApiResponse.formatBytes(0) == "0 B")
        #expect(ApiResponse.formatBytes(1023) == "1023 B")
        #expect(ApiResponse.formatBytes(1024) == "1.0 KB")
        #expect(ApiResponse.formatBytes(1_048_575) == "1024.0 KB")
        #expect(ApiResponse.formatBytes(1_048_576) == "1.0 MB")
        #expect(ApiResponse.formatBytes(1_073_741_824) == "1.00 GB")
    }
}

// MARK: - JSON formatting

@Suite struct JSONFormatterTests {

    /// Key order is the payload's own; re-sorting it misrepresents what the
    /// server sent, which matters when you are inspecting an API.
    @Test func preservesKeyOrder() throws {
        let pretty = try #require(JSONFormatter.prettyPrint(#"{"zebra":1,"apple":2,"mango":3}"#))
        let zebra = try #require(pretty.range(of: "zebra"))
        let apple = try #require(pretty.range(of: "apple"))
        let mango = try #require(pretty.range(of: "mango"))
        #expect(zebra.lowerBound < apple.lowerBound)
        #expect(apple.lowerBound < mango.lowerBound)
    }

    @Test func indentsNestedStructures() throws {
        let pretty = try #require(JSONFormatter.prettyPrint(#"{"a":{"b":[1,2]}}"#))
        #expect(
            pretty == """
                {
                  "a": {
                    "b": [
                      1,
                      2
                    ]
                  }
                }
                """
        )
    }

    @Test func keepsEmptyContainersCompact() throws {
        #expect(try #require(JSONFormatter.prettyPrint(#"{"a":{},"b":[]}"#)) == """
            {
              "a": {},
              "b": []
            }
            """)
    }

    @Test func doesNotTouchBracesInsideStrings() throws {
        let pretty = try #require(JSONFormatter.prettyPrint(#"{"a":"{\"nested\": [1,2]}"}"#))
        #expect(pretty.contains(#""{\"nested\": [1,2]}""#))
        #expect(pretty.components(separatedBy: "\n").count == 3)
    }

    @Test func preservesEscapesAndUnicode() throws {
        let pretty = try #require(JSONFormatter.prettyPrint(#"{"a":"line\nbreak é \\ \" end"}"#))
        #expect(pretty.contains(#"line\nbreak é \\ \" end"#))
    }

    @Test func preservesNumberFormatting() throws {
        let pretty = try #require(
            JSONFormatter.prettyPrint(#"{"a":1.50,"b":1e10,"c":-0.0,"d":12345678901234567890}"#)
        )
        #expect(pretty.contains("1.50"))
        #expect(pretty.contains("1e10"))
        #expect(pretty.contains("12345678901234567890"))
    }

    @Test func handlesTopLevelArraysAndFragments() throws {
        #expect(try #require(JSONFormatter.prettyPrint("[1,2]")) == "[\n  1,\n  2\n]")
        #expect(JSONFormatter.prettyPrint("123") == "123")
        #expect(JSONFormatter.prettyPrint(#""text""#) == #""text""#)
        #expect(JSONFormatter.prettyPrint("null") == "null")
    }

    @Test func returnsNilForInvalidJSON() {
        #expect(JSONFormatter.prettyPrint("{oops") == nil)
        #expect(JSONFormatter.prettyPrint("") == nil)
        #expect(JSONFormatter.prettyPrint("   ") == nil)
        #expect(JSONFormatter.prettyPrint("not json at all") == nil)
    }

    @Test func reformatsAlreadyIndentedJSON() throws {
        let input = "{\n\t\"a\" :   1 ,\n\t\"b\":2\n}"
        #expect(try #require(JSONFormatter.prettyPrint(input)) == "{\n  \"a\": 1,\n  \"b\": 2\n}")
    }

    @Test func minifyCollapsesWhitespaceOutsideStrings() {
        #expect(JSONFormatter.minify("{\n  \"a\": 1,\n  \"b\": \"x y\"\n}") == #"{"a":1,"b":"x y"}"#)
        #expect(JSONFormatter.minify("{bad") == nil)
    }

    @Test func prettyThenMinifyRoundTrips() throws {
        let original = #"{"a":[1,{"b":"x"}],"c":null}"#
        let pretty = try #require(JSONFormatter.prettyPrint(original))
        #expect(JSONFormatter.minify(pretty) == original)
    }

    @Test func validatesJSON() {
        #expect(JSONFormatter.isValidJSON(#"{"a":1}"#))
        #expect(JSONFormatter.isValidJSON("[]"))
        #expect(!JSONFormatter.isValidJSON("{"))
        #expect(!JSONFormatter.isValidJSON(""))
    }
}

// MARK: - XML formatting

@Suite struct XMLFormatterTests {

    @Test func indentsNestedElements() throws {
        #expect(try #require(XMLFormatter.prettyPrint("<a><b>text</b><c/></a>")) == """
            <a>
              <b>text</b>
              <c/>
            </a>
            """)
    }

    @Test func keepsTheDeclarationOnItsOwnLine() throws {
        let pretty = try #require(
            XMLFormatter.prettyPrint("<?xml version=\"1.0\"?><root><a>1</a></root>")
        )
        #expect(pretty.hasPrefix("<?xml version=\"1.0\"?>\n<root>"))
    }

    @Test func passesCommentsAndCDATAThrough() throws {
        let pretty = try #require(
            XMLFormatter.prettyPrint("<a><!-- a > b --><![CDATA[x > y]]></a>")
        )
        #expect(pretty.contains("<!-- a > b -->"))
        #expect(pretty.contains("<![CDATA[x > y]]>"))
    }

    @Test func doesNotBreakOnAGreaterThanInsideAnAttribute() throws {
        let pretty = try #require(XMLFormatter.prettyPrint("<a title=\"x > y\"><b/></a>"))
        #expect(pretty.contains("<a title=\"x > y\">"))
    }

    @Test func treatsVoidHTMLElementsAsSelfContained() throws {
        let pretty = try #require(XMLFormatter.prettyPrint("<div><br><img src=\"a\"><p>hi</p></div>"))
        #expect(pretty == """
            <div>
              <br>
              <img src="a">
              <p>hi</p>
            </div>
            """)
    }

    @Test func handlesAttributesAndNamespaces() throws {
        let pretty = try #require(
            XMLFormatter.prettyPrint(#"<ns:root xmlns:ns="urn:x"><ns:a id="1">v</ns:a></ns:root>"#)
        )
        #expect(pretty.contains(#"<ns:a id="1">v</ns:a>"#))
    }

    @Test func returnsNilForNonMarkup() {
        #expect(XMLFormatter.prettyPrint("just text") == nil)
        #expect(XMLFormatter.prettyPrint("") == nil)
    }

    @Test func survivesUnclosedMarkup() {
        #expect(XMLFormatter.prettyPrint("<a><b>") != nil)
        #expect(XMLFormatter.prettyPrint("<a") != nil)
    }

    @Test func theResponsePrettyPrinterPicksTheRightFormatter() throws {
        #expect(jsonResponse(#"{"a":1}"#).prettyBody == "{\n  \"a\": 1\n}")
        let xml = response(
            headers: [(key: "Content-Type", value: "application/xml")],
            body: Data("<a><b>1</b></a>".utf8)
        )
        #expect(xml.prettyBody == "<a>\n  <b>1</b>\n</a>")
        #expect(response(body: Data("plain".utf8)).prettyBody == nil)
    }
}

// MARK: - JSON path probe

@Suite struct JSONProbeTests {

    private let payload = Data(
        #"""
        {
          "ok": true,
          "count": 3,
          "ratio": 1.5,
          "nothing": null,
          "name": "widget",
          "items": [{"id": 10, "tags": ["a", "b"]}, {"id": 20}],
          "meta": {"page": {"next": "/p/2"}},
          "odd.key": "dotted"
        }
        """#.utf8
    )

    @Test func readsScalarsAtTheTopLevel() {
        #expect(JSONProbe.probe("ok", in: payload) == .bool(true))
        #expect(JSONProbe.probe("count", in: payload) == .number(3))
        #expect(JSONProbe.probe("ratio", in: payload) == .number(1.5))
        #expect(JSONProbe.probe("name", in: payload) == .string("widget"))
        #expect(JSONProbe.probe("nothing", in: payload) == .null)
    }

    @Test func walksNestedObjectsAndArrays() {
        #expect(JSONProbe.probe("meta.page.next", in: payload) == .string("/p/2"))
        #expect(JSONProbe.probe("items[0].id", in: payload) == .number(10))
        #expect(JSONProbe.probe("items[1].id", in: payload) == .number(20))
        #expect(JSONProbe.probe("items[0].tags[1]", in: payload) == .string("b"))
    }

    @Test func acceptsALeadingDollar() {
        #expect(JSONProbe.probe("$.items[0].id", in: payload) == .number(10))
        #expect(JSONProbe.probe("$items[0].id", in: payload) == .number(10))
    }

    @Test func indexesFromTheEndWithANegativeIndex() {
        #expect(JSONProbe.probe("items[-1].id", in: payload) == .number(20))
        #expect(JSONProbe.probe("items[-3]", in: payload) == nil)
    }

    @Test func readsAQuotedKeyContainingADot() {
        #expect(JSONProbe.probe(#"["odd.key"]"#, in: payload) == .string("dotted"))
        #expect(JSONProbe.probe("['odd.key']", in: payload) == .string("dotted"))
    }

    @Test func describesContainersByShape() {
        #expect(JSONProbe.probe("items", in: payload) == .array(count: 2))
        #expect(JSONProbe.probe("meta", in: payload) == .object(keys: 1))
    }

    /// A missing path is distinguishable from a path holding JSON null.
    @Test func distinguishesMissingFromNull() {
        #expect(JSONProbe.probe("absent", in: payload) == nil)
        #expect(JSONProbe.probe("nothing", in: payload) == .null)
        #expect(JSONProbe.probe("items[9].id", in: payload) == nil)
        #expect(JSONProbe.probe("name.deeper", in: payload) == nil)
        #expect(JSONProbe.probe("count[0]", in: payload) == nil)
    }

    @Test func handlesEmptyAndInvalidInput() {
        #expect(JSONProbe.probe("a", in: Data()) == nil)
        #expect(JSONProbe.probe("a", in: Data("not json".utf8)) == nil)
        #expect(JSONProbe.probe("", in: payload) == .object(keys: 8))
    }

    @Test func rendersValuesForComparison() {
        #expect(JSONProbeValue.number(3).stringValue == "3")
        #expect(JSONProbeValue.number(1.5).stringValue == "1.5")
        #expect(JSONProbeValue.bool(false).stringValue == "false")
        #expect(JSONProbeValue.null.stringValue == "null")
        #expect(JSONProbeValue.string("x").stringValue == "x")
        #expect(JSONProbeValue.array(count: 2).stringValue == "[2 items]")
    }

    @Test func parsesPathSegments() {
        #expect(JSONProbe.segments(of: "a.b[0].c") == [.key("a"), .key("b"), .index(0), .key("c")])
        #expect(JSONProbe.segments(of: "[2]") == [.index(2)])
        #expect(JSONProbe.segments(of: "a[unclosed") == [.key("a")])
    }
}

// MARK: - Assertions

@Suite struct ApiAssertionTests {

    private let subject = ApiResponse(
        statusCode: 201,
        headers: [
            (key: "Content-Type", value: "application/json"),
            (key: "X-Request-Id", value: "abc123"),
        ],
        body: Data(#"{"id":7,"name":"widget","tags":[],"active":true}"#.utf8),
        elapsedMs: 150
    )

    private func check(
        _ target: AssertionTarget, _ op: AssertionOperator, _ expected: String = ""
    ) -> AssertionResult {
        ApiAssertions.evaluate(
            ApiAssertion(target: target, op: op, expected: expected), against: subject
        )
    }

    @Test func comparesTheStatusCode() {
        #expect(check(.statusCode, .equals, "201").passed)
        #expect(!check(.statusCode, .equals, "200").passed)
        #expect(check(.statusCode, .notEquals, "500").passed)
        #expect(check(.statusCode, .lessThan, "300").passed)
        #expect(check(.statusCode, .greaterThan, "200").passed)
        #expect(!check(.statusCode, .greaterThan, "201").passed)
    }

    @Test func numericAndTextualEqualityAgreeOnNumbers() {
        #expect(check(.statusCode, .equals, "201.0").passed)
        #expect(check(.statusCode, .equals, " 201 ").passed)
    }

    @Test func comparesResponseTimeAndSize() {
        #expect(check(.responseTimeMs, .lessThan, "1000").passed)
        #expect(!check(.responseTimeMs, .lessThan, "100").passed)
        #expect(check(.bodySize, .greaterThan, "10").passed)
    }

    @Test func readsHeadersCaseInsensitively() {
        #expect(check(.header("content-type"), .contains, "json").passed)
        #expect(check(.header("X-Request-Id"), .equals, "abc123").passed)
        #expect(check(.header("x-request-id"), .exists).passed)
        #expect(check(.header("X-Missing"), .notExists).passed)
        #expect(!check(.header("X-Missing"), .exists).passed)
    }

    @Test func aMissingHeaderIsNotEqualToAnything() {
        #expect(!check(.header("X-Missing"), .equals, "x").passed)
        #expect(check(.header("X-Missing"), .notEquals, "x").passed)
        #expect(!check(.header("X-Missing"), .contains, "x").passed)
    }

    @Test func readsJSONPaths() {
        #expect(check(.jsonPath("id"), .equals, "7").passed)
        #expect(check(.jsonPath("name"), .equals, "widget").passed)
        #expect(check(.jsonPath("active"), .equals, "true").passed)
        #expect(check(.jsonPath("tags"), .exists).passed)
        #expect(check(.jsonPath("missing"), .notExists).passed)
        #expect(!check(.jsonPath("missing"), .exists).passed)
    }

    @Test func matchesTheBodyAsTextAndByRegex() {
        #expect(check(.bodyText, .contains, "widget").passed)
        #expect(check(.bodyText, .notContains, "gadget").passed)
        #expect(check(.bodyText, .matchesRegex, #""id":\s*\d+"#).passed)
        #expect(!check(.bodyText, .matchesRegex, #""id":\s*"\w+""#).passed)
        #expect(check(.bodyText, .isNotEmpty).passed)
        #expect(!check(.bodyText, .isEmpty).passed)
    }

    @Test func anInvalidRegexFailsWithAnExplanation() {
        let result = check(.bodyText, .matchesRegex, "[unclosed")
        #expect(!result.passed)
        #expect(result.detail == "invalid regex")
    }

    @Test func nonNumericComparisonsFailWithAnExplanation() {
        let result = check(.jsonPath("name"), .lessThan, "10")
        #expect(!result.passed)
        #expect(result.detail.contains("not a number"))

        let badExpectation = check(.statusCode, .lessThan, "abc")
        #expect(!badExpectation.passed)
        #expect(badExpectation.detail.contains("expected value is not a number"))
    }

    @Test func theFailureDetailShowsWhatWasFound() {
        #expect(check(.statusCode, .equals, "200").detail == "\"201\"")
        #expect(check(.header("X-Missing"), .equals, "x").detail == "not present")
    }

    @Test func aLongValueIsTruncatedInTheDetail() {
        let long = ApiResponse(
            statusCode: 200, headers: [], body: Data(String(repeating: "x", count: 500).utf8),
            elapsedMs: 1
        )
        let result = ApiAssertions.evaluate(
            ApiAssertion(target: .bodyText, op: .equals, expected: "y"), against: long
        )
        #expect(result.detail.count < 140)
        #expect(result.detail.hasSuffix("…\""))
    }

    @Test func disabledAssertionsAreSkipped() {
        let results = ApiAssertions.evaluate(
            [
                ApiAssertion(target: .statusCode, op: .equals, expected: "201"),
                ApiAssertion(enabled: false, target: .statusCode, op: .equals, expected: "500"),
            ],
            against: subject
        )
        #expect(results.count == 1)
        #expect(results[0].passed)
    }

    @Test func summarisesPassesAndFailures() {
        let results = ApiAssertions.evaluate(
            [
                ApiAssertion(target: .statusCode, op: .equals, expected: "201"),
                ApiAssertion(target: .statusCode, op: .equals, expected: "500"),
                ApiAssertion(target: .jsonPath("id"), op: .equals, expected: "7"),
            ],
            against: subject
        )
        let summary = ApiAssertions.summary(results)
        #expect(summary.passed == 2)
        #expect(summary.failed == 1)
    }

    @Test func targetsWithoutAnArgumentAreUnusable() {
        #expect(!check(.header(""), .exists).passed)
        #expect(!check(.jsonPath(""), .exists).passed)
    }

    @Test func labelsReadAsSentences() {
        #expect(
            ApiAssertion(target: .statusCode, op: .equals, expected: "200").label
                == "status code equals 200"
        )
        #expect(
            ApiAssertion(target: .header("Content-Type"), op: .exists).label
                == "header Content-Type exists"
        )
        #expect(
            ApiAssertion(target: .jsonPath("a.b"), op: .contains, expected: "x").label
                == "json a.b contains x"
        )
    }

    @Test func targetsSurviveEncodingWithTheirArgument() throws {
        for target in [
            AssertionTarget.statusCode, .responseTimeMs, .bodySize, .bodyText,
            .header("X-A"), .jsonPath("a[0].b"),
        ] {
            let assertion = ApiAssertion(target: target, op: .exists)
            let data = try JSONEncoder().encode(assertion)
            let decoded = try JSONDecoder().decode(ApiAssertion.self, from: data)
            #expect(decoded.target == target)
        }
    }

    @Test func unaryOperatorsIgnoreTheExpectedField() {
        for op in AssertionOperator.allCases where op.isUnary {
            #expect(!ApiAssertion(target: .statusCode, op: op).label.contains("200"))
        }
    }
}
