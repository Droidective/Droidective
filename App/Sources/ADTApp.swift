import ADBKit
import SwiftUI
import UserNotifications

/// UserDefaults key for Settings ▸ General ▸ "Keep running in the background".
/// Read with `object(forKey:)` nil-coalesced to true, so it defaults to on.
let keepRunningInBackgroundKey = "keepRunningInBackground"

/// UserDefaults key for how long (minutes) a closed Quick Actions panel keeps
/// its session for resume; 0 disables resume. Defaults to 5.
let quickPanelResumeMinutesKey = "quickPanelResumeMinutes"

/// UserDefaults key for Settings ▸ General ▸ Quick Actions ▸ "Close the panel
/// after running an action". Off by default: the panel stays up showing the
/// result. A failed action always keeps the panel open so the error is
/// readable.
let quickPanelCloseAfterRunKey = "quickPanelCloseAfterRun"

/// Routes app packages opened from Finder (double-click / "Open With") into
/// the install inbox, which surfaces the device picker once the UI is ready.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// The app-wide state, so quit and window-close can tear down the right
    /// window's kept-alive sessions.
    @MainActor var core: AppCore { AppCore.shared }

    /// True from the moment termination is requested until it's cancelled, so
    /// the window-close observer doesn't mistake quit's window teardown for
    /// "the user closed the window" and start background mode mid-quit.
    @MainActor var isQuitting = false

    func application(_ application: NSApplication, open urls: [URL]) {
        // Files we can't install ride along so the receiver can say so once
        // the UI is up, instead of the open being silently ignored.
        guard !urls.isEmpty else { return }
        InstallInbox.shared.receive(urls)
    }

    /// Delete any decompiled-cache directories the previous quit set aside
    /// (see `applicationWillTerminate`). The tree walk is slow, so it runs
    /// detached — never on the main thread's launch path.
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task.detached(priority: .utility) {
            CacheTrash.sweep(around: AppPaths.decompiledCacheDir)
        }
        // Clicking a "install finished" notification (posted while
        // backgrounded) should land in the app, not just bounce the Dock.
        UNUserNotificationCenter.current().delegate = self
        // Selector-based (not the block API): `Notification` isn't Sendable,
        // so a @Sendable block can't hand it to the main actor. The selector
        // route delivers it straight into a @MainActor method — safe because
        // willClose is always posted on the main thread.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil
        )
    }

    /// A workspace window closed: tear down *that* window's sessions. Once no
    /// primary window is left, background mode also drops the Dock icon — the
    /// app stays resident for the menu bar icon, global hotkeys, and the Quick
    /// Actions panel; quit still exits fully.
    @MainActor @objc private func windowWillClose(_ notification: Notification) {
        guard !isQuitting else { return }
        // Structural identification, not identifiers: SwiftUI re-stamps a
        // window's identifier (`main-AppWindow-1`) by close time, so the
        // `droidective-main` tag can't be trusted here. Panels don't count, and
        // Settings does (an accessory app's visible windows lose the menu bar).
        guard let closing = notification.object as? NSWindow,
              closing.canBecomeMain, !(closing is NSPanel)
        else { return }
        // Sessions must never run behind a closed window, so the workspace
        // tears down whether or not other windows remain.
        core.closeWindow(closing)
        // Minimized windows count — a window in the Dock is still the user's
        // workspace, not a cue to go accessory.
        let remaining = NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized)
                && $0.canBecomeMain && !($0 is NSPanel)
        }
        guard !remaining else { return }
        if UserDefaults.standard.object(forKey: keepRunningInBackgroundKey) as? Bool ?? true,
           NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Relaunching from Finder/Spotlight while resident in the background (no
    /// Dock icon, window closed) lands here — reopen the main window. Checked
    /// structurally, not via `hasVisibleWindows`: an open Quick Actions panel
    /// counts as a visible window and would otherwise make the relaunch a
    /// no-op with no main window and no Dock icon.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        MainActor.assumeIsolated {
            let hasPrimary = NSApp.windows.contains {
                ($0.isVisible || $0.isMiniaturized) && $0.canBecomeMain && !($0 is NSPanel)
            }
            guard !hasPrimary else { return true }
            core.activateAnyWindow()
            return false
        }
    }

    /// Clicking an install notification reopens the main window — while
    /// backgrounded the app is an accessory, so plain activation would land
    /// on nothing.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in AppCore.shared.activateAnyWindow() }
        completionHandler()
    }

    /// Block quit when losable work is in flight (an active recording / unsaved
    /// edit) to show the leave prompt; otherwise stop a kept-alive Reactotron
    /// session so we don't orphan the listener or the reverse tunnel. Both defer
    /// termination and reply once resolved.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // From here on, window closes belong to quit teardown, not
            // background mode. Cleared again if the quit gets cancelled
            // (`AppCore.cancelQuit`).
            isQuitting = true
            // Each window with work at stake gets its confirmation in turn;
            // the last resolution drives termination.
            guard core.requestQuit() else { return .terminateLater }
            core.finishQuitNow()
            return .terminateLater
        }
    }

    /// On quit, discard the decompiled cache. The APK Studio session is
    /// in-memory (gone with the process) and its decompiled output is
    /// regenerable, so it shouldn't linger in ~/Library/Caches between runs.
    /// Downloaded tools live in Application Support and are kept — they're
    /// expensive to re-fetch. Deleting the tree here hung quit for seconds
    /// (tens of thousands of jadx files, unlinked one by one on the main
    /// thread — Sentry DROIDECTIVE-MAC-R), so it's a constant-time rename; the
    /// next launch sweeps the renamed leftovers in the background.
    func applicationWillTerminate(_ notification: Notification) {
        CacheTrash.setAside(AppPaths.decompiledCacheDir)
    }
}

