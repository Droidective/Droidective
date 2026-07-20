import ADBKit
import Foundation
import Testing
@testable import ReactotronMCP

/// Port of upstream `test/serialization.test.ts` plus the buffered-command
/// summary shapes the tools/resources return.
@Suite struct McpSerializationTests {
    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func buffered(
        _ command: ReactotronCommand, messageId: Int = 7, clientId: String? = "app-1"
    ) -> McpBufferedCommand {
        McpBufferedCommand(
            messageId: messageId, connectionId: 1, clientId: clientId,
            command: command, frameBytes: 100
        )
    }

    // MARK: - compactJson / truncate / safeSerialize

    @Test func compactJsonProducesNoIndentation() throws {
        let text = McpSerialization.compactJson(try json(#"{"a":1,"b":[1,2]}"#))
        #expect(!text.contains("\n"))
        #expect(!text.contains("  "))
        #expect(text.contains(#""a":1"#))
    }

    @Test func truncateReturnsOriginalWhenUnderLimit() {
        #expect(McpSerialization.truncate("short", limit: 100) == "short")
    }

    @Test func truncateAppendsDefaultMessageWhenOverLimit() {
        let result = McpSerialization.truncate(String(repeating: "x", count: 5000), limit: 1000)
        #expect(result.count <= 1000)
        #expect(result.contains("[TRUNCATED — response was ~5K chars.]"))
    }

    @Test func truncateAppendsCustomGuidance() {
        let result = McpSerialization.truncate(
            String(repeating: "x", count: 5000), limit: 1000,
            guidance: "Pass a path to narrow the state read."
        )
        #expect(result.contains("Pass a path to narrow the state read."))
        #expect(result.count <= 1000)
    }

    @Test func safeSerializeUsesMaxResponseCharsAsDefaultLimit() throws {
        let big = JSONValue.array(
            (0 ..< 60_000).map { .string("item-\($0)-padding-padding") })
        let result = McpSerialization.safeSerialize(big)
        #expect(result.count <= McpConstants.maxResponseChars)
        #expect(result.contains("[TRUNCATED"))
        let small = McpSerialization.safeSerialize(try json(#"{"ok":true}"#))
        #expect(small == #"{"ok":true}"#)
    }

    // MARK: - summarizeCommand

    @Test func summaryKeepsMetadataAndStripsPayload() throws {
        let command = ReactotronCommand(
            type: "display",
            payload: try json(#"{"name":"BIG","value":{"huge":"payload"}}"#),
            important: true, date: "2026-07-20T10:00:00.000Z", deltaTime: 12
        )
        let summary = McpSerialization.summarizeCommand(buffered(command))
        #expect(summary["type"]?.stringValue == "display")
        #expect(summary["messageId"]?.intValue == 7)
        #expect(summary["clientId"]?.stringValue == "app-1")
        #expect(summary["important"]?.boolValue == true)
        #expect(summary["deltaTime"]?.doubleValue == 12)
        #expect(summary["payload"] == nil)
        #expect(summary["payloadPreview"] != nil)
    }

    @Test func apiResponseGetsAOneLinerPreview() throws {
        let command = ReactotronCommand(
            type: "api.response",
            payload: try json(#"""
            {"duration":123,
             "request":{"method":"POST","url":"https://api.x.dev/login"},
             "response":{"status":200}}
            """#)
        )
        let summary = McpSerialization.summarizeCommand(buffered(command))
        #expect(summary["payloadPreview"]?.stringValue
            == "POST https://api.x.dev/login -> 200 (123ms)")
    }

    @Test func logGetsALevelPrefixedPreview() throws {
        let command = ReactotronCommand(
            type: "log", payload: try json(#"{"level":"warn","message":"disk full"}"#))
        let summary = McpSerialization.summarizeCommand(buffered(command))
        #expect(summary["payloadPreview"]?.stringValue == "[warn] disk full")
    }

    @Test func longLogMessagesAreCapped() throws {
        let long = String(repeating: "m", count: 500)
        let command = ReactotronCommand(
            type: "log", payload: try json(#"{"level":"debug","message":"\#(long)"}"#))
        let preview = try #require(
            McpSerialization.summarizeCommand(buffered(command))["payloadPreview"]?.stringValue)
        #expect(preview.hasSuffix("..."))
        #expect(preview.count <= McpConstants.maxPayloadPreviewChars + 16)
    }

    @Test func stateValuesResponseShowsThePath() throws {
        let command = ReactotronCommand(
            type: "state.values.response", payload: try json(#"{"path":"user.profile"}"#))
        #expect(McpSerialization.summarizeCommand(buffered(command))["payloadPreview"]?.stringValue
            == "path: user.profile")
        let rootCommand = ReactotronCommand(
            type: "state.values.response", payload: try json(#"{"valid":true}"#))
        #expect(McpSerialization.summarizeCommand(buffered(rootCommand))["payloadPreview"]?.stringValue
            == "path: (root)")
    }

    @Test func genericPayloadPreviewIsTruncated() throws {
        let command = ReactotronCommand(
            type: "custom.thing",
            payload: try json(#"{"blob":"\#(String(repeating: "z", count: 400))"}"#)
        )
        let preview = try #require(
            McpSerialization.summarizeCommand(buffered(command))["payloadPreview"]?.stringValue)
        #expect(preview.hasSuffix("..."))
        #expect(preview.count <= McpConstants.maxPayloadPreviewChars + 3)
    }

    // MARK: - summarizeNetworkEntry

    @Test func networkEntryKeepsUrlMethodStatusDuration() throws {
        let command = ReactotronCommand(
            type: "api.response",
            payload: try json(#"""
            {"duration":45.5,
             "request":{"method":"GET","url":"https://x.dev/v1/items",
                        "headers":{"Accept":"application/json"},"data":null},
             "response":{"status":304,"headers":{"ETag":"abc"},"body":""}}
            """#),
            date: "2026-07-20T10:00:00.000Z"
        )
        let entry = McpSerialization.summarizeNetworkEntry(buffered(command))
        #expect(entry["request"]?["method"]?.stringValue == "GET")
        #expect(entry["request"]?["url"]?.stringValue == "https://x.dev/v1/items")
        #expect(entry["response"]?["status"]?.intValue == 304)
        #expect(entry["duration"]?.doubleValue == 45.5)
        #expect(entry["messageId"]?.intValue == 7)
        #expect(entry["request"]?["data"] == nil)
    }

    @Test func largeBodiesArePreviewTruncated() throws {
        let bigBody = String(repeating: "b", count: 2000)
        let command = ReactotronCommand(
            type: "api.response",
            payload: try json(#"""
            {"request":{"method":"POST","url":"u","data":"\#(bigBody)"},
             "response":{"status":200,"body":"\#(bigBody)"}}
            """#)
        )
        let entry = McpSerialization.summarizeNetworkEntry(buffered(command))
        let requestData = try #require(entry["request"]?["data"]?.stringValue)
        let responseBody = try #require(entry["response"]?["body"]?.stringValue)
        #expect(requestData.count == McpConstants.maxBodyPreviewChars + 3)
        #expect(requestData.hasSuffix("..."))
        #expect(responseBody.count == McpConstants.maxBodyPreviewChars + 3)
        #expect(responseBody.hasSuffix("..."))
    }
}
