import ADBKit
import AVFoundation
import SwiftUI

/// Owns the `AVSampleBufferDisplayLayer` the session feeds compressed frames to.
/// Frames are enqueued from the stream-consumer task, OFF the main actor — a
/// frame must never wait on a busy UI run loop, or a startup stall builds a
/// backlog the mirror then replays seconds behind the device.
/// `AVQueuedSampleBufferRendering.enqueue` is callable from any thread; the
/// single consumer task serializes it, and the lock covers our bookkeeping.
/// The layer itself is created and laid out on the main actor.
final class MirrorRenderer: @unchecked Sendable {
    let displayLayer: AVSampleBufferDisplayLayer

    private var renderer: AVSampleBufferVideoRenderer { displayLayer.sampleBufferRenderer }
    private let lock = NSLock()
    private var lastDimensions: (width: Int, height: Int)?

    @MainActor init() {
        displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer, width: Int, height: Int) {
        lock.lock()
        // A resolution change (device rotation) needs a flush, or the renderer can
        // stall on the old format instead of re-priming on the incoming key frame.
        let sizeChanged = lastDimensions.map { $0 != (width, height) } ?? false
        lastDimensions = (width, height)
        lock.unlock()
        if sizeChanged { renderer.flush() }
        // A failed renderer won't recover until flushed; the next key frame re-primes it.
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sampleBuffer)
    }

    func clear() {
        lock.lock()
        lastDimensions = nil
        lock.unlock()
        renderer.flush()
    }
}

/// An NSView that keeps the display layer sized to its bounds and forwards mouse
/// and keyboard input as normalized callbacks. Flipped so coordinates share the
/// device's top-left origin.
final class MirrorLayerNSView: NSView {
    var onTouch: ((ScrcpyControlMessage.TouchAction, CGPoint) -> Void)?
    var onKeycode: ((UInt32, ScrcpyControlMessage.KeyAction) -> Void)?
    var onText: ((String) -> Void)?
    var onPaste: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var videoSize: CGSize?

    private let displayLayer: AVSampleBufferDisplayLayer
    /// Shown instead of the video while the pane is mid-resize: a phone-shaped
    /// outline at the video's aspect. Re-letterboxing the live video layer on
    /// every tick of a divider/window drag competes with the rest of the
    /// window's relayout; a plain CALayer tracks the drag for free, and the
    /// video snaps back in (no reconnect — the stream keeps running unseen)
    /// once the size settles.
    private let placeholderLayer = CALayer()
    private var resizeSettle: DispatchWorkItem?
    private var isResizing = false

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
        placeholderLayer.isHidden = true
        placeholderLayer.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
        placeholderLayer.borderColor = NSColor(white: 1, alpha: 0.25).cgColor
        placeholderLayer.borderWidth = 1
        placeholderLayer.cornerRadius = 14
        layer?.addSublayer(placeholderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used from a nib") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        if isResizing { syncPlaceholderFrame() } else { syncDisplayLayerFrame() }
    }

    /// `layout()` alone misses direct frame changes (a SwiftUI split-divider
    /// drag resizes the view without a constraint pass) — track every size
    /// change explicitly. A change arriving while the view already has a laid-
    /// out video means the user is dragging: swap to the placeholder and defer
    /// the video re-letterbox until the size rests.
    override func setFrameSize(_ newSize: NSSize) {
        let hadLayout = displayLayer.frame != .zero && bounds.size != .zero
        super.setFrameSize(newSize)
        guard hadLayout, videoSize != nil else {
            syncDisplayLayerFrame()
            return
        }
        beginResizeIfNeeded()
        syncPlaceholderFrame()
        scheduleResizeSettle()
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        if videoSize != nil { beginResizeIfNeeded() }
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        endResize()
    }

    private func beginResizeIfNeeded() {
        guard !isResizing else { return }
        isResizing = true
        displayLayer.isHidden = true
        placeholderLayer.isHidden = false
    }