/// One window of the main `WindowGroup`. The workspace itself is owned by
/// `AppCore`'s registry, keyed by the window's presented `WorkspaceID`, so
/// SwiftUI re-initializing this view — which it does freely — rebinds the same
/// window instead of handing the user a blank one.
struct WorkspaceHost: View {
    /// The real app delegate (the adaptor instance) — on macOS `NSApp.delegate`
    /// is SwiftUI's own wrapper, so casting it to `AppDelegate` fails silently.
    let appDelegate: AppDelegate
    /// This host's own identity. A plain object created with the view's
    /// `@State`, so it lives exactly as long as the window does — and, unlike
    /// a `WindowGroup` presented value, SwiftUI can neither persist it across
    /// launches nor re-present a stale one into an existing window.
    @State private var token = WorkspaceToken()
    @State private var core = AppCore.shared
    @AppStorage("sidebarWidth") private var sidebarWidth = 300.0
    @AppStorage(sidebarAutoHideDefaultsKey) private var sidebarAutoHide = false

    /// Resolved per render rather than captured: the answer is a stable
    /// dictionary lookup, and resolving late is what lets a window that comes
    /// up unasked adopt a workspace whose window was closed.
    private var state: AppState { core.workspace(claiming: token.id) }

    /// The sidebar and notifications panel are fixed-width, so opening the
    /// notifications panel on a narrow window would otherwise crush the detail
    /// pane to uselessness (the welcome title wrapping one letter per line).
    /// Grow the window's minimum width with whichever side panels are showing,
    /// so the detail pane always keeps at least `detailMinWidth`. Per-window:
    /// a split in one window must not widen another's minimum.
    private var minWindowWidth: CGFloat {
        // A split needs room for two usable panes side by side (2 × 320 + the
        // seam); a single pane needs one. Without this the split overflows when
        // the window is small.
        let detailMinWidth: CGFloat = state.isSplit ? 648 : 360
        let notifications: CGFloat = state.showNotifications ? 321 : 0
        // An auto-hidden sidebar overlays the content, so it costs no width.
        let sidebar: CGFloat = state.sidebarVisible && !sidebarAutoHide
            ? CGFloat(min(max(sidebarWidth, 300), 460))
            : 0
        // The content is laid out at window ÷ fontScale then scaled up, so the
        // window must be fontScale× wider to give the layout the same logical
        // room — otherwise zooming in (⌘=) crushes the panes.
        return max(760, sidebar + detailMinWidth + notifications) * state.fontScale
    }

    var body: some View {
        RootView()
            .environment(state)
            .frame(minWidth: minWindowWidth, minHeight: 480)
            .onAppear { state.appDelegate = appDelegate }
    }
}

/// A window host's identity token. Reference type so `@State` keeps one per
/// window for the window's lifetime.
final class WorkspaceToken {
    let id = WorkspaceID.generate()
}

