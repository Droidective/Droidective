import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @AppStorage("sidebarWidth") private var sidebarWidth = 300.0
    @AppStorage(sidebarAutoHideDefaultsKey) private var sidebarAutoHide = false
    /// Left-pane fraction (0…1) of the editor split; the layout clamps it so
    /// neither pane collapses.
    @AppStorage("tabSplitFraction") private var splitFraction = 0.5
    /// In-flight drag values for the two seams. Layout reads these over the
    /// persisted @AppStorage values so a drag never writes UserDefaults per
    /// tick — each write re-evaluates the App scene (and the window minimum
    /// width derived from `sidebarWidth`) mid-drag, which stuttered the drag.
    @State private var sidebarDragWidth: Double?
    @State private var splitDragFraction: Double?
    @AppStorage("hasSeenTour") private var hasSeenTour = false
    @AppStorage("hasChosenRole") private var hasChosenRole = false
    @AppStorage("launchCount") private var launchCount = 0
    @AppStorage("starPromptShown") private var starPromptShown = false
    @AppStorage("theme") private var theme = "dark"
    @State private var presentStar = false
    /// True only while the *first-run* role picker is up, so its dismissal
    /// chains into the welcome tour. Changing role later (pill / Settings)
    /// leaves this false, so the tour never reappears.
    @State private var pickerIsFirstRun = false
    @Environment(\.colorScheme) private var colorScheme

    /// Launches before the one-time GitHub-star nudge.
    private let starPromptAfterLaunches = 10

    /// Theme color-sync needs two modifiers because they reach different layers,
    /// and neither alone is enough:
    ///
    /// - `.preferredColorScheme(preferredScheme)` sets the hosting NSWindow's
    ///   appearance, so the *native* menus/popovers presented from this window
    ///   (the device-picker dropdown, the overrides menu) render in the matching
    ///   appearance instead of always light.
    /// - `.environment(\.colorScheme, injectedColorScheme)` forces the value the
    ///   *SwiftUI-drawn* content resolves named asset colors against. A `Menu`'s
    ///   label is hosted in a context that doesn't reliably inherit the window
    ///   appearance for asset resolution, so without this the device-picker title
    ///   (`.textMain`) renders white-on-white in light mode even though the bar's
    ///   `.bgSurface` background resolves correctly.
    ///
    /// `nil` / system pass-through for "auto" keeps both following the system
    /// appearance live.
    private var preferredScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil  // "auto" → follow the system appearance
        }
    }

    private var injectedColorScheme: ColorScheme {
        switch theme {
        case "light": return .light
        case "auto": return colorScheme
        default: return .dark
        }
    }

    private var shouldPromptStar: Bool {
        LaunchPrompt.starDue(
            starPromptShown: starPromptShown, launchCount: launchCount, afterLaunches: starPromptAfterLaunches)
    }

    var body: some View {
        @Bindable var state = state
        // Read pendingExit here so body re-renders when a navigation is deferred
        // (the exitGuard alone is often unchanged), driving the leave dialog.
        let showExitDialog = state.pendingExit.map { !$0.saving } ?? false
        return zoomedContent
            .overlay(alignment: .topTrailing) { devMetricsOverlay }
            .modifier(PostTourCelebration(state: state))
            .environment(\.colorScheme, injectedColorScheme)
            .preferredColorScheme(preferredScheme)
            .background(WindowAccessor { window in
                // Track the main window by reference — the ⌘W monitor and
                // `activateMainWindow` need to tell it apart from Settings /
                // panels, and identifiers don't survive a close (SwiftUI
                // re-stamps `main-AppWindow-1` over any tag).
                state.mainWindow = window
                // Restore the user's saved window frame; only fill the screen's
                // usable area on the very first launch (nothing to restore), so
                // a resized window survives relaunch instead of being maximized.
                let autosaveName = NSWindow.FrameAutosaveName(RootView.mainWindowFrameAutosaveName)
                if !window.setFrameUsingName(autosaveName), let screen = window.screen ?? NSScreen.main {
                    window.setFrame(screen.visibleFrame, display: true)
                }
                window.setFrameAutosaveName(autosaveName)
                WindowMinSizeGuard.shared.attach(to: window)
            })
            .overlay {
                // Full-window takeover (macOS has no fullScreenCover), shown
                // before the tour for brand-new users and from "Change role".
                if state.presentRolePicker {
                    RolePickerView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.presentRolePicker)
            .sheet(isPresented: $state.presentTour) {
                TourView()
            }
            .background {
                // Its own host view so the star sheet reliably presents (two
                // .sheet modifiers on one view can drop one).
                Color.clear.sheet(isPresented: $presentStar) {
                    StarPromptView(onStar: { state.openRepository() })
                }
            }
            #if !APPSTORE
            .modifier(WhatsNewPresenter())
            #endif
            .onAppear { performLaunchSetup() }
            .onChange(of: state.presentRolePicker) { _, showing in rolePickerVisibilityChanged(showing) }
            .onChange(of: colorScheme) { _, _ in updateDockIcon() }
            .onChange(of: state.activeTabID) { _, id in Telemetry.shared.featureBecameActive(id) }
            .onChange(of: state.openFeatureIDs) { _, ids in Telemetry.shared.openFeaturesChanged(ids) }
            .confirmationDialog(
                state.pendingGuard?.title ?? "",
                isPresented: Binding(
                    get: { showExitDialog },
                    set: { shown in
                        if !shown, state.pendingExit?.saving == false { state.cancelExit() }
                    }
                ),
                titleVisibility: .visible,
                presenting: state.pendingGuard
            ) { info in
                exitDialogButtons(for: info)
            } message: { info in
                Text(info.message)
            }
            .modifier(TerminalCloseConfirmation(state: state))
    }

    /// The debug-only self-metrics HUD (memory/CPU/network), pinned top-right over
    /// the content. Empty in Release; visibility inside is driven by the
    /// Settings ▸ Appearance toggle.
    @ViewBuilder private var devMetricsOverlay: some View {
        #if DEBUG
        DevMetricsOverlay().padding(.top, 10).padding(.trailing, 10)
        #endif
    }

    /// Runs once when the root view appears: wires AppState callbacks, applies
    /// stored prefs/theme/hotkeys, and shows the first due launch prompt. Kept
    /// out of `body` so the view-builder expression stays cheap to type-check.
    private func performLaunchSetup() {
        state.openMainWindow = { openWindow(id: "main") }
        state.openPalette = {
            FloatingPanelController.palette.show { close in
                PaletteWindowView(onClose: close)
                    .environment(state)
                    .tint(.brandAccent)
            }
        }
        // A double-clicked APK opens the Quick Actions panel on its options
        // screen (install in place / APK Studio / the Install App screen)
        // instead of taking over the main window. Anything else handed to
        // "Open With → Droidective" gets a toast instead of silence.
        InstallInbox.shared.onReceive = { urls in
            let apks = urls.filter { $0.pathExtension.lowercased() == "apk" }
            for other in urls where other.pathExtension.lowercased() != "apk" {
                state.showToast(Toast(message: "Not an APK: \(other.lastPathComponent)", ok: false))
            }
            guard !apks.isEmpty else { return }
            QuickActionsPanel.showAPKOptions(apks, state: state)
        }
        #if !APPSTORE
        // Update toasts ("available" / "ready — relaunch" / "up to date")
        // originate in the updater; route them through the app's toast +
        // notification-history pipeline.
        SparkleUpdater.shared.notify = { [weak state] toast in state?.showToast(toast) }
        // First launch of a version the updater installed: announce it with
        // a "What's New" notification whose button opens the changelog
        // modal. `take` consumes the stash, so reopening the window (this
        // setup re-runs in background mode) can't re-announce; the changelog
        // stays reachable from the notification history all session.
        if let pending = UpdaterViewModel.takeWhatsNewForLaunch() {
            state.whatsNew = pending
            state.showToast(Toast(
                message: "Updated to Droidective \(pending.version).",
                ok: true, level: .success, action: .showWhatsNew, important: true))
        }
        #endif
        migrateDefaultsIfNeeded()
        applyStoredTheme()
        // Enumerate installed font families now so the Settings ▸ Appearance
        // font picker opens instantly.
        FontCatalog.preload()
        updateDockIcon()
        // Watch the app's own CPU/RAM and report sustained spikes to telemetry
        // with the features open at the time (consent-gated in Telemetry).
        PerformanceMonitor.shared.start { [state] in
            PerformanceMonitor.FeatureContext(
                activeFeature: state.activeTabID,
                openFeatures: state.openFeatureIDs
            )
        }
        HotkeyManager.install(state: state)
        Telemetry.shared.applyRole(state.selectedRole?.rawValue)
        Telemetry.shared.trackAppLaunched(launchCount: launchCount)
        Telemetry.shared.featureBecameActive(state.activeTabID)
        Telemetry.shared.openFeaturesChanged(state.openFeatureIDs)
        installCloseTabMonitor()
        installDragJanitor()
        installFocusRelease()
        switch LaunchPrompt.next(
            hasChosenRole: hasChosenRole, hasSeenTour: hasSeenTour,
            starPromptShown: starPromptShown,
            launchCount: launchCount, starAfterLaunches: starPromptAfterLaunches
        ) {
        case .rolePicker:
            // Brand-new user: pick a role first, then run the tour.
            pickerIsFirstRun = true
            state.presentRolePicker = true
        case .tour:
            state.presentTour = true
        case .star:
            presentStar = true
        case nil:
            break
        }
    }

    /// The main window's frame-autosave name — the value must stay
    /// "droidective-main" so existing users' saved frames survive.
    /// (Recognizing the window itself goes through `AppState.mainWindow` by
    /// reference; identifiers don't survive a close.)
    fileprivate static let mainWindowFrameAutosaveName = "droidective-main"
    private static var closeTabMonitorInstalled = false

    /// ⌘W closes the active tab, not the window. A local key-down monitor
    /// intercepts ⌘W for the main window before AppKit's default Close-Window
    /// runs (local monitors see the event first and can swallow it); the red
    /// traffic-light button still closes the whole window. Installed once.
    private func installCloseTabMonitor() {
        guard !RootView.closeTabMonitorInstalled else { return }
        RootView.closeTabMonitorInstalled = true
        let state = self.state
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "w",
                  let keyWindow = NSApp.keyWindow, keyWindow === state.mainWindow
            else { return event }
            state.closeActiveTab()
            return nil
        }
    }

    private static var dragJanitorInstalled = false

    /// A drag has no "ended without a drop" callback: releasing a dragged tab
    /// (or a terminal rail row) outside any drop target fires no delegate, so
    /// the drag state — and the insertion guideline keyed off it — stayed
    /// stuck. Normal mouse events don't flow while a drag session runs, so the
    /// first one arriving with drag state still set means exactly that ending;
    /// clear it there. Installed once. This is also what lets the Terminal
    /// drop its whole-view cleanup catch, which blocked the pane's tab drops
    /// (drops route to the deepest region by geometry, not type).
    private func installDragJanitor() {
        guard !RootView.dragJanitorInstalled else { return }
        RootView.dragJanitorInstalled = true
        let state = self.state
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { event in
            if state.draggingTabID != nil { state.draggingTabID = nil }
            if state.terminals.railDragActive { state.terminals.clearRailDrag() }
            return event
        }
    }

    private static var focusReleaseInstalled = false

    /// Clicking outside the active text field should end its editing. macOS
    /// keeps an `NSTextField`'s field editor first responder until something
    /// else takes focus, so clicking empty chrome otherwise leaves the field
    /// editing and swallowing keystrokes. On each left-click, if a field editor
    /// is active and the click landed neither in it nor on the control it edits,
    /// resign to the window — committing the field without closing panels
    /// (`makeFirstResponder(nil)` keeps the window key). One monitor covers
    /// every `TextField`/`SecureField`/search field in every window. Installed
    /// once. Multi-line `TextEditor`s aren't field editors, so they're left
    /// alone (their own click handling manages focus).
    private func installFocusRelease() {
        guard !RootView.focusReleaseInstalled else { return }
        RootView.focusReleaseInstalled = true
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            guard let window = event.window,
                  let editor = window.firstResponder as? NSTextView, editor.isFieldEditor
            else { return event }
            let editedControl = editor.delegate as? NSView
            let clickedInField = window.contentView?.hitTest(event.locationInWindow).map { hit in
                hit === editor || hit.isDescendant(of: editor)
                    || (editedControl.map { hit.isDescendant(of: $0) } ?? false)
            } ?? false
            if !clickedInField { window.makeFirstResponder(nil) }
            return event
        }
    }

    /// Only the first-run role picker chains into the tour; changing role later
    /// (pill / Settings) must not reopen it.
    private func rolePickerVisibilityChanged(_ showing: Bool) {
        if !showing && pickerIsFirstRun {
            pickerIsFirstRun = false
            if !hasSeenTour { state.presentTour = true }
        }
    }

    @ViewBuilder
    private func exitDialogButtons(for info: AppState.ExitGuard) -> some View {
        switch info.style {
        case .recording:
            Button("Stop & Save") { state.beginExitSave() }
            Button("Discard", role: .destructive) { state.discardAndExit() }
            Button("Keep Recording", role: .cancel) { state.cancelExit() }
        case .edits:
            Button("Discard", role: .destructive) { state.discardAndExit() }
            Button("Keep Editing", role: .cancel) { state.cancelExit() }
        }
    }

    /// macOS has no native light/dark app icon, so swap the Dock icon at
    /// runtime to match the active theme. The decode happens off the main
    /// thread: `NSImage(named:)` is lazy, so assigning it directly made the
    /// first `NSDockTile display` decode and colorspace-convert the full
    /// asset on the main thread — a 2s+ hang at launch, concurrent with
    /// window restore (Sentry DROIDECTIVE-MAC-T). Only the cheap assignment
    /// of the pre-rasterized bitmap stays on the main actor.
    private func updateDockIcon() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let name = dark ? "AppLogoDark" : "AppLogoLight"
        Task.detached(priority: .userInitiated) {
            guard let icon = RootView.rasterizedDockIcon(named: name) else { return }
            await MainActor.run {
                // A theme flip can race two of these tasks; drop a stale result.
                let nowDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                guard name == (nowDark ? "AppLogoDark" : "AppLogoLight") else { return }
                NSApp.applicationIconImage = NSImage(cgImage: icon, size: .zero)
            }
        }
    }

    /// Decodes the named logo asset into a plain 8-bit sRGB bitmap, forcing
    /// the PNG decode and any colorspace conversion to happen here (off the
    /// main thread) instead of inside the Dock tile's first render.
    private nonisolated static func rasterizedDockIcon(named name: String) -> CGImage? {
        guard let image = NSImage(named: name),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: source.width, height: source.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return context.makeImage()
    }

    /// One-time switch to the v2 defaults — dark appearance and how-it-works
    /// notes hidden — for users who installed before they changed. Runs once;
    /// any later manual change in Settings sticks.
    private func migrateDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didMigrateDefaultsV2") else { return }
        defaults.set("dark", forKey: "theme")
        defaults.set(false, forKey: "showFeatureNotes")
        defaults.set(true, forKey: "didMigrateDefaultsV2")
    }

    /// macOS ignores SwiftUI dynamic type, so ⌘=/⌘- zoom is done by scaling the
    /// content: it's laid out at size/scale, then scaled up to fill the window,
    /// which enlarges every font and reflows the layout. The GeometryReader and
    /// scaleEffect wrap `split` unconditionally — at 1.0× it's an identity
    /// transform (no coordinate offset, so `.help`/hover/chart selection keep
    /// working) — so `split` holds one stable view identity across zoom steps.
    /// Branching on the scale (plain `split` at 1.0×, wrapped otherwise) moved
    /// `split` between two conditional branches, which rebuilt the subtree and
    /// wiped descendants' @State (e.g. a captured screenshot) on every zoom
    /// across 1.0×.
    private var zoomedContent: some View {
        GeometryReader { geo in
            split
                .frame(
                    width: geo.size.width / state.fontScale,
                    height: geo.size.height / state.fontScale,
                    alignment: .topLeading
                )
                .scaleEffect(state.fontScale, anchor: .topLeading)
        }
    }

    /// Plain HStack split (not NavigationSplitView) for a flat, flush,
    /// full-height VS Code-style sidebar with a single continuous divider.
    private var split: some View {
        HStack(spacing: 0) {
            if state.sidebarVisible && !sidebarAutoHide {
                SidebarPaletteView()
                    .frame(width: sidebarDragWidth ?? min(max(sidebarWidth, 300), 460))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                ResizeHandle(value: $sidebarWidth, live: $sidebarDragWidth, range: 300...460)
            }
            VStack(spacing: 0) {
                // Device bar on top (shared across panes); each pane's own tab
                // strip sits below it, inside the pane — VS Code-style. Shown
                // whenever any visible pane needs a device, so focusing the
                // catalog in one pane of a split doesn't pull the bar (and the
                // progress strip) out from under a live feature in the other.
                if state.workspace.groups.contains(where: { $0.activeTab != "catalog" }) {
                    DeviceBarView()
                    if let operation = state.runningOperation {
                        OperationProgressStrip(operation: operation)
                    }
                }
                HStack(spacing: 0) {
                    panesArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topTrailing) { ToastOverlay() }
                    if state.showNotifications {
                        Divider()
                        NotificationPanelView()
                            .frame(width: 320)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.bgRoot)
            .animation(.spring(duration: 0.28), value: state.showNotifications)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.textMain)
        // A tab drag released over dead space (the sidebar, device bar, an empty
        // strip area — anything that isn't a pane/chip/split target) never fires
        // a drop delegate, which would leave `draggingTabID` set and the
        // split-create overlay stuck blocking the pane. Catch those here and
        // clear it. Only a target while a tab drag is in flight; returns false so
        // it never swallows a real drop (inner targets are hit first).
        .onDrop(of: [.workspaceTab], delegate: TabDragCancelCatch(
            isDragging: state.draggingTabID != nil,
            clear: { state.draggingTabID = nil }
        ))
        // Dock-style auto-hide: the sidebar leaves the layout and rides over
        // the content, revealed by pushing the mouse against the left edge
        // (or ⌘B) and hidden again once the pointer moves past it. One
        // continuous-hover tracker on the whole split decides both — a thin
        // transparent hot-strip never received hover events reliably.
        .onContinuousHover { phase in
            guard sidebarAutoHide, case .active(let point) = phase else { return }
            if point.x <= 8, !state.sidebarOverlayShown {
                withAnimation(.easeOut(duration: 0.18)) { state.sidebarOverlayShown = true }
            } else if state.sidebarOverlayShown, point.x > overlaySidebarWidth + 8 {
                withAnimation(.easeIn(duration: 0.18)) { state.sidebarOverlayShown = false }
            }
        }
        .overlay(alignment: .leading) {
            if sidebarAutoHide && state.sidebarOverlayShown {
                SidebarPaletteView()
                    .frame(width: overlaySidebarWidth)
                    .background(.bgSurface)
                    // Not a Divider: in an overlay (ZStack context) a Divider
                    // lays out horizontally, which painted a full-width line
                    // across the sidebar's vertical middle every time the
                    // overlay was revealed. Draw the trailing edge explicitly.
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color.borderSubtle).frame(width: 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 14, x: 6)
                    .transition(.move(edge: .leading))
            }
        }
        // The Settings ▸ Appearance toggle flips the mode without going
        // through toggleSidebarMode — apply the same safeguard here: never
        // leave BOTH the fixed sidebar and the overlay hidden (turning
        // auto-hide off after ⌘B would silently vanish the sidebar).
        .onChange(of: sidebarAutoHide) { _, autoHide in
            state.sidebarOverlayShown = false
            if !autoHide, !state.sidebarVisible {
                withAnimation(.easeInOut(duration: 0.18)) { state.sidebarVisible = true }
            }
        }
        // The stationary ancestor space both seam drags measure in — a drag
        // measured in the handle's own space feeds back on itself as the
        // handle moves (jitter), and being inside the zoom scaleEffect keeps
        // deltas in logical coordinates at any ⌘= zoom level.
        .coordinateSpace(name: ResizeHandle.dragSpace)
    }

    private var overlaySidebarWidth: CGFloat {
        min(max(sidebarWidth, 300), 460)
    }

    /// The editor area: one pane, or two side by side split by a draggable seam.
    /// Each pane is clipped at its *fixed-width* frame: a tab whose content
    /// can't compress (a wide toolbar in a hidden tab, a hub grid) makes the
    /// pane's inner flexible frames grow past the pane, and clipping any of
    /// those inner frames is a no-op because their bounds grow with the
    /// content. Only the fixed frame here has the pane's true bounds — without
    /// this clip the overflow painted over the sidebar and the other pane.
    private var panesArea: some View {
        GeometryReader { geo in
            let leftW = splitLeftWidth(geo.size.width)
            let rightW = max(0, geo.size.width - leftW - 8)
            HStack(spacing: 0) {
                EditorPane(index: 0)
                    .frame(width: state.isSplit ? leftW : geo.size.width, alignment: .topLeading)
                    .clipped()
                if state.isSplit {
                    SplitDivider(
                        fraction: $splitFraction, live: $splitDragFraction,
                        totalWidth: geo.size.width
                    )
                    .frame(width: 8)
                    EditorPane(index: 1)
                        .frame(width: rightW, alignment: .topLeading)
                        .clipped()
                }
            }
            .navigationTitle(activeTitle)
        }
    }

    private func splitLeftWidth(_ totalW: CGFloat) -> CGFloat {
        let dividerW: CGFloat = 8
        let available = max(0, totalW - dividerW)
        // Never claim more than half the width per pane, so a tight pane area — a
        // small window, or a high font zoom shrinking the logical width — shrinks
        // both panes evenly instead of overflowing the right one off-screen.
        let minPane = min(320, available / 2)
        let fraction = splitDragFraction ?? splitFraction
        return min(max(available * fraction, minPane), available - minPane)
    }

    /// Window title for the focused pane's active tab. The chrome screens
    /// (Home / Manage Features / About) aren't registry features, so they're
    /// named here — this is the only `.navigationTitle` in the main window
    /// (every tab stays mounted, so a per-view title from a hidden tab would
    /// override the active one's).
    private var activeTitle: String {
        switch state.activeTabID {
        case nil: return ""
        case "home": return "Home"
        case "catalog": return "Feature Catalog"
        case "about": return "About & Feedback"
        case let id?: return FeatureRegistry.byID[id].map { state.presented($0).title } ?? ""
        }
    }
}

