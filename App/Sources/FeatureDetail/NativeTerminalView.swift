import ADBKit
import AppKit
import SwiftTerm
import SwiftUI

/// SwiftTerm's Mac view computes an auto-scroll velocity while drag-selecting
/// past the viewport edge but never schedules the timer that would consume it,
/// so a selection stops dead at the visible edge. This subclass drives the
/// scroll itself, and adds the other desktop-terminal table stakes SwiftTerm
/// leaves to the host: a right-click Copy/Paste menu and find-bar entry points.
/// What the terminal's right-click menu can ask of the owning manager —
/// routed out through `TerminalSession.onMenuAction`.
enum TerminalMenuAction: Int {
    case splitVertically = 1
    case splitHorizontally
    case newTab
    case rename
    case close
}

final class DroidTerminalView: LocalProcessTerminalView {
    private var dragWatchTimer: Timer?

    /// Where the user parked the viewport, so streaming output can't yank it
    /// back to the newest line (see `TerminalScrollPin`).
    private lazy var scrollPin = TerminalScrollPin(
        scrollbackLines: getTerminal().options.scrollback
    )
    /// The wheel/keyboard tap that feeds the pin — see `installInputMonitor`.
    private var inputMonitor: Any?

    /// SwiftTerm's default background, captured before the first alpha is
    /// applied so returning to an opaque window restores the stock look.
    private var opaqueBackground: NSColor?
    private var appliedBackgroundAlpha: Double = 1.0

    /// Translucent-window support. SwiftTerm paints its background TWICE —
    /// a whole-frame fill plus a per-run fill behind every default-background
    /// cell — so a partial alpha compounds (2a−a²) into a near-solid wash
    /// that reads as "not translucent". Under translucency the terminal
    /// therefore paints NO default background at all (alpha 0, both fills
    /// become no-ops) and the pane underlay beneath it carries the one tint;
    /// selection, ANSI cell colors, and the caret still draw their own
    /// opaque colors on top.
    func applyBackgroundAlpha(_ alpha: Double) {
        if opaqueBackground == nil { opaqueBackground = nativeBackgroundColor }
        guard let base = opaqueBackground, alpha != appliedBackgroundAlpha else { return }
        appliedBackgroundAlpha = alpha
        let target = alpha >= 0.999 ? base : base.withAlphaComponent(0)
        nativeBackgroundColor = target
        layer?.backgroundColor = target.cgColor
        needsDisplay = true
    }

    /// Routes the terminal-management items of the right-click menu.
    var onMenuAction: ((TerminalMenuAction) -> Void)?
    /// Whether this shell shares its tab with other split panes — picks the
    /// Close item's title (pane vs terminal).
    var isInSplit: (() -> Bool)?
    /// Fired on every frame change; the session debounces it into a prompt
    /// repaint nudge once the layout settles.
    var onFrameChanged: (() -> Void)?
    /// Asks the manager to make this pane the active one — fired when a file
    /// drop lands here, so ⌘W / splits / new-tab inheritance follow the shell
    /// the user just dropped into.
    var onDropFocus: (() -> Void)?

    // MARK: - File drops

    private var acceptsFileDrops = false

    /// Only the visible tab's shells accept file drags. Every open tab stays
    /// mounted behind an `opacity(0)` keep-alive, and AppKit routes a drag to
    /// the deepest *registered* view under the cursor regardless of SwiftUI
    /// hit-testing — a hidden shell registered for file URLs would swallow
    /// the drop meant for the one on screen. Registering only `.fileURL`
    /// keeps the in-app tab drags (private UTIs) flowing past to their own
    /// targets.
    func setAcceptsFileDrops(_ accepts: Bool) {
        guard accepts != acceptsFileDrops else { return }
        acceptsFileDrops = accepts
        if accepts {
            registerForDraggedTypes([.fileURL])
        } else {
            unregisterDraggedTypes()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFileURLs(sender).isEmpty ? [] : .copy
    }

    /// Dropping files types their paths into the shell (quoted only when
    /// needed, trailing space — like Terminal.app), and focuses this pane.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let paths = droppedFileURLs(sender).map(\.path)
        guard !paths.isEmpty else { return false }
        onDropFocus?()
        window?.makeFirstResponder(self)
        send(txt: TerminalText.droppedPathsInsertion(paths))
        return true
    }

