import Foundation

/// Pure ordering for the search palettes — the in-app ⌘K palette and the Quick
/// Actions panel share it, so the ranking rules live here (tested) instead of
/// in the views.
public enum PaletteSearch {
    /// Features in display order. Hub-absorbed members never appear (their hub
    /// carries their keywords). With a query, matches rank by relevance —
    /// registry order breaks ties — enabled before disabled. Without one,
    /// pinned features lead in pin order, then the rest of the registry,
    /// enabled first.
    public static func features(
        query: String, enabled: Set<String>, favorites: [String]
    ) -> [FeatureDef] {
        if !query.isEmpty {
            let ranked = FeatureRegistry.all.enumerated()
                .filter { $0.element.matches(query) && !$0.element.isAbsorbedByHub }
                .sorted { lhs, rhs in
                    let rl = lhs.element.relevance(for: query)
                    let rr = rhs.element.relevance(for: query)
                    return rl != rr ? rl > rr : lhs.offset < rhs.offset
                }
                .map(\.element)
            return ranked.filter { enabled.contains($0.id) }
                + ranked.filter { !enabled.contains($0.id) }
        }
        let pinned = favorites
            .compactMap { FeatureRegistry.byID[$0] }
            .filter { !$0.isAbsorbedByHub }
        let pinnedIDs = Set(pinned.map(\.id))
        let rest = FeatureRegistry.all.filter { !$0.isAbsorbedByHub && !pinnedIDs.contains($0.id) }
        return pinned
            + rest.filter { enabled.contains($0.id) }
            + rest.filter { !enabled.contains($0.id) }
    }

    /// Custom commands matching a query against name or command template,
    /// case-insensitively; an empty query keeps the user's saved order.
    public static func commands(_ commands: [CustomCommand], query: String) -> [CustomCommand] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return commands }
        return commands.filter {
            $0.name.lowercased().contains(needle) || $0.command.lowercased().contains(needle)
        }
    }
}
