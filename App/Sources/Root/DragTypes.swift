import AppKit
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
    /// A Mirror Wall tile dragged to rearrange the grid.
    static let mirrorWallTile = UTType(exportedAs: "com.rohindh.droidective.mirror-wall-tile")
}

/// A drag item carried under a private `type`. The drop delegates key off view
/// state (`draggingTabID` and friends), so the payload is only a marker that
/// keeps the item off the plain-text type.
func privateDragItem(_ type: UTType, _ payload: String) -> NSItemProvider {
    // Register the marker eagerly (`init(item:typeIdentifier:)`) rather than
    // through a `registerDataRepresentation` load handler: the payload is a
    // small static marker known up front, so there's nothing to load lazily,
    // and the closure-based API's completion is imported main-actor-isolated —
    // calling it from the handler's nonisolated context fails to compile under
    // whole-module (Release) builds (Debug's incremental build missed it).
    // Legacy item registration is process-global (equivalent to `.all`
    // visibility), so the drag still survives macOS's system-pasteboard bridge.
    NSItemProvider(item: Data(payload.utf8) as NSData, typeIdentifier: type.identifier)
}

/// The same marker as `privateDragItem`, written for an AppKit dragging
/// session (`TabDragSource`) rather than for SwiftUI's `.onDrag`.
///
/// `NSItemProvider` is not an `NSPasteboardWriting`, so a session cannot carry
/// one directly. A pasteboard item holding the identical UTI and payload is
/// what SwiftUI's drop targets end up reading either way — they see the
/// provider AppKit synthesises from the drag pasteboard, so the drop half is
/// unchanged by which of the two started the drag.
func privateDragPasteboardItem(_ type: UTType, _ payload: String) -> NSPasteboardItem {
    let item = NSPasteboardItem()
    item.setData(Data(payload.utf8), forType: NSPasteboard.PasteboardType(type.identifier))
    return item
}
