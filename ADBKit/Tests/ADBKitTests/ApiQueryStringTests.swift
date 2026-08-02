import Foundation
import Testing

@testable import ADBKit

@Suite struct ApiQueryStringTests {

    @Test func parametersComeOutInOrder() {
        let found = ApiQueryString.parameters(in: "https://x.dev/s?b=2&a=1")
        #expect(found.map(\.key) == ["b", "a"])
        #expect(found.map(\.value) == ["2", "1"])
    }

    @Test func valuesArePercentDecoded() {
        let found = ApiQueryString.parameters(in: "https://x.dev?q=hello%20world&n=a%2Bb")
        #expect(found.map(\.value) == ["hello world", "a+b"])
    }

    @Test func plusSignsDecodeAsSpaces() {
        #expect(ApiQueryString.parameters(in: "https://x.dev?q=two+words").first?.value == "two words")
    }

    @Test func aValuelessFlagKeepsItsName() {
        let found = ApiQueryString.parameters(in: "https://x.dev?debug")
        #expect(found.map(\.key) == ["debug"])
        #expect(found.map(\.value) == [""])
    }

    @Test func anEmptyValueSurvives() {
        let found = ApiQueryString.parameters(in: "https://x.dev?a=&b=2")
        #expect(found.map(\.value) == ["", "2"])
    }

    @Test func aValueContainingAnEqualsIsNotSplitTwice() {
        #expect(
            ApiQueryString.parameters(in: "https://x.dev?token=a=b=c").first?.value == "a=b=c"
        )
    }

    @Test func theFragmentIsNotPartOfTheQuery() {
        let found = ApiQueryString.parameters(in: "https://x.dev?a=1#section")
        #expect(found.map(\.value) == ["1"])
    }

    @Test func aURLWithNoQueryYieldsNothing() {
        #expect(ApiQueryString.parameters(in: "https://x.dev/path").isEmpty)
        #expect(ApiQueryString.parameters(in: "").isEmpty)
        #expect(ApiQueryString.hasQuery("https://x.dev/path") == false)
        #expect(ApiQueryString.hasQuery("https://x.dev/path?a=1"))
    }

    @Test func emptyPairsAreSkipped() {
        let found = ApiQueryString.parameters(in: "https://x.dev?a=1&&b=2")
        #expect(found.map(\.key) == ["a", "b"])
    }

    @Test func strippingTheQueryKeepsTheFragment() {
        #expect(
            ApiQueryString.removingQuery(from: "https://x.dev/p?a=1#top") == "https://x.dev/p#top"
        )
        #expect(ApiQueryString.removingQuery(from: "https://x.dev/p?a=1") == "https://x.dev/p")
    }

    @Test func aURLWithoutAQueryIsReturnedUntouched() {
        #expect(ApiQueryString.removingQuery(from: "https://x.dev/p") == "https://x.dev/p")
    }

    @Test func extractingThenBuildingProducesTheSameRequest() throws {
        // The point of the round trip: what goes on the wire must not change.
        let before = SavedRequest(url: "https://x.dev/s?q=hello%20world&n=2")
        var after = SavedRequest(url: ApiQueryString.removingQuery(from: before.url))
        after.queryParams = ApiQueryString.parameters(in: before.url)

        let built = try HttpRequestBuilder.prepare(before)
        let rebuilt = try HttpRequestBuilder.prepare(after)
        #expect(built.url == rebuilt.url)
    }
}
