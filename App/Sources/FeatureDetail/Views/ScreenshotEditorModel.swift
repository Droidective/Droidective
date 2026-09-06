import AppKit
import Foundation
import SwiftUI

/// A screenshot being annotated, kept per window by `FeatureStateStore` rather
/// than as view `@State`.
///
/// The editor writes nothing to disk until the user saves or copies, so
/// everything in it is unsaved work: the capture itself, the markup drawn on
/// it, and the undo history that can take any of it back. Rebuilding the view —
/// which a tab does whenever it moves to the other split pane or to another
/// window — would throw all three away. That is the one loss in this app the
/// user cannot recover from by waiting: a log refills, a decompile re-runs, an
/// annotation is gone.
///
/// `image` doubles as "is an editor open in this tab": the three hosts (the
/// Screenshot tab, the mirror, the Mirror Wall) render `ScreenshotEditorView`
/// exactly while this holds a capture, so opening and closing the editor is
/// `open(_:)` and `close()` rather than each host keeping its own flag.
///
/// Only state that a *move* should carry lives here. What a drag is doing right
/// now (the stroke being drawn, the handle being pulled) stays in the view: a
/// drag cannot be in flight across a move, and giving it a longer life than the
/// mouse button would only let a stale grab resume against a new gesture.
@MainActor
@Observable
final class ScreenshotEditorModel {
    /// The capture being edited — the base image, which crop and rotate
    /// replace. Nil when this tab has no editor open.
    var image: NSImage?
    var annotations: [Annotation] = []
    /// Past / future states for ⌘Z / ⇧⌘Z — each snapshot is the full
    /// (image, annotations) pair, so undo also reverses a clear or a crop.
    var undoStack: [EditorSnapshot] = []
    var redoStack: [EditorSnapshot] = []

    /// The drawing settings new markup is made with. Carried across a move for
    /// the same reason the markup is: the user chose them.
    var tool: MarkupTool = .pen
    var color: Color = .red
    var width: CGFloat = 6
    var redactStyle: RedactStyle = .blur
    /// Redact defaults for new regions (per-annotation values live on `Annotation`).
    var blurStrength: Double = 0.4
    var fillOpacity: Double = 1

    /// 1.0 == fit-to-view; the displayed scale is `fit * zoom`. `pinchAnchor`
    /// is the zoom a pinch scales from, and travels with `zoom` — separating
    /// them would make the first pinch after a move jump back to the old scale.
    var zoom: CGFloat = 1
    var pinchAnchor: CGFloat = 1

    var cropping = false
    var cropRect: CGRect?
    /// Crop-box rotation in radians.
    var cropRotation: Double = 0

    /// Select-mode editing: which annotation is picked, and which text label is
    /// open for re-editing (nil = placing new text).
    var selecting = false
    var selectedID: Annotation.ID?
    var editingTextID: Annotation.ID?
    /// Normalized location of the text field being typed into (nil = none), and
    /// its contents. A half-typed label is markup the user has not committed
    /// yet, so it moves with the rest of it.
    var textPoint: CGPoint?
    var editingText = ""

    var lastSavedURL: URL?
    /// Unsaved markup/edits exist — drives the leave prompt. Reset on save/copy.
    var dirty = false
    /// Identifies the leave guard, so a stale clear can't wipe another's — and
    /// so the window this tab moves to re-registers the same one.
    let exitGuardID = UUID()

    /// Open a fresh capture, discarding whatever the editor held. Every host
    /// reaches this through the Discard/Save/Edit prompt, which is where the
    /// user has already been asked about the previous one.
    func open(_ capture: NSImage) {
        close()
        image = capture
    }

    /// Close the editor and forget the capture — "New", or the tab closing.
    func close() {
        image = nil
        annotations = []
        undoStack = []
        redoStack = []
        cropping = false
        cropRect = nil
        cropRotation = 0
        selecting = false
        selectedID = nil
        editingTextID = nil
        textPoint = nil
        editingText = ""
        zoom = 1
        pinchAnchor = 1
        lastSavedURL = nil
        dirty = false
    }
}
