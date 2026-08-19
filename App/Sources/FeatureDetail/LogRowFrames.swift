import AppKit
import SwiftUI

/// Where each visible row sits in a log feed, so a drag can tell which rows it
/// has crossed — a row only ever knows its own frame.
///
/// A plain reference box, deliberately *not* observable: rows report into it on
/// every scroll and layout pass, and holding this in `@State` would re-render the
/// feed per pixel. `LogTailViewV2` keeps its own measurements in one for the same
/// reason.
@MainActor final class LogRowFrames<ID: Hashable> {
    var frames: [ID: CGRect] = [:]

    /// The row whose band contains `y`. A drag that runs past the first or last
    /// row answers with the nearest one, so sweeping off the edge of the feed
    /// selects to the end instead of stopping where the pointer left the rows.
    ///
    /// Only rows that are *on screen* have frames (see `reportingRowFrame`), so
    /// this answers about what the reader can actually see — `ids` may be
    /// thousands of buffered rows.
    func row(at y: CGFloat, among ids: [ID]) -> ID? {
        var nearest: (id: ID, distance: CGFloat)?
        for id in ids {
            guard let frame = frames[id] else { continue }
            // Half-open band: the boundary between two rows belongs to the lower
            // one, or a click on the seam would pick the row above the pointer.
            if y >= frame.minY, y < frame.maxY { return id }
            let distance = min(abs(y - frame.minY), abs(y - frame.maxY))
            if nearest == nil || distance < nearest!.distance { nearest = (id, distance) }
        }
        return nearest?.id
    }
}

extension View {
    /// Report this row's frame in the feed's coordinate space, for drag-select
    /// hit-testing. Paired with `.coordinateSpace(name:)` on the feed.
    func reportingRowFrame<ID: Hashable>(
        _ id: ID, in space: String, into frames: LogRowFrames<ID>
    ) -> some View {
        background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(space))
                Color.clear
                    .onAppear { frames.frames[id] = frame }
                    .onChange(of: frame) { _, new in frames.frames[id] = new }
                    // A row scrolled out of a `LazyVStack` stops reporting but
                    // its last frame would linger — and a click is then matched
                    // against where that row *used* to be, which is how a sweep
                    // could start from a row nowhere near the pointer.
                    .onDisappear { frames.frames[id] = nil }
            }
        }
    }
}

/// How a click means to change a selection, read from the modifiers the event
/// carried. SwiftUI's tap gesture doesn't report them, and composing one gesture
/// per modifier makes the plain tap's precedence depend on gesture order — so the
/// event's own flags are read as the tap is handled.
enum LogRowClick: Equatable {
    /// ⌘: add or drop this row, leaving the rest alone.
    case toggle
    /// ⇧: take the range from the last row picked.
    case extend
    /// No modifier: the row's own business (expand/collapse), and any selection
    /// is dropped.
    case plain

    init(modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            self = .toggle
        } else if modifiers.contains(.shift) {
            self = .extend
        } else {
            self = .plain
        }
    }

}

/// Drives log-row selection from real mouse events, because SwiftUI's gestures
/// can't reach these rows.
///
/// A console line is selectable `Text` end to end, and selection-enabled text
/// swallows the click before anything *behind* it runs — which is exactly where
/// these feeds put the row's own click, so a gesture added there never fired.
/// A local monitor sees the event before the responder chain does, so ⌘-click,
/// ⇧-click and a drag-sweep work over text. `⌥` is left alone: that is how text
/// itself is selected now.
///
/// Precedent: the terminal drives its wheel the same way, because SwiftTerm
/// seals `scrollWheel`. Same rule applies here — one monitor per mounted feed,
/// scoped to its own view's bounds, torn down with the view.
struct LogSelectionMouse: NSViewRepresentable {
    /// Whether this feed is the one on screen. A hidden keep-alive tab keeps its
    /// view mounted, and this monitor bypasses hit testing — so without this the
    /// hidden pane would answer (and swallow) clicks meant for the visible one.
    let isActive: Bool
    /// A press landed at this feed-space y: the pane fixes the sweep's anchor
    /// *row* here. Anchoring to the y instead would drift, because a streaming
    /// feed moves its rows under a held pointer.
    let onPress: (CGFloat) -> Void
    /// Feed-space y of the click, and what its modifiers meant.
    let onClick: (CGFloat, LogRowClick) -> Void
    /// The pointer moved to this feed-space y while sweeping; the anchor is the
    /// row the pane recorded on the press. `additive` (⌘ or ⇧ held) unions the
    /// span with what was already picked instead of replacing it.
    let onSweep: (CGFloat, Bool) -> Void
    /// A sweep just ended: the click AppKit delivers next must not clear it.
    let onSweepEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        // Flipped, so its y matches the SwiftUI coordinate space the rows report
        // their frames in — top-left origin, not AppKit's bottom-left.
        let view = FlippedView()
        context.coordinator.attach(to: view, from: self)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(to: view, from: self)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
        /// Never in the way: the monitor is what reads the mouse, and this view
        /// sits behind the rows purely to give them a coordinate space.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        private weak var view: NSView?
        private var monitor: Any?
        private var handlers: LogSelectionMouse?
        /// Where the button went down, in feed space; nil when no button is down
        /// inside the feed. Only the drag *threshold* is measured from it — the
        /// sweep's anchor is a row, held by the pane.
        private var pressY: CGFloat?
        /// Whether this drag has moved far enough to be a sweep rather than a click.
        private var swept = false

        func attach(to view: NSView, from handlers: LogSelectionMouse) {
            self.view = view
            self.handlers = handlers
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                // `NSEvent` isn't Sendable, so the isolated body hands back only
                // the decision and the event is passed on out here — the same
                // shape the terminal's shared monitor uses.
                let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// True when the event is ours and must not travel any further.
        private func handle(_ event: NSEvent) -> Bool {
            guard let view, let handlers, handlers.isActive,
                  let window = view.window, event.window === window
            else { return false }
            let point = view.convert(event.locationInWindow, from: nil)
            // Outside this feed (another pane, the toolbar, another window's
            // content): not ours to touch.
            guard view.bounds.contains(point) else { return false }
            // ⌥ is how the text itself is selected now, so it passes straight
            // through to the text view.
            guard !event.modifierFlags.contains(.option) else { return false }

            switch event.type {
            case .leftMouseDown:
                pressY = point.y
                swept = false
                // Fixes the anchor row, and clears a suppression left over from a
                // sweep whose closing click never landed on a row.
                handlers.onPress(point.y)
                let click = LogRowClick(modifiers: event.modifierFlags)
                switch click {
                case .toggle, .extend:
                    handlers.onClick(point.y, click)
                    return true           // never also a text click
                case .plain:
                    return false          // a plain click stays the row's own
                }
            case .leftMouseDragged:
                guard let pressY else { return false }
                // Swallow the sub-threshold jitter too: letting it through is
                // what would start a text selection before the sweep begins.
                guard swept || abs(point.y - pressY) > 3 else { return true }
                swept = true
                let additive = event.modifierFlags.contains(.command)
                    || event.modifierFlags.contains(.shift)
                handlers.onSweep(point.y, additive)
                return true
            case .leftMouseUp:
                defer { pressY = nil }
                if swept { handlers.onSweepEnd() }
                return false
            default:
                return false
            }
        }
    }
}
