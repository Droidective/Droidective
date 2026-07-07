import Foundation

/// Pure grouping + ordering model for the Terminal feature's tab rail: named
/// groups of tab ids, each collapsible, with tabs reorderable within and
/// across groups and groups reorderable among themselves. Kept out of the
/// SwiftUI layer (the `SidebarOrdering` pattern) so every move is unit-tested
/// without a UI. The sessions behind the ids live in the App layer; this type
/// only owns *where* each tab sits.
public struct TerminalTabs: Equatable, Sendable {
    public struct Group: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var name: String
        public var isCollapsed: Bool
        public internal(set) var tabIDs: [UUID]

        init(name: String) {
            id = UUID()
            self.name = name
            isCollapsed = false
            tabIDs = []
        }
    }

    public static let defaultGroupName = "Terminals"

    public private(set) var groups: [Group] = []

    public init() {}

    // MARK: - Queries

    /// Every tab id in display order — groups top to bottom, tabs within them.
    public var allTabIDs: [UUID] { groups.flatMap(\.tabIDs) }

    public var tabCount: Int { groups.reduce(0) { $0 + $1.tabIDs.count } }

    public func group(_ id: UUID) -> Group? {
        groups.first { $0.id == id }
    }

    public func groupID(ofTab id: UUID) -> UUID? {
        groups.first { $0.tabIDs.contains(id) }?.id
    }

    // MARK: - Group operations

    /// Adds an empty group at the end. An empty/whitespace name falls back to
    /// the default so the rail never shows a blank header.
    @discardableResult
    public mutating func addGroup(named name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let group = Group(name: trimmed.isEmpty ? Self.defaultGroupName : trimmed)
        groups.append(group)
        return group.id
    }

    /// Renames a group; empty/whitespace names are ignored.
    public mutating func renameGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = trimmed
    }

    public mutating func setCollapsed(_ id: UUID, _ collapsed: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].isCollapsed = collapsed
    }

    /// Removes the group and returns the tab ids it held, in order — the
    /// caller owns the sessions behind them and must tear those down.
    @discardableResult
    public mutating func removeGroup(_ id: UUID) -> [UUID] {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return [] }
        return groups.remove(at: index).tabIDs
    }

    /// Moves a whole group so it sits immediately before `target`. No-op when
    /// either id is unknown or they're the same group.
    public mutating func moveGroup(_ id: UUID, before target: UUID) {
        guard id != target,
              let from = groups.firstIndex(where: { $0.id == id }) else { return }
        let moving = groups.remove(at: from)
        if let to = groups.firstIndex(where: { $0.id == target }) {
            groups.insert(moving, at: to)
        } else {
            groups.insert(moving, at: from)
        }
    }

    public mutating func moveGroupToEnd(_ id: UUID) {
        guard let from = groups.firstIndex(where: { $0.id == id }) else { return }
        let moving = groups.remove(at: from)
        groups.append(moving)
    }

    // MARK: - Tab operations

    /// Appends a tab to `groupID`, or to the last group when nil — creating
    /// the default group first if none exist (so `add` can never lose a tab).
    public mutating func add(tab: UUID, toGroup groupID: UUID? = nil) {
        if groups.isEmpty {
            addGroup(named: Self.defaultGroupName)
        }
        let index = groupID.flatMap { id in groups.firstIndex { $0.id == id } } ?? groups.count - 1
        groups[index].tabIDs.append(tab)
    }

    /// Removes a tab from whichever group holds it. Empty groups stay — the
    /// user shaped them and may be about to refill them.
    @discardableResult
    public mutating func remove(tab: UUID) -> Bool {
        for index in groups.indices {
            if let at = groups[index].tabIDs.firstIndex(of: tab) {
                groups[index].tabIDs.remove(at: at)
                return true
            }
        }
        return false
    }

    /// Moves a tab so it sits immediately before `target`, crossing groups
    /// when the target lives elsewhere. No-op when either id is unknown.
    public mutating func move(tab: UUID, before target: UUID) {
        guard tab != target,
              let fromGroup = groups.firstIndex(where: { $0.tabIDs.contains(tab) }),
              let toGroup = groups.firstIndex(where: { $0.tabIDs.contains(target) }),
              let from = groups[fromGroup].tabIDs.firstIndex(of: tab) else { return }
        groups[fromGroup].tabIDs.remove(at: from)
        // Look the target up *after* the removal — same-group moves shift it.
        guard let to = groups[toGroup].tabIDs.firstIndex(of: target) else { return }
        groups[toGroup].tabIDs.insert(tab, at: to)
    }

    /// Moves a tab to the end of `groupID`. No-op when either id is unknown.
    public mutating func move(tab: UUID, toEndOfGroup groupID: UUID) {
        guard let toGroup = groups.firstIndex(where: { $0.id == groupID }),
              let fromGroup = groups.firstIndex(where: { $0.tabIDs.contains(tab) }),
              let from = groups[fromGroup].tabIDs.firstIndex(of: tab) else { return }
        // A same-group "to end" of the last tab is already a no-op shape.
        groups[fromGroup].tabIDs.remove(at: from)
        groups[toGroup].tabIDs.append(tab)
    }

    // MARK: - Focus math

    /// The tab focus should land on after `id` closes: the tab that slides
    /// into its slot in the flattened order, or the previous one when it was
    /// last — mirroring the app's own tab-close behavior across groups.
    public func neighbor(of id: UUID) -> UUID? {
        let flat = allTabIDs
        guard let index = flat.firstIndex(of: id) else { return nil }
        let remaining = flat.filter { $0 != id }
        guard !remaining.isEmpty else { return nil }
        return remaining[min(index, remaining.count - 1)]
    }

    /// The tab `offset` steps away in the flattened order, wrapping — feeds
    /// the Next/Previous Terminal commands across group boundaries.
    public func tab(offset: Int, from id: UUID) -> UUID? {
        let flat = allTabIDs
        guard !flat.isEmpty else { return nil }
        guard let index = flat.firstIndex(of: id) else { return flat.first }
        let count = flat.count
        return flat[((index + offset) % count + count) % count]
    }
}
