import Foundation

/// What a `console.*` call means for the feed's group nesting.
public enum ConsoleGroupPlacement: Sendable, Equatable {
    /// An ordinary row, indented `depth` levels, nested inside the group
    /// headers in `path` (outermost first).
    case entry(depth: Int, path: [Int])
    /// A `console.group` / `console.groupCollapsed` header. It sits at the
    /// *outer* depth — the rows after it are the ones that indent.
    case groupStart(depth: Int, path: [Int], collapsed: Bool)
    /// A `console.groupEnd` — it closes the innermost group and shows no row of
    /// its own. Rendering one produced the empty rows trailing a grouped burst.
    case groupEnd
}

/// The running `console.group` nesting of a console stream. Chrome indents the
/// rows between a `group` and its `groupEnd`, draws a rule down the left of the
/// block, and lets the header collapse it; this is the pure half — which depth
/// each incoming call belongs to, and which headers it hangs under.
///
/// Unbalanced groups are the normal case (an app that throws between `group` and
/// `groupEnd` never closes it), so a stray `groupEnd` is a no-op and the nesting
/// resets whenever the stream restarts: a JS reload or a clear must not leave
/// the rest of the session indented under a group that no longer exists.
public struct ConsoleGroupTracker: Sendable, Equatable {
    /// Ids of the group headers currently open, outermost first.
    public private(set) var open: [Int] = []

    /// The depth the next ordinary row lands at.
    public var depth: Int { open.count }

    public init() {}

    /// Where a console call of this type belongs. `id` is the entry id the
    /// produced row will carry — a group header registers it so its own rows
    /// can name the header they hang under (which is how collapsing one hides
    /// exactly its block).
    public mutating func placement(for consoleType: String, id: Int) -> ConsoleGroupPlacement {
        switch consoleType {
        case "startGroup", "startGroupCollapsed":
            let placement = ConsoleGroupPlacement.groupStart(
                depth: open.count, path: open, collapsed: consoleType == "startGroupCollapsed"
            )
            open.append(id)
            return placement
        case "endGroup":
            if !open.isEmpty { open.removeLast() }
            return .groupEnd
        default:
            return .entry(depth: open.count, path: open)
        }
    }

    /// Back to the top level — a JS context replacement, a clear, or a fresh
    /// connection all start the nesting over.
    public mutating func reset() {
        open.removeAll()
    }
}
