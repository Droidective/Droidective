#if canImport(Network)

import ADBKit
import Foundation
import Testing
@testable import ReactotronMCP

/// Port of upstream `lib/reactotron-mcp/test/redaction.test.ts` — the cases
/// that define the redaction contract. Fixtures build `JSONValue` from JSON
/// text so they read like the originals.
@Suite struct McpRedactionTests {
    private let redacted = McpRedaction.redactedMarker

    private let rules = McpRedactionRules(
        sensitiveKeys: ["password", "secret", "api_key", "authorization", "cookie"],
        statePathPatterns: ["auth.tokens.*", "user.ssn"],
        valuePatterns: [
            #"Bearer\s+[A-Za-z0-9\-._~+/]+=*"#,
            #"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#,
        ]
    )

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func redact(_ value: JSONValue, rules: McpRedactionRules? = nil) -> JSONValue {
        McpRedaction.redact(value, parsed: McpRedaction.parse(rules ?? self.rules))
    }

    // MARK: - redact()

    @Test func redactsSensitiveKeyNamesCaseInsensitive() throws {
        let result = redact(try json(
            #"{"username":"alice","Password":"s3cret","SECRET":"abc"}"#))
        #expect(result["username"]?.stringValue == "alice")
        #expect(result["Password"]?.stringValue == redacted)
        #expect(result["SECRET"]?.stringValue == redacted)
    }

    @Test func redactsNestedSensitiveKeys() throws {
        let result = redact(try json(#"{"user":{"name":"alice","password":"s3cret"}}"#))
        #expect(result["user"]?["name"]?.stringValue == "alice")
        #expect(result["user"]?["password"]?.stringValue == redacted)
    }

    @Test func redactsHeaderNamesAnywhereTheyAppear() throws {
        let result = redact(try json(#"""
        {"lastResponse":{"requestHeaders":{
            "Authorization":"Bearer abc123","Cookie":"session=xyz",
            "Content-Type":"application/json"}}}
        """#))
        let headers = result["lastResponse"]?["requestHeaders"]
        #expect(headers?["Authorization"]?.stringValue == redacted)
        #expect(headers?["Cookie"]?.stringValue == redacted)
        #expect(headers?["Content-Type"]?.stringValue == "application/json")
    }

    @Test func redactsASetCookieArrayValueNotJustString() throws {
        let setCookieRules = McpRedactionRules(sensitiveKeys: ["set-cookie"])
        let result = redact(
            try json(#"{"headers":{"Set-Cookie":["session=xyz; HttpOnly","remember=1"]}}"#),
            rules: setCookieRules
        )
        #expect(result["headers"]?["Set-Cookie"]?.stringValue == redacted)
    }

    @Test func redactsValuesMatchingValuePatterns() throws {
        let result = redact(try json(
            #"{"message":"Token is Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0 and more"}"#))
        let message = try #require(result["message"]?.stringValue)
        #expect(!message.contains("Bearer"))
        #expect(message.contains(redacted))
        #expect(message.contains("and more"))
    }

    @Test func redactsJwtLikeValues() throws {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            + "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0"
        let result = redact(try json(#"{"token":"\#(jwt)","label":"test"}"#))
        #expect(result["token"]?.stringValue == redacted)
        #expect(result["label"]?.stringValue == "test")
    }

    @Test func redactsStatePathsMatchingPatterns() throws {
        let result = redact(try json(#"""
        {"auth":{"tokens":{"access":"abc","refresh":"def"},"username":"alice"},
         "user":{"ssn":"123-45-6789","name":"Alice"}}
        """#))
        #expect(result["auth"]?["tokens"]?["access"]?.stringValue == redacted)
        #expect(result["auth"]?["tokens"]?["refresh"]?.stringValue == redacted)
        #expect(result["auth"]?["username"]?.stringValue == "alice")
        #expect(result["user"]?["ssn"]?.stringValue == redacted)
        #expect(result["user"]?["name"]?.stringValue == "Alice")
    }

    @Test func statePathAnchoringForSubtreeRequests() throws {
        // The app returned the subtree at "auth.tokens" — patterns written
        // against the full tree still line up via the statePath anchor.
        let subtree = try json(#"{"access":"abc","refresh":"def"}"#)
        let result = McpRedaction.redactState(
            subtree, parsed: McpRedaction.parse(rules), statePath: "auth.tokens")
        #expect(result["access"]?.stringValue == redacted)
        #expect(result["refresh"]?.stringValue == redacted)
    }

    @Test func handlesNullValues() throws {
        #expect(redact(.null) == .null)
        let result = redact(try json(#"{"key":null,"password":"secret"}"#))
        #expect(result["key"] == .null)
        #expect(result["password"]?.stringValue == redacted)
    }

    @Test func handlesArrays() throws {
        let result = redact(try json(
            #"[{"password":"s3cret","name":"alice"},{"password":"p4ss","name":"bob"}]"#))
        let items = try #require(result.arrayValue)
        #expect(items[0]["password"]?.stringValue == redacted)
        #expect(items[0]["name"]?.stringValue == "alice")
        #expect(items[1]["password"]?.stringValue == redacted)
        #expect(items[1]["name"]?.stringValue == "bob")
    }

    @Test func handlesPrimitives() {
        #expect(redact(.number(42)) == .number(42))
        #expect(redact(.bool(true)) == .bool(true))
        #expect(redact(.string("plain text")) == .string("plain text"))
    }

    @Test func redactsSensitiveQueryParametersInUrls() throws {
        var withKey = rules
        withKey.sensitiveKeys += ["key", "token"]
        let result = redact(
            try json(#"{"url":"https://api.example.com/games?key=14e7149770cd4fdf&other=visible"}"#),
            rules: withKey
        )
        #expect(result["url"]?.stringValue
            == "https://api.example.com/games?key=\(redacted)&other=visible")
    }

    @Test func redactsMultipleSensitiveQueryParameters() throws {
        var withKey = rules
        withKey.sensitiveKeys += ["key", "token"]
        let result = redact(
            try json(#"{"url":"https://api.example.com/data?key=abc&token=xyz&page=1"}"#),
            rules: withKey
        )
        #expect(result["url"]?.stringValue
            == "https://api.example.com/data?key=\(redacted)&token=\(redacted)&page=1")
    }

    @Test func preservesUrlFragmentsWhileRedactingQuery() throws {
        var withKey = rules
        withKey.sensitiveKeys += ["token"]
        let result = redact(
            try json(#"{"url":"https://x.dev/a?token=abc#section"}"#), rules: withKey)
        #expect(result["url"]?.stringValue == "https://x.dev/a?token=\(redacted)#section")
    }

    @Test func doesNotRedactQueryParamsWhenNoSensitiveKeysMatch() throws {
        let result = redact(try json(#"{"url":"https://api.example.com/data?page=1&limit=10"}"#))
        #expect(result["url"]?.stringValue == "https://api.example.com/data?page=1&limit=10")
    }

    @Test func doesNotRedactNonMatchingKeysOrValues() throws {
        let data = try json(#"{"username":"alice","email":"alice@example.com","count":42}"#)
        #expect(redact(data) == data)
    }

    @Test func emptyRulesRedactNothing() throws {
        let data = try json(#"{"password":"secret","headers":{"Authorization":"Bearer xyz"}}"#)
        #expect(redact(data, rules: McpRedactionRules()) == data)
    }

    @Test func redactsFormEncodedBodies() throws {
        let result = redact(try json(#"{"body":"user=alice&password=hunter2&stay=1"}"#))
        #expect(result["body"]?.stringValue == "user=alice&password=\(redacted)&stay=1")
    }

    @Test func proseWithEqualsIsNotFormEncoded() {
        #expect(!McpRedaction.looksLikeFormEncoded("the answer is x=5 in this equation"))
        #expect(McpRedaction.looksLikeFormEncoded("user=alice&password=x"))
        #expect(!McpRedaction.looksLikeFormEncoded(""))
    }

    @Test func redactsInsideJsonEncodedStrings() throws {
        // A request body serialized as a JSON string still gets key redaction.
        let result = redact(try json(
            #"{"data":"{\"username\":\"alice\",\"password\":\"hunter2\"}"}"#))
        let body = try #require(result["data"]?.stringValue)
        #expect(body.contains(redacted))
        #expect(!body.contains("hunter2"))
        #expect(body.contains("alice"))
    }

    @Test func invalidRegexPatternsAreSkippedNotFatal() throws {
        let withBadPattern = McpRedactionRules(
            sensitiveKeys: ["password"],
            valuePatterns: ["([unclosed", #"Bearer\s+\w+"#]
        )
        let result = redact(
            try json(#"{"note":"Bearer abc123","password":"x"}"#), rules: withBadPattern)
        #expect(result["note"]?.stringValue == redacted)
        #expect(result["password"]?.stringValue == redacted)
    }

    // MARK: - Default rules & value patterns

    @Test func defaultRulesCoverTheUpstreamKeyList() {
        let keys = Set(McpRedaction.defaultRules.sensitiveKeys)
        for expected in [
            "authorization", "cookie", "set-cookie", "x-api-key",
            "x-csrf-token", "x-xsrf-token", "csrf-token",
            "x-forwarded-for", "x-real-ip",
            "password", "passwd", "pwd", "secret", "access_token",
            "token", "bearer", "jwt", "id_token", "idtoken",
            "session", "sessionid", "csrf", "xsrf",
            "client_secret", "clientsecret",
        ] {
            #expect(keys.contains(expected), "missing default key \(expected)")
        }
    }

    @Test func valuePatternsMatchCommonTokenFormats() {
        let patternRules = McpRedactionRules(valuePatterns: McpRedaction.defaultRules.valuePatterns)
        func redactedString(_ text: String) -> String? {
            redact(.string(text), rules: patternRules).stringValue
        }
        #expect(redactedString("Bearer abc123def456") == redacted)
        #expect(redactedString("sk-abcdefghijklmnopqrstuvwxyz") == redacted)
        #expect(redactedString("ghp_abcdefghijklmnopqrstuvwxyz1234567") == redacted)
        #expect(redactedString("xoxb-abc123-def456-ghi789") == redacted)
        // Built at runtime so secret scanning doesn't flag the test file.
        #expect(redactedString(["sk", "ant"].joined(separator: "-") + "-"
            + String(repeating: "x", count: 32)) == redacted)
        #expect(redactedString("AKI" + "A" + String(repeating: "X", count: 16)) == redacted)
        #expect(redactedString("AIz" + "a" + String(repeating: "X", count: 35)) == redacted)
        #expect(redactedString(["sk", "live", String(repeating: "X", count: 28)]
            .joined(separator: "_")) == redacted)
        #expect(redactedString(
            "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----")
            == redacted)
        #expect(redactedString("hello world") == "hello world")
    }

    // MARK: - resolveEffectiveRules (the two-key model)

    @Test func returnsServerDefaultsWhenNoClientConfig() {
        let result = McpRedaction.resolveEffectiveRules(server: .standard, client: nil)
        #expect(result == McpRedactionServerConfig.standard.defaults)
    }

    @Test func mergesAdditionalRulesFromClient() throws {
        let client = McpRedactionConfig(
            additionalRules: McpRedactionRules(sensitiveKeys: ["myCustomField", "x-custom-auth"]))
        let result = try #require(McpRedaction.resolveEffectiveRules(server: .standard, client: client))
        #expect(result.sensitiveKeys.contains("myCustomField"))
        #expect(result.sensitiveKeys.contains("x-custom-auth"))
        #expect(result.sensitiveKeys.contains("password"))
        #expect(result.sensitiveKeys.contains("authorization"))
    }

    @Test func ignoresRemoveRulesWhenServerDisallows() throws {
        let client = McpRedactionConfig(
            removeRules: McpRedactionRules(sensitiveKeys: ["authorization"]))
        let result = try #require(McpRedaction.resolveEffectiveRules(server: .standard, client: client))
        #expect(result.sensitiveKeys.contains("authorization"))
    }

    @Test func honorsRemoveRulesWhenServerAllows() throws {
        var server = McpRedactionServerConfig.standard
        server.allowClientRemoveRules = true
        let client = McpRedactionConfig(
            removeRules: McpRedactionRules(sensitiveKeys: ["AUTHORIZATION", "PASSWORD"]))
        let result = try #require(McpRedaction.resolveEffectiveRules(server: server, client: client))
        #expect(!result.sensitiveKeys.contains("authorization"))
        #expect(!result.sensitiveKeys.contains("password"))
        #expect(result.sensitiveKeys.contains("cookie"))
    }

    @Test func ignoresDisableRedactionWhenServerDisallows() {
        let client = McpRedactionConfig(disableRedaction: true)
        let result = McpRedaction.resolveEffectiveRules(server: .standard, client: client)
        #expect(result == McpRedactionServerConfig.standard.defaults)
    }

    @Test func disablesWhenClientAsksAndServerAllows() {
        var server = McpRedactionServerConfig.standard
        server.allowClientDisable = true
        let client = McpRedactionConfig(disableRedaction: true)
        #expect(McpRedaction.resolveEffectiveRules(server: server, client: client) == nil)
    }

    @Test func removeAndAdditionalRulesCombine() throws {
        var server = McpRedactionServerConfig.standard
        server.allowClientRemoveRules = true
        let client = McpRedactionConfig(
            additionalRules: McpRedactionRules(sensitiveKeys: ["mySecret"]),
            removeRules: McpRedactionRules(sensitiveKeys: ["password"])
        )
        let result = try #require(McpRedaction.resolveEffectiveRules(server: server, client: client))
        #expect(!result.sensitiveKeys.contains("password"))
        #expect(result.sensitiveKeys.contains("mySecret"))
        #expect(result.sensitiveKeys.contains("secret"))
    }

    @Test func parsesClientConfigFromIntroPayload() throws {
        let payload = try json(#"""
        {"mcpRedaction":{"disableRedaction":true,
          "additionalRules":{"sensitiveKeys":["companyToken"]},
          "removeRules":{"valuePatterns":["p"]}}}
        """#)
        let config = try #require(McpRedactionConfig(json: payload["mcpRedaction"]))
        #expect(config.disableRedaction)
        #expect(config.additionalRules?.sensitiveKeys == ["companyToken"])
        #expect(config.removeRules?.valuePatterns == ["p"])
        #expect(McpRedactionConfig(json: nil) == nil)
        #expect(McpRedactionConfig(json: .string("nope")) == nil)
    }

    // MARK: - AsyncStorage

    @Test func redactsSetItemWithSensitiveStorageKey() throws {
        let parsed = McpRedaction.parse(rules)
        let result = McpRedaction.redactAsyncStorage(
            try json(#"{"key":"auth:password","value":"hunter2"}"#), parsed: parsed)
        #expect(result["key"]?.stringValue == "auth:password")
        #expect(result["value"]?.stringValue == redacted)
    }

    @Test func leavesSetItemWithBenignStorageKey() throws {
        let parsed = McpRedaction.parse(rules)
        let result = McpRedaction.redactAsyncStorage(
            try json(#"{"key":"theme","value":"dark"}"#), parsed: parsed)
        #expect(result["value"]?.stringValue == "dark")
    }

    @Test func redactsMultiSetPairs() throws {
        let parsed = McpRedaction.parse(rules)
        let result = McpRedaction.redactAsyncStorage(
            try json(#"{"pairs":[["user.api_key","sk-123"],["lang","en"]]}"#), parsed: parsed)
        let pairs = try #require(result["pairs"]?.arrayValue)
        #expect(pairs[0].arrayValue?[1].stringValue == redacted)
        #expect(pairs[1].arrayValue?[1].stringValue == "en")
    }
}

#endif
