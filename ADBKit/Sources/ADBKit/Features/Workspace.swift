import Foundation

/// The editor-group workspace: one or two panes (`TabState` groups) side by
/// side, plus which one holds focus. Pure value type kept out of the SwiftUI
/// layer (like `TabState`/`SidebarOrdering`) so the fiddly multi-group rules —
/// collapsing an emptied pane, shifting indices, global id uniqueness, keeping
/// a pane focused, and never leaving the workspace empty — are unit-tested
/// without a UI or a device.
///
/// A feature id is open in at most one group, so moving a tab between panes is a
/// move, not a copy. `fallback` is the id seeded when the workspace would
/// otherwise be empty (the app passes "home") — kept as data so this type stays
/// free of any UI/registry knowledge.
public struct Workspace: Sendable, Equatable {
    /// The tab seeded when the last tab would close (never leave an empty pane).
    public let fallback: String
    /// The open panes, left to right — always 1 or 2.
    public private(set) var groups: [TabState]
    /// Which pane holds focus (index into `groups`) — new tabs, close, and cycle
    /// act on it. Always a valid index.
    public private(set) var focusedGroup: Int

    /// A fresh workspace with a single pane showing `fallback`.
    public init(fallback: String) {
        self.fallback = fallback
        groups = [TabState(openTabs: [fallback], activeTab: fallback)]
        focusedGroup = 0
    }

    /// Rebuild from persisted panes, enforcing every invariant: at most two
    /// panes, ids valid (`isValidID`) and globally unique, a non-empty result
    /// (seed `fallback`), and an in-range `focusedGroup`.
    public init(
        restoring persisted: [TabGroupState],
        focusedGroup: Int?,
        fallback: String,
        isValidID: (String) -> Bool
    ) {
        self.fallback = fallback
        var restored: [TabState] = []
        var seen = Set<String>()
        for group in persisted.prefix(2) {
            let valid = group.tabs.filter { isValidID($0) && seen.insert($0).inserted }
            guard !valid.isEmpty else { continue }
            restored.append(TabState(openTabs: valid, activeTab: group.activeTab))
        }
        groups = restored.isEmpty ? [TabState(openTabs: [fallback], activeTab: fallback)] : restored
        self.focusedGroup = min(max(focusedGroup ?? 0, 0), groups.count - 1)
    }

    // MARK: - Reads

    /// The focused pane's active tab — drives the device bar, sidebar highlight,
    /// and window title.
    public var activeTab: String? {
        groups.indices.contains(focusedGroup) ? groups[focusedGroup].activeTab : nil
    }
    /// Every pane's active tab (both fronts).
    public var activeTabs: Set<String> { Set(groups.compactMap(\.activeTab)) }
    /// True when split into two panes.
    public var isSplit: Bool { groups.count > 1 }
    /// Total open tabs across all panes.
    public var totalTabs: Int { groups.reduce(0) { $0 + $1.openTabs.count } }

    public func openTabs(inGroup index: Int) -> [String] {
        groups.indices.contains(index) ? groups[index].openTabs : []
    }
    public func activeTab(inGroup index: Int) -> String? {
        groups.indices.contains(index) ? groups[index].activeTab : nil
    }
    public func groupIndex(of id: String) -> Int? {
        groups.firstIndex { $0.openTabs.contains(id) }
    }

    // MARK: - Mutations

    /// Open `id`, or refocus it wherever it's already open. A not-yet-open id
    /// lands in the focused pane.
    public mutating func open(_ id: String) {
        if let group = groupIndex(of: id) {
            focusedGroup = group
            groups[group].open(id)
        } else {
            groups[focusedGroup].open(id)
        }
    }

    /// Close `id` (in whichever pane holds it). Collapses an emptied second pane;
    /// reopens `fallback` if the last pane would empty; keeps focus in range.
    public mutating func close(_ id: String) {
        guard let group = groupIndex(of: id) else { return }
        groups[group].close(id)
        guard groups[group].openTabs.isEmpty else { return }
        if groups.count > 1 {
            groups.remove(at: group)
            focusedGroup = min(focusedGroup, groups.count - 1)
        } else {
            groups[group].open(fallback) // never leave the workspace empty
        }
    }

