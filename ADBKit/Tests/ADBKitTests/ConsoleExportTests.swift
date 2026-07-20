@testable import ADBKit
import Foundation
import Testing

struct ConsoleExportTests {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    @Test func emptyFeedExportsEmptyArray() throws {
        let json = try #require(ConsoleExport.json([]))
        let data = try #require(json.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [Any])
        #expect(decoded.isEmpty)
    }

    @Test func exportsEntriesInGivenOrderWithISOTimestamps() throws {
        let json = try #require(ConsoleExport.json([
            ConsoleExportEntry(at: date(0), type: "log", level: "error", text: "boom"),
            ConsoleExportEntry(at: date(1.5), type: "input", text: "1 + 1"),
        ]))
        let data = try #require(json.data(using: .utf8))
        let decoded = try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )
        #expect(decoded.count == 2)
        #expect(decoded[0]["timestamp"] as? String == "1970-01-01T00:00:00.000Z")
        #expect(decoded[0]["type"] as? String == "log")
        #expect(decoded[0]["level"] as? String == "error")
        #expect(decoded[0]["text"] as? String == "boom")
        // Fractional seconds survive — bursts land several entries per second.
        #expect(decoded[1]["timestamp"] as? String == "1970-01-01T00:00:01.500Z")
        #expect(decoded[1]["type"] as? String == "input")
    }

    @Test func levelIsOmittedWhenAbsent() throws {
        let json = try #require(ConsoleExport.json([
            ConsoleExportEntry(at: date(0), type: "notice", text: "connected"),
        ]))
        #expect(!json.contains("\"level\""))
    }

    @Test func escapesQuotesAndNewlines() throws {
        let json = try #require(ConsoleExport.json([
            ConsoleExportEntry(at: date(0), type: "log", level: "log", text: "a \"quoted\"\nline"),
        ]))
        let data = try #require(json.data(using: .utf8))
        let decoded = try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )
        #expect(decoded[0]["text"] as? String == "a \"quoted\"\nline")
    }
}
