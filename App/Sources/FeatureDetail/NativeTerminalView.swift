import AppKit
import SwiftTerm
import SwiftUI

/// SwiftTerm's Mac view computes an auto-scroll velocity while drag-selecting
/// past the viewport edge but never schedules the timer that would consume it,
/// so a selection stops dead at the visible edge. This subclass drives the
/// scroll itself, and adds the other desktop-terminal table stakes SwiftTerm
/// leaves to the host: a right-click Copy/Paste menu and find-bar entry points.
final class DroidTerminalView: LocalProcessTerminalView {
    private var dragWatchTimer: Timer?

    /// SwiftTerm seals `mouseDragged` as `public` (not `open`), so the drag
    /// can't be observed by override. But every drag-selection announces
    /// itself here (`startSelection` notifies the moment the drag begins) —
    /// a selection change while the left button is down means a drag-select
    /// is in flight, so start watching the pointer.
    override func selectionChanged(source: SwiftTerm.Terminal) {
        super.selectionChanged(source: source)
        guard NSEvent.pressedMouseButtons & 1 == 1 else { return }
        // When the program owns the mouse (vim, htop), drags go to it and no
        // selection is being made — nothing to scroll.
        guard !(allowMouseReporting && getTerminal().mouseMode != .off) else { return }
        startDragWatch()
    }

