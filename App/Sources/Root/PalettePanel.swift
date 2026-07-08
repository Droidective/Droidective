import AppKit
import SwiftUI

/// A borderless panel that can still take key focus. Borderless `NSWindow`s
/// return `false` from `canBecomeKey`/`canBecomeMain` by default, which would
/// stop a palette's search field from receiving input; overriding them keeps
/// the panel chromeless yet focusable. A panel we own (vs. a SwiftUI `Window`
/// scene) can do this without colliding with SwiftUI's window constraints.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns one floating, borderless panel hosting SwiftUI content — the shared
/// chassis of the ⌘T palette and the Quick Actions panel. Borderless removes
/// the 32pt title-bar region a hidden-title-bar `Window` scene always
/// reserves, so the content sizes the panel exactly — flush at top and
/// bottom. The panel resizes to its content, keeps its top edge anchored as
/// results grow/shrink, and closes when it loses key (click-away) or on Esc.
@MainActor
final class FloatingPanelController {
    /// The in-app ⌘T search palette.
    static let palette = FloatingPanelController(activatesApp: true)

    /// The global-hotkey Quick Actions panel. Non-activating: it takes key
    /// input without activating Droidective, so whatever app was frontmost
    /// keeps focus underneath — summonable while the app is resident in the
    /// background with no window and no Dock icon.
    static let quickActions = FloatingPanelController(activatesApp: false)

    private let activatesApp: Bool
    private var panel: KeyablePanel?
    private var anchorMaxY: CGFloat = 0
    private var resignObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?

    /// While true, losing key focus doesn't close the panel — set around an
    /// open/save dialog the panel itself presents (e.g. Install APK's file
    /// picker), which necessarily takes key.
    var holdsThroughResign = false

    /// Fired whenever the panel actually closes (Esc, click-away, auto-close),
    /// for session bookkeeping like the Quick Actions resume timestamp.
    var onClosed: (() -> Void)?

    private init(activatesApp: Bool) {
        self.activatesApp = activatesApp
    }

    var isVisible: Bool { panel != nil }

    /// Present the panel with `content`, which receives the close action to
    /// wire into its Esc/dismiss handling. Re-showing an open panel just
    /// re-fronts it.
    func show<Content: View>(@ViewBuilder content: (_ close: @escaping () -> Void) -> Content) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let root = content { [weak self] in self?.close() }
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]

        let panel = KeyablePanel(contentViewController: hosting)
        panel.styleMask = activatesApp ? [.borderless] : [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Lay the SwiftUI content out first so `.preferredContentSize` has
        // produced the real 520×height frame before we center. Otherwise
        // `positionInitially` centers the pre-layout placeholder width and the
        // palette lands off-center.
        hosting.view.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.view.fittingSize)

        positionInitially(panel)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.holdsThroughResign else { return }
                self.close()
            }
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.keepCentered() } }
    }

    func close() {
        guard let panel else { return }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resignObserver = nil
        resizeObserver = nil
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
        onClosed?()
    }

    /// Re-front and re-key the open panel (after a modal dialog took key).
    func makeKey() {
        panel?.makeKeyAndOrderFront(nil)
    }


    /// Center on screen, and remember the top edge so later resizes grow
    /// downward from there instead of drifting up off the bottom-left origin.
    private func positionInitially(_ panel: NSPanel) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let frame = panel.frame
        let visible = screen.visibleFrame
        let x = visible.midX - frame.width / 2
        let y = visible.midY - frame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        anchorMaxY = panel.frame.maxY
    }

    /// Keep the top edge anchored (so the search field doesn't jump as the
    /// results list grows) while staying horizontally centered on the current
    /// screen — the results list resizing the panel would otherwise leave a
    /// first-frame miscenter uncorrected on the X axis.
    private func keepCentered() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        var origin = panel.frame.origin
        let x = screen.visibleFrame.midX - panel.frame.width / 2
        let y = anchorMaxY - panel.frame.height
        if abs(origin.x - x) > 0.5 || abs(origin.y - y) > 0.5 {
            origin.x = x
            origin.y = y
            panel.setFrameOrigin(origin)
        }
    }
}
