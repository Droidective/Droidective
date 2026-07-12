import ADBKit
import SwiftUI

/// UserDefaults key for Settings ▸ General ▸ "Keep running in the background".
/// Read with `object(forKey:)` nil-coalesced to true, so it defaults to on.
let keepRunningInBackgroundKey = "keepRunningInBackground"

/// UserDefaults key for how long (minutes) a closed Quick Actions panel keeps
/// its session for resume; 0 disables resume. Defaults to 5.
let quickPanelResumeMinutesKey = "quickPanelResumeMinutes"

/// Routes APKs opened from Finder (double-click / "Open With") into the install
/// inbox, which surfaces the device picker once the UI is ready.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Wired in `ADTApp.body` (the adaptor instance is the real delegate), so
    /// quit and window-close can tear down kept-alive sessions.
    weak var appState: AppState?

    /// True from the moment termination is requested until it's cancelled, so
    /// the window-close observer doesn't mistake quit's window teardown for
    /// "the user closed the window" and start background mode mid-quit.
    @MainActor var isQuitting = false

    func application(_ application: NSApplication, open urls: [URL]) {
        // Non-APKs ride along so the receiver can say "Not an APK" once the
        // UI is up, instead of the open being silently ignored.
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
        // Selector-based (not the block API): `Notification` isn't Sendable,
        // so a @Sendable block can't hand it to the main actor. The selector
        // route delivers it straight into a @MainActor method — safe because
        // willClose is always posted on the main thread.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil
        )
    }

    /// Background mode: closing the main window (not quitting) stops running
    /// feature work and — once no primary window is left — removes the Dock
    /// icon. The app stays resident for the menu bar icon, global hotkeys, and
    /// the Quick Actions panel; quit still exits fully.
    @MainActor @objc private func windowWillClose(_ notification: Notification) {
        guard !isQuitting, let appState else { return }
        // Structural identification, not identifiers: SwiftUI re-stamps the
        // main window's identifier (`main-AppWindow-1`) by close time, so the
        // `droidective-main` tag can't be trusted here. Background mode starts
        // when the last *primary* window closes — panels don't count, and
        // Settings does (an accessory app's visible windows lose the menu bar).
        guard let closing = notification.object as? NSWindow,
              closing.canBecomeMain, !(closing is NSPanel)
        else { return }
        // Minimized windows count — a main window in the Dock is still the
        // user's workspace, not a cue to kill sessions and go accessory.
        let remaining = NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized)
                && $0.canBecomeMain && !($0 is NSPanel)
        }
        guard !remaining else { return }
        // Feature work always stops with the last window — sessions must not
        // run behind a closed window in either mode. The background pref only
        // decides whether the app then goes accessory (menu bar / hotkeys /
        // Quick Actions) or stays a regular Dock app.
        appState.enterBackground()
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
            guard !hasPrimary, let appState else { return true }
            appState.activateMainWindow()
            return false
        }
    }

    /// Block quit when losable work is in flight (an active recording / unsaved
    /// edit) to show the leave prompt; otherwise stop a kept-alive Reactotron
    /// session so we don't orphan the listener or the reverse tunnel. Both defer
    /// termination and reply once resolved.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState else { return .terminateNow }
        return MainActor.assumeIsolated {
            // From here on, window closes belong to quit teardown, not
            // background mode. Cleared again if the quit gets cancelled
            // (`AppState.cancelDeferredQuit`).
            isQuitting = true
            // The leave prompt's resolution (quit / cancel) drives termination.
            if !appState.requestQuit() { return .terminateLater }
            guard appState.reactotronSession.isRunning else { return .terminateNow }
            Task { @MainActor in
                await appState.reactotronSession.stopForQuit()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
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

@main
struct ADTApp: App {
    @State private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("sidebarWidth") private var sidebarWidth = 300.0
    @AppStorage(sidebarAutoHideDefaultsKey) private var sidebarAutoHide = false
    /// The user-chosen accent and font. Read here so changing them re-renders
    /// the scene and re-keys RootView (`.id`), forcing every `.brandAccent`
    /// and `Font.app` to re-resolve.
    @AppStorage(accentColorDefaultsKey) private var accentHex = ""
    @AppStorage(appFontFamilyDefaultsKey) private var appFontFamily = ""
    @AppStorage(appFontSizeScaleDefaultsKey) private var appFontSizeScale = 1.0

    /// One key covering every appearance pref the view tree resolves statically.
    private var appearanceKey: String { "\(accentHex)|\(appFontFamily)|\(appFontSizeScale)" }

    /// ⌃1…⌃9 accelerators for jumping straight to a tab by position.
    private static let tabDigitKeys: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    /// ⌘1…⌘9 then ⌘0 — the first ten sidebar rows, app-wide (the Go menu).
    private static let sidebarDigitKeys: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    /// The sidebar and notifications panel are fixed-width, so opening the
    /// notifications panel on a narrow window would otherwise crush the detail
    /// pane to uselessness (the welcome title wrapping one letter per line).
    /// Grow the window's minimum width with whichever side panels are showing,
    /// so the detail pane always keeps at least `detailMinWidth`.
    private var minWindowWidth: CGFloat {
        // A split needs room for two usable panes side by side (2 × 320 + the
        // seam); a single pane needs one. Without this the split overflows when
        // the window is small.
        let detailMinWidth: CGFloat = appState.isSplit ? 648 : 360
        let notifications: CGFloat = appState.showNotifications ? 321 : 0
        // An auto-hidden sidebar overlays the content, so it costs no width.
        let sidebar: CGFloat = appState.sidebarVisible && !sidebarAutoHide
            ? CGFloat(min(max(sidebarWidth, 300), 460))
            : 0
        // The content is laid out at window ÷ fontScale then scaled up, so the
        // window must be fontScale× wider to give the layout the same logical
        // room — otherwise zooming in (⌘=) crushes the panes.
        return max(760, sidebar + detailMinWidth + notifications) * appState.fontScale
    }

    /// Menu title for the Go menu's n-th slot — the live feature name so the
    /// menu doubles as a legend for the ⌘-digit shortcuts.
    /// Terminal-tab commands act on the visible terminal strip, so they enable
    /// only while the Terminal feature is the active tab and has a shell open.
    private var terminalCommandsEnabled: Bool {
        appState.activeTabID == "terminal" && !appState.terminals.tabs.isEmpty
    }

    private func sidebarShortcutTitle(_ rank: Int) -> String {
        let features = appState.orderedSidebarMatches
        guard features.indices.contains(rank) else { return "Sidebar Item \(rank + 1)" }
        return "Open \(features[rank].title)"
    }

    init() {
        // HotkeyManager.install is deferred to RootView.onAppear — Carbon
        // hot-key registration needs a running event loop, which App.init
        // predates.
        _appState = State(initialValue: AppState(env: AppEnvironment()))
        // Count this launch for the star-nudge threshold (gated in RootView).
        // Telemetry is anonymous and on by default; start it as early as possible.
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: "launchCount") + 1, forKey: "launchCount")
        Telemetry.shared.start()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(appState)
                .frame(minWidth: minWindowWidth, minHeight: 480)
                // Force the brand accent on standard controls (prominent
                // buttons, switches, sliders) so they stay green regardless of
                // the Mac's system accent color, which otherwise overrides the
                // AccentColor asset.
                .tint(.brandAccent)
                // Re-key on the appearance prefs so changing the accent or font
                // rebuilds the tree and every `.brandAccent`/`Font.app`
                // re-resolves. AppState (and its device list) is owned above
                // this view, so the rebuild preserves it.
                .id(appearanceKey)
                .onAppear {
                    // Wire the delegate ↔ state references through the adaptor
                    // instance: on macOS `NSApp.delegate` is SwiftUI's own
                    // wrapper, so casting it to `AppDelegate` fails silently.
                    appDelegate.appState = appState
                    appState.appDelegate = appDelegate
                }
                .onChange(of: scenePhase) { _, phase in
                    appState.setForeground(phase == .active)
                }
        }
        .windowStyle(.automatic)
        .commands {
            ScreenshotEditCommandsMenu()

            // ⌘N belongs to the Terminal, not "New Window" — a second window of
            // this single-workspace app was never useful. Replacing .newItem
            // removes the stock New Window item and its shortcut.
            CommandGroup(replacing: .newItem) {
                Button("New Terminal") {
                    appState.activateMainWindow()
                    appState.requestFeature("terminal")
                    appState.terminals.newTab()
                }
                .keyboardShortcut("n", modifiers: .command)

                // ⌘D/⇧⌘D split the focused pane, iTerm-style; the new shell
                // starts in that pane's working directory.
                Button("Split Terminal Vertically") {
                    appState.terminals.splitActivePane(.vertical)
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!terminalCommandsEnabled)

                Button("Split Terminal Horizontally") {
                    appState.terminals.splitActivePane(.horizontal)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!terminalCommandsEnabled)

                Button("Close Terminal") {
                    if let id = appState.terminals.activeID { appState.closeTerminalShell(id) }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!terminalCommandsEnabled)

                Button("Rename Terminal…") {
                    appState.terminals.requestRenameActiveTab()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!terminalCommandsEnabled)

                Divider()

                Button("Next Terminal") { appState.terminals.cycle(by: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(!terminalCommandsEnabled)
                Button("Previous Terminal") { appState.terminals.cycle(by: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(!terminalCommandsEnabled)
            }

            CommandMenu("Tab") {
                // ⌘T opens the search palette; the chosen feature opens in a
                // tab (a new one, or refocuses it if already open).
                Button("New Tab") {
                    appState.activateMainWindow()
                    appState.openPalette?()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") { appState.closeActiveTab() }
                    .keyboardShortcut("w", modifiers: .command)

                Divider()

                // Control-based so they don't fight the form fields' Tab focus
                // traversal or the palette's ⌘1–9 result jumps.
                Button("Next Tab") { appState.selectNextTab() }
                    .keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab") { appState.selectPreviousTab() }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])

                Divider()

                ForEach(Array(Self.tabDigitKeys.enumerated()), id: \.offset) { index, key in
                    Button("Show Tab \(index + 1)") { appState.selectTab(index: index) }
                        .keyboardShortcut(key, modifiers: .control)
                }
            }

            // ⌘1…⌘9/⌘0 open the first ten sidebar rows from anywhere in the
            // app — the same numbering the sidebar's ⌘-held badges show.
            CommandMenu("Go") {
                ForEach(Array(Self.sidebarDigitKeys.enumerated()), id: \.offset) { rank, key in
                    Button(sidebarShortcutTitle(rank)) {
                        appState.activateMainWindow()
                        appState.openSidebarFeature(rank: rank)
                    }
                    .keyboardShortcut(key, modifiers: .command)
                }
            }

            CommandGroup(replacing: .appInfo) {
                Button("About Droidective") {
                    appState.activateMainWindow()
                    appState.requestFeature("about")
                }
                #if !APPSTORE
                CheckForUpdatesCommand(updater: SparkleUpdater.shared)
                #endif
            }

            // The stock ⌘, opens Settings without bringing the app forward, so
            // it lands hidden behind the floating, non-activating Quick Actions
            // panel. Replace it with one that dismisses the panel and activates
            // the app first.
            CommandGroup(replacing: .appSettings) {
                OpenSettingsButton()
            }

            CommandGroup(replacing: .help) {
                Button("Report an Issue…") { appState.reportBug() }
                Button("Request a Feature…") { appState.requestFeature() }
                Divider()
                Button("Droidective on GitHub") { appState.openRepository() }
                Button("Release Notes") { appState.openReleases() }
            }

            CommandGroup(after: .textEditing) {
                Button("Find Feature") {
                    appState.openPalette?()
                }

                Button("Manage Features") {
                    appState.activateMainWindow()
                    appState.requestFeature("catalog")
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                // SwiftTerm ships a find bar but SwiftUI's stock Edit menu has
                // no Find items to reach it — wire them for the focused shell.
                // Disabled outside the Terminal so ⌘F falls through to views
                // with their own find (e.g. the JS console's filter).
                Button("Find in Terminal…") {
                    appState.terminals.activeSession?.showFindBar()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!terminalCommandsEnabled)

                Button("Find Next") {
                    appState.terminals.activeSession?.findNext()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!terminalCommandsEnabled)

                Button("Find Previous") {
                    appState.terminals.activeSession?.findPrevious()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!terminalCommandsEnabled)
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    appState.toggleSidebar()
                }
                .keyboardShortcut("b", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    appState.increaseFontSize()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Font Size") {
                    appState.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)

                // ⇧⌘0 — plain ⌘0 belongs to the Go menu's tenth sidebar row.
                Button("Actual Size") {
                    appState.resetFontSize()
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }
        }

        // The pop-out screen mirror (the mirror control bar's window button,
        // also listed in the Window menu). Sized like a phone by default.
        Window("Screen Mirror", id: MirrorWindow.windowID) {
            MirrorWindowView()
                .environment(appState)
                .tint(.brandAccent)
                .id(appearanceKey)
        }
        .defaultSize(width: 420, height: 850)

        Settings {
            SettingsView()
                .environment(appState)
                .tint(.brandAccent)
                .id(appearanceKey)
        }

        MenuBarExtra("Droidective", systemImage: "iphone.gen3", isInserted: $showMenuBarExtra) {
            MenuBarView()
                .environment(appState)
        }
    }
}

/// Settings… menu item (⌘,). Opens the SwiftUI Settings scene, but first
/// closes the Quick Actions panel and activates the app so the Settings window
/// comes to the front instead of behind the panel's floating level.
private struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            FloatingPanelController.quickActions.close()
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

struct MenuBarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let device = state.selectedDevice {
            Text(device.label)
        } else {
            Text("No device")
        }
        Divider()

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