/// The confetti burst that rewards finishing the tour by opening the Quick
/// Actions panel. Its own modifier (not part of RootView's body expression)
/// to keep that body's type-check time in bounds.
private struct PostTourCelebration: ViewModifier {
    let state: AppState

    func body(content: Content) -> some View {
        content.overlay { ConfettiCelebration(trigger: state.confettiTrigger) }
    }
}

/// Confirms closing the Terminal feature tab — or quitting the app — while
/// shells are still open; either kills every one of them. Its own modifier
/// (not part of RootView's body expression) to keep that body's type-check
/// time in bounds.
private struct TerminalCloseConfirmation: ViewModifier {
    let state: AppState

    func body(content: Content) -> some View {
        // Buttons resolve the prompt themselves; the binding's `set` only
        // fires for an outside dismissal (Esc), which counts as Cancel — the
        // resolve guard makes a post-button set(false) a no-op.
        content.alert("Close all terminals?", isPresented: Binding(
            get: { state.terminalClosePrompt != nil },
            set: { if !$0 { state.resolveTerminalPrompt(confirmed: false) } }
        )) {
            Button(
                state.terminalClosePrompt == .quit ? "Quit" : "Close Terminals",
                role: .destructive
            ) { state.resolveTerminalPrompt(confirmed: true) }
            Button("Cancel", role: .cancel) { state.resolveTerminalPrompt(confirmed: false) }
        } message: {
            Text(message)
        }
    }

