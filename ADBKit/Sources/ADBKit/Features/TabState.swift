import Foundation

/// The open feature tabs and which one is active. Pure value type, kept out of
/// the SwiftUI layer (like `SidebarOrdering`) so the open/close/cycle math is
/// unit-tested without a UI or a device.
///
/// Tabs are *strictly distinct features*: a feature's id identifies its tab, so
/// opening a feature that's already open just refocuses it — there are never two
/// tabs for the same feature. At most `maxTabs` are open at once.
public struct TabState: Sendable, Equatable {
    /// The hard cap on simultaneously open tabs.
    public static let maxTabs = 10

    /// Open tabs (feature ids) in strip order, left to right.
    public private(set) var openTabs: [String]
    /// The foreground tab — always one of `openTabs`, or nil only when none are
    /// open.
    public private(set) var activeTab: String?

    /// Build a state, normalizing `activeTab` to an open tab (or the first open
    /// tab) so a stale persisted value can't point at a closed tab.
    public init(openTabs: [String] = [], activeTab: String? = nil) {
        self.openTabs = openTabs
        self.activeTab = activeTab.flatMap { openTabs.contains($0) ? $0 : nil } ?? openTabs.first
    }

    /// Open `id`, or refocus it if already open. Returns false only when a *new*
    /// tab can't be opened because the cap is reached — the caller surfaces a
    /// hint. Refocusing an already-open tab always succeeds.
    @discardableResult
    public mutating func open(_ id: String) -> Bool {
        if openTabs.contains(id) {
            activeTab = id
            return true
        }
        guard openTabs.count < Self.maxTabs else { return false }
        openTabs.append(id)
        activeTab = id
        return true
    }

    /// Close `id`. If it was the active tab, focus the neighbor that slid into
    /// its slot (its old right neighbor), or the new last tab when the rightmost
    /// closed. `activeTab` becomes nil only when no tabs remain.
    public mutating func close(_ id: String) {
        guard let index = openTabs.firstIndex(of: id) else { return }
        let wasActive = activeTab == id
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

    /// Adopt a new left-to-right order (a permutation of the open tabs) from a
    /// drag-reorder. Keeps the active tab. Ignored unless `newOrder` is exactly
    /// the current set of tabs.
    public mutating func reorder(_ newOrder: [String]) {
        guard newOrder.count == openTabs.count, Set(newOrder) == Set(openTabs) else { return }
        openTabs = newOrder
    }

    /// Activate the tab at a 0-based index (⌘1–⌘9). No-op when out of range.
    public mutating func activate(index: Int) {
        guard openTabs.indices.contains(index) else { return }
        activeTab = openTabs[index]
    }
}
