import SwiftUI
import UniformTypeIdentifiers

/// Private, same-process drag types for the app's own drag-and-drop. These
/// exist because a plain-text (`NSString`) drag is claimed at the AppKit level
/// by any mounted text view registered for string drags — SwiftTerm's terminal
/// and logcat's NSTextView both are — *before* SwiftUI's drop targets see it,
/// and `opacity(0)` / `allowsHitTesting(false)` on a hidden keep-alive tab
/// don't unregister an NSView's dragged types. A tab dragged over an open (or
/// merely mounted) Terminal or logcat silently went nowhere. Carrying the
/// drags under types those views never registered for keeps them SwiftUI's.
extension UTType {
    /// A workspace tab dragged from a pane's tab strip (reorder / move across
    /// panes / drop-to-split).
    static let workspaceTab = UTType(exportedAs: "com.rohindh.droidective.workspace-tab")
    /// A Terminal-rail shell tab or group dragged within the rail.
    static let terminalRailItem = UTType(exportedAs: "com.rohindh.droidective.terminal-rail-item")
}

/// A drag item carried under a private `type`. The drop delegates key off view
/// state (`draggingTabID` and friends), so the payload is only a marker that
/// keeps the item off the plain-text type.
func privateDragItem(_ type: UTType, _ payload: String) -> NSItemProvider {
    let provider = NSItemProvider()
    // `.all` visibility, not `.ownProcess`: macOS bridges the item to the
    // system drag pasteboard, and a process-restricted representation can be
    // dropped in that bridge — the payload is a non-sensitive marker anyway.
    provider.registerDataRepresentation(
        forTypeIdentifier: type.identifier, visibility: .all
    ) { completion in
        completion(Data(payload.utf8), nil)
        return nil
    }
    return provider
}