    private var message: String {
        let count = state.terminals.tabs.count
        return count == 1
            ? "This ends your running shell session — anything still running in it will be killed."
            : "This ends \(count) running shell sessions — anything still running in them will be killed."
    }
}

/// Hosts one editor group's tabs. All the group's tabs stay mounted in a ZStack
/// — so an active recording or a live log stream keeps running when you switch
/// to another tab in the same pane, and a tab keeps its view state when you come
/// back — with only the group's active tab visible and interactive. Each tab is
/// handed its feature id and whether it's on screen via the environment, which
/// device-heavy live views (network/CPU polling, the mirror) use to pause while
/// hidden. (Moving a tab to the other pane recreates it, so a recording stops if
/// dragged across panes — switching within a pane is the keep-alive path.)
struct TabHostView: View {
    @Environment(AppState.self) private var state
    let group: Int

    var body: some View {
        let ids = state.openTabIDs(inGroup: group)
        let active = state.activeTab(inGroup: group)
        ZStack {
            ForEach(ids, id: \.self) { id in
                FeatureDetailView(featureID: id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.tabFeatureID, id)
                    .environment(\.tabIsActive, id == active)
                    .opacity(id == active ? 1 : 0)
                    .allowsHitTesting(id == active)
                    .accessibilityHidden(id != active)
                    .zIndex(id == active ? 1 : 0)
            }
        }
    }
}

