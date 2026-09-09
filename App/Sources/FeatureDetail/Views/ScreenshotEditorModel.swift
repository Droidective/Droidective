import ADBKit
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
        publishMemory()
    }

    /// Tell `AppMemory` what this editor is holding.
    ///
    /// A device screenshot decodes to roughly 18 MB (1440x3120 at 4 bytes a
    /// pixel) and the undo history keeps `maxUndo` more states, so an editor
    /// mid-session is one of the larger things in the process — and nothing
    /// measured it, which is exactly the blind spot that left 1.4 GB
    /// unaccounted for.
    ///
    /// Images are counted by identity, not per snapshot: annotation edits
    /// share one `NSImage` by reference and only crop and rotate make a new
    /// one, so counting each snapshot's image separately would report twenty
    /// copies of a capture that exists once.
    ///
    /// Called on the transitions that change the size — opening, closing, and
    /// each undo-stack move — never per stroke.
    func publishMemory() {
        guard let image else { return AppMemory.shared.forget(from: self) }
        var seen: Set<ObjectIdentifier> = []
        var bytes = 0
        for candidate in [image] + undoStack.map(\.image) + redoStack.map(\.image)
        where seen.insert(ObjectIdentifier(candidate)).inserted {
            bytes += Self.residentBytes(of: candidate)
        }
        AppMemory.shared.report(
            .screenshot, from: self,
            residentBytes: bytes,
            items: undoStack.count + redoStack.count,
            watched: true)
    }

    /// A decoded bitmap's cost: pixels times four bytes.
    ///
    /// Read off the representation rather than `size`, which is in points — a
    /// Retina capture would otherwise be under-counted fourfold. An image with
    /// no bitmap representation (never seen here; every capture is a decoded
    /// PNG) contributes nothing rather than a guess.
    private static func residentBytes(of image: NSImage) -> Int {
        image.representations.reduce(0) { total, rep in
            max(total, rep.pixelsWide * rep.pixelsHigh * 4)
        }
    }

    /// Close the editor and forget the capture — "New", or the tab closing.
    func close() {
        AppMemory.shared.forget(from: self)
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
