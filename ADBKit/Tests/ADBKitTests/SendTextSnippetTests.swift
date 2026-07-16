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

    @Test func recordUseBumpsOnlyTheMatch() {
        var presets = Presets(sendTextSnippets: [
            SendTextSnippet(name: "a", text: "1"), SendTextSnippet(name: "b", text: "2"),
        ])
        presets.recordSnippetUse(named: "b")
        presets.recordSnippetUse(named: "b")
        presets.recordSnippetUse(named: "missing")
        #expect(presets.sendTextSnippets == [
            SendTextSnippet(name: "a", text: "1", uses: 0),
            SendTextSnippet(name: "b", text: "2", uses: 2),
        ])
    }

    @Test func topSnippetsRanksByUsesThenSaveOrder() {
        let presets = Presets(sendTextSnippets: [
            SendTextSnippet(name: "old-tie", text: "1", uses: 1),
            SendTextSnippet(name: "hot", text: "2", uses: 5),
            SendTextSnippet(name: "new-tie", text: "3", uses: 1),
            SendTextSnippet(name: "cold", text: "4", uses: 0),
            SendTextSnippet(name: "warm", text: "5", uses: 3),
            SendTextSnippet(name: "mild", text: "6", uses: 2),
        ])
        // The quick-insert row shows at most the top 5.
        #expect(presets.topSnippets(limit: 5).map(\.name) == ["hot", "warm", "mild", "old-tie", "new-tie"])
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
