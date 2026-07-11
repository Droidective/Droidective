import Foundation

/// Pure layout model for the panes inside one terminal tab. A tab starts as a
/// single pane; splitting a pane divides its space with a new one, and panes
/// nest the way iTerm's do — splitting along the axis of the enclosing split
/// adds an equal sibling (thirds, quarters…) instead of halving the pane, and
/// closing a pane hands its space back. Kept out of the SwiftUI layer (the
/// `TerminalTabs` pattern) so every mutation is unit-tested without a UI; the
/// PTY sessions behind the pane ids live in the App layer.
public struct TerminalSplitTree: Equatable, Sendable {
    /// Which way a split divides its space: `.vertical` is a vertical divider
    /// (panes side by side), `.horizontal` a horizontal one (panes stacked).
    public enum Direction: Equatable, Sendable {
        case vertical
        case horizontal
    }

    public indirect enum Node: Equatable, Sendable {
        case pane(UUID)
        case split(Direction, [Node])
    }

    /// Nil once every pane has been removed — the owning tab is done.
    public private(set) var root: Node?

    public init(pane: UUID) {
        root = .pane(pane)
    }

    // MARK: - Queries

    /// Every pane id in layout order (depth-first, first-to-last per split).
    public var paneIDs: [UUID] {
        root.map(Self.panes(in:)) ?? []
    }

    public var paneCount: Int { paneIDs.count }

    public func contains(_ pane: UUID) -> Bool {
        paneIDs.contains(pane)
    }

    // MARK: - Splitting

    /// Divide `pane`'s space with `newPane`, which lands after it (right of it
    /// for `.vertical`, below it for `.horizontal`). Splitting along the axis
    /// of the pane's enclosing split inserts an equal sibling rather than
    /// nesting, so repeated same-direction splits stay evenly sized. No-op
    /// when `pane` is unknown or `newPane` already exists.
    @discardableResult
    public mutating func split(
        pane: UUID, direction: Direction, adding newPane: UUID
    ) -> Bool {
        guard let root, contains(pane), !contains(newPane) else { return false }
        self.root = Self.splitting(root, pane: pane, direction: direction, newPane: newPane)
        return true
    }

    // MARK: - Removing

    /// Remove a pane; its siblings absorb the space. A split left with one
    /// child collapses into it (merging into a same-direction parent so
    /// sibling sizing stays flat). Removing the last pane empties the tree.
    @discardableResult
    public mutating func remove(pane: UUID) -> Bool {
        guard let root, contains(pane) else { return false }
        self.root = Self.removing(pane, from: root)
        return true
    }

    // MARK: - Focus math

    /// The pane focus should land on after `pane` closes: the one that slides
    /// into its slot in layout order, or the previous one when it was last —
    /// the same math as `TerminalTabs.neighbor`.
    public func neighbor(of pane: UUID) -> UUID? {
        let flat = paneIDs
        guard let index = flat.firstIndex(of: pane) else { return nil }
        let remaining = flat.filter { $0 != pane }
        guard !remaining.isEmpty else { return nil }
        return remaining[min(index, remaining.count - 1)]
    }

    // MARK: - Internal helpers

    private static func panes(in node: Node) -> [UUID] {
        switch node {
        case .pane(let id):
            return [id]
        case .split(_, let children):
            return children.flatMap(panes(in:))
        }
    }

    private static func splitting(
        _ node: Node, pane: UUID, direction: Direction, newPane: UUID
    ) -> Node {
        switch node {
        case .pane(let id):
            guard id == pane else { return node }
            return .split(direction, [.pane(pane), .pane(newPane)])
        case .split(let axis, var children):
            // The pane is a direct child of a same-direction split → an equal
            // sibling, not a nested halving.
            if axis == direction, let index = children.firstIndex(of: .pane(pane)) {
                children.insert(.pane(newPane), at: index + 1)
                return .split(axis, children)
            }
            return .split(axis, children.map {
                splitting($0, pane: pane, direction: direction, newPane: newPane)
            })
        }
    }

    private static func removing(_ pane: UUID, from node: Node) -> Node? {
        switch node {
        case .pane(let id):
            return id == pane ? nil : node
        case .split(let axis, let children):
            var kept: [Node] = []
            for child in children {
                if let reduced = removing(pane, from: child) { kept.append(reduced) }
            }
            if kept.isEmpty { return nil }
            if kept.count == 1 { return kept[0] }
            // A collapse can surface a same-direction split — flatten it so
            // its panes become equal siblings again.
            var flattened: [Node] = []
            for child in kept {
                if case .split(let childAxis, let grandchildren) = child, childAxis == axis {
                    flattened.append(contentsOf: grandchildren)
                } else {
                    flattened.append(child)
                }
            }
            return .split(axis, flattened)
        }
    }
}
