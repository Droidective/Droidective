import Foundation
import Testing
@testable import ADBKit

private struct Row: Identifiable, Equatable {
    let id: Int
    let text: String

    init(_ id: Int, _ text: String = "") {
        self.id = id
        self.text = text.lowercased()
    }
}

@Suite struct FilteredLogBufferTests {
    @Test func emptyFilterFastPathMirrorsEntries() {
        var buffer = FilteredLogBuffer<Row>(capacity: 10)
        buffer.append([Row(1), Row(2)], isIncluded: nil)
        buffer.append([Row(3)], isIncluded: nil)
        #expect(buffer.filtered == buffer.entries)
        #expect(buffer.entries.map(\.id) == [1, 2, 3])
    }

    @Test func emptyFilterFastPathMirrorsEntriesAcrossEviction() {
        var buffer = FilteredLogBuffer<Row>(capacity: 3)
        buffer.append([Row(1), Row(2), Row(3), Row(4)], isIncluded: nil)
        buffer.append([Row(5)], isIncluded: nil)
        #expect(buffer.entries.map(\.id) == [3, 4, 5])
        #expect(buffer.filtered == buffer.entries)
    }

    @Test func incrementalAppendMatchesFullRecompute() {
        let isEven: (Row) -> Bool = { $0.id.isMultiple(of: 2) }
        var buffer = FilteredLogBuffer<Row>(capacity: 100)
        for batch in [[Row(1), Row(2)], [Row(3)], [Row(4), Row(5), Row(6)], []] {
            buffer.append(batch, isIncluded: isEven)
        }
        #expect(buffer.filtered == buffer.entries.filter(isEven))
        #expect(buffer.filtered.map(\.id) == [2, 4, 6])
    }

    @Test func capEvictionDropsEvictedRowsFromFiltered() {
        let isEven: (Row) -> Bool = { $0.id.isMultiple(of: 2) }
        var buffer = FilteredLogBuffer<Row>(capacity: 4)
        buffer.append((1 ... 4).map { Row($0) }, isIncluded: isEven)
        #expect(buffer.filtered.map(\.id) == [2, 4])
        // 5...8 evict 1...4; the projection must lose 2 and 4 and gain 6 and 8.
        buffer.append((5 ... 8).map { Row($0) }, isIncluded: isEven)
        #expect(buffer.entries.map(\.id) == [5, 6, 7, 8])
        #expect(buffer.filtered == buffer.entries.filter(isEven))
        #expect(buffer.filtered.map(\.id) == [6, 8])
    }

    @Test func partialEvictionKeepsSurvivingMatches() {
        let isOdd: (Row) -> Bool = { !$0.id.isMultiple(of: 2) }
        var buffer = FilteredLogBuffer<Row>(capacity: 3)
        buffer.append((1 ... 5).map { Row($0) }, isIncluded: isOdd)
        // Entries 1 and 2 evicted; survivors are 3, 4, 5.
        #expect(buffer.entries.map(\.id) == [3, 4, 5])
        #expect(buffer.filtered.map(\.id) == [3, 5])
    }

    @Test func refilterRecomputesTheProjection() {
        var buffer = FilteredLogBuffer<Row>(capacity: 10)
        buffer.append((1 ... 5).map { Row($0) }, isIncluded: nil)
        buffer.refilter { $0.id > 3 }
        #expect(buffer.filtered.map(\.id) == [4, 5])
        buffer.refilter(isIncluded: nil)
        #expect(buffer.filtered == buffer.entries)
    }

    @Test func removeAllEmptiesBothProjections() {
        var buffer = FilteredLogBuffer<Row>(capacity: 10)
        buffer.append([Row(1), Row(2)], isIncluded: nil)
        buffer.removeAll()
        #expect(buffer.entries.isEmpty)
        #expect(buffer.filtered.isEmpty)
    }

    @Test func byteBudgetEvictsOldestWhenCountCapIsNowhereNear() {
        // 10-entry cap but a 100-byte budget: three 40-byte rows exceed it, so
        // the oldest goes even though the count cap alone would keep all three.
        var buffer = FilteredLogBuffer<Row>(capacity: 10, byteBudget: 100, cost: { _ in 40 })
        buffer.append([Row(1), Row(2), Row(3)], isIncluded: nil)
        #expect(buffer.entries.map(\.id) == [2, 3])
        #expect(buffer.filtered == buffer.entries)
    }

    @Test func byteBudgetAlwaysKeepsTheNewestEntry() {
        // One entry alone over budget must not empty the feed.
        var buffer = FilteredLogBuffer<Row>(capacity: 10, byteBudget: 100, cost: { _ in 500 })
        buffer.append([Row(1)], isIncluded: nil)
        buffer.append([Row(2)], isIncluded: nil)
        #expect(buffer.entries.map(\.id) == [2])
    }

    @Test func byteBudgetEvictionDropsEvictedRowsFromFiltered() {
        var buffer = FilteredLogBuffer<Row>(capacity: 10, byteBudget: 90, cost: { _ in 40 })
        let filter: (Row) -> Bool = { $0.id % 2 == 1 }
        buffer.append([Row(1), Row(2)], isIncluded: filter)
        buffer.append([Row(3)], isIncluded: filter)   // over budget → Row(1) evicted
        #expect(buffer.entries.map(\.id) == [2, 3])
        #expect(buffer.filtered.map(\.id) == [3])
    }

    @Test func textQueryIncrementalAppendMatchesFullRecompute() {
        let query = ConsoleQuery("Error")
        let match: (Row) -> Bool = { query.matches($0.text) }
        var buffer = FilteredLogBuffer<Row>(capacity: 4)
        buffer.append([Row(1, "network ERROR: 500"), Row(2, "ok")], isIncluded: match)
        buffer.append([Row(3, "an error again"), Row(4, "fine"), Row(5, "Error at start")], isIncluded: match)
        #expect(buffer.filtered == buffer.entries.filter(match))
        #expect(buffer.filtered.map(\.id) == [3, 5])
    }
}

@Suite struct ConsoleQueryTests {
    @Test func emptyQueryMatchesEverything() {
        let query = ConsoleQuery("")
        #expect(query.isEmpty)
        #expect(query.matches("anything"))
        #expect(query.matches(""))
    }

    @Test func whitespaceOnlyQueryIsEmpty() {
        #expect(ConsoleQuery("   ").isEmpty)
        #expect(ConsoleQuery("  hi  ").normalized == "hi")
    }

    @Test func matchingIsCaseInsensitive() {
        // The cached side is lowercased at ingest; the query side at creation.
        #expect(ConsoleQuery("WARN").matches("deprecation warning".lowercased()))
        #expect(ConsoleQuery("fetch").matches("Fetch failed: timeout".lowercased()))
        #expect(!ConsoleQuery("fetch").matches("nothing here".lowercased()))
    }

    @Test func matchesAcrossAndBesideCRLF() {
        let text = "First line\r\nSecond LINE".lowercased()
        #expect(ConsoleQuery("first").matches(text))
        #expect(ConsoleQuery("Second line").matches(text))
        // "\r\n" is a single Character; a plain-"\n" query must not match it.
        #expect(!ConsoleQuery("line\nsecond").matches(text))
        #expect(ConsoleQuery("line\r\nsecond").matches(text))
    }
}
