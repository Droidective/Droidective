import Testing
@testable import ADBKit

@Suite struct PaletteSearchTests {
    private var allEnabled: Set<String> { Set(FeatureRegistry.all.map(\.id)) }

    @Test func emptyQueryLeadsWithPinnedThenEnabledThenDisabled() {
        let visible = FeatureRegistry.all.filter { !$0.isAbsorbedByHub }
        let pinned = [visible[4].id, visible[1].id]
        let disabled = visible[7].id
        let enabled = allEnabled.subtracting([disabled])

        let result = PaletteSearch.features(query: "", enabled: enabled, favorites: pinned)

        #expect(result.prefix(2).map(\.id) == pinned)
        #expect(result.last?.id == disabled)
        #expect(Set(result.map(\.id)).count == result.count)
        #expect(result.count == visible.count)
    }

    @Test func exactTitleQueryRanksThatFeatureFirst() throws {
        let target = FeatureRegistry.all.first { !$0.isAbsorbedByHub && $0.id == "logcat" }
        let title = try #require(target).title

        let result = PaletteSearch.features(query: title, enabled: allEnabled, favorites: [])

        #expect(result.first?.id == "logcat")
    }

    @Test func disabledMatchesSinkBelowEnabledOnes() throws {
        // Disable every match for a broad query except one — that one must lead.
        let matches = FeatureRegistry.all.filter { $0.matches("app") && !$0.isAbsorbedByHub }
        try #require(matches.count >= 2)
        let keep = matches[matches.count - 1].id
        let enabled = allEnabled.subtracting(matches.map(\.id)).union([keep])

        let result = PaletteSearch.features(query: "app", enabled: enabled, favorites: [])

        #expect(result.first?.id == keep)
    }

    @Test func absorbedHubMembersNeverSurfaceEvenByExactTitle() throws {
        for memberID in FeatureRegistry.absorbedFeatureIDs {
            let member = try #require(FeatureRegistry.byID[memberID])
            let result = PaletteSearch.features(
                query: member.title, enabled: allEnabled, favorites: [memberID]
            )
            #expect(!result.contains { $0.id == memberID })
        }
    }

    @Test func commandsMatchNameOrTemplateCaseInsensitively() {
        let commands = [
            CustomCommand(name: "Wipe app data", command: "shell pm clear {bundleId}", needsBundle: true, createdAt: 1),
            CustomCommand(name: "List packages", command: "shell pm list packages", needsBundle: false, createdAt: 2),
            CustomCommand(name: "Reboot", command: "reboot", needsBundle: false, createdAt: 3),
        ]

        #expect(PaletteSearch.commands(commands, query: "WIPE").map(\.name) == ["Wipe app data"])
        #expect(PaletteSearch.commands(commands, query: "pm").count == 2)
        #expect(PaletteSearch.commands(commands, query: "ssh").isEmpty)
    }

    @Test func emptyCommandQueryKeepsSavedOrder() {
        let commands = [
            CustomCommand(name: "B", command: "b", needsBundle: false, createdAt: 2),
            CustomCommand(name: "A", command: "a", needsBundle: false, createdAt: 1),
        ]
        #expect(PaletteSearch.commands(commands, query: "  ").map(\.name) == ["B", "A"])
    }
}