@main
struct ADTApp: App {
    /// The app-wide half of the state. Windows get their own `AppState` from
    /// it; this reference exists so the menus and scenes can reach it.
    @State private var core = AppCore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("sidebarWidth") private var sidebarWidth = 300.0
    @AppStorage(sidebarAutoHideDefaultsKey) private var sidebarAutoHide = false
    /// The user-chosen accent, background, and font. Read here so changing
    /// them re-renders the scene and re-keys RootView (`.id`), forcing every
    /// `.brandAccent`, background token, and `Font.app` to re-resolve.
    @AppStorage(accentColorDefaultsKey) private var accentHex = ""
    @AppStorage(backgroundColorDefaultsKey) private var backgroundHex = ""
    @AppStorage(textColorDefaultsKey) private var textHex = ""
    @AppStorage(appFontFamilyDefaultsKey) private var appFontFamily = ""
    @AppStorage(appFontSizeScaleDefaultsKey) private var appFontSizeScale = 1.0

    /// One key covering every appearance pref the view tree resolves statically.
    private var appearanceKey: String {
        "\(accentHex)|\(backgroundHex)|\(textHex)|\(appFontFamily)|\(appFontSizeScale)"
    }

    /// ⌃1…⌃9 accelerators for jumping straight to a tab by position.
    private static let tabDigitKeys: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    /// ⌘1…⌘9 then ⌘0 — the first ten sidebar rows, app-wide (the Go menu).
    private static let sidebarDigitKeys: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    /// The window the menu commands act on: whichever was last key. nil only
    /// while the app is resident with every window closed, where the commands
    /// that need one reopen it first.
    private var appState: AppState? { core.frontmost }

    /// Menu title for the Go menu's n-th slot — the live feature name so the
    /// menu doubles as a legend for the ⌘-digit shortcuts.
    /// Terminal-tab commands act on the visible terminal strip, so they enable
    /// only while the Terminal feature is the active tab and has a shell open.
    private var terminalCommandsEnabled: Bool {
        guard let appState else { return false }
        return appState.activeTabID == "terminal" && !appState.terminals.tabs.isEmpty
    }

    private func sidebarShortcutTitle(_ rank: Int) -> String {
        let features = appState?.orderedSidebarMatches ?? []
        guard features.indices.contains(rank) else { return "Sidebar Item \(rank + 1)" }
        return "Open \(features[rank].title)"
    }