/// Accepts a tab dragged from a strip onto a pane (or the split-create zone).
/// The dragged id is read live from `AppState.draggingTabID`, never captured:
/// after a drop the views shift under the stationary cursor and the dying drag
/// session can deliver one more dropEntered to whatever lands there — a frozen
/// id would re-light the target after the drop already cleared it. The dropped
/// item only triggers the drop. `onTargetedChange` drives an optional hover
/// highlight.
struct TabPaneDrop: DropDelegate {
    let state: AppState
    let onDrop: (String) -> Void
    var onTargetedChange: ((Bool) -> Void)?

    private var draggingID: String? { state.draggingTabID }

    func validateDrop(info: DropInfo) -> Bool { draggingID != nil }
    func dropEntered(info: DropInfo) { if draggingID != nil { onTargetedChange?(true) } }
    func dropExited(info: DropInfo) { onTargetedChange?(false) }
    func performDrop(info: DropInfo) -> Bool {
        onTargetedChange?(false)
        guard let id = draggingID else { return false }
        onDrop(id)
        return true
    }
}

/// One editor pane: its tab strip above its mounted tabs. Dropping a dragged tab
/// on the *content* moves it into this pane (when split) or splits the workspace
/// (when not). The split preview appears only while the drag is actually over
/// the content — dragging within the strip reorders (with its own guideline) and
/// shows no split preview.
private struct EditorPane: View {
    @Environment(AppState.self) private var state
    let index: Int
    @State private var contentTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TabStripView(group: index)
            TabHostView(group: index)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.workspaceTab], delegate: TabPaneDrop(
                    state: state,
                    onDrop: { id in
                        if state.isSplit {
                            state.moveTab(id, toGroup: index)
                        } else {
                            state.splitTab(id)
                        }
                        state.draggingTabID = nil
                    },
                    onTargetedChange: { contentTargeted = $0 }
                ))
                .overlay(alignment: .trailing) {
                    // Only promise a split the model will honor: `split()`
                    // requires >1 tab (something must stay behind), so a
                    // single-tab drag shows no preview instead of a dead one.
                    if !state.isSplit, contentTargeted,
                       state.openTabIDs(inGroup: index).count > 1 { splitPreview }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Non-interactive right-half wash showing where the new split pane will land
    /// (the content's drop target performs the actual split).
    private var splitPreview: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.brandAccent.opacity(0.16))
                .overlay(alignment: .leading) { Rectangle().fill(.brandAccent).frame(width: 2) }
                .overlay {
                    Label("Drop to split", systemImage: "rectangle.split.2x1")
                        .font(.app(.headline))
                        .foregroundStyle(.brandAccent)
                }
                .frame(width: geo.size.width / 2, height: geo.size.height)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)
        }
    }
}

