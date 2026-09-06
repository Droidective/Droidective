import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A tab chip's drag, run as a real AppKit dragging session.
///
/// SwiftUI's `.onDrag` cannot answer the two questions a tear-off needs — did
/// anything accept the drop, and *where on screen* did it land — and there is
/// no callback that reports either. `NSDraggingSource` reports both, once, in
/// `draggingSession(_:endedAt:operation:)`.
///
/// The item on the pasteboard is the same `NSItemProvider` `.onDrag` used to
/// return (`privateDragItem(.workspaceTab,…)`), so every existing SwiftUI
/// `.onDrop(of: [.workspaceTab])` target — the strips, the panes, the split
/// shield — accepts it exactly as before. Only the *source* half changed.
///
/// The backing view is deliberately hit-test transparent: the chip's tap,
/// close button and context menu stay SwiftUI's, and the session is started
/// from a SwiftUI `DragGesture` instead. A `DragGesture` is safe inside the
/// strip's `ScrollView` because trackpad scrolling arrives as `scrollWheel`
/// events, which are not gestures and never compete with it.
struct TabDragSource: NSViewRepresentable {
    /// The handle the chip's gesture calls to start a drag.
    let starter: TabDragStarter

    func makeNSView(context: Context) -> TabDragSourceView {
        let view = TabDragSourceView()
        starter.view = view
        return view
    }

    func updateNSView(_ nsView: TabDragSourceView, context: Context) {
        // Re-point on every update: SwiftUI can rebuild the representable's
        // view for the same chip, and a stale handle would silently make the
        // chip undraggable. Cheap, and writes no observable state (see the
        // update-loop rule in CLAUDE.md).
        starter.view = nsView
    }
}

/// The chip's side of the drag: a plain reference the view writes itself into,
/// so a SwiftUI gesture can reach AppKit without any observable state changing.
@MainActor
final class TabDragStarter {
    fileprivate weak var view: TabDragSourceView?

    /// Begin dragging this chip.
    ///
    /// - Parameters:
    ///   - featureID: the tab being dragged.
    ///   - image: a snapshot of the chip, rendered once, which rides the cursor.
    ///   - grabOffset: where in the chip the pointer went down, from its
    ///     top-left, y down — so the torn-off window can put that same point
    ///     back under the cursor.
    ///   - canTearOff: whether a release away from the app would open a window.
    ///   - onEnded: called once when the session finishes.
    func begin(
        featureID: String,
        image: NSImage?,
        grabOffset: CGSize,
        canTearOff: Bool,
        onEnded: @escaping (TabDragOutcome) -> Void
    ) {
        view?.begin(
            featureID: featureID, image: image, grabOffset: grabOffset,
            canTearOff: canTearOff, onEnded: onEnded)
    }
}

/// How a tab drag finished.
struct TabDragOutcome {
    /// Whether a drop target took the tab. Those drops are already handled by
    /// the target itself.
    let accepted: Bool
    /// Whether the user backed out with Escape.
    let cancelled: Bool
    /// Where the drag ended, in screen coordinates.
    let screenPoint: CGPoint
    /// Where in the chip the pointer had grabbed it.
    let grabOffset: CGSize
    /// The chip's own position inside its window, from the window's top-left,
    /// y down — the vertical half of where a torn-off window's strip sits.
    let chipOriginInWindow: CGPoint
    /// The window the drag started from, and its size, which a torn-off window
    /// inherits.
    let sourceWindowFrame: CGRect
    /// The app's windows as they were when the drag began — what decides
    /// whether the release landed away from the app.
    let windowFrames: [CGRect]
}

/// The `NSView` that owns the dragging session.
final class TabDragSourceView: NSView, NSDraggingSource {
    private var onEnded: ((TabDragOutcome) -> Void)?
    private var grabOffset: CGSize = .zero
    /// The chip's place in its window, and the window's frame, as they were
    /// when the drag started.
    ///
    /// Captured up front rather than read back in `endedAt`, because by then
    /// this view may no longer be in a window at all: a drop that moved the tab
    /// to another window tears its chip down first, and a `guard let window`
    /// there silently swallowed the whole callback.
    private var chipOriginInWindow: CGPoint = .zero
    private var sourceWindowFrame: CGRect = .zero
    private var escapeMonitor: Any?
    private var cancelled = false
    /// Whether releasing away from the app would actually open a window. A tab
    /// that cannot (its window's only one) must still animate home on release,
    /// or the chip vanishes and reappears with nothing having happened.
    private var canTearOff = false
    /// The app's window frames, captured once per drag.
    ///
    /// `movedTo` runs for every mouse move, and walking `NSApp.windows` there
    /// would allocate an array per move for an answer that cannot change: a
    /// window can't be moved or opened while the drag holds the mouse. A window
    /// closed by something else mid-drag leaves this stale in the safe
    /// direction — the release reads as a miss and the tab stays put.
    private var windowFrames: [CGRect] = []