    // A tab closing mid-drag unparents the view before the button lifts; the
    // repeating timer retains its target, so it must die here too.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { stopDragWatch() }
    }

    private func startDragWatch() {
        guard dragWatchTimer == nil else { return }
        let timer = Timer(
            timeInterval: 0.05, target: self, selector: #selector(dragWatchTick),
            userInfo: nil, repeats: true
        )
        // .common so it keeps firing during the mouse-drag event stream.
        RunLoop.main.add(timer, forMode: .common)
        dragWatchTimer = timer
    }

    private func stopDragWatch() {
        dragWatchTimer?.invalidate()
        dragWatchTimer = nil
    }

    @objc private func dragWatchTick() {
        guard NSEvent.pressedMouseButtons & 1 == 1, let window, selectionActive else {
            stopDragWatch()
            return
        }
        // Scroll when the pointer is within a small band at either edge, not
        // only past it — the terminal's bottom edge usually sits at the screen
        // edge, where macOS clamps the cursor, so "past the edge" can be
        // unreachable (Terminal.app uses the same edge-zone trick). The view
        // is y-up: the top edge reveals scrollback (up), the bottom edge
        // advances toward the newest output (down). Between the zones there's
        // nothing to do — keep watching until the button lifts.
        let zone: CGFloat = 8
        let location = window.mouseLocationOutsideOfEventStream
        let point = convert(location, from: nil)
        if point.y > bounds.height - zone {
            scrollUp(lines: dragScrollStep(overshoot: point.y - (bounds.height - zone)))
        } else if point.y < zone {
            scrollDown(lines: dragScrollStep(overshoot: zone - point.y))
        } else {
            return
        }
        // Replay the drag at the (unmoved) pointer so the selection extends
        // into the rows the scroll just revealed.
        let synthesized = NSEvent.mouseEvent(
            with: .leftMouseDragged, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        )
        if let synthesized { mouseDragged(with: synthesized) }
    }

    /// Farther past the edge scrolls faster, like every native text view.
    private func dragScrollStep(overshoot: CGFloat) -> Int {
        max(1, min(6, Int(overshoot / 12)))
    }

    /// Right-click menu. Items target self so validation runs through
    /// SwiftTerm's `validateUserInterfaceItem` (Copy needs a selection).
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        addItem(to: menu, title: "Copy", action: #selector(SwiftTerm.TerminalView.copy(_:)), key: "c")
        addItem(to: menu, title: "Paste", action: #selector(SwiftTerm.TerminalView.paste(_:)), key: "v")
        addItem(to: menu, title: "Select All", action: #selector(NSResponder.selectAll(_:)), key: "a")
        menu.addItem(.separator())
        let find = addItem(
            to: menu, title: "Find…",
            action: #selector(SwiftTerm.TerminalView.performFindPanelAction(_:)), key: "f"
        )
        find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        return menu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }
}

/// One real embedded shell (PTY-backed, via SwiftTerm). The Terminal feature's
/// manager owns one session per tab, all held on `AppState` so every shell and
/// its scrollback survive switching features. The login shell is started
/// lazily the first time the tab is shown.
@MainActor
final class TerminalSession {
    private var terminalView: DroidTerminalView?
    /// Latched by `kill()`. SwiftUI's teardown pass can call `view(serial:)`
    /// once more on the dying representable — without the latch that silently
    /// respawned an orphan shell for every closed tab.
    private var killed = false

    /// Fired when the shell ends on its own (`exit`, EOF, a crash) — not when
    /// `kill()` tears it down — so the owning tab can close like the × does.
    var onProcessExit: (() -> Void)?

    /// The session's terminal view, starting the login shell on first use. The
    /// selected device serial is exported as `ANDROID_SERIAL` so `adb` targets
    /// it without `-s`.
    func view(serial: String?) -> LocalProcessTerminalView {
        if let terminalView { return terminalView }
        let view = DroidTerminalView(frame: .zero)
        view.font = Self.terminalFont(size: 12)
        view.processDelegate = self
        terminalView = view
        guard !killed else { return view } // dead husk for the unmount pass

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        if let serial, !serial.isEmpty {
            environment["ANDROID_SERIAL"] = serial
        }
        view.startProcess(
            executable: environment["SHELL"] ?? "/bin/zsh",
            args: ["-l"],
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        return view
    }

    /// Terminate the shell and drop the view — used when a terminal tab closes.
    /// SwiftTerm's `terminate()` closes the PTY and sends SIGTERM, which an
    /// interactive zsh *ignores* — follow up with SIGHUP, which it honors.
    func kill() {
        killed = true
        if let terminalView {
            let pid = terminalView.process.shellPid
            terminalView.terminate()
            if pid != 0 {
                Darwin.kill(pid, SIGHUP)
            }
        }
        terminalView = nil
    }

    /// Open SwiftTerm's built-in find bar over this shell's scrollback.
    func showFindBar() { sendFindPanelAction(.showFindPanel) }
    func findNext() { sendFindPanelAction(.next) }
    func findPrevious() { sendFindPanelAction(.previous) }

    /// SwiftTerm's find entry point is menu-shaped — it reads the action off
    /// an `NSMenuItem` tag — so the menu-bar commands feed it a synthetic item.
    private func sendFindPanelAction(_ action: NSFindPanelAction) {
        guard let terminalView else { return }
        let item = NSMenuItem()
        item.tag = Int(action.rawValue)
        terminalView.performFindPanelAction(item)
    }

    /// A fixed-width Nerd Font so prompt-theme glyphs (powerline separators,
    /// icons) render instead of missing-glyph boxes; falls back to the system
    /// monospace when no Nerd Font is installed.
    static func terminalFont(size: CGFloat) -> NSFont {
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies
        let family = families.first { $0.range(of: "Nerd Font Mono", options: .caseInsensitive) != nil }
            ?? families.first { $0.range(of: "Nerd Font", options: .caseInsensitive) != nil }
            ?? families.first { $0.range(of: "Nerd", options: .caseInsensitive) != nil }
        if let family, let font = manager.font(withFamily: family, traits: [], weight: 5, size: size) {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// The delegate is adopted only to hear the shell end on its own — sizing and
/// titles are handled inside SwiftTerm. `LocalProcess` posts these callbacks
/// on the main queue (its default dispatch queue), so hopping back onto the
/// main actor with `assumeIsolated` is safe.
extension TerminalSession: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            guard !killed else { return } // kill() already closed the tab
            onProcessExit?()
        }
    }
}

/// SwiftUI host for one terminal session. SwiftUI tears down and recreates the
/// representable when a tab is hidden/reshown; returning the session's view
/// directly let SwiftUI reset it, spawning a fresh-looking shell. Instead we
/// hand SwiftUI a fresh container each time and re-parent the session's one
/// live terminal into it, so the PTY session and scrollback truly persist.
struct NativeTerminalView: NSViewRepresentable {
    let session: TerminalSession
    let serial: String?
    /// Whether this session's tab is the focused one in the terminal strip.
    let isActive: Bool

    /// Remembers the last activation state so focus is grabbed only on the
    /// inactive→active edge — not on every SwiftUI update, which would steal
    /// the first responder from the sidebar search field mid-typing.
    final class Coordinator {
        var wasActive = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        mount(in: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        mount(in: nsView, coordinator: context.coordinator)
    }

    private func mount(in container: NSView, coordinator: Coordinator) {
        let terminal = session.view(serial: serial)
        if terminal.superview !== container {
            terminal.removeFromSuperview()
            terminal.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(terminal)
            NSLayoutConstraint.activate([
                terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                terminal.topAnchor.constraint(equalTo: container.topAnchor),
                terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        // Focus the shell when its tab becomes active (or on first show) so
        // typing works right away, like Terminal.app — no click required.
        if isActive && !coordinator.wasActive {
            Task { @MainActor in
                terminal.window?.makeFirstResponder(terminal)
            }
        }
        coordinator.wasActive = isActive
    }
}