/// Root-level catch for a tab drag released over dead space: clears the drag
/// state so the split-create overlay can't get stuck. A target only while a tab
/// drag is in flight (so it never interferes with sidebar reordering, which
/// leaves `draggingTabID` nil), and returns false so real drops on inner targets
/// still win.
struct TabDragCancelCatch: DropDelegate {
    let isDragging: Bool
    let clear: () -> Void

    func validateDrop(info: DropInfo) -> Bool { isDragging }
    func performDrop(info: DropInfo) -> Bool {
        clear()
        return false
    }
}

/// The draggable seam between the two split panes. Stores a fraction (0…1) of
/// the total width so the split survives window resizes; the host clamps it so
/// neither pane collapses.
private struct SplitDivider: View {
    @Binding var fraction: Double
    @Binding var live: Double?
    let totalWidth: CGFloat
    @State private var startFraction: Double?

    var body: some View {
        Color.clear
            .overlay { Rectangle().fill(Color.borderSubtle).frame(width: 1) }
            .contentShape(Rectangle())
            .onHover { $0 ? NSCursor.resizeLeftRight.set() : NSCursor.arrow.set() }
            .gesture(
                DragGesture(coordinateSpace: .named(ResizeHandle.dragSpace))
                    .onChanged { gesture in
                        let base = startFraction ?? fraction
                        if startFraction == nil { startFraction = fraction }
                        let delta = totalWidth > 0 ? gesture.translation.width / totalWidth : 0
                        live = min(0.8, max(0.2, base + delta))
                    }
                    .onEnded { _ in
                        if let live { fraction = live }
                        live = nil
                        startFraction = nil
                    }
            )
    }
}