    /// Move `id` into pane `dest` (append + activate). Collapses the source pane
    /// if it empties. No-op for the same pane or an invalid `dest`.
    public mutating func move(_ id: String, toGroup dest: Int) {
        guard let src = groupIndex(of: id), src != dest, groups.indices.contains(dest) else { return }
        groups[src].close(id)
        groups[dest].open(id)
        if groups[src].openTabs.isEmpty { groups.remove(at: src) }
        focusedGroup = groupIndex(of: id) ?? focusedGroup
    }

    /// Whether `id` can leave this workspace for *another window*.
    ///
    /// Only that it is open: moving a window's last tab into another window is
    /// a legitimate way to consolidate two windows, and leaves this one showing
    /// `fallback` exactly as closing that tab would.
    public func canDetach(_ id: String) -> Bool {
        groupIndex(of: id) != nil
    }

    /// Whether `id` can leave for a window *of its own*.
    ///
    /// Stricter, because something has to stay behind: a workspace whose only
    /// tab left for a new window would not be a move, it would be the *window*
    /// moving — and the window already moves. Same "something must stay"
    /// precondition `split` carries, counted across both panes rather than
    /// within one, because detaching collapses an emptied pane.
    public func canDetachToNewWindow(_ id: String) -> Bool {
        canDetach(id) && totalTabs > 1
    }

    /// Remove `id` from this workspace and return it, for a handoff to another
    /// window.
    ///
    /// Deliberately the same removal `close` performs — collapse an emptied
    /// second pane, keep `focusedGroup` in range, and never leave the workspace
    /// empty — because a window that has just given its last tab away should
    /// look exactly like one whose last tab was closed, rather than a blank.
    public mutating func detach(_ id: String) -> String? {
        guard canDetach(id) else { return nil }
        close(id)
        return id
    }

    /// Split the workspace: move `id` into a new second pane. Requires its pane
    /// to hold more than one tab (something must stay behind) and no existing
    /// split.
    public mutating func split(_ id: String) {
        guard groups.count == 1, let src = groupIndex(of: id), groups[src].openTabs.count > 1 else { return }
        groups[src].close(id)
        groups.append(TabState(openTabs: [id], activeTab: id))
        focusedGroup = 1
    }

    /// Reorder `id` within its own pane so it sits before `targetID` (nil = end).
    public mutating func reorder(_ id: String, before targetID: String?) {
        guard let group = groupIndex(of: id) else { return }
        let order = targetID.map { SidebarOrdering.move(id, before: $0, in: groups[group].openTabs) }
            ?? SidebarOrdering.moveToEnd(id, in: groups[group].openTabs)
        groups[group].reorder(order)
    }

    /// Resolve a strip/pane drop: reorder within the same pane, or move to `dest`
    /// and position at the drop target.
    public mutating func drop(_ id: String, intoGroup dest: Int, before targetID: String?) {
        guard let src = groupIndex(of: id) else { return }
        if src == dest {
            // A nil target is the strip's dead space past the last chip, which
            // means "put it at the end" — `reorder` already reads it that way.
            // Skipping the call for nil made that a dead drop in the tab's own
            // pane while working across panes, which is the asymmetry the strip
            // documents itself as *not* having.
            reorder(id, before: targetID)
        } else {
            move(id, toGroup: dest)
            if let targetID { reorder(id, before: targetID) }
        }
    }

    /// Activate the next / previous tab within the focused pane (wraps).
    public mutating func cycleForward() {
        guard groups.indices.contains(focusedGroup) else { return }
        groups[focusedGroup].activateNext()
    }
    public mutating func cycleBackward() {
        guard groups.indices.contains(focusedGroup) else { return }
        groups[focusedGroup].activatePrevious()
    }
    /// Activate the tab at a 0-based index in the focused pane.
    public mutating func activate(index: Int) {
        guard groups.indices.contains(focusedGroup) else { return }
        groups[focusedGroup].activate(index: index)
    }
    /// Give a pane focus (clicking one of its tabs, or its + button).
    public mutating func focus(_ index: Int) {
        if groups.indices.contains(index) { focusedGroup = index }
    }

    /// Collapse to a single pane showing `fallback` (e.g. after a role change).
    public mutating func reset() {
        groups = [TabState(openTabs: [fallback], activeTab: fallback)]
        focusedGroup = 0
    }
}