    private func droppedFileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onFrameChanged?()
    }

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
        if newWindow == nil {
            stopDragWatch()
            removeInputMonitor()
        } else {
            installInputMonitor()
        }
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
        noteViewportMoved()
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

    // MARK: - Scrolling

    /// SwiftTerm seals `scrollWheel` as `public` (not `open`) — like
    /// `mouseDragged` above — so the wheel is taken over with a local event
    /// monitor instead, which is also the only way to hear a keystroke land
    /// (`keyDown` is sealed the same way). Both feed `scrollPin`: the terminal
    /// otherwise drags the viewport back to the newest line on every line the
    /// program writes, which makes scrolling back through the output of
    /// anything that keeps drawing — an agent CLI, `tail -f`, a build — look
    /// like scrolling is broken.
    private func installInputMonitor() {
        guard inputMonitor == nil else { return }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) {
            [weak self] event in
            // `NSEvent` isn't Sendable, so the isolated body hands back the
            // decision and the event is passed on out here.
            let consumed = MainActor.assumeIsolated { self?.handleMonitored(event) ?? false }
            return consumed ? nil : event
        }
    }

    /// Returns whether the event was consumed here (only ever a wheel event —
    /// keystrokes are observed, never swallowed).
    private func handleMonitored(_ event: NSEvent) -> Bool {
        guard isEventInThisTerminal(event) else { return false }
        guard event.type == .scrollWheel else {
            followOutputAfterTyping(event)
            return false
        }
        return handleScrollWheel(event)
    }

    private func removeInputMonitor() {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
    }

    /// Every mounted terminal installs a monitor — including the hidden
    /// keep-alive tabs — so each one must claim only its own events: the
    /// pointer inside this view for the wheel, the keyboard focus for keys.
    private func isEventInThisTerminal(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        // Reject an event that belongs to *another* window, but not one with
        // no window at all: a synthesized event (accessibility tooling, a UI
        // test) carries none, and the hit test below is the real answer to
        // "is the pointer over this terminal".
        if let eventWindow = event.window, eventWindow !== window { return false }
        if event.type == .keyDown { return window.firstResponder === self }
        guard let hit = window.contentView?.hitTest(event.locationInWindow) else { return false }
        return hit === self || hit.isDescendant(of: self)
    }

    /// Returns whether the wheel event was consumed here. Three destinations,
    /// in the order every desktop terminal picks them: the program that took
    /// the mouse over, else the program on the alternate screen, else this
    /// terminal's own scrollback.
    private func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard event.deltaY != 0 else { return false }
        let terminal = getTerminal()
        let up = event.deltaY > 0
        if allowMouseReporting, terminal.mouseMode != .off {
            sendWheelReport(
                up: up, ticks: TerminalWheel.reports(delta: event.deltaY, rows: terminal.rows),
                event: event, terminal: terminal
            )
            return true
        }
        let lines = TerminalWheel.lines(delta: event.deltaY, rows: terminal.rows)
        if terminal.isCurrentBufferAlternate {
            sendAlternateScroll(up: up, lines: lines, terminal: terminal)
            return true
        }
        if up {
            scrollUp(lines: lines)
        } else {
            scrollDown(lines: lines)
        }
        noteViewportMoved()
        return true
    }

    /// A program that asked for the mouse (an agent CLI, `htop`, `vim` with
    /// `mouse=a`) scrolls its own content and expects the wheel as a mouse
    /// *button* report — and it usually sits on the alternate screen, where
    /// there is no scrollback to move instead. SwiftTerm's wheel handling
    /// never reports to the program, so the wheel is simply dead in every one
    /// of them until this forwards it.
    private func sendWheelReport(
        up: Bool, ticks: Int, event: NSEvent, terminal: SwiftTerm.Terminal
    ) {
        let flags = event.modifierFlags
        let buttons = terminal.encodeButton(
            button: up ? 4 : 5, release: false,
            shift: flags.contains(.shift), meta: flags.contains(.option),
            control: flags.contains(.control)
        )
        let cell = cellUnderPointer(event)
        for _ in 0..<ticks {
            terminal.sendEvent(buttonFlags: buttons, x: cell.col, y: cell.row)
        }
    }

    /// The grid cell under the pointer. SwiftTerm keeps its cell metrics
    /// internal, so they are recovered from the frame and the grid it laid
    /// out in it — off by at most a cell at the far edge, which no
    /// wheel-scrolling program cares about.
    private func cellUnderPointer(_ event: NSEvent) -> (col: Int, row: Int) {
        let terminal = getTerminal()
        let cols = max(1, terminal.cols)
        let rows = max(1, terminal.rows)
        let point = convert(event.locationInWindow, from: nil)
        let col = Int(point.x / max(1, bounds.width / CGFloat(cols)))
        let row = Int((bounds.height - point.y) / max(1, bounds.height / CGFloat(rows)))
        return (min(max(0, col), cols - 1), min(max(0, row), rows - 1))
    }

    /// The alternate screen keeps no scrollback, so there is nothing to move
    /// the viewport through — the wheel drives the program instead, one cursor
    /// key per line (xterm's alternate scroll, which is how `less`, `vim` and
    /// `man` scroll under a wheel everywhere else).
    private func sendAlternateScroll(up: Bool, lines: Int, terminal: SwiftTerm.Terminal) {
        let key: [UInt8]
        switch (up, terminal.applicationCursor) {
        case (true, true): key = EscapeSequences.moveUpApp
        case (true, false): key = EscapeSequences.moveUpNormal
        case (false, true): key = EscapeSequences.moveDownApp
        case (false, false): key = EscapeSequences.moveDownNormal
        }
        send(Array(repeating: key, count: lines).flatMap { $0 })
    }

    /// Typing returns to the live output like every desktop terminal does —
    /// keystrokes landing off-screen is worse than losing the scroll position.
    /// Command shortcuts (⌘F, ⌘C) send nothing to the shell, so they don't.
    private func followOutputAfterTyping(_ event: NSEvent) {
        guard scrollPin.isPinned, !event.modifierFlags.contains(.command) else { return }
        scrollPin.release()
        scroll(toPosition: 1)
    }

    /// Record where the user just left the viewport. At the bottom the pin is
    /// dropped, so new output scrolls the view again.
    private func noteViewportMoved() {
        scrollPin.userScrolled(
            to: getTerminal().getTopVisibleRow(), atBottom: !canScroll || scrollPosition >= 1
        )
    }

    /// The terminal has moved the viewport to the newest line after scrolling
    /// one line of output. Put it back if the user is reading history: the
    /// rows on screen don't change, so nothing needs repainting beyond what
    /// the feed already marked dirty.
    /// A program switching to (or away from) the alternate screen — where
    /// SwiftTerm leaves the right margin uninitialized and corrupts every
    /// `CSI T` scroll. See `TerminalCompat`.
    override func bufferActivated(source: SwiftTerm.Terminal) {
        TerminalCompat.repairAlternateScreenMargins(source)
        super.bufferActivated(source: source)
    }

    override func scrolled(source terminal: SwiftTerm.Terminal, yDisp: Int) {
        if terminal.isCurrentBufferAlternate {
            scrollPin.release()
        } else if let row = scrollPin.bufferScrolled(bottomRow: yDisp), row != yDisp {
            // The live buffer, not `scrollTo(row:)`: during synchronized
            // output (DECSET 2026, which agent CLIs draw their frames with)
            // the terminal displays a frozen snapshot and `scrollTo` compares
            // against *that*, so it would skip the write the frame's end then
            // reveals.
            terminal.buffer.yDisp = row
        }
        super.scrolled(source: terminal, yDisp: yDisp)
    }

    /// Right-click menu: the standard edit/find items (targeting self so
    /// validation runs through SwiftTerm's `validateUserInterfaceItem` — Copy
    /// needs a selection) plus the terminal-management actions, routed to the
    /// manager via `onMenuAction`.
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
        menu.addItem(.separator())
        addAction(to: menu, title: "Split Vertically", action: .splitVertically, key: "d")
        addAction(to: menu, title: "Split Horizontally", action: .splitHorizontally, key: "d",
                  modifiers: [.command, .shift])
        addAction(to: menu, title: "New Terminal", action: .newTab, key: "n")
        addAction(to: menu, title: "Rename Terminal…", action: .rename, key: "r",
                  modifiers: [.command, .shift])
        menu.addItem(.separator())
        addAction(
            to: menu,
            title: (isInSplit?() ?? false) ? "Close Pane" : "Close Terminal",
            action: .close, key: "w"
        )
        return menu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func addAction(
        to menu: NSMenu, title: String, action: TerminalMenuAction, key: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) {
        let item = NSMenuItem(
            title: title, action: #selector(performMenuAction(_:)), keyEquivalent: key
        )
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.tag = action.rawValue
        menu.addItem(item)
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = TerminalMenuAction(rawValue: sender.tag) else { return }
        onMenuAction?(action)
    }

    /// SwiftTerm's validation knows only its own selectors and would leave
    /// the management items (split/new/rename/close) permanently disabled.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(performMenuAction(_:)) { return true }
        return super.validateUserInterfaceItem(item)
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

    /// Where the login shell starts. New tabs and split panes inherit the
    /// spawning shell's live working directory here; nil falls back to home.
    private let startDirectory: String?

    /// Typed into the shell as soon as it starts (the custom commands'
    /// "run in Terminal" path). Newline-terminated on send so it executes;
    /// the PTY buffers it until the shell is ready to read.
    private let initialCommand: String?

    init(startDirectory: String? = nil, initialCommand: String? = nil) {
        self.startDirectory = startDirectory
        self.initialCommand = initialCommand
    }

    /// Fired when the shell ends on its own (`exit`, EOF, a crash) — not when
    /// `kill()` tears it down — so the owning tab can close like the × does.
    var onProcessExit: (() -> Void)?

    /// Fired when the user clicks into this shell's pane — lets the manager
    /// track which pane of a split tab is active.
    var onFocus: (() -> Void)?

    /// A right-click menu action on this shell (split, new tab, rename,
    /// close) — handled by the manager, which knows the pane's tab.
    var onMenuAction: ((TerminalMenuAction) -> Void)?

    /// Whether this shell shares its tab with other split panes (the menu's
    /// Close item says Pane vs Terminal) — answered by the manager.
    var isInSplit: (() -> Bool)?

    /// The debounced repaint nudge scheduled while this pane's frame is
    /// changing (split, pane close, window resize, layout toggle).
    private var repaintNudge: Task<Void, Never>?

    /// The shell's live working directory, read from the kernel
    /// (`proc_pidinfo`) so it needs no OSC 7 shell configuration. Nil until
    /// the shell has started (a tab never shown has no process yet).
    var currentDirectory: String? {
        guard let pid = terminalView?.process.shellPid, pid != 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) > 0 else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { buffer -> String? in
            guard let base = buffer.baseAddress else { return nil }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    /// The directory session resume remembers for this shell: the live cwd
    /// when the process is running, else where it was going to start — so a
    /// restored tab that was never shown (no process yet) keeps its remembered
    /// directory across teardown cycles instead of decaying to home.
    var directoryToRemember: String? { currentDirectory ?? startDirectory }

    /// The session's terminal view, starting the login shell on first use. The
    /// selected device serial is exported as `ANDROID_SERIAL` so `adb` targets
    /// it without `-s`.
    func view(serial: String?) -> LocalProcessTerminalView {
        if let terminalView { return terminalView }
        let view = DroidTerminalView(frame: .zero)
        view.font = Self.terminalFont(size: 12)
        view.processDelegate = self
        view.onMenuAction = { [weak self] action in self?.onMenuAction?(action) }
        view.isInSplit = { [weak self] in self?.isInSplit?() ?? false }
        // A file drop focuses the pane it landed in, same as a click.
        view.onDropFocus = { [weak self] in self?.onFocus?() }
        // Any frame change (split, pane close, window resize) can leave the
        // shell's prompt drawn for the old width — nudge a redisplay once the
        // layout stops moving.
        view.onFrameChanged = { [weak self] in self?.scheduleRepaintNudge() }
        terminalView = view
        guard !killed else { return view } // dead husk for the unmount pass

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        if let serial, !serial.isEmpty {
            environment["ANDROID_SERIAL"] = serial
        }
        // The inherited directory may have been deleted since it was read —
        // fall back to home rather than failing the spawn.
        var isDirectory: ObjCBool = false
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cwd = startDirectory.flatMap { dir -> String? in
            FileManager.default.fileExists(atPath: dir, isDirectory: &isDirectory)
                && isDirectory.boolValue ? dir : nil
        } ?? home
        view.startProcess(
            executable: environment["SHELL"] ?? "/bin/zsh",
            args: ["-l"],
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: cwd
        )
        if let initialCommand {
            view.send(txt: initialCommand + "\n")
        }
        return view
    }

    /// Give this shell keyboard focus — called after a neighboring pane or
    /// tab closes so typing lands in the survivor without a click.
    func takeFocus() {
        guard let terminalView, let window = terminalView.window else { return }
        // A background sibling exiting on its own must not yank the keyboard
        // out of a text field (the rename sheet, the find bar) mid-typing.
        if window.firstResponder is NSText { return }
        window.makeFirstResponder(terminalView)
    }

    /// Coalesce frame changes into one repaint nudge after the layout
    /// settles — a mid-churn nudge would redisplay at a transient size.
    private func scheduleRepaintNudge() {
        repaintNudge?.cancel()
        repaintNudge = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.forcePromptRedisplay()
        }
    }

    /// Force the shell to redisplay its prompt at the current size. Splitting
    /// narrows the surviving pane, which soft-wraps the prompt row; zle's
    /// first WINCH redraw over that wrapped row lands misaligned (its
    /// relative cursor moves don't account for the wrap) and zsh skips
    /// redisplay entirely when the size hasn't changed, so a plain SIGWINCH
    /// can't clean it up. Detour the PTY winsize one column down and back:
    /// the kernel delivers two real WINCHes, and the second redisplay — from
    /// zle's now self-consistent state — repaints cleanly at the true size.
    /// (The kernel signals the tty's foreground process group, so vim/htop
    /// relayout too.)
    func forcePromptRedisplay() async {
        guard let terminalView, terminalView.process.running else { return }
        let terminal = terminalView.getTerminal()
        guard terminal.cols > 1 else { return }
        var detour = winsize(
            ws_row: UInt16(terminal.rows), ws_col: UInt16(terminal.cols - 1),
            ws_xpixel: 0, ws_ypixel: 0
        )
        _ = PseudoTerminalHelpers.setWinSize(
            masterPtyDescriptor: terminalView.process.childfd, windowSize: &detour
        )
        try? await Task.sleep(for: .milliseconds(80))
        // Restore through SwiftTerm's own numbers in case a real resize
        // landed in between.
        guard let view = self.terminalView, view.process.running else { return }
        var size = view.getWindowSize()
        _ = PseudoTerminalHelpers.setWinSize(
            masterPtyDescriptor: view.process.childfd, windowSize: &size
        )
    }

    /// Terminate the shell and drop the view — used when a terminal tab closes.
    /// SwiftTerm's `terminate()` closes the PTY and sends SIGTERM, which an
    /// interactive zsh *ignores* — follow up with SIGHUP, which it honors.
    func kill() {
        killed = true
        repaintNudge?.cancel()
        if let terminalView {
            let pid = terminalView.process.shellPid
            terminalView.terminate()
            if pid != 0 {
                Darwin.kill(pid, SIGHUP)
            }
            // Detach the dead view: on a pane close, the SwiftUI container it
            // sat in can outlive it (a surviving sibling mounts there next).
            terminalView.removeFromSuperview()
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

/// The container a session's terminal mounts into. SwiftTerm seals
/// `becomeFirstResponder`/`mouseDown` as `public` (not `open`), so a click
/// into a pane can't be observed on the terminal view itself — the container
/// spots it in `hitTest` instead (called on the way to routing the click) and
/// tells the session, which is how a split pane takes focus.
private final class TerminalPaneContainer: NSView {
    var onClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit != nil, let event = NSApp.currentEvent,
           event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
            onClick?()
        }
        return hit
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
    /// Whether this session's pane is the focused one in the terminal strip.
    let isActive: Bool
    /// Whether this pane's tab is the one on screen — gates file-drop
    /// registration so hidden keep-alive tabs can't capture drags (see
    /// `DroidTerminalView.setAcceptsFileDrops`).
    let isVisibleTab: Bool
    @Environment(\.windowOpacity) private var windowOpacity

    /// Remembers the last activation state so focus is grabbed only on the
    /// inactive→active edge — not on every SwiftUI update, which would steal
    /// the first responder from the sidebar search field mid-typing.
    final class Coordinator {
        var wasActive = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = TerminalPaneContainer()
        mount(in: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        mount(in: nsView, coordinator: context.coordinator)
    }

    private func mount(in container: NSView, coordinator: Coordinator) {
        let terminal = session.view(serial: serial)
        (terminal as? DroidTerminalView)?
            .applyBackgroundAlpha(WindowEffects.clamped(windowOpacity))
        (terminal as? DroidTerminalView)?.setAcceptsFileDrops(isVisibleTab)
        // Re-set on every update, not just on make: SwiftUI may reuse this
        // container for a different session, and a click must focus the shell
        // that lives here now, not the one mounted first.
        (container as? TerminalPaneContainer)?.onClick = { [weak session] in
            session?.onFocus?()
        }
        if terminal.superview !== container {
            // Evict whatever an earlier session left mounted here.
            for stale in container.subviews where stale !== terminal {
                stale.removeFromSuperview()
            }
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