/// Reads the hosting `NSWindow` once it attaches, so the main window can be
/// sized to fill the screen on launch. `viewDidMoveToWindow` runs on the main
/// actor with the window in place — no async hop, so it stays Swift-6 clean.
private final class WindowReaderView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var resolved = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !resolved, let window else { return }
        resolved = true
        onWindow?(window)
    }
}

/// Keeps the main window at or above 85% of its screen's usable area — the
/// dense multi-pane layout degrades below that. Sets `NSWindow.minSize` (so
/// resize drags stop at the floor) and re-applies when the window changes
/// screens or the display configuration changes, growing the window back if a
/// restored/saved frame is under the floor of the current screen.
@MainActor
final class WindowMinSizeGuard {
    static let shared = WindowMinSizeGuard()
    static let screenFraction = 0.85
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func attach(to window: NSWindow) {
        self.window = window
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        let reapply: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { WindowMinSizeGuard.shared.apply() }
        }
        observers = [
            center.addObserver(
                forName: NSWindow.didChangeScreenNotification, object: window, queue: .main,
                using: reapply),
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                queue: .main, using: reapply),
        ]
        apply()
    }

    private func apply() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let floor = NSSize(
            width: (visible.width * Self.screenFraction).rounded(),
            height: (visible.height * Self.screenFraction).rounded())
        window.minSize = floor
        guard !window.styleMask.contains(.fullScreen) else { return }
        var frame = window.frame
        guard frame.width < floor.width || frame.height < floor.height else { return }
        frame.size.width = max(frame.width, floor.width)
        frame.size.height = max(frame.height, floor.height)
        // Growing can push the frame past the screen edge — slide it back in
        // (the floor is 85% of `visible`, so it always fits).
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onWindow = onResolve
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {}
}

