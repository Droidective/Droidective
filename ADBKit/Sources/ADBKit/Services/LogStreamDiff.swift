import Foundation

/// How a rendered log pane catches up with the ring buffer behind it. The
/// stream only ever drops lines at the head (ring trim) and appends at the
/// tail, so those become surgical edits; anything else (filter change, clear)
/// rebuilds. Pure so the plan — the off-by-one-prone part — is unit-tested
/// without AppKit.
public enum LogStreamDiff: Equatable, Sendable {
    /// The buffer already matches what's rendered.
    case unchanged
    /// The shapes don't line up as a trim + append — start over.
    case rebuild
    /// Drop the first `dropHead` rendered lines, then append the incoming
    /// lines from index `appendFrom` on.
    case edit(dropHead: Int, appendFrom: Int)

    public static func plan(rendered: [UUID], incoming: [UUID]) -> LogStreamDiff {
        if incoming.count == rendered.count,
           incoming.first == rendered.first, incoming.last == rendered.last {
            return .unchanged
        }
        guard let first = incoming.first,
              let overlapStart = rendered.firstIndex(of: first) else { return .rebuild }
        // The rendered lines from `overlapStart` down must reappear verbatim
        // at the head of `incoming` — checking the count and the last id is
        // enough because ids are unique and both sides preserve stream order.
        let overlap = rendered.count - overlapStart
        guard incoming.count >= overlap, incoming[overlap - 1] == rendered.last else { return .rebuild }
        return .edit(dropHead: overlapStart, appendFrom: overlap)
    }
}
