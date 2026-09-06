import ADBKit
import AppKit

/// Reads the files on the in-flight drag, so the overlay can name them while
/// the pointer is still down.
///
/// `dropDestination(for:)` hands over its items only once the drop happens —
/// `isTargeted` says *that* something is over the view, never *what*. The
/// design turns on the overlay stating the consequence before the button comes
/// up, so the hover text comes from the drag pasteboard, which AppKit keeps
/// populated for the life of the session. This is display only: the drop
/// itself still uses the URLs SwiftUI delivers, so an empty read costs a
/// specific sentence and nothing else.
enum DragPasteboard {
    static func droppedPaths() -> [DroppedPath] {
        let board = NSPasteboard(name: .drag)
        let urls = (board.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        return paths(from: urls)
    }

    /// The same classification for URLs that actually arrived on a drop.
    static func paths(from urls: [URL]) -> [DroppedPath] {
        urls.filter(\.isFileURL).map { url in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return DroppedPath(path: url.path, isDirectory: isDirectory.boolValue)
        }
    }
}
