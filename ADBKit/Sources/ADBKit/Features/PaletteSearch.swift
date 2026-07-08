import Foundation

/// Pure ordering for the search palettes — the in-app ⌘T palette and the Quick
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
            // Score once per feature — relevance scans title/keywords, so
            // recomputing it inside the sort comparator is O(n log n) scans.
            var scored: [Scored] = []
            for (offset, feature) in FeatureRegistry.all.enumerated() {
                let score = feature.relevance(for: query)
                if score > 0, !feature.isAbsorbedByHub {
                    scored.append(Scored(feature: feature, offset: offset, score: score))
                }
            }
            scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            let ranked = scored.map(\.feature)
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
    /// toggle, or form action that's enabled — hub members included (they are
    /// the quick actions; a member's enabledness rides on its hub, since the
    /// catalog manages members only through the hub). View and system screens
    /// need the full app and never appear. Empty query leads with pinned
    /// features then registry order; otherwise matches rank by relevance,
    /// registry order breaking ties.
    public static func quickActions(
        query: String, implemented: Set<String>, enabled: Set<String>, favorites: [String]
    ) -> [FeatureDef] {
        var hubByMember: [String: String] = [:]
        for (hub, members) in FeatureRegistry.absorbedByHub {
            for member in members { hubByMember[member] = hub }
        }
        let actionable = FeatureRegistry.all.enumerated().filter { entry in
            let feature = entry.element
            let isAction = feature.kind == .instantAction
                || feature.kind == .toggleAction
                || feature.kind == .formAction
            guard isAction, implemented.contains(feature.id) else { return false }
            if let hub = hubByMember[feature.id] { return enabled.contains(hub) }
            return enabled.contains(feature.id)
        }
        guard !query.isEmpty else {
            let all = actionable.map(\.element)
            let pinned = favorites.compactMap { id in all.first { $0.id == id } }
            let pinnedIDs = Set(pinned.map(\.id))
            return pinned + all.filter { !pinnedIDs.contains($0.id) }
        }
        var scored: [Scored] = []
        for entry in actionable {
            let score = entry.element.relevance(for: query)
            if score > 0 {
                scored.append(Scored(feature: entry.element, offset: entry.offset, score: score))
            }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
        return scored.map(\.feature)
    }

    /// A feature with its registry position and query relevance, computed
    /// once before sorting.
    private struct Scored {
        let feature: FeatureDef
        let offset: Int
        let score: Int
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
