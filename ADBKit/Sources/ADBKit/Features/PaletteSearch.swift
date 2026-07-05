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

    /// The Quick Actions panel's universe: every *implemented* instant,
    /// toggle, or form action — hub members included (they are the quick
    /// actions; a hub is just their in-app grouping). View and system screens
    /// need the full app and never appear. Empty query keeps registry order;
    /// otherwise matches rank by relevance, registry order breaking ties.
    public static func quickActions(query: String, implemented: Set<String>) -> [FeatureDef] {
        let actionable = FeatureRegistry.all.enumerated().filter {
            let kind = $0.element.kind
            return (kind == .instantAction || kind == .toggleAction || kind == .formAction)
                && implemented.contains($0.element.id)
        }
        guard !query.isEmpty else { return actionable.map(\.element) }
        return actionable
            .filter { $0.element.matches(query) }
            .sorted { lhs, rhs in
                let rl = lhs.element.relevance(for: query)
                let rr = rhs.element.relevance(for: query)
                return rl != rr ? rl > rr : lhs.offset < rhs.offset
            }
            .map(\.element)
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
