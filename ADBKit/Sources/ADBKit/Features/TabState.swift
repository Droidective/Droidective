import Foundation

/// The open feature tabs and which one is active. Pure value type, kept out of
/// the SwiftUI layer (like `SidebarOrdering`) so the open/close/cycle math is
/// unit-tested without a UI or a device.
///
/// Tabs are *strictly distinct features*: a feature's id identifies its tab, so
/// opening a feature that's already open just refocuses it — there are never two
/// tabs for the same feature.
///
/// Pinned tabs are the first `pinnedCount` of `openTabs` (see `TabPinning`), so
/// every mutation here either maintains that count or leaves the prefix alone.
public struct TabState: Sendable, Equatable {
    /// Open tabs (feature ids) in strip order, left to right.
    public private(set) var openTabs: [String]
    /// The foreground tab — always one of `openTabs`, or nil only when none are
    /// open.
    public private(set) var activeTab: String?
    /// How many of the leading tabs are pinned. Always `0...openTabs.count`.
    public private(set) var pinnedCount: Int

    /// Build a state, normalizing `activeTab` to an open tab (or the first open
    /// tab) so a stale persisted value can't point at a closed tab.
    public init(openTabs: [String] = [], activeTab: String? = nil, pinnedCount: Int = 0) {
        self.openTabs = openTabs
        self.activeTab = activeTab.flatMap { openTabs.contains($0) ? $0 : nil } ?? openTabs.first
        self.pinnedCount = min(max(pinnedCount, 0), openTabs.count)
    }

    /// The pinned tabs, in strip order — what the strip marks and what a
    /// window persists.
    public var pinnedTabs: [String] { Array(openTabs.prefix(pinnedCount)) }

    public func isPinned(_ id: String) -> Bool {
        openTabs.prefix(pinnedCount).contains(id)
    }

    /// Pin `id`: it joins the end of the pinned prefix. A no-op when it isn't
    /// open or is pinned already.
    public mutating func pin(_ id: String) {
        guard let from = openTabs.firstIndex(of: id), from >= pinnedCount else { return }
        openTabs.remove(at: from)
        openTabs.insert(id, at: pinnedCount)
        pinnedCount += 1
    }

    /// Unpin `id`: it drops to the front of the unpinned tabs.
    ///
    /// Not back where it was before it was pinned — `pin` doesn't record that,
    /// and remembering it would be state that goes stale the moment a
    /// neighbouring tab closes. The boundary is where the eye last saw the tab
    /// anyway, and it beats a jump to the end of the strip.
    public mutating func unpin(_ id: String) {
        guard let from = openTabs.firstIndex(of: id), from < pinnedCount else { return }
        openTabs.remove(at: from)
        openTabs.insert(id, at: pinnedCount - 1)
        pinnedCount -= 1
    }

    /// Open `id`, or refocus it if already open.
    public mutating func open(_ id: String) {
        if !openTabs.contains(id) {
            openTabs.append(id)
        }
        activeTab = id
    }

    /// Close `id`. If it was the active tab, focus the neighbor that slid into
    /// its slot (its old right neighbor), or the new last tab when the rightmost
    /// closed. `activeTab` becomes nil only when no tabs remain.
    public mutating func close(_ id: String) {
        guard let index = openTabs.firstIndex(of: id) else { return }
        let wasActive = activeTab == id
        if index < pinnedCount { pinnedCount -= 1 }
        openTabs.remove(at: index)
        guard wasActive else { return }
        activeTab = openTabs.isEmpty ? nil : openTabs[min(index, openTabs.count - 1)]
    }

    /// Activate the next tab to the right, wrapping to the first.
    public mutating func activateNext() { cycle(by: 1) }
    /// Activate the previous tab to the left, wrapping to the last.
    public mutating func activatePrevious() { cycle(by: -1) }

    private mutating func cycle(by offset: Int) {
        guard !openTabs.isEmpty else { return }
        let current = activeTab.flatMap { openTabs.firstIndex(of: $0) } ?? 0
        activeTab = openTabs[(current + offset + openTabs.count) % openTabs.count]
    }

    /// Move `id` from a drag-reorder so it sits before `targetID` (nil = the end
    /// of the strip). Keeps the active tab.
    ///
    /// Clamped to `id`'s own region: a reorder may never interleave pinned and
    /// unpinned tabs, so a drop aimed across the boundary lands *at* it. See
    /// `TabPinning.clampedTarget`.
    public mutating func reorder(_ id: String, before targetID: String?) {
        guard openTabs.contains(id) else { return }
        let target = TabPinning.clampedTarget(
            id, before: targetID, in: openTabs, pinnedCount: pinnedCount)
        openTabs = target.map { SidebarOrdering.move(id, before: $0, in: openTabs) }
            ?? SidebarOrdering.moveToEnd(id, in: openTabs)
    }

    /// Activate the tab at a 0-based index (⌘1–⌘9). No-op when out of range.
    public mutating func activate(index: Int) {
        guard openTabs.indices.contains(index) else { return }
        activeTab = openTabs[index]
    }
}