    init() {
        // HotkeyManager.install is deferred to RootView.onAppear — Carbon
        // hot-key registration needs a running event loop, which App.init
        // predates. Touching the core here starts its async bootstrap (device
        // polling, the persisted layout) before the first window renders.
        _ = AppCore.shared
        // Count this launch for the star-nudge threshold (gated in RootView).
        // Telemetry is anonymous and on by default; start it as early as possible.
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: "launchCount") + 1, forKey: "launchCount")
        Telemetry.shared.start()
    }

    var body: some Scene {
        // One window per device-scoped workspace. The presented `WorkspaceID`
        // is what binds a window to its selection, tabs and sessions; a fresh
        // one means a new workspace, a parked one reopens where it left off.
        WindowGroup(id: "main") {
            WorkspaceHost(appDelegate: appDelegate)
                // Force the brand accent on standard controls (prominent
                // buttons, switches, sliders) so they stay green regardless of
                // the Mac's system accent color, which otherwise overrides the
                // AccentColor asset.
                .tint(.brandAccent)
                // Re-key on the appearance prefs so changing the accent or font
                // rebuilds the tree and every `.brandAccent`/`Font.app`
                // re-resolves. The workspace is owned by AppCore, not by this
                // view, so the rebuild preserves every window's tabs.
                .id(appearanceKey)
        }
        // File opens (double-clicked .apk/.apks/.xapk/.apkm/.aab) are handled by
        // `AppDelegate.application(_:open:)`; without this, every open event
        // also makes the WindowGroup spawn a duplicate window — which
        // scene restoration then multiplies across launches.
        .handlesExternalEvents(matching: [])
        .windowStyle(.automatic)
        .commands {
            ScreenshotEditCommandsMenu()

            // ⌘N stays the Terminal's. Replacing .newItem removes the stock
            // New Window item, so the workspace window lands on ⇧⌘N — with a
            // device submenu, since a new window almost always means "and put
            // this other device in it".
            CommandGroup(replacing: .newItem) {
                Button("New Window") { core.openNewWindow() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])

                Menu("New Window for Device") {
                    let claimed = Set(core.registry.entries.compactMap(\.serial))
                    ForEach(core.readyDevices) { device in
                        Button(core.deviceTitle(device)) {
                            core.openNewWindow(targeting: device.serial)
                        }
                        // A device that already has a window would just make a
                        // duplicate workspace; the picker in that window is the
                        // way to do it deliberately.
                        .disabled(claimed.contains(device.serial))
                    }
                    if core.readyDevices.isEmpty {
                        Text("No devices connected")
                    }
                }

                Divider()

                Button("New Terminal") {
                    guard let appState else { return }
                    appState.activateMainWindow()
                    appState.requestFeature("terminal")
                    // An empty rail resumes the remembered session instead of
                    // pre-filling a fresh tab here — a tab created now would
                    // make the view's restore-on-empty a no-op.
                    if appState.terminals.tabs.isEmpty {
                        appState.openTerminalResumingWork()
                    } else {
                        appState.terminals.newTab()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                // ⌘D/⇧⌘D split the focused pane, iTerm-style; the new shell
                // starts in that pane's working directory.
                Button("Split Terminal Vertically") {
                    appState?.terminals.splitActivePane(.vertical)
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!terminalCommandsEnabled)

                Button("Split Terminal Horizontally") {
                    appState?.terminals.splitActivePane(.horizontal)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!terminalCommandsEnabled)

                Button("Close Terminal") {
                    if let id = appState?.terminals.activeID { appState?.closeTerminalShell(id) }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!terminalCommandsEnabled)

                Button("Rename Terminal…") {
                    appState?.terminals.requestRenameActiveTab()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!terminalCommandsEnabled)

                Divider()

                Button("Next Terminal") { appState?.terminals.cycle(by: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(!terminalCommandsEnabled)
                Button("Previous Terminal") { appState?.terminals.cycle(by: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(!terminalCommandsEnabled)
            }

            CommandMenu("Tab") {
                // ⌘T opens the search palette; the chosen feature opens in a
                // tab (a new one, or refocuses it if already open).
                Button("New Tab") {
                    appState?.activateMainWindow()
                    appState?.openPalette?()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") { appState?.closeActiveTab() }
                    .keyboardShortcut("w", modifiers: .command)

                Divider()

                // Control-based so they don't fight the form fields' Tab focus
                // traversal or the palette's ⌘1–9 result jumps.
                Button("Next Tab") { appState?.selectNextTab() }
                    .keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab") { appState?.selectPreviousTab() }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])

                Divider()

                ForEach(Array(Self.tabDigitKeys.enumerated()), id: \.offset) { index, key in
                    Button("Show Tab \(index + 1)") { appState?.selectTab(index: index) }
                        .keyboardShortcut(key, modifiers: .control)
                }
            }

            // ⌘1…⌘9/⌘0 open the first ten sidebar rows from anywhere in the
            // app — the same numbering the sidebar's ⌘-held badges show.
            CommandMenu("Go") {
                ForEach(Array(Self.sidebarDigitKeys.enumerated()), id: \.offset) { rank, key in
                    Button(sidebarShortcutTitle(rank)) {
                        appState?.activateMainWindow()
                        appState?.openSidebarFeature(rank: rank)
                    }
                    .keyboardShortcut(key, modifiers: .command)
                }
            }

            CommandGroup(replacing: .appInfo) {
                Button("About Droidective") {
                    appState?.activateMainWindow()
                    appState?.requestFeature("about")
                }
                #if !APPSTORE
                CheckForUpdatesCommand(updater: SparkleUpdater.shared)
                #endif
            }

            CommandGroup(replacing: .help) {
                Button("Report an Issue…") { appState?.reportBug() }
                Button("Request a Feature…") { appState?.requestFeature() }
                Divider()
                Button("Droidective on GitHub") { appState?.openRepository() }
                Button("Release Notes") { appState?.openReleases() }
            }

            CommandGroup(after: .textEditing) {
                Button("Find Feature") {
                    appState?.openPalette?()
                }

                Button("Manage Features") {
                    appState?.activateMainWindow()
                    appState?.requestFeature("catalog")
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                // SwiftTerm ships a find bar but SwiftUI's stock Edit menu has
                // no Find items to reach it — wire them for the focused shell.
                // Disabled outside the Terminal so ⌘F falls through to views
                // with their own find (e.g. the JS console's filter).
                Button("Find in Terminal…") {
                    appState?.terminals.activeSession?.showFindBar()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!terminalCommandsEnabled)

                Button("Find Next") {
                    appState?.terminals.activeSession?.findNext()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!terminalCommandsEnabled)

                Button("Find Previous") {
                    appState?.terminals.activeSession?.findPrevious()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!terminalCommandsEnabled)
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    appState?.toggleSidebar()
                }
                .keyboardShortcut("b", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    appState?.increaseFontSize()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Font Size") {
                    appState?.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)

                // ⇧⌘0 — plain ⌘0 belongs to the Go menu's tenth sidebar row.
                Button("Actual Size") {
                    appState?.resetFontSize()
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }
        }

        // The pop-out screen mirror (the mirror control bar's window button,
        // also listed in the Window menu). Sized like a phone by default. It
        // follows the window that opened it — one pop-out, one owner.
        Window("Screen Mirror", id: MirrorWindow.windowID) {
            WorkspaceScopedView(owner: core.mirrorWindowOwner) { MirrorWindowView() }
                .tint(.brandAccent)
                .id(appearanceKey)
        }
        .defaultSize(width: 420, height: 850)

        Settings {
            WorkspaceScopedView { SettingsView() }
                .tint(.brandAccent)
                .id(appearanceKey)
                // The stock ⌘, opens Settings without bringing the app
                // forward, so it lands hidden behind the floating,
                // non-activating Quick Actions panel. A replaced .appSettings
                // command fixed that, but macOS 26 adds its own Settings…
                // item regardless — two menu entries — so the panel dismissal
                // and activation ride the window appearing instead.
                .onAppear {
                    FloatingPanelController.quickActions.close()
                    NSApp.activate(ignoringOtherApps: true)
                }
        }

        MenuBarExtra("Droidective", systemImage: "iphone.gen3", isInserted: $showMenuBarExtra) {
            WorkspaceScopedView { MenuBarView() }
        }
    }
}

/// Hosts a view that wants an `AppState` in a scene that isn't a workspace
/// window — Settings, the mirror pop-out, the menu-bar extra. They act on the
/// frontmost window and follow it as the user switches, which is why the
/// environment value is resolved here rather than captured once.
struct WorkspaceScopedView<Content: View>: View {
    /// Pin to one workspace instead of following the front. The mirror pop-out
    /// uses this: there's a single pop-out window, and it should keep showing
    /// the device of the window that opened it rather than swapping every time
    /// the user clicks between windows.
    var owner: WorkspaceID?
    @State private var core = AppCore.shared
    @ViewBuilder let content: Content

    var body: some View {
        if let state = owner.flatMap({ core.workspace(id: $0) }) ?? core.frontmost {
            content.environment(state)
        }
    }
}

struct MenuBarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let device = state.selectedDevice {
            Text(state.deviceDisplayName(device))
        } else {
            Text("No device")
        }
        Divider()

        #if !APPSTORE
        // Background mode has no sidebar pill — surface a pending update
        // here so menu-bar-only users still see it. Hidden when idle.
        UpdateMenuItems()
        #endif

        // Always-on quick actions — no window needed.
        Button("Quick Actions…") {
            QuickActionsPanel.toggle(state: state)
        }
        Button("Screenshot") {
            runByID("screenshot")
        }
        Button("Mirror Screen") {
            state.activateMainWindow()
            state.requestFeature("scrcpy")
        }
        Divider()

        ForEach(state.menuBarFeatures) { feature in
            Button(feature.title) {
                if feature.kind == .instantAction {
                    Task { await state.run(feature: feature, params: [:]) }
                } else {
                    state.activateMainWindow()
                    state.requestFeature(feature.id)
                }
            }
        }
        Divider()
        Button("Open Droidective") {
            state.activateMainWindow()
        }
        Button("Quit Droidective") {
            NSApp.terminate(nil)
        }
    }

    private func runByID(_ id: String) {
        guard let feature = FeatureRegistry.byID[id] else { return }
        Task { await state.run(feature: feature, params: [:]) }
    }
}
