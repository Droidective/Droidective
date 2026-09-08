import Foundation

/// The pinned-prefix rules for a tab strip.
///
/// A pane's pinned tabs are exactly the first `pinnedCount` of its open tabs —
/// pinning is a *position*, not a parallel set, so the two can never disagree
/// about which tabs are pinned or what order they sit in. Everything that
/// rearranges tabs has to keep that prefix intact, which is what the two
/// functions here are for: `normalized` establishes it from persisted data, and
/// `clampedTarget` stops a drag-reorder breaking it.
///
/// Pure and value-typed so both rules are unit-tested without a UI or a device,
/// and so the strip can ask where a drop will *actually* land before it paints
/// the insertion guideline promising it.
public enum TabPinning {
    /// Partition `tabs` so the pinned ones lead, keeping the relative order
    /// within each region, and report how many there are.
    ///
    /// The persisted form is a list of ids rather than a count, because a
    /// restore drops tabs whose feature is gone (`Workspace.init(restoring:)`)
    /// and a count would then point at whatever slid into their place.
    public static func normalized(
        _ tabs: [String], pinned: Set<String>
    ) -> (tabs: [String], pinnedCount: Int) {
        let front = tabs.filter { pinned.contains($0) }
        let rest = tabs.filter { !pinned.contains($0) }
        return (front + rest, front.count)
    }

    /// The insertion target a reorder may actually use.
    ///
    /// A drop that would land an unpinned tab inside the pinned prefix — or a
    /// pinned tab past it — is pulled back to the boundary, the way Chrome
    /// stops the drag there rather than silently reordering somewhere else.
    /// `target` is the id the tab should sit before, nil for the end of the
    /// strip; the result has the same meaning.
    ///
    /// A tab that isn't in `tabs` (a drag from another window, still to arrive)
    /// keeps its target: it has no region here yet.
    public static func clampedTarget(
        _ id: String, before target: String?, in tabs: [String], pinnedCount: Int
    ) -> String? {
        guard let from = tabs.firstIndex(of: id) else { return target }
        // Where `SidebarOrdering.move` would put it: removing the tab first
        // shifts a target that sat to its right one slot left, and an absent
        // (or nil) target means the end.
        let landing: Int
        if let to = tabs.firstIndex(where: { $0 == target }) {
            landing = to > from ? to - 1 : to
        } else {
            landing = tabs.count - 1
        }
        let isPinned = from < pinnedCount
        let staysInRegion = isPinned ? landing < pinnedCount : landing >= pinnedCount
        guard !staysInRegion else { return target }
        // The boundary, from either side: the first unpinned tab. With nothing
        // unpinned there is no boundary to stop at and the end is the prefix.
        return tabs.indices.contains(pinnedCount) ? tabs[pinnedCount] : nil
    }
}