    /// Divider drags have no live-resize begin/end signals — the size resting
    /// for a beat is the end. During a window live resize the explicit
    /// `viewDidEndLiveResize` is the end; a mid-drag pause must not swap the
    /// video back in, so the timer defers to `inLiveResize`.
    private func scheduleResizeSettle() {
        resizeSettle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.inLiveResize else { return }
                self.endResize()
            }
        }
        resizeSettle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func endResize() {
        resizeSettle?.cancel()
        resizeSettle = nil
        guard isResizing else { return }
        isResizing = false
        syncDisplayLayerFrame()
        displayLayer.isHidden = false
        placeholderLayer.isHidden = true
    }

    private func syncDisplayLayerFrame() {
        guard displayLayer.frame != bounds else { return }
        // Sublayer frame changes are implicitly animated — a 0.25s lag per
        // divider tick reads as the video chasing the drag. Snap instead.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    private func syncPlaceholderFrame() {
        let frame = videoRect() ?? bounds
        guard placeholderLayer.frame != frame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeholderLayer.frame = frame
        CATransaction.commit()
    }

    // MARK: - Mouse → touch

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let point = normalized(event) { onTouch?(.down, point) }
    }

    override func mouseDragged(with event: NSEvent) {
        if let point = normalized(event) { onTouch?(.move, point) }
    }

    override func mouseUp(with event: NSEvent) {
        if let point = normalized(event) { onTouch?(.up, point) }
    }

    /// The aspect-fit rect the video occupies inside the (letterboxed) bounds.
    private func videoRect() -> CGRect? {
        guard let size = videoSize, size.width > 0, size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return nil }
        let viewAspect = bounds.width / bounds.height
        let videoAspect = size.width / size.height
        if videoAspect > viewAspect {
            let height = bounds.width / videoAspect
            return CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        }
        let width = bounds.height * videoAspect
        return CGRect(x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height)
    }

    private func normalized(_ event: NSEvent) -> CGPoint? {
        guard let rect = videoRect() else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        return CGPoint(x: (clampedX - rect.minX) / rect.width, y: (clampedY - rect.minY) / rect.height)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v": onPaste?()
            case "c": onCopy?()
            case "x": onCut?()
            default: break  // other ⌘ shortcuts pass to the Mac
            }
            return
        }
        if let keycode = Self.androidKeycode(for: event.keyCode) {
            onKeycode?(keycode, .down)
            return
        }
        if let text = event.characters, !text.isEmpty { onText?(text) }
    }

    override func keyUp(with event: NSEvent) {
        if let keycode = Self.androidKeycode(for: event.keyCode) { onKeycode?(keycode, .up) }
    }

    /// Map the macOS keys that have no text representation to Android keycodes.
    private static func androidKeycode(for macKeyCode: UInt16) -> UInt32? {
        switch macKeyCode {
        case 36, 76: 66   // Return / Keypad Enter → ENTER
        case 51: 67       // Delete → DEL (backspace)
        case 117: 112     // Forward Delete → FORWARD_DEL
        case 53: 4        // Escape → BACK
        case 48: 61       // Tab → TAB
        case 123: 21      // ← LEFT
        case 124: 22      // → RIGHT
        case 125: 20      // ↓ DOWN
        case 126: 19      // ↑ UP
        default: nil
        }
    }
}

/// SwiftUI bridge for the live mirror surface.
struct MirrorVideoView: NSViewRepresentable {
    let renderer: MirrorRenderer
    var videoSize: CGSize?
    var onTouch: ((ScrcpyControlMessage.TouchAction, CGPoint) -> Void)?
    var onKeycode: ((UInt32, ScrcpyControlMessage.KeyAction) -> Void)?
    var onText: ((String) -> Void)?
    var onPaste: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = MirrorLayerNSView(displayLayer: renderer.displayLayer)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? MirrorLayerNSView else { return }
        apply(to: view)
    }

    private func apply(to view: MirrorLayerNSView) {
        view.videoSize = videoSize
        view.onTouch = onTouch
        view.onKeycode = onKeycode
        view.onText = onText
        view.onPaste = onPaste
        view.onCopy = onCopy
        view.onCut = onCut
    }
}
