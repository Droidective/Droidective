import Foundation
import Testing
@testable import ADBKit

@Suite struct SendTextSnippetTests {
    // MARK: - Presets snippet management

    @Test func addTrimsNameAndRejectsEmptyOrDuplicate() {
        var presets = Presets()
        let added = presets.addSnippet(named: "  Metro host  ", text: "{ip}:8081")
        #expect(added)
        #expect(presets.sendTextSnippets.map(\.name) == ["Metro host"])
        let duplicate = presets.addSnippet(named: "Metro host", text: "something else")
        let blankName = presets.addSnippet(named: "   ", text: "x")
        let emptyText = presets.addSnippet(named: "no text", text: "")
        #expect(!duplicate)
        #expect(!blankName)
        #expect(!emptyText)
        #expect(presets.sendTextSnippets.count == 1)
    }

    @Test func namesAreClampedToTheLimit() {
        var presets = Presets()
        let long = String(repeating: "n", count: SendTextSnippet.nameLimit + 10)
        let added = presets.addSnippet(named: long, text: "x")
        #expect(added)
        #expect(presets.sendTextSnippets.first?.name.count == SendTextSnippet.nameLimit)
    }

    @Test func removeDeletesByName() {
        var presets = Presets(sendTextSnippets: [
            SendTextSnippet(name: "a", text: "1"), SendTextSnippet(name: "b", text: "2"),
        ])
        presets.removeSnippet(named: "a")
        #expect(presets.sendTextSnippets.map(\.name) == ["b"])
    }

    @Test func recordUseBumpsAndStampsOnlyTheMatch() {
        var presets = Presets(sendTextSnippets: [
            SendTextSnippet(name: "a", text: "1"), SendTextSnippet(name: "b", text: "2"),
        ])
        presets.recordSnippetUse(named: "b", at: 100)
        presets.recordSnippetUse(named: "b", at: 200)
        presets.recordSnippetUse(named: "missing", at: 300)
        #expect(presets.sendTextSnippets == [
            SendTextSnippet(name: "a", text: "1", uses: 0),
            SendTextSnippet(name: "b", text: "2", uses: 2, lastUsedAt: 200),
        ])
    }

    @Test func addStampsANewSnippetAsJustUsed() {
        var presets = Presets()
        presets.addSnippet(named: "fresh", text: "x", at: 42)
        #expect(presets.sendTextSnippets.first?.lastUsedAt == 42)
    }

    @Test func recentSnippetsRankByFreshnessThenUsesThenSaveOrder() {
        let presets = Presets(sendTextSnippets: [
            SendTextSnippet(name: "old-tie", text: "1", uses: 1),
            SendTextSnippet(name: "yesterday", text: "2", uses: 1, lastUsedAt: 1000),
            SendTextSnippet(name: "new-tie", text: "3", uses: 1),
            SendTextSnippet(name: "just-now", text: "4", uses: 0, lastUsedAt: 3000),
            SendTextSnippet(name: "this-morning", text: "5", uses: 9, lastUsedAt: 2000),
            SendTextSnippet(name: "much-used", text: "6", uses: 5),
        ])
        // Freshness first; never-used snippets (pre-lastUsedAt files) follow
        // by use count, ties in save order.
        #expect(presets.recentSnippets(limit: 6).map(\.name) == [
            "just-now", "this-morning", "yesterday", "much-used", "old-tie", "new-tie",
        ])
        #expect(presets.recentSnippets(limit: 2).map(\.name) == ["just-now", "this-morning"])
    }

    @Test func snippetsWithoutLastUsedAtStillDecode() throws {
        // Files written before the field existed carry no lastUsedAt key.
        let old = Data(#"{"name":"a","text":"1","uses":3}"#.utf8)
        let snippet = try JSONDecoder().decode(SendTextSnippet.self, from: old)
        #expect(snippet == SendTextSnippet(name: "a", text: "1", uses: 3, lastUsedAt: nil))
    }

    @Test func matchesSearchesNameAndTextCaseInsensitively() {
        let snippet = SendTextSnippet(name: "Metro host", text: "{ip}:8081")
        #expect(snippet.matches("metro"))
        #expect(snippet.matches("8081"))
        #expect(snippet.matches("{IP}"))
        #expect(snippet.matches("  metro "))
        #expect(snippet.matches(""))
        #expect(!snippet.matches("logcat"))
    }

    // MARK: - Placeholder expansion

    @Test func expandReplacesEveryOccurrence() {
        let expanded = SnippetPlaceholders.expand(
            "curl http://{ip}:8081 # {ip} again, plus {clipboard}",
            values: ["ip": "192.168.1.7", "clipboard": "token123"])
        #expect(expanded == "curl http://192.168.1.7:8081 # 192.168.1.7 again, plus token123")
    }

    @Test func unknownAndUnclosedTokensStayAsTyped() {
        let expanded = SnippetPlaceholders.expand("{nope} and {ip", values: ["ip": "1.2.3.4"])
        #expect(expanded == "{nope} and {ip")
    }

    @Test func missingValueLeavesTokenInPlace() {
        // No clipboard string available → the token survives so the user sees
        // what didn't resolve instead of silently losing it.
        let expanded = SnippetPlaceholders.expand("{clipboard}!", values: [:])
        #expect(expanded == "{clipboard}!")
    }

    @Test func substitutedValuesAreNeverRescanned() {
        // A clipboard that itself contains a placeholder token must be
        // inserted verbatim — sequential replaces expanded it (or not)
        // depending on dictionary iteration order.
        let expanded = SnippetPlaceholders.expand(
            "{clipboard} → {ip}",
            values: ["clipboard": "{ip}", "ip": "1.2.3.4"])
        #expect(expanded == "{ip} → 1.2.3.4")
    }
}