    /// Events belong to SwiftUI. This view exists only to be a dragging source
    /// and to measure the chip; taking hits would break the chip's tap, its
    /// close button and its context menu.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var isFlipped: Bool { true }

    func begin(
        featureID: String,
        image: NSImage?,
        grabOffset: CGSize,
        canTearOff: Bool,
        onEnded: @escaping (TabDragOutcome) -> Void
    ) {
        self.canTearOff = canTearOff
        windowFrames = Self.appWindowFrames()
        // `beginDraggingSession` needs the mouse event that started the drag.
        // Inside a `DragGesture` callback that is the live `leftMouseDragged`.
        guard let event = NSApp.currentEvent, window != nil else {
            // No session will start, so nothing else will report back — tell
            // the caller now, as a cancel, or the chip stays latched mid-drag.
            onEnded(TabDragOutcome(
                accepted: false, cancelled: true, screenPoint: .zero, grabOffset: .zero,
                chipOriginInWindow: .zero, sourceWindowFrame: .zero, windowFrames: []))
            return
        }
        self.onEnded = onEnded
        self.grabOffset = grabOffset
        cancelled = false
        if let window {
            // This view is flipped, so `convert(.zero, to: nil)` is its
            // *top*-left in window base coordinates, which are y-up from the
            // window's bottom. The strip metrics this feeds are y-down from the
            // window's top, so the two only need subtracting from the height.
            let originInWindow = convert(NSPoint.zero, to: nil)
            chipOriginInWindow = CGPoint(
                x: originInWindow.x, y: window.frame.height - originInWindow.y)
            sourceWindowFrame = window.frame
        }

        let item = NSDraggingItem(pasteboardWriter: privateDragPasteboardItem(.workspaceTab, featureID))
        if let image {
            item.setDraggingFrame(bounds, contents: image)
        } else {
            item.setDraggingFrame(bounds, contents: NSImage(size: bounds.size))
        }
        let session = beginDraggingSession(with: [item], event: event, source: self)
        // Snapping back is right for a miss inside the app, and wrong for a
        // tear-off — the chip should not fly home a beat before its window
        // appears. Re-decided per move in `draggingSession(_:movedTo:)`.
        session.animatesToStartingPositionsOnCancelOrFail = true
        installEscapeMonitor()
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return .move
        default:
            // Not `[]`: an empty mask paints the ⊘ "no drop" cursor over the
            // desktop, which is precisely where dropping *does* something. No
            // other app registers this private UTI, so advertising an operation
            // here cannot hand the tab to anyone else.
            return .generic
        }
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        // Outside the app the drop opens a window, so a slide-back would be a
        // lie; inside it, a miss really should return the chip to the strip.
        session.animatesToStartingPositionsOnCancelOrFail = !canTearOff
            || TabDetachPolicy.isInsideApp(point: screenPoint, windowFrames: windowFrames)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        removeEscapeMonitor()
        let handler = onEnded
        onEnded = nil
        guard let handler else { return }
        handler(TabDragOutcome(
            accepted: operation != [],
            cancelled: cancelled || Self.escapeIsDown(),
            screenPoint: screenPoint,
            grabOffset: grabOffset,
            chipOriginInWindow: chipOriginInWindow,
            sourceWindowFrame: sourceWindowFrame,
            windowFrames: windowFrames))
    }

    // MARK: - Escape

    /// AppKit reports an Escape-cancelled drag exactly like a refused one, at
    /// wherever the cursor sits — so a cancel out over the desktop would open a
    /// window the user was busy *not* asking for.
    ///
    /// Two detectors, because whether a local monitor is delivered at all
    /// during AppKit's drag loop is not contractual: the monitor catches it
    /// when it fires, and `escapeIsDown` catches the (normal) case where the
    /// key is still held when the session reports back. `CGEventSource.keyState`
    /// reads hardware key state and needs no accessibility permission.
    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancelled = true }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    private static func escapeIsDown() -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: 53)
    }

    /// Frames of the app's own visible windows, for the inside/outside test.
    /// Panels count: the Quick Actions panel is somewhere a drop should miss,
    /// not somewhere it should spawn a window.
    private static func appWindowFrames() -> [CGRect] {
        NSApp.windows.filter(\.isVisible).map(\.frame)
    }
}
