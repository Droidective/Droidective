import Testing

@testable import ADBKit

@Suite struct LogLineFilterTests {
    private func line(tag: String, message: String) -> LogLine {
        LogLine(
            raw: "06-01 12:00:00.000  100  200 I \(tag): \(message)",
            time: "06-01 12:00:00.000", pid: "100", level: "I", tag: tag, message: message
        )
    }

    // MARK: visible (the Filter field — hides non-matching lines)

    @Test func emptyFilterAndNoTagKeepsEverything() {
        let lines = [line(tag: "Net", message: "up"), line(tag: "UI", message: "drawn")]
        #expect(LogLineFilter.visible(lines, tag: nil, filter: "") == lines)
    }

    @Test func tagFilterIsExact() {
        let net = line(tag: "Net", message: "up")
        let netty = line(tag: "Netty", message: "up")
        #expect(LogLineFilter.visible([net, netty], tag: "Net", filter: "") == [net])
    }

    @Test func textFilterIsCaseInsensitive() {
        let hit = line(tag: "Net", message: "Connection FAILED")
        let miss = line(tag: "Net", message: "connected")
        #expect(LogLineFilter.visible([hit, miss], tag: nil, filter: "failed") == [hit])
    }

    @Test func tagAndTextFiltersCombine() {
        let both = line(tag: "Net", message: "timeout")
        let wrongTag = line(tag: "UI", message: "timeout")
        let wrongText = line(tag: "Net", message: "ok")
        #expect(
            LogLineFilter.visible([both, wrongTag, wrongText], tag: "Net", filter: "timeout")
                == [both])
    }

    @Test func noMatchesReturnsEmpty() {
        let lines = [line(tag: "Net", message: "up")]
        #expect(LogLineFilter.visible(lines, tag: nil, filter: "zzz").isEmpty)
    }

    // MARK: findMatches (the Find bar — display order)

    @Test func findMatchesFollowDisplayOrder() {
        let first = line(tag: "A", message: "hit one")
        let second = line(tag: "B", message: "miss")
        let third = line(tag: "C", message: "hit two")
        let lines = [first, second, third]
        #expect(LogLineFilter.findMatches(in: lines, query: "HIT", newestFirst: false)
            == [first.id, third.id])
        #expect(LogLineFilter.findMatches(in: lines, query: "HIT", newestFirst: true)
            == [third.id, first.id])
    }

    @Test func emptyFindQueryMatchesNothing() {
        let lines = [line(tag: "A", message: "hit")]
        #expect(LogLineFilter.findMatches(in: lines, query: "", newestFirst: false).isEmpty)
    }

    // MARK: advance (next/previous with wrap)

    @Test func advanceWithoutACurrentMatchStartsAtTheNearestEnd() {
        let matches = [line(tag: "A", message: "x").id, line(tag: "B", message: "x").id]
        #expect(LogLineFilter.advance(from: nil, in: matches, forward: true) == matches.first)
        #expect(LogLineFilter.advance(from: nil, in: matches, forward: false) == matches.last)
    }

    @Test func advanceWrapsAtBothEnds() {
        let matches = [line(tag: "A", message: "x").id, line(tag: "B", message: "x").id]
        #expect(LogLineFilter.advance(from: matches[1], in: matches, forward: true) == matches[0])
        #expect(LogLineFilter.advance(from: matches[0], in: matches, forward: false) == matches[1])
    }

    @Test func advanceFromATrimmedMatchFallsBackToTheNearestEnd() {
        let matches = [line(tag: "A", message: "x").id, line(tag: "B", message: "x").id]
        let gone = line(tag: "C", message: "x").id
        #expect(LogLineFilter.advance(from: gone, in: matches, forward: true) == matches.first)
        #expect(LogLineFilter.advance(from: gone, in: matches, forward: false) == matches.last)
    }

    @Test func advanceWithNoMatchesReturnsNil() {
        #expect(LogLineFilter.advance(from: nil, in: [], forward: true) == nil)
    }
}
