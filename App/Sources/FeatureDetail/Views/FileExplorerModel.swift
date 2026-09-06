import ADBKit
import Foundation

/// The File Explorer's place on the device, kept per window by
/// `FeatureStateStore` rather than as view `@State`.
///
/// Where you had browsed to is the whole point of the feature — being dropped
/// back at `/sdcard` because the tab moved to another window is exactly the
/// kind of "it restarted" that a move should not do. The directory *listing*
/// deliberately stays in the view: it reloads from the path in one `ls`, and a
/// listing that was current a minute ago is worse than one fetched now.
@MainActor
@Observable
final class FileExplorerModel {
    /// The browsed path, split into components.
    var pathComponents: [String] = []
    var selection: Set<String> = []
    /// Device-side clipboard: source paths plus whether to move (cut).
    var clipboard: (paths: [String], isCut: Bool)?
    var isRooted = false
    /// When on (rooted devices only), browse the whole filesystem from "/" via su.
    var rootMode = false
}
