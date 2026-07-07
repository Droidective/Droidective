import Foundation

/// Pure layout model for the Terminal feature's tab rail. Tabs are *loose*
/// (ungrouped) by default; a group is created only by wrapping a tab, and a
/// group deletes itself the moment its last tab leaves. Loose tabs and groups
/// share one ordered list so they interleave the way browser/VS-Code tab
/// groups do — a tab dragged out of a group lands where it's dropped. Kept out
/// of the SwiftUI layer (the `SidebarOrdering` pattern) so every move is
/// unit-tested without a UI; the sessions behind the ids live in the App layer.
public struct TerminalTabs: Equatable, Sendable {
    public struct Group: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var name: String
        public var isCollapsed: Bool
        public internal(set) var tabIDs: [UUID]

        init(id: UUID = UUID(), name: String, tabIDs: [UUID]) {
            self.id = id
            self.name = name
            isCollapsed = false
            self.tabIDs = tabIDs
        }
    }

    /// A top-level row of the rail: a loose tab, or a group of tabs.
    public enum Entry: Identifiable, Equatable, Sendable {
        case tab(UUID)
        case group(Group)

        public var id: UUID {
            switch self {
            case .tab(let id): return id
            case .group(let group): return group.id
            }
        }
    }

    public static let defaultGroupName = "Group"

    public private(set) var entries: [Entry] = []

    public init() {}

    // MARK: - Queries

    /// Every tab id in display order — loose tabs and each group's tabs, top
    /// to bottom.
    public var allTabIDs: [UUID] {
        entries.flatMap { entry -> [UUID] in
            switch entry {
            case .tab(let id): return [id]
            case .group(let group): return group.tabIDs
            }
        }
    }

    public var tabCount: Int { allTabIDs.count }

    /// The groups in display order (loose tabs omitted).
    public var groups: [Group] {
        entries.compactMap { if case .group(let group) = $0 { return group } else { return nil } }
    }

    public func group(_ id: UUID) -> Group? {
        for entry in entries {
            if case .group(let group) = entry, group.id == id { return group }
        }
        return nil
    }

    /// The group holding `id`, or nil when the tab is loose.
    public func groupID(ofTab id: UUID) -> UUID? {
        for entry in entries {
            if case .group(let group) = entry, group.tabIDs.contains(id) { return group.id }
        }
        return nil
    }

    // MARK: - Adding

    /// Append a tab — loose, or to `groupID` when given. Default is loose, so
    /// a fresh rail has no groups at all.
    public mutating func add(tab: UUID, toGroup groupID: UUID? = nil) {
        if let groupID, let index = groupIndex(groupID) {
            mutateGroup(at: index) { $0.tabIDs.append(tab) }
        } else {
            entries.append(.tab(tab))
        }
    }

    // MARK: - Grouping

    /// Wrap `tab` in a new group, created at the tab's current position. An
    /// empty/whitespace name falls back to the default. Returns the group id,
    /// or nil when the tab isn't present.
    @discardableResult
    public mutating func newGroup(named name: String, containing tab: UUID) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let groupName = trimmed.isEmpty ? Self.defaultGroupName : trimmed

        // A loose tab becomes a group in place; a grouped tab detaches (its old
        // group may vanish) and the new group lands at the end.
        if let index = looseIndex(ofTab: tab) {
            let group = Group(name: groupName, tabIDs: [tab])
            entries[index] = .group(group)
            return group.id
        }
        guard groupID(ofTab: tab) != nil else { return nil }
        remove(tab: tab)
        let group = Group(name: groupName, tabIDs: [tab])
        entries.append(.group(group))
        return group.id
    }

    /// Renames a group; empty/whitespace names are ignored.
    public mutating func renameGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = groupIndex(id) else { return }
        mutateGroup(at: index) { $0.name = trimmed }
    }

    public mutating func setCollapsed(_ id: UUID, _ collapsed: Bool) {
        guard let index = groupIndex(id) else { return }
        mutateGroup(at: index) { $0.isCollapsed = collapsed }
    }

    /// Remove a group and return the tab ids it held, in order — the caller
    /// owns the sessions and must tear them down.
    @discardableResult
    public mutating func removeGroup(_ id: UUID) -> [UUID] {
        guard let index = groupIndex(id), case .group(let group) = entries[index] else { return [] }
        entries.remove(at: index)
        return group.tabIDs
    }

    // MARK: - Removing

    /// Remove a tab from wherever it sits. A group left empty by the removal
    /// deletes itself.
    @discardableResult
    public mutating func remove(tab: UUID) -> Bool {
        for index in entries.indices {
            switch entries[index] {
            case .tab(let id) where id == tab:
                entries.remove(at: index)
                return true
            case .group(var group):
                guard let at = group.tabIDs.firstIndex(of: tab) else { continue }
                group.tabIDs.remove(at: at)
                if group.tabIDs.isEmpty {
                    entries.remove(at: index)
                } else {
                    entries[index] = .group(group)
                }
                return true
            default:
                continue
            }
        }
        return false
    }

    // MARK: - Moving tabs

    /// Move `tab` so it sits immediately before `target`. The destination
    /// follows the target: before a loose tab it becomes loose; before a
    /// grouped tab it joins that group. No-op when either id is unknown or
    /// they're the same.
    public mutating func move(tab: UUID, before target: UUID) {
        guard tab != target, tabExists(tab), tabExists(target) else { return }
        remove(tab: tab)
        insert(tab: tab, before: target)
    }

    /// Move `tab` to the end of `groupID`. No-op when it's already that group's
    /// sole tab, or when either id is unknown.
    public mutating func move(tab: UUID, toEndOfGroup groupID: UUID) {
        guard tabExists(tab), let group = group(groupID) else { return }
        if group.tabIDs == [tab] { return }
        remove(tab: tab)
        guard let index = groupIndex(groupID) else { return }
        mutateGroup(at: index) { $0.tabIDs.append(tab) }
    }

    /// Move `tab` out to the end of the rail as a loose tab.
    public mutating func moveToLooseEnd(tab: UUID) {
        guard tabExists(tab) else { return }
        // Already the last loose entry → nothing to do.
        if case .tab(let id)? = entries.last, id == tab { return }
        remove(tab: tab)
        entries.append(.tab(tab))
    }

    // MARK: - Moving groups

    /// Move a group so it sits immediately before `target` (another top-level
    /// entry — a group or a loose tab). No-op when the ids match or are unknown.
    public mutating func moveGroup(_ id: UUID, before target: UUID) {
        guard id != target, let from = entryIndex(id) else { return }
        let moving = entries.remove(at: from)
        if let to = entryIndex(target) {
            entries.insert(moving, at: to)
        } else {
            entries.insert(moving, at: from)
        }
    }

    public mutating func moveGroupToEnd(_ id: UUID) {
        guard let from = entryIndex(id) else { return }
        let moving = entries.remove(at: from)
        entries.append(moving)
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

    // MARK: - Internal helpers

    private func tabExists(_ id: UUID) -> Bool {
        allTabIDs.contains(id)
    }

    /// The top-level index of a loose tab entry (not a tab inside a group).
    private func looseIndex(ofTab id: UUID) -> Int? {
        entries.firstIndex { if case .tab(let tab) = $0 { return tab == id } else { return false } }
    }

    private func groupIndex(_ id: UUID) -> Int? {
        entries.firstIndex { if case .group(let group) = $0 { return group.id == id } else { return false } }
    }

    /// The top-level index of any entry (loose tab or group) by its id.
    private func entryIndex(_ id: UUID) -> Int? {
        entries.firstIndex { $0.id == id }
    }

    private mutating func mutateGroup(at index: Int, _ body: (inout Group) -> Void) {
        guard case .group(var group) = entries[index] else { return }
        body(&group)
        entries[index] = .group(group)
    }

    /// Insert `tab` immediately before `target`, matching the target's context:
    /// a loose target inserts a loose entry, a grouped target inserts into that
    /// group. Assumes `tab` has already been detached.
    private mutating func insert(tab: UUID, before target: UUID) {
        for index in entries.indices {
            switch entries[index] {
            case .tab(let id) where id == target:
                entries.insert(.tab(tab), at: index)
                return
            case .group(var group):
                guard let at = group.tabIDs.firstIndex(of: target) else { continue }
                group.tabIDs.insert(tab, at: at)
                entries[index] = .group(group)
                return
            default:
                continue
            }
        }
    }
}