/// A draggable divider that resizes an adjacent pane. Drag ticks write `live`
/// (transient @State the layout reads over `value`); the final size is
/// committed to `value` — the persisted @AppStorage — once on release.
/// `inverted` is for panes that grow when dragging toward the start (e.g. a
/// bottom bar dragged upward). The host must attach
/// `.coordinateSpace(name: ResizeHandle.dragSpace)` on a stationary ancestor.
struct ResizeHandle: View {
    /// Named coordinate space every seam drag measures in. Measuring in the
    /// handle's own space feeds the handle's movement back into the
    /// translation, which oscillates the drag.
    static let dragSpace = "resizeDragSpace"

    @Binding var value: Double
    @Binding var live: Double?
    let range: ClosedRange<Double>
    var axis: Axis = .horizontal
    var inverted = false
    @State private var startValue: Double?

    var body: some View {
        Divider()
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(
                        width: axis == .horizontal ? 8 : nil,
                        height: axis == .vertical ? 8 : nil
                    )
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .named(Self.dragSpace))
                            .onChanged { gesture in
                                let base = startValue ?? value
                                if startValue == nil { startValue = value }
                                let delta = axis == .horizontal ? gesture.translation.width : gesture.translation.height
                                let next = base + (inverted ? -delta : delta)
                                live = min(max(next, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in
                                if let live { value = live }
                                live = nil
                                startValue = nil
                            }
                    )
            }
    }
}

/// Progress strip pinned under the device bar: a real percentage bar when
/// the transfer size is known, a spinner otherwise.
struct OperationProgressStrip: View {
    let operation: AppState.OperationStatus

    var body: some View {
        HStack(spacing: 10) {
            if let fraction = operation.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 260)
                Text("\(Int(fraction * 100))%")
                    .font(.app(.footnote).monospacedDigit())
                    .foregroundStyle(.textMuted)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(operation.label)
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bgSurface)
        .overlay(alignment: .bottom) { Divider() }
    }
}
