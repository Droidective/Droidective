import Foundation
import Testing

@testable import ADBKit

/// Reads a token back as the substring it points at, which is the property that
/// actually matters: a length that drifts by one paints the wrong characters.
private func text(_ token: SyntaxToken, in source: String) -> String {
    let utf16 = Array(source.utf16)
    let slice = utf16[token.location..<(token.location + token.length)]
    return String(decoding: slice, as: UTF16.self)
}

private func tokens(_ source: String, _ format: ResponseFormat) -> [SyntaxToken] {
    SyntaxHighlighter.tokens(for: source, format: format)
}

@Suite struct JSONSyntaxTests {

    @Test func keysAndStringValuesAreToldApart() throws {
        let source = #"{"name":"ada"}"#
        let found = tokens(source, .json)
        let keys = found.filter { $0.kind == .key }
        let strings = found.filter { $0.kind == .string }
        #expect(keys.map { text($0, in: source) } == [#""name""#])
        #expect(strings.map { text($0, in: source) } == [#""ada""#])
    }

    @Test func numbersCoverSignExponentAndFraction() throws {
        let source = #"{"a":-1.5e+10,"b":42}"#
        let numbers = tokens(source, .json).filter { $0.kind == .number }
        #expect(numbers.map { text($0, in: source) } == ["-1.5e+10", "42"])
    }

    @Test func literalsAreTokenized() throws {
        let source = #"[true,false,null]"#
        let literals = tokens(source, .json).filter { $0.kind == .literal }
        #expect(literals.map { text($0, in: source) } == ["true", "false", "null"])
    }

    @Test func aColonInsideAStringDoesNotMakeTheNextStringAKey() throws {
        let source = #"{"url":"http://x/y","n":1}"#
        let keys = tokens(source, .json).filter { $0.kind == .key }
        #expect(keys.map { text($0, in: source) } == [#""url""#, #""n""#])
    }

    @Test func escapedQuotesDoNotEndAString() throws {
        let source = #"{"a":"say \"hi\"","b":2}"#
        let strings = tokens(source, .json).filter { $0.kind == .string }
        #expect(strings.map { text($0, in: source) } == [#""say \"hi\"""#])
    }

    @Test func literalPrefixesInsideWordsAreNotLiterals() throws {
        // `nullable` is not `null`; it lives inside a string and must stay one.
        let source = #"{"k":"nullable"}"#
        #expect(tokens(source, .json).contains { $0.kind == .literal } == false)
    }

    @Test func offsetsSurviveMultiByteCharacters() throws {
        let source = #"{"emoji":"🙂","after":1}"#
        let found = tokens(source, .json)
        let keys = found.filter { $0.kind == .key }
        #expect(keys.map { text($0, in: source) } == [#""emoji""#, #""after""#])
        let numbers = found.filter { $0.kind == .number }
        #expect(numbers.map { text($0, in: source) } == ["1"])
    }

    @Test func aTruncatedBodyStillTokenizesWhatArrived() throws {
        let source = #"{"a":1,"b":"unterminated"#
        let found = tokens(source, .json)
        #expect(!found.isEmpty)
        #expect(found.allSatisfy { $0.location + $0.length <= source.utf16.count })
    }

    @Test func jsonLinesTokenizeAsOneStream() throws {
        let source = "{\"a\":1}\n{\"b\":2}"
        let keys = tokens(source, .json).filter { $0.kind == .key }
        #expect(keys.map { text($0, in: source) } == [#""a""#, #""b""#])
    }
}

@Suite struct MarkupSyntaxTests {

    @Test func tagNamesAttributesAndValuesAreSeparated() throws {
        let source = #"<a href="/x" id='y'>text</a>"#
        let found = tokens(source, .html)
        #expect(found.filter { $0.kind == .tag }.map { text($0, in: source) } == ["<a", "</a"])
        #expect(
            found.filter { $0.kind == .attribute }.map { text($0, in: source) } == ["href", "id"]
        )
        #expect(
            found.filter { $0.kind == .value }.map { text($0, in: source) } == [#""/x""#, "'y'"]
        )
    }

    @Test func aGreaterThanInsideAnAttributeDoesNotEndTheTag() throws {
        let source = #"<a title="x > y"><b/>"#
        let tags = tokens(source, .html).filter { $0.kind == .tag }
        #expect(tags.map { text($0, in: source) } == ["<a", "<b"])
    }

    @Test func commentsAreOneToken() throws {
        let source = "<div><!-- a > b --></div>"
        let comments = tokens(source, .html).filter { $0.kind == .comment }
        #expect(comments.map { text($0, in: source) } == ["<!-- a > b -->"])
    }

    @Test func doctypeAndProcessingInstructionsAreDeclarations() throws {
        let source = "<!doctype html><?xml version=\"1.0\"?><a/>"
        let declarations = tokens(source, .xml).filter { $0.kind == .declaration }
        #expect(
            declarations.map { text($0, in: source) } == ["<!doctype html>", "<?xml version=\"1.0\"?>"]
        )
    }

    @Test func cdataIsTreatedAsAString() throws {
        let source = "<a><![CDATA[x > y]]></a>"
        let strings = tokens(source, .xml).filter { $0.kind == .string }
        #expect(strings.map { text($0, in: source) } == ["<![CDATA[x > y]]>"])
    }

    @Test func textBetweenTagsIsNotTokenized() throws {
        let source = "<p>hello world</p>"
        let covered = tokens(source, .html).reduce(0) { $0 + $1.length }
        #expect(covered == "<p".utf16.count + "</p".utf16.count)
    }

    @Test func anUnterminatedTagDoesNotRunPastTheEnd() throws {
        let source = "<div class=\"x"
        let found = tokens(source, .html)
        #expect(found.allSatisfy { $0.location + $0.length <= source.utf16.count })
    }

    @Test func namespacedElementsKeepTheirPrefix() throws {
        let source = #"<ns:root xmlns:ns="urn:x"/>"#
        let tags = tokens(source, .xml).filter { $0.kind == .tag }
        #expect(tags.map { text($0, in: source) } == ["<ns:root"])
    }
}

@Suite struct SyntaxHighlighterScopeTests {

    @Test func plainTextAndBinaryAreNotTokenized() {
        #expect(tokens("hello", .text).isEmpty)
        #expect(tokens("hello", .binary).isEmpty)
        #expect(tokens("hello", .image).isEmpty)
    }

    @Test func aBodyOverTheCapIsLeftPlain() {
        let huge = String(repeating: "{\"a\":1}", count: SyntaxHighlighter.maxHighlightableLength)
        #expect(huge.utf16.count > SyntaxHighlighter.maxHighlightableLength)
        #expect(tokens(huge, .json).isEmpty)
    }

    @Test func aBodyAtTheCapIsStillTokenized() {
        let source = #"{"a":1}"#
        #expect(source.utf16.count <= SyntaxHighlighter.maxHighlightableLength)
        #expect(!tokens(source, .json).isEmpty)
    }

    @Test func tokensNeverOverlapOrRunBackwards() {
        let source = #"{"a":[1,true,"x"],"b":{"c":null}}"#
        let found = tokens(source, .json)
        for (previous, next) in zip(found, found.dropFirst()) {
            #expect(previous.location + previous.length <= next.location)
        }
    }

    @Test func markupTokensNeverOverlapOrRunBackwards() {
        let source = #"<html><body class="a b"><!-- c --><img src="x"/></body></html>"#
        let found = tokens(source, .html)
        for (previous, next) in zip(found, found.dropFirst()) {
            #expect(previous.location + previous.length <= next.location)
        }
    }
}
