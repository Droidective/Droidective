import ADBKit
import Foundation

/// A decompiled APK and the browsing of it, kept per window by
/// `FeatureStateStore` rather than as view `@State`.
///
/// jadx and apktool take *minutes* on a real APK, and produce tens of thousands
/// of files. Rebuilding the view — which a tab does whenever it moves to the
/// other split pane or to another window — used to throw the tree away and run
/// the decompiler again from the top. `treeKey` records which APK and
/// decompiler produced the tree, so a remount asking the same question keeps
/// its answer and a different one still re-runs.
///
/// The decompile *in flight* does not survive: it belongs to the view's
/// `.task`, which SwiftUI cancels on unmount, so a move mid-run starts it over.
/// That is the honest read — nothing else owns the process — and it costs only
/// the run the user is already waiting on.
@MainActor
@Observable
final class DecompileModel {
    /// jadx (Java) or apktool (smali + resources).
    var mode: DecompileService.Mode = .jadx
    /// Whether the decompiler and a Java runtime are both present. Kept so a
    /// move doesn't flash the setup gate on its way back to the browser.
    var toolReady = false
    var checkingTool = true
    /// A tool download in progress. The install task outlives the view that
    /// started it, so its progress has to land somewhere the next view can see.
    let download = DownloadState()

    /// The APK being browsed, when the browser picked it itself. APK Studio
    /// injects its own and this stays nil — the workspace owns the selection
    /// there, and its session already moves with the tab.
    var apkURL: URL?
    /// The setup or decompile failure to show, nil when all is well.
    var status: String?

    /// The decompiled file tree, and what `prepKey` built it — the APK and the
    /// decompiler it came from.
    var root: FileNode?
    var treeKey: String?

    var selection: String?
    var fileText: String?
    var fileLanguage = ""
    /// The line the editor should jump to and highlight (0 = none).
    var targetLine = 0

    var filter = ""
    var searchScope = DecompileSearchScope.name
    var searchHits: [DecompileService.SearchHit] = []
}

/// What the sidebar's search box searches: file names, or the code itself.
enum DecompileSearchScope: String, CaseIterable {
    case name = "File name"
    case contents = "Code"
}
