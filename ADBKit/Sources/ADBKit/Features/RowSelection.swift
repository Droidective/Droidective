import Foundation

/// Multi-selection over an ordered list of log rows — the model behind ⌘-click,
/// ⇧-click and drag-select in the streaming feeds. Pure, because the part that
/// goes subtly wrong is never the highlight: it is where the *anchor* sits after
/// each gesture, which decides what the next range spans.
///
/// The order is passed in per call rather than held, because the feed's order is
/// a filtered, reversible, ring-trimmed view that changes under the selection —
/// see `retain(in:)`.
public struct RowSelection<ID: Hashable & Sendable>: Sendable, Equatable {
    public private(set) var ids: Set<ID> = []
    /// The row a range extends from: the last row picked deliberately (a plain
    /// or ⌘ click, or where a drag began), never one swept over by a range.
    public private(set) var anchor: ID?

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }
    public func contains(_ id: ID) -> Bool { ids.contains(id) }

    /// A plain click: this row alone.
    public mutating func replace(with id: ID) {
        ids = [id]
        anchor = id
    }

    /// ⌘-click: add or drop one row and leave the rest alone. The row becomes
    /// the anchor either way — the next ⇧-click spans from what was last
    /// touched, which is what makes ⌘-then-⇧ predictable.
    public mutating func toggle(_ id: ID) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        anchor = id
    }

    /// ⇧-click: everything from the anchor to `id` in display order. `additive`
    /// keeps what was already selected; otherwise the range replaces it. With no
    /// anchor there is nothing to span, so this behaves like the plain click.
    ///
    /// The anchor deliberately stays put: shift-clicking further down, then
    /// back up, re-spans from the same start instead of ratcheting.
    public mutating func extend(to id: ID, in order: [ID], additive: Bool = false) {
        // A row the feed doesn't have is a click on nothing — leave the
        // selection alone rather than inventing a range around it.
        guard let end = order.firstIndex(of: id) else { return }
        // The anchor, on the other hand, can vanish under a live feed (trimmed,
        // filtered, cleared). Then there is no span, and this is a plain click.
        guard let anchor, let start = order.firstIndex(of: anchor) else {
            if additive { toggle(id) } else { replace(with: id) }
            return
        }
        apply(span: order[min(start, end)...max(start, end)], additive: additive)
    }

    /// A drag: the rows between where the pointer went down and where it is now.
    /// Called repeatedly as the pointer moves, so it always recomputes the span
    /// from the drag's own start — dragging back shrinks the selection again.
    public mutating func select(from start: ID, to end: ID, in order: [ID], additive: Bool = false) {
        guard let first = order.firstIndex(of: start), let last = order.firstIndex(of: end) else { return }
        apply(span: order[min(first, last)...max(first, last)], additive: additive)
        anchor = start
    }

    public mutating func clear() {
        ids = []
        anchor = nil
    }

    /// Drop rows that are no longer in the feed — cleared, filtered out, or
    /// trimmed by the ring buffer. Without this the count and any copy would
    /// include events the reader cannot see.
    public mutating func retain(in order: [ID]) {
        let live = Set(order)
        guard !ids.isSubset(of: live) || anchor.map({ !live.contains($0) }) == true else { return }
        ids.formIntersection(live)
        if let anchor, !live.contains(anchor) { self.anchor = nil }
    }

    /// The selected rows in display order — what a copy has to produce, since a
    /// `Set` has none.
    public func ordered(in order: [ID]) -> [ID] {
        order.filter(ids.contains)
    }

    private mutating func apply(span: ArraySlice<ID>, additive: Bool) {
        ids = additive ? ids.union(span) : Set(span)
    }
}
