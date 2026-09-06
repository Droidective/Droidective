import ADBKit
import AppKit
import Foundation
import Observation
import SwiftUI

/// UserDefaults key for the sidebar's Dock-style auto-hide mode — spelled
/// once, read via `@AppStorage` in the views and directly here.
let sidebarAutoHideDefaultsKey = "sidebarAutoHide"

/// A tappable follow-up a toast / notification row can carry, rendered as a
/// button (see `AppState.performNotificationAction`).
enum NotificationAction: Equatable, Sendable {
    /// Download and install an announced update (relaunches when done).
    case updateNow
    /// Relaunch into an update that's already downloaded and staged.
    case relaunchToUpdate
    /// Open the changelog modal for the update that just installed.
    case showWhatsNew

    var buttonTitle: String {
        switch self {
        case .updateNow: return "Update Now"
        case .relaunchToUpdate: return "Relaunch"
        case .showWhatsNew: return "What's New"
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Level: Equatable {
        case success, info, warning, error
    }

    let id = UUID()
    let message: String
    let ok: Bool
    let level: Level
    var copyText: String?
    var revealPath: String?
    var action: NotificationAction?
    /// Whether this is kept in the notifications history. Errors and warnings
    /// always are; a success only when it produced an artifact (a reveal
    /// path) — routine confirmations like "Copied" are dropped.
    let important: Bool
    /// Whether this also becomes a macOS notification. Defaults to
    /// `important`, so what the notification bar keeps, Notification Center
    /// keeps too — foreground included, since a 5s overlay is missable and
    /// nothing else outlives it. Install per-APK toasts opt out because the
    /// batch posts one summary instead.
    let postsSystemNotification: Bool

    init(
        message: String,
        ok: Bool,
        level: Level? = nil,
        copyText: String? = nil,
        revealPath: String? = nil,
        action: NotificationAction? = nil,
        important: Bool? = nil,
        postsSystemNotification: Bool? = nil
    ) {
        self.message = message
        self.ok = ok
        let resolved = level ?? (ok ? .success : .error)
        self.level = resolved
        self.copyText = copyText
        self.revealPath = revealPath
        self.action = action
        let resolvedImportant = important
            ?? (resolved == .error || resolved == .warning || revealPath != nil)
        self.important = resolvedImportant
        self.postsSystemNotification = postsSystemNotification ?? resolvedImportant
    }
}

/// A notification kept in the history panel — the important subset of toasts.
struct AppNotification: Identifiable, Equatable {
    let id: UUID
    let message: String
    let level: Toast.Level
    var copyText: String?
    var revealPath: String?
    var action: NotificationAction?
    let date: Date
}

/// One window's workspace: its device, its tabs, its terminals and consoles.
///
/// The app can have several — see `AppCore`, which owns whatever must exist
/// once (the device poll, the tool caches, the feature curation, the Reactotron
/// and MCP listeners) and hands each window an instance of this. Everything
/// app-wide is forwarded below, so a feature view reads `state.devices` or
/// `state.layout` without knowing which window it's in.
@MainActor
@Observable
final class AppState {
    /// The app-wide half. Every window shares one.
    let core: AppCore
    /// This window's stable identity for the session — the key into
    /// `AppCore`'s registry and the persisted `WindowState`.
    let id: WorkspaceID

    var env: AppEnvironment { core.env }

    /// APK Studio's loaded-APK session. In-memory, so it resumes across
    /// navigation within a run and is cleared when the app quits (the decompiled
    /// cache is wiped alongside it — see `AppDelegate.applicationWillTerminate`).
    let apkStudio = ApkStudioSession()

    /// The Finder-opened-APK screen's files (the `apk-open` workspace tab —
    /// deliberately not a registry feature; it exists only when a file
    /// arrives). In-memory like the studio session.
    let apkOpen = ApkOpenSession()

    /// Switch via `requestDevice(_:)`, not direct assignment — that routes the
    /// change through the leave guard so an active recording isn't lost, and
    /// keeps the core's registry (which window owns which device) in step.
    private(set) var selectedSerial: String?
    var runOnAll = false
    var searchText = ""
    /// The sidebar/palette's keyboard-navigation highlight (↑/↓ while searching).
    /// Transient (not persisted) and separate from the active tab, so arrowing
    /// through results moves a highlight without opening a tab per keystroke —
    /// only ⏎ / click / ⌘<n> opens one.
    var searchHighlightID: String?
    /// The editor-group workspace (VS Code-style split panes): one pane = no
    /// split, two = a left/right split. Each pane owns its tabs and active tab; a
    /// feature is open in at most one pane, so dragging a tab between panes MOVES
    /// it. All the multi-pane rules (collapse, cap, uniqueness, focus, never
    /// empty) live in the pure, tested `Workspace`; mutate via the methods below
    /// so each change persists. Tabs stay mounted, so switching within a pane
    /// never destroys in-flight work — the leave guard fires on *closing* a tab
    /// (or quitting), not on switching.
    private(set) var workspace = Workspace(fallback: "home")

    /// The tab *this* window is dragging, or nil — which is the question every
    /// existing caller asks (fade the original chip, suppress its own
    /// guideline). The drag itself lives on `AppCore` because it can end in
    /// another window; `anyTabDrag` is the app-wide view of it.
    var draggingTabID: String? {
        get { core.tabDrag.flatMap { $0.source == id ? $0.featureID : nil } }
        set {
            if let newValue {
                core.tabDrag = TabDrag(featureID: newValue, source: id)
            } else if core.tabDrag?.source == id {
                core.tabDrag = nil
            }
        }
    }

    /// The focused pane's active tab: drives the device bar, sidebar highlight,
    /// and window title.
    var activeTabID: String? { workspace.activeTab }
    /// Both panes' active tabs — the sidebar highlights all of them.
    var activeTabIDs: Set<String> { workspace.activeTabs }
    /// True when the workspace is split into two panes.
    var isSplit: Bool { workspace.isSplit }
    /// The open tabs of pane `index` (empty if that pane doesn't exist).
    func openTabIDs(inGroup index: Int) -> [String] { workspace.openTabs(inGroup: index) }
    /// Every open tab across both panes — the performance monitor sends these
    /// with a resource incident so spikes are attributable to a feature.
    var openFeatureIDs: [String] { workspace.groups.flatMap(\.openTabs) }
    /// The active tab of pane `index`.
    func activeTab(inGroup index: Int) -> String? { workspace.activeTab(inGroup: index) }
    var toasts: [Toast] = []
    /// History of important notifications (errors, warnings, key wins), newest
    /// first. Routine success toasts are not kept.
    var notifications: [AppNotification] = []
    #if !APPSTORE
    /// The changelog of the update that installed at this launch (consumed
    /// from the stash by RootView's launch setup). Held for the session so
    /// the "What's New" notification button can open it any time.
    var whatsNew: UpdaterViewModel.WhatsNew?
    /// Presents the changelog sheet (see `WhatsNewPresenter` on RootView).
    var presentWhatsNew = false
    #endif
    /// Whether the notifications side panel is open.
    var showNotifications = false
    /// Important notifications arrived since the panel was last opened.
    var unreadNotifications = 0
    /// The row a clicked macOS notification asked for: scrolled to and
    /// flashed once, then cleared by the panel so it doesn't re-flash on
    /// every later render.
    var focusedNotification: UUID?
    var isRunningFeature = false

    // Layout toggle: ⌘B (sidebar).
    var sidebarVisible = true
    /// Drives the first-launch / replayable welcome tour sheet.
    var presentTour = false
    /// True while the tour's final "try Quick Actions" page is on screen —
    /// pressing the hotkey there finishes the tour with confetti (see TourView).
    var awaitingQuickActionsTry = false
    /// Bumped to fire a confetti burst over the main window (see
    /// `ConfettiCelebration` in RootView).
    var confettiTrigger = 0

    /// Called whenever the Quick Actions panel opens. While the tour's final
    /// page is waiting for it, the open finishes the tour — marks it seen,
    /// closes the sheet, and pops confetti.
    func noteQuickActionsOpened() {
        guard awaitingQuickActionsTry else { return }
        awaitingQuickActionsTry = false
        // The tour's own @AppStorage("hasSeenTour") readers observe this.
        UserDefaults.standard.set(true, forKey: "hasSeenTour")
        presentTour = false
        confettiTrigger += 1
    }

    /// Ends the tour without the Quick Actions try — Skip, Finish, or an Esc
    /// dismissal. Marks it seen so it never re-presents; no confetti (that's
    /// the reward for pressing the hotkey for real).
    func endTour() {
        awaitingQuickActionsTry = false
        UserDefaults.standard.set(true, forKey: "hasSeenTour")
        presentTour = false
    }
    /// Drives the first-launch role picker (a full-window takeover) and the
    /// "Change role" flow. Picking a role seeds a curated feature set.
    var presentRolePicker = false
    /// Owners of an in-flight performance/network/screen recording, keyed by
    /// feature id. The device and bundle pickers lock while any recording runs,
    /// so a second recorder in another tab can't have the device switched out
    /// from under it when the first one stops.
    private(set) var recordingOwners: Set<String> = []

    /// True while any recording is in flight — locks the device/bundle pickers.
    var recordingActive: Bool { !recordingOwners.isEmpty }

    /// Mark a recording started/stopped for `owner` (its feature id).
    func setRecording(_ active: Bool, owner: String) {
        if active {
            recordingOwners.insert(owner)
        } else {
            recordingOwners.remove(owner)
        }
    }

    /// Views holding losable work (an active recording, unsaved editor edits)
    /// register a guard here, keyed by the owning tab's feature id, so closing
    /// that tab — or switching device / quitting — routes through `pendingExit`
    /// for confirmation instead of silently discarding the work. Open tabs stay
    /// mounted, so switching tabs is always safe and never consults this.
    private(set) var exitGuards: [String: ExitGuard] = [:]
    /// A navigation deferred until the user resolves the relevant `exitGuards`
    /// entry (close a guarded tab, switch device, or quit with work in flight).
    private(set) var pendingExit: PendingExit?

    /// The JS Console (Hermes CDP) session — owned here so its log buffer and
    /// connection survive leaving the feature, like the Reactotron session.
    /// `var`, not `let`, because it travels with its tab: see `MovedSessions`.
    private(set) var jsConsoleSession: JSConsoleSession

    /// The Terminal feature's shells — owned here so every tab's PTY session
    /// and scrollback survive leaving the feature, and replaceable so they
    /// survive the tab moving to another window too (`MovedSessions`).
    private(set) var terminals = TerminalManager()

    /// With auto-hide on (Settings ▸ Appearance), the sidebar rides over the
    /// content instead of sitting in the layout; this is that overlay's
    /// visibility, driven by the left-edge hover zone and ⌘B.
    var sidebarOverlayShown = false

    /// Full View: the app's own chrome — sidebar, device bar, tab strip — is
    /// hidden and the window goes into macOS full screen, so the feature on
    /// screen gets the whole display. Transient by design (a mode you toggle,
    /// never a state you relaunch into), and per window.
    private(set) var fullView = false

    /// Enter or leave Full View, taking the window's native full-screen state
    /// with it. Leaving native full screen by the green button leaves the mode
    /// too — RootView watches for that, so the two can't disagree.
    func toggleFullView() {
        setFullView(!fullView)
    }

    func setFullView(_ on: Bool) {
        guard fullView != on else { return }
        withAnimation(.easeInOut(duration: 0.2)) { fullView = on }
        if on {
            // With the chrome gone there's no button left in sight for most
            // features, so say how to get back instead of leaving the user to
            // find the menu. Not kept in the notification history.
            showToast(Toast(
                message: "Full view — press ⇧⌘F to leave",
                ok: true, level: .info, important: false))
        }
        guard let window = nsWindow else { return }
        if window.styleMask.contains(.fullScreen) != on {
            window.toggleFullScreen(nil)
        }
    }

    func toggleSidebar() {
        if UserDefaults.standard.bool(forKey: sidebarAutoHideDefaultsKey) {
            withAnimation(.easeInOut(duration: 0.18)) { sidebarOverlayShown.toggle() }
        } else {
            withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
        }
    }

    /// The split divider was dragged past the 30% pane floor — the user wants
    /// more width than the panes can give, so cede the sidebar's. ⌘B (or the
    /// left-edge hover in auto-hide mode) brings it back.
    func hideSidebarForSplitRoom() {
        if UserDefaults.standard.bool(forKey: sidebarAutoHideDefaultsKey) {
            guard sidebarOverlayShown else { return }
            withAnimation(.easeIn(duration: 0.18)) { sidebarOverlayShown = false }
        } else {
            guard sidebarVisible else { return }
            withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible = false }
        }
    }

    /// The device bar's sidebar button. When a split-resize has evicted the
    /// pinned sidebar (fixed mode, `sidebarVisible == false`), the click just
    /// brings it back — it used to be a dead no-op that only worked on the
    /// second press. Otherwise it switches between the fixed sidebar and
    /// Dock-style auto-hide.
    func toggleSidebarMode() {
        let defaults = UserDefaults.standard
        let current = defaults.bool(forKey: sidebarAutoHideDefaultsKey)
        let next = SidebarVisibility.afterButtonPress(autoHide: current, fixedVisible: sidebarVisible)
        withAnimation(.easeInOut(duration: 0.18)) {
            if next.autoHide != current {
                defaults.set(next.autoHide, forKey: sidebarAutoHideDefaultsKey)
            }
            sidebarVisible = next.fixedVisible
            sidebarOverlayShown = next.overlayShown
        }
    }

    /// Reconcile the live flags to a mode the Settings ▸ Appearance toggle just
    /// set (RootView observes the persisted flag and calls this), so that path
    /// and `toggleSidebarMode` can't drift. Idempotent — the button's own flip
    /// re-runs it harmlessly.
    func reconcileSidebarVisibility(autoHide: Bool) {
        let next = SidebarVisibility.afterModeChange(autoHide: autoHide, fixedVisible: sidebarVisible)
        sidebarVisible = next.fixedVisible
        sidebarOverlayShown = next.overlayShown
    }

    // MARK: - Font scaling (⌘= / ⌘- / ⌘0)

    /// UI zoom factors ⌘=/⌘- step through (1.0 = default). macOS doesn't honor
    /// SwiftUI dynamic type, so the window content is scaled instead — which
    /// grows every font, icon, and control together and reflows the layout.
    private static let scales: [Double] = [0.8, 0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]
    private static let defaultScaleIndex = 2

    /// Index into `scales`; persisted so the chosen size survives relaunch.
    var fontScaleStep = AppState.defaultScaleIndex

    /// Applied to the window content via a scaleEffect zoom.
    var fontScale: Double { Self.scales[fontScaleStep] }

    func increaseFontSize() { setFontScale(fontScaleStep + 1) }
    func decreaseFontSize() { setFontScale(fontScaleStep - 1) }
    func resetFontSize() { setFontScale(Self.defaultScaleIndex) }

    private func setFontScale(_ step: Int) {
        fontScaleStep = min(max(step, 0), Self.scales.count - 1)
        UserDefaults.standard.set(fontScaleStep, forKey: "fontScaleStep")
    }

    /// The app bundle this window targets. Per-window, so two devices can be
    /// driven against different apps; a new window inherits the last choice.
    var selectedBundleId: String?
    /// An `.aab` opened from Finder (double-click / Open With), staged for the
    /// AAB to APK feature. The view consumes (clears) it once shown.
    var pendingConvertAAB: URL?
    /// A video opened from Finder ("Open With ▸ Droidective"), staged for the
    /// Video Editor. Consumed by `claimPendingVideo` once the editor has it,
    /// so returning to the tab later doesn't reopen the same file.
    var pendingVideo: URL?
    /// The real app delegate (the adaptor instance, wired in `ADTApp.body`) —
    /// `NSApp.delegate` is SwiftUI's wrapper on macOS, so casting it fails.
    weak var appDelegate: AppDelegate?
    /// This window, resolved by RootView's `WindowAccessor`. Held by
    /// *reference* because identifiers can't be trusted across a close:
    /// SwiftUI re-stamps its own (`main-AppWindow-1`) over any tag, which
    /// broke the ⌘W tab-close monitor after a close → reopen cycle. It's also
    /// how the app-wide event monitors map a key window back to its workspace.
    weak var nsWindow: NSWindow?
    /// Set by RootView; opens the floating ⌘T search palette.
    var openPalette: (() -> Void)?
    struct OperationStatus: Equatable {
        var label: String
        /// 0…1 when the total is known, nil = indeterminate.
        var fraction: Double?
    }

    /// The long-running operation in flight (pull, record, copy…) — the
    /// progress strip under the device bar reflects it.
    var runningOperation: OperationStatus?

    /// APK installs in flight or recently finished (one entry per APK ×
    /// device). The install screens render these live; the progress strip
    /// mirrors the running ones via `installOperation` (AppState+Install).
    var installJobs: [InstallJob] = []

    /// Files being copied onto a device by a drop — one entry per batch per
    /// device, so a Mirror Wall drop shows six independent chips rather than
    /// one toast that can only describe the last one.
    var transferJobs: [TransferJob] = []

    /// The task behind each running transfer, so its chip's ✕ can cancel it.
    /// Ignored by observation: nothing renders a Task, and the dictionary
    /// churns on every batch.
    @ObservationIgnored var transferTasks: [UUID: Task<Void, Never>] = [:]

    /// Whether the one-time "drop files here" hint is on screen. Owned by the
    /// workspace, not the mirror view: that view is rebuilt as its session
    /// changes, and a hint held in its `@State` flashed for a second and was
    /// missed rather than lasting its window.
    var mirrorDropHintVisible = false
    @ObservationIgnored var mirrorDropHintTask: Task<Void, Never>?

    /// Wrap a slow operation so the UI shows what's happening (spinner).
    func withOperation<T: Sendable>(_ label: String, _ work: () async throws -> T) async rethrows -> T {
        // A long task is starting — the in-context moment to ask for
        // notification permission, so its completion can reach a user who
        // switched away (see SystemNotifier).
        SystemNotifier.requestAuthorizationOnce()
        runningOperation = OperationStatus(label: label)
        defer { runningOperation = nil }
        return try await work()
    }

    /// Wrap a pull whose destination grows on disk: progress is the local
    /// file's size against the known source size — a real percentage.
    func withFileProgress<T: Sendable>(
        _ label: String,
        destination: URL,
        expectedBytes: Int?,
        _ work: () async throws -> T
    ) async rethrows -> T {
        guard let expectedBytes, expectedBytes > 0 else {
            return try await withOperation(label, work)
        }
        SystemNotifier.requestAuthorizationOnce()
        runningOperation = OperationStatus(label: label, fraction: 0)
        let poller = Task { [weak self] in
            while true {
                // A plain `try?` here swallows the cancellation thrown by
                // sleep and lets one final status write land AFTER the defer
                // below has cleared the strip — leaving it stuck forever.
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                let written = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? Int ?? 0
                self?.runningOperation = OperationStatus(
                    label: label,
                    fraction: min(1, Double(written) / Double(expectedBytes))
                )
            }
        }
        defer {
            poller.cancel()
            runningOperation = nil
        }
        return try await work()
    }

    // MARK: - Save destinations

    /// Ask where to save one pulled file. nil = user cancelled.
    func askSaveLocation(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = try? ScreenCaptureService.ensureCaptureDir()
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Ask for a folder to receive several pulled files. nil = cancelled.
    func askSaveFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = prompt
        panel.directoryURL = try? ScreenCaptureService.ensureCaptureDir()
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// UserDefaults flag: the one-time capture-folder ask already ran.
    static let captureFolderPromptedKey = "captureFolderPrompted"

    /// One-time ask before the first *silent* save into the capture folder:
    /// keep the ~/Downloads/Droidective default or pick a folder, and note that
    /// Settings ▸ Privacy can change it later. Saves that already show a save
    /// panel don't call this — the user picks a location there anyway.
    func confirmCaptureFolderOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.captureFolderPromptedKey) else { return }
        defaults.set(true, forKey: Self.captureFolderPromptedKey)
        // A folder chosen in Settings before the first save answers the question.
        if let path = defaults.string(forKey: ScreenCaptureService.captureFolderDefaultsKey),
           !path.trimmingCharacters(in: .whitespaces).isEmpty {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Where should Droidective save captures?"
        alert.informativeText = """
        Screenshots, recordings, and other saved files go to Downloads/Droidective \
        unless you pick another folder. You can change this anytime in Settings ▸ Privacy.
        """
        alert.addButton(withTitle: "Use Downloads/Droidective")
        alert.addButton(withTitle: "Choose Folder…")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let folder = askSaveFolder(prompt: "Save captures here") {
            defaults.set(folder.path, forKey: ScreenCaptureService.captureFolderDefaultsKey)
        }
    }
    /// Last result per feature id, shown inline in the detail pane.
    var lastResults: [String: (result: FeatureResult, at: Date)] = [:]

    /// Bring the app forward, reopening this window if it was closed. When
    /// resident in the background (no Dock icon — see `AppDelegate`), rejoin
    /// the Dock first; that policy flip needs a runloop turn before activation
    /// reliably fronts the window, so that path hops once.
    func activateMainWindow() {
        if NSApp.activationPolicy() == .regular {
            bringMainWindowFront()
        } else {
            NSApp.setActivationPolicy(.regular)
            Task { self.bringMainWindowFront() }
        }
        // Window close stopped the JS console's discovery (the view stays
        // mounted, so its lifecycle hooks won't re-fire) — resume it for a
        // still-open tab. Reactotron stays down: its screen offers an explicit
        // Retry, and restarting a server socket shouldn't be a side effect.
        if openFeatureIDs.contains("js-console") {
            jsConsoleSession.start(serials: targetSerials)
        }
        // Same mounted-view caveat for the terminal: the background close
        // killed its shells, so a still-open tab reopens on an empty rail —
        // resume the remembered directories (shells spawn lazily on render).
        if openFeatureIDs.contains("terminal"), terminals.tabs.isEmpty {
            openTerminalResumingWork()
        }
    }

    private func bringMainWindowFront() {
        NSApp.activate(ignoringOtherApps: true)
        // The tracked reference first (identifiers are unreliable across a
        // close); the structural fallback excludes panels, whose KeyablePanel
        // overrides `canBecomeMain` to true.
        if let nsWindow {
            nsWindow.makeKeyAndOrderFront(nil)
        } else {
            // Parked by a background-mode close: reopen with *this* id so the
            // window comes back to its own tabs, not a blank workspace.
            core.reopenWindow(for: id)
        }
        setForeground(true)
    }

    /// Feature opens that arrived before the layout finished loading (e.g. an
    /// APK double-clicked in Finder on cold launch). Replayed after restore.
    private var pendingFeatureOpens: [String] = []
    /// False until this window has taken its persisted state (or been told
    /// there is none). Guards tab persistence the same way `didLoadLayout`
    /// does app-wide — writing before the restore would clobber the file.
    private(set) var didRestore = false
    /// False until a real `NSWindow` has bound to this workspace. Nothing is
    /// written to disk before that, so a workspace SwiftUI asks for but never
    /// shows can't leave a ghost window behind for the next launch.
    private(set) var didBind = false

    /// Called by `AppCore.bind` once this workspace has a window on screen.
    func noteBound() {
        guard !didBind else { return }
        didBind = true
        persistWindowState()
    }

    init(core: AppCore, id: WorkspaceID) {
        self.core = core
        self.id = id
        let savedStep = UserDefaults.standard.object(forKey: "fontScaleStep") as? Int ?? Self.defaultScaleIndex
        fontScaleStep = min(max(savedStep, 0), Self.scales.count - 1)
        jsConsoleSession = JSConsoleSession(adb: core.env.client)
        wireSessions()
    }

    /// Point the per-window sessions back at this window. Called at init and
    /// again whenever one is replaced — either by a session arriving from
    /// another window, or by the fresh one left behind when it leaves.
    private func wireSessions() {
        jsConsoleSession.app = self
        // Typing `exit` (or a shell crash) closes that tab like the × does.
        // The contains-check drops late callbacks racing a killAll teardown.
        terminals.onShellExited = { [weak self] id in
            guard let self, self.terminals.tabs.contains(where: { $0.id == id }) else { return }
            self.closeTerminalShell(id)
        }
    }

    /// This window's model for `feature`, built on first use and kept until
    /// the tab closes — the state a feature wants to survive its view being
    /// rebuilt (a log buffer, a fetched list). See `FeatureStateStore`.
    func featureState<T: AnyObject>(
        _ type: T.Type, for feature: String, make: () -> T
    ) -> T {
        core.featureStates.model(type, feature: feature, in: id, make: make)
    }

    /// The live per-window work a moving tab takes with it.
    ///
    /// A feature whose state lives in an object owned by the *window* — the
    /// terminal's PTYs and scrollback, the JS console's CDP connection and
    /// console history — would otherwise be torn down here and rebuilt there,
    /// which is a restart wearing a move's clothes. The object crosses instead,
    /// and the window it left gets a fresh one so it keeps working.
    ///
    /// Only features whose work outlives their view need an entry: everything
    /// else either rebuilds cheaply or is already app-wide (the Reactotron
    /// relay, which no window owns).
    struct MovedSessions {
        var terminals: TerminalManager?
        var jsConsole: JSConsoleSession?
        /// The moving tab's `FeatureStateStore` model, if it keeps one — the
        /// buffer or loaded work a rebuilt view would otherwise start without.
        var featureState: AnyObject?
        /// Which feature `featureState` belongs to.
        var featureID: String?

        var isEmpty: Bool { terminals == nil && jsConsole == nil && featureState == nil }
    }

    /// Hand `featureID`'s live session over, leaving a fresh one behind.
    func takeMovableSessions(for featureID: String) -> MovedSessions {
        var moved = MovedSessions()
        switch featureID {
        case TabHandoff.terminalFeatureID:
            moved.terminals = terminals
            terminals = TerminalManager()
        case "js-console":
            moved.jsConsole = jsConsoleSession
            jsConsoleSession = JSConsoleSession(adb: core.env.client)
        default:
            break
        }
        // Every feature may have one, so this is not part of the switch: the
        // store answers nil for the ones that keep nothing.
        moved.featureID = featureID
        moved.featureState = core.featureStates.take(feature: featureID, in: id)
        if moved.terminals != nil || moved.jsConsole != nil { wireSessions() }
        return moved
    }

    /// Sessions taken by `detachTab`, waiting for the receiving window. Held
    /// for the length of one handoff only; `AppCore` collects it immediately.
    var pendingMovedSessions = MovedSessions()

    /// Take live sessions arriving with a tab from another window.
    func adoptMovableSessions(_ moved: MovedSessions) {
        guard !moved.isEmpty else { return }
        if let featureID = moved.featureID {
            core.featureStates.put(moved.featureState, feature: featureID, in: id)
        }
        guard moved.terminals != nil || moved.jsConsole != nil else { return }
        if let terminals = moved.terminals { self.terminals = terminals }
        if let jsConsole = moved.jsConsole { jsConsoleSession = jsConsole }
        wireSessions()
    }

    /// Adopt this window's persisted state, or start fresh when `saved` is nil
    /// (a window the user opened rather than one being reopened at launch).
    /// Called once, by `AppCore`, as soon as the layout has loaded.
    func restore(from saved: WindowState?) {
        guard !didRestore else { return }
        didRestore = true
        if let saved {
            selectedSerial = saved.serial
            selectedBundleId = saved.bundleId
            terminalResumeDirs = saved.terminalResumeDirs
            mirrorWallSerials = saved.mirrorWallSerials
            // Reopen the tabs from the last session (idle — recordings/streams
            // don't resume). Falls back to a single Home tab for a new user or
            // a layout written before tabs existed.
            workspace = Workspace(
                restoring: saved.tabGroups ?? [],
                focusedGroup: saved.focusedGroup,
                fallback: "home",
                isValidID: Self.isValidTabID
            )
        } else {
            // A new window: target the device it was opened for (or the first
            // one no other window is showing) and inherit the last app bundle.
            selectedBundleId = core.lastSelectedBundleId
            selectedSerial = core.windowSeedTarget(id) ?? firstFreeSerial()
        }
        // Replay feature opens that raced the load (e.g. openAPKs from Finder).
        for pending in pendingFeatureOpens {
            workspace.open(pending)
        }
        pendingFeatureOpens = []
        core.noteSelection(selectedSerial, in: id)
        core.noteOpenFeatures(Set(openFeatureIDs), in: id)
        persistWindowState()
        if selectedSerial != nil { Task { await refreshOverrides() } }
    }

    /// A ready device no other window is showing — what a brand-new window
    /// lands on, so opening a second window usually needs no further clicks.
    /// Falls back to any ready device when every one is already claimed.
    private func firstFreeSerial() -> String? {
        let ready = core.readyDevices.map(\.serial)
        return core.registry.unclaimed(from: ready).first ?? ready.first
    }

    /// Reconcile this window's selection against a new device list: drop a
    /// device that left, adopt one when we had none, and refetch overrides
    /// when either happened.
    func reconcileSelection(among devices: [Device]) {
        let ready = devices.filter(\.isReady)
        // "Run on all" only makes sense with more than one device.
        if ready.count <= 1, runOnAll {
            runOnAll = false
            persistSelection()
        }
        let before = selectedSerial
        if let selectedSerial, !devices.contains(where: { $0.serial == selectedSerial }) {
            // Prefer a device no other window has taken, so two windows don't
            // collapse onto the same device when one unplugs.
            self.selectedSerial = core.registry.unclaimed(from: ready.map(\.serial))
                .first { $0 != selectedSerial } ?? ready.first?.serial
        } else if selectedSerial == nil, didRestore {
            selectedSerial = firstFreeSerial()
        }
        if selectedSerial != before {
            core.noteSelection(selectedSerial, in: id)
            persistWindowState()
        }
        // Refetch overrides when the selection changed, or once when the
        // selected device becomes ready — not on every unrelated device-list
        // change (an empty override set is the common steady state, so
        // "empty" alone can't mean "never loaded").
        let readySelected = selectedDevice?.isReady == true
        if selectedSerial != before || (readySelected && overridesFetchedForSerial != selectedSerial) {
            Task { await refreshOverrides() }
        }
    }

    // MARK: - Overrides

    var activeOverrides: [ActiveOverride] = []
    /// The ready serial the overrides were last fetched for; nil until the
    /// selected device has been probed. Gates the devices-changed refetch.
    private var overridesFetchedForSerial: String?

    func refreshOverrides() async {
        guard let device = selectedDevice, device.isReady else {
            activeOverrides = []
            overridesFetchedForSerial = nil
            return
        }
        overridesFetchedForSerial = device.serial
        switch device.platform {
        case .android:
            activeOverrides = (try? await env.engine.overrides.active(serial: device.serial)) ?? []
        case .iosSimulator:
            activeOverrides = await env.engine.simulators.activeOverrides(udid: device.serial)
        }
    }

    func resetOverride(_ kind: OverrideKind) {
        guard let device = selectedDevice else { return }
        Task {
            await CommandLog.userInitiated {
                do {
                    switch device.platform {
                    case .android:
                        try await env.engine.overrides.reset(serial: device.serial, kind: kind)
                    case .iosSimulator:
                        try await env.engine.simulators.reset(udid: device.serial, kind: kind)
                    }
                    showToast(Toast(message: "\(kind.label) reset", ok: true))
                } catch {
                    showToast(Toast(message: error.localizedDescription, ok: false))
                }
            }
            await refreshOverrides()
        }
    }

    func resetAllOverrides() {
        guard let device = selectedDevice else { return }
        Task {
            await CommandLog.userInitiated {
                do {
                    switch device.platform {
                    case .android:
                        try await env.engine.overrides.resetAll(serial: device.serial)
                    case .iosSimulator:
                        try await env.engine.simulators.resetAll(udid: device.serial)
                    }
                    showToast(Toast(message: "All overrides reset", ok: true))
                } catch {
                    showToast(Toast(message: error.localizedDescription, ok: false))
                }
            }
            await refreshOverrides()
        }
    }

    var selectedDevice: Device? {
        devices.first { $0.serial == selectedSerial }
    }

    /// Serials a device-scoped feature should run against. The selected
    /// device always comes first so single-device views (`targetSerials
    /// .first`) show the device the bar displays, even with run-on-all on.
    var targetSerials: [String] {
        let ready = devices.filter(\.isReady)
        let selected = ready.first { $0.serial == selectedSerial }
        if effectiveRunOnAll {
            var serials = ready.map(\.serial)
            if let selected, let index = serials.firstIndex(of: selected.serial) {
                serials.swapAt(0, index)
            }
            return serials
        }
        return selected.map { [$0.serial] } ?? []
    }

    /// Whether the focused tab's feature offers "Run on all devices". The toggle
    /// only appears — and only takes effect — for this curated set (see
    /// `FeatureRegistry.runAllFeatureIDs`); everything else is single-device.
    var activeFeatureSupportsRunAll: Bool {
        guard let id = activeTabID, let feature = FeatureRegistry.byID[id] else { return false }
        return feature.supportsRunAll
    }

    /// Run-on-all actually in effect: the toggle is on AND the active feature
    /// supports it. Gating fan-out here (not just on the raw `runOnAll`) means a
    /// toggle left on from a supported feature can never silently fan out onto a
    /// single-device one.
    var effectiveRunOnAll: Bool { runOnAll && activeFeatureSupportsRunAll }

    /// Drop a wireless adb connection (one device, or all when `target` is nil).
    /// USB/emulator devices can't be disconnected this way — the device bar
    /// only offers this for wireless devices.
    func disconnectWireless(target: String?) {
        let connection = env.engine.connection
        Task {
            await CommandLog.userInitiated {
                do {
                    let result = try await connection.disconnect(target: target)
                    showToast(Toast(message: result.message, ok: result.ok, important: true))
                } catch {
                    showToast(Toast(message: error.localizedDescription, ok: false))
                }
            }
        }
    }

    // MARK: - Leave guard (protect in-flight recordings / unsaved edits)

    /// Work that navigating away would destroy. `style` picks the confirmation's
    /// copy and button set: a recording offers Stop & save, an edit doesn't.
    struct ExitGuard: Equatable, Identifiable {
        enum Style: Equatable { case recording, edits }
        let id: UUID
        /// The feature id of the tab that owns this guard, so closing a tab can
        /// tell whether *its* work is the work at stake.
        var featureID: String
        var style: Style
        var title: String
        var message: String
    }

    /// A navigation held back until the user resolves the active `ExitGuard`.
    struct PendingExit: Equatable {
        /// `handoff` moves a tab to another window, which unmounts its view
        /// exactly as closing it does — so it is held behind the same guard.
        enum Target: Equatable {
            case closeTab(String), device(String), quit
            case handoff(String, HandoffDestination)
        }
        var target: Target
        /// Flips true when the user chooses "Stop & save": the active view runs
        /// its own save, then calls `finishExitSave()`. The dialog hides while
        /// the save is in flight.
        var saving = false
    }

    /// Register (or replace) the leave guard for a tab. A protected view calls
    /// this when losable work begins, and `clearExitGuard` when it ends.
    func setExitGuard(_ value: ExitGuard) { exitGuards[value.featureID] = value }

    /// Hold a navigation behind the active leave confirmation. `pendingExit` is
    /// `private(set)` so only the paths that know how to resolve it can arm it.
    func holdBehindGuard(_ target: PendingExit.Target) {
        pendingExit = PendingExit(target: target)
    }

    /// Clear the guard identified by `id`, wherever it's keyed — so a torn-down
    /// view can't wipe a guard a newer view just registered (ids are unique).
    func clearExitGuard(_ id: UUID) {
        exitGuards = exitGuards.filter { $0.value.id != id }
    }

    /// The guard the pending leave confirmation is about: the closing tab's
    /// guard, or any active guard when switching device / quitting.
    var pendingGuard: ExitGuard? {
        switch pendingExit?.target {
        case .closeTab(let id), .handoff(let id, _): return exitGuards[id]
        case .device, .quit: return exitGuards.values.first
        case nil: return nil
        }
    }

    /// Whether the pending leave would destroy `featureID`'s work — true for a
    /// close of that exact tab, or any device-switch / quit (which leaves every
    /// tab). A guarded view's save-on-leave gates on this so closing one tab
    /// can't make a different tab save.
    func pendingExitConcerns(_ featureID: String) -> Bool {
        switch pendingExit?.target {
        case .closeTab(let id), .handoff(let id, _): return id == featureID
        case .device, .quit: return true
        case nil: return false
        }
    }

    /// Whether a tab is actively recording — drives its red pulse in the tab
    /// strip. A `.recording` guard is registered exactly while screen/mirror
    /// recording or while a performance/network capture holds unexported samples.
    func tabIsRecording(_ id: String) -> Bool {
        exitGuards[id]?.style == .recording
    }

    /// Open `id`, or refocus it wherever it's already open. Every feature open
    /// (sidebar, palette, menu, hotkeys, Finder) routes through here; a not-yet-
    /// open feature lands in the focused group. Switching is always safe (tabs
    /// stay mounted), so there's no leave guard.
    func requestFeature(_ id: String) {
        Telemetry.shared.trackFeatureUsed(id, kind: FeatureRegistry.byID[id]?.kind.rawValue ?? "view")
        guard didRestore else {
            // This window hasn't taken its persisted state yet; record the open
            // so `restore` can replay it without a default clobbering disk.
            pendingFeatureOpens.append(id)
            return
        }
        workspace.open(id)
        persistTabs()
    }

    /// This window's device-icon color, or nil to use the app accent. Only the
    /// windows *after* the first take one, so a single-window session and the
    /// original window both keep the accent the rest of the app uses.
    var deviceTint: Color? {
        guard let ordinal = core.registry.ordinal(of: id) else { return nil }
        return DeviceTint.color(forWindow: ordinal)
    }

    /// What put the "close all terminals?" prompt on screen: closing the
    /// Terminal feature tab, or quitting the app — both kill every live shell,
    /// so both are held until the user confirms losing them (RootView shows
    /// the alert).
    enum TerminalClosePrompt { case closeTab, quit }

    /// Set while the terminal close/quit confirmation is on screen.
    var terminalClosePrompt: TerminalClosePrompt?

    /// Close a tab (in whichever pane holds it). A tab whose view holds losable
    /// work routes through the leave confirmation first, since closing unmounts
    /// the view (which would destroy that work). Closing any other is immediate.
    func closeTab(_ id: String) {
        // Closing the Terminal feature kills every shell — confirm first while
        // any are open. Peeling shells one at a time (⌘W) only lands here once
        // none remain, so that path stays prompt-free. Not an ExitGuard: those
        // also hold device switches, which shells don't care about.
        if id == "terminal", !terminals.tabs.isEmpty {
            terminalClosePrompt = .closeTab
            return
        }
        if exitGuards[id] != nil {
            pendingExit = PendingExit(target: .closeTab(id))
        } else {
            performClose(id)
        }
    }

    /// Resolve the terminal confirmation. Confirming kills every shell and
    /// finishes the held close or quit; cancelling a quit must reply to the
    /// deferred termination (`applicationShouldTerminate` returned
    /// `.terminateLater`), mirroring `cancelExit`.
    func resolveTerminalPrompt(confirmed: Bool) {
        guard let prompt = terminalClosePrompt else { return }
        terminalClosePrompt = nil
        switch prompt {
        case .closeTab:
            if confirmed { performClose("terminal") }
        case .quit:
            if confirmed {
                rememberTerminalDirectories()
                terminals.killAll()
                core.resumeQuit()
            } else {
                core.cancelQuit()
            }
        }
    }

    /// Close every tab in pane `group` except `id` (the strip's context menu).
    /// Home is spared — it rides the strip's permanent house button, not a
    /// chip. Each close routes through `closeTab`, so a guarded tab (a live
    /// recording, open shells) still gets its confirmation instead of being
    /// dropped silently — it stays open if the user cancels.
    func closeOtherTabs(than id: String, inGroup group: Int) {
        for other in openTabIDs(inGroup: group) where other != id && other != "home" {
            closeTab(other)
        }
    }

    /// Close the focused pane's active tab (⌘W).
    func closeActiveTab() {
        // ⌘W inside the Terminal feature peels one split pane, then one shell
        // tab at a time (focus slides to its neighbor); the feature tab itself
        // closes only once no shells remain.
        if workspace.activeTab == "terminal", let shellID = terminals.activeID {
            if terminals.closeActivePane() { return }
            closeTerminalShell(shellID)
            return
        }
        if let id = workspace.activeTab { closeTab(id) }
    }

    /// Close one terminal shell tab (killing its process). Closing the last
    /// shell closes the Terminal feature tab with it — an empty terminal pane
    /// is a dead end. Every shell-closing path (⌘W, the chip ×, the menu bar)
    /// routes through here.
    func closeTerminalShell(_ id: UUID) {
        terminals.close(id)
        if terminals.tabs.isEmpty { closeTab("terminal") }
    }

    /// Close a whole rail group, killing each shell in it. Like single
    /// closes, the Terminal feature tab goes with the last shell.
    func closeTerminalGroup(_ id: UUID) {
        terminals.closeGroup(id)
        if terminals.tabs.isEmpty { closeTab("terminal") }
    }

    /// Give a pane keyboard focus — its `+` focuses it so a new tab lands there.
    func focusGroup(_ index: Int) { workspace.focus(index); persistTabs() }

    func selectNextTab() { workspace.cycleForward(); persistTabs() }
    func selectPreviousTab() { workspace.cycleBackward(); persistTabs() }
    /// Activate the tab at a 0-based index in the focused pane (⌃1–⌃9).
    func selectTab(index: Int) { workspace.activate(index: index); persistTabs() }

    /// Drag-reorder a tab within its own pane so it sits before `targetID`.
    func reorderTab(_ id: String, before targetID: String?) {
        workspace.reorder(id, before: targetID)
        persistTabs()
    }

    /// Move `id` into pane `dest` — dragging a tab to the other pane.
    func moveTab(_ id: String, toGroup dest: Int) {
        workspace.move(id, toGroup: dest)
        persistTabs()
    }

    /// Resolve a strip/pane drop: reorder within the same pane, or move to the
    /// other pane and position it at the drop target.
    func dropTab(_ id: String, intoGroup dest: Int, before targetID: String?) {
        workspace.drop(id, intoGroup: dest, before: targetID)
        persistTabs()
    }

    /// Resolve a tab drop into *this* window, wherever the tab came from.
    ///
    /// One funnel for every strip and pane target, so the cross-window case
    /// can't be handled in one place and forgotten in another; `TabDropRouter`
    /// (pure, in ADBKit) makes the actual decision. A tab from another window
    /// is a handoff routed through `beginHandoff` on its *source*, so a live
    /// recording or open shells still get their confirmation rather than being
    /// dropped silently — and the slot rides along, so a move held behind that
    /// confirmation still lands where it was dropped.
    func acceptTabDrop(_ drag: TabDrag, on target: TabDropRouter.Target) {
        core.tabDrag = nil
        let outcome = TabDropRouter.outcome(
            drag: TabDropRouter.Drag(featureID: drag.featureID, source: drag.source),
            window: id,
            target: target,
            shape: dropShape(for: target))
        switch outcome {
        case .ignore:
            break
        case .place(let group, let before):
            dropTab(drag.featureID, intoGroup: group, before: before)
        case .split:
            splitTab(drag.featureID)
        case .handoff(let source, let group, let before):
            core.workspace(id: source)?.beginHandoff(
                drag.featureID,
                to: .window(id, slot: HandoffSlot(group: group, before: before)))
        }
    }

    /// This window's panes as the drop router sees them.
    private func dropShape(for target: TabDropRouter.Target) -> TabDropRouter.Shape {
        let group = switch target {
        case .strip(let group, _): group
        case .pane(let group): group
        }
        return TabDropRouter.Shape(
            isSplit: isSplit, paneTabCount: openTabIDs(inGroup: group).count)
    }

    /// Whether dropping the tab in flight on `group`'s content would split this
    /// window — what the pane's "Drop to split" preview asks before promising.
    func dropWouldSplit(_ drag: TabDrag?, inGroup group: Int) -> Bool {
        guard let drag else { return false }
        let target = TabDropRouter.Target.pane(group: group)
        return TabDropRouter.outcome(
            drag: TabDropRouter.Drag(featureID: drag.featureID, source: drag.source),
            window: id,
            target: target,
            shape: dropShape(for: target)) == .split
    }

    /// Split the workspace: move `id` into a new second pane.
    func splitTab(_ id: String) {
        workspace.split(id)
        persistTabs()
    }

    private func performClose(_ id: String) {
        workspace.close(id)
        stopBackgroundWork(for: id, reason: .closing)
        // Closing a tab means done with it: its buffer goes too, rather than
        // reappearing the next time the feature is opened.
        core.featureStates.discard(feature: id, in: self.id)
        persistTabs()
    }

    /// Whether `featureID`'s tab can leave this window for another *open* one.
    func canDetachTab(_ featureID: String) -> Bool { workspace.canDetach(featureID) }

    /// Whether it can leave for a window of its own — stricter, because
    /// something has to stay behind (see `Workspace.canDetachToNewWindow`).
    func canDetachTabToNewWindow(_ featureID: String) -> Bool {
        workspace.canDetachToNewWindow(featureID)
    }

    /// Remove `featureID`'s tab and stop the work this window was doing on its
    /// behalf, returning the state that has to travel with it.
    ///
    /// The order matters twice over. The tab leaves the workspace *before* the
    /// registry is told, so an exclusive feature (scrcpy, the JS console) is
    /// released here before the receiving window asks for it — otherwise it
    /// comes up on the collision banner instead of running. And the carry is
    /// read *after* the work is stopped, because stopping the Terminal is what
    /// snapshots its shells' directories.
    func detachTab(_ featureID: String) -> TabHandoff.Carry {
        guard workspace.detach(featureID) != nil else { return .none }
        // Taken before anything is stopped: these keep running and cross to the
        // receiving window, which is what makes a move a move rather than a
        // restart. `stopBackgroundWork` skips exactly these on `.handoff`.
        pendingMovedSessions = takeMovableSessions(for: featureID)
        stopBackgroundWork(for: featureID, reason: .handoff)
        let carry = TabHandoff.Carry(
            terminalResumeDirs: featureID == TabHandoff.terminalFeatureID
                ? terminalResumeDirs : nil,
            mirrorWallSerials: featureID == TabHandoff.mirrorWallFeatureID
                ? mirrorWallSerials : nil)
        persistTabs()
        return carry
    }

    /// Take a tab moved in from another window, with the state it carried and
    /// (for a drag) the slot it was dropped on.
    ///
    /// A feature is open in at most one tab per window, so arriving at a window
    /// that already shows it *merges*: `requestFeature` refocuses the existing
    /// tab and the moved one's view state is discarded. That is the honest read
    /// of the invariant — there is nowhere for a second copy to go.
    func adoptHandoff(_ featureID: String, carrying carry: TabHandoff.Carry, at slot: HandoffSlot?) {
        if let dirs = carry.terminalResumeDirs { terminalResumeDirs = dirs }
        if let serials = carry.mirrorWallSerials { mirrorWallSerials = serials }
        requestFeature(featureID)
        if let slot { dropTab(featureID, intoGroup: slot.group, before: slot.before) }
    }

    /// Why a tab's work is being stopped. A tab that is *moving* keeps the
    /// app-wide sessions it shares with other windows alive across the move.
    enum StopReason { case closing, handoff }

    /// Closing a tab fully stops that feature's background work. Most features
    /// stop when their view unmounts (their `.task` is cancelled on close), but a
    /// few sessions are owned here and kept alive across tab *switches* — so
    /// closing their tab has to tear them down explicitly. A feature is open in at
    /// most one tab, so once it's closed no other tab still needs it.
    private func stopBackgroundWork(for id: String, reason: StopReason) {
        // With MCP on, the relay must survive tab/window close — agents keep
        // querying while the user isn't looking (Settings ▸ MCP turns it off).
        // The relay is app-wide, so another window still showing it keeps it
        // up too: this window's close must not pull the timeline out from
        // under the other one.
        // A *moving* tab is about to reopen in another window, so the relay it
        // shares with every window must survive the gap — stopping it would
        // drop every connected RN client for the sake of a tab that never
        // really closed. `AppCore.reconcileSharedSessions` catches the case
        // where the move somehow didn't land.
        if id == "reactotron", reason == .closing, reactotronSession.isRunning,
           !mcp.keepsRelayAlive,
           !core.featureIsOpenElsewhere("reactotron", excluding: self.id) {
            Task { await reactotronSession.stop() }
        }
        // Both of these travel with a moving tab (`MovedSessions`), so on a
        // handoff the session that is about to keep running in another window
        // has already been handed over and this window holds a fresh one —
        // stopping it here would tear down the wrong thing, and stopping the
        // moved one would undo the move.
        if id == "js-console", reason == .closing {
            jsConsoleSession.stop()
            Task { await jsConsoleSession.removeReverseTunnels() }
        }
        if id == "terminal", reason == .closing {
            // Implicit teardown (feature tab closed, background window close,
            // role reset) — remember the shells' directories before killing
            // them, so the next Terminal open resumes where they were.
            rememberTerminalDirectories()
            terminals.killAll()
        }
    }

    /// Save this window's tabs into the shared layout's per-window record.
    private func persistTabs() {
        core.noteOpenFeatures(Set(openFeatureIDs), in: id)
        persistWindowState()
    }

    /// Write this window's whole record (device, bundle, tabs, terminal-resume
    /// directories) into the shared layout and flush it. No-ops until the
    /// window has restored, so an empty default can't clobber the saved file.
    func persistWindowState() {
        guard didRestore, didBind else { return }
        core.layout.upsertWindow(windowRecord)
        core.persistLayout()
    }

    /// This window as a persisted record. Also what a tab moved out of here
    /// inherits its device and app bundle from (`TabHandoff.seed`), so the two
    /// can't describe a window differently.
    var windowRecord: WindowState {
        WindowState(
            id: id,
            serial: selectedSerial,
            bundleId: selectedBundleId,
            tabGroups: workspace.groups.map {
                TabGroupState(tabs: $0.openTabs, activeTab: $0.activeTab)
            },
            focusedGroup: workspace.focusedGroup,
            terminalResumeDirs: terminalResumeDirs,
            mirrorWallSerials: mirrorWallSerials
        )
    }

    /// Working directories of this window's terminal tabs at the last implicit
    /// teardown — the next Terminal open in *this* window resumes them.
    var terminalResumeDirs: [String]?

    /// Devices this window's Mirror Wall shows, in tile order. Per window (two
    /// windows can watch different sets), and persisted, so a wall arranged for
    /// six devices comes back arranged.
    var mirrorWallSerials: [String]? {
        didSet {
            guard mirrorWallSerials != oldValue else { return }
            persistWindowState()
        }
    }

    /// Tell the conflict rules which devices this window is mirroring outside
    /// its own selection — the wall's live tiles and its pop-out mirror
    /// windows. Replaces the previous set, so a tile that stops streaming
    /// releases its device (see `WorkspaceRegistry.setClaims`).
    func noteMirrorClaims(_ serials: Set<String>, featureID: String) {
        core.noteMirrorClaims(serials, featureID: featureID, in: id)
    }

    /// Ids that can back a tab: every registry feature plus the standalone
    /// Home / About / Catalog screens and the Finder-opened-APK screen.
    private static func isValidTabID(_ id: String) -> Bool {
        FeatureRegistry.byID[id] != nil || ["home", "about", "catalog", "apk-open"].contains(id)
    }

    /// This window closed. Stop the sessions it owns — terminal shells,
    /// JS-console reverse tunnels, and the shared Reactotron relay when no
    /// other window still shows it — so no feature process outlives the UI
    /// (view-owned work like recordings and log streams already dies with its
    /// view). The tabs stay in the persisted record, so reopening restores them
    /// idle.
    func enterBackground() {
        for featureID in openFeatureIDs {
            stopBackgroundWork(for: featureID, reason: .closing)
        }
    }

    /// `AppCore` calls this when the window is gone for good: same teardown as
    /// backgrounding, plus a final write of what the tabs looked like.
    func tearDownForWindowClose() {
        enterBackground()
        persistWindowState()
    }

    /// Role change: back to a single Home tab. The reset drops every open tab
    /// without routing through `performClose`, so stop each one's background
    /// work explicitly — otherwise kept-alive sessions (terminal shells, the
    /// Reactotron server) leak with no UI left to reach them.
    func resetForRoleChange() {
        for featureID in workspace.groups.flatMap(\.openTabs) {
            stopBackgroundWork(for: featureID, reason: .closing)
        }
        workspace.reset()
        persistTabs()
        presentRolePicker = false
    }

    /// Switch the active device, or hold it behind a confirmation when a guard
    /// is active.
    ///
    /// A device another window already shows is not stolen by default: the
    /// picker focuses that window instead (`DeviceBarView`), and only an
    /// explicit "open it here anyway" reaches this with `force`.
    func requestDevice(_ serial: String, force: Bool = false) {
        guard serial != selectedSerial else { return }
        if !force, let owner = core.registry.owner(ofDevice: serial, excluding: id) {
            core.focusWindow(owner)
            return
        }
        if exitGuards.isEmpty {
            applySelection(serial)
        } else {
            pendingExit = PendingExit(target: .device(serial))
        }
    }

    /// Commit a device switch: update the registry (so the other windows'
    /// pickers reflect it immediately), refetch overrides, and persist.
    private func applySelection(_ serial: String?) {
        selectedSerial = serial
        core.noteSelection(serial, in: id)
        persistSelection()
        Task { await refreshOverrides() }
    }

    /// Whether quitting would destroy work in *this* window — an active
    /// recording / unsaved edit, or live terminal shells. `AppCore` walks every
    /// window and prompts them one at a time.
    var blocksQuit: Bool { !exitGuards.isEmpty || !terminals.tabs.isEmpty }

    /// Put this window's quit confirmation on screen. Guards come first: a
    /// recording is the more destructive loss, and `performPendingExit`
    /// resumes the chain either way.
    func beginQuitPrompt() {
        if !exitGuards.isEmpty {
            pendingExit = PendingExit(target: .quit)
        } else if !terminals.tabs.isEmpty {
            terminalClosePrompt = .quit
        }
    }

    /// "Discard" / "Discard changes": drop the at-risk work and run the deferred
    /// navigation. A tab close clears just that tab's guard (and its view aborts
    /// in `.onDisappear` as it unmounts); a device-switch / quit leaves every
    /// tab, so clear them all and let each view abort.
    func discardAndExit() {
        switch pendingExit?.target {
        case .closeTab(let id), .handoff(let id, _): exitGuards[id] = nil
        case .device, .quit: exitGuards.removeAll()
        case nil: break
        }
        performPendingExit()
    }

    /// "Keep recording" / "Keep editing": abandon the pending navigation.
    func cancelExit() {
        let wasQuit = pendingExit?.target == .quit
        pendingExit = nil
        if wasQuit { core.cancelQuit() }
    }

    /// "Stop & save": ask the active view to save (it observes `pendingExit`),
    /// keeping the dialog hidden until it calls `finishExitSave()`.
    func beginExitSave() { pendingExit?.saving = true }

    /// Called by the active view once its save-on-leave finished, to proceed.
    func finishExitSave() { performPendingExit() }

    private func performPendingExit() {
        guard let pending = pendingExit else { return }
        pendingExit = nil
        switch pending.target {
        case .closeTab(let id): performClose(id)
        case .handoff(let id, let destination):
            core.completeHandoff(id, from: self.id, to: destination)
        case .device(let serial): applySelection(serial)
        // This window is clear; the next one with work at stake gets its turn.
        case .quit: core.resumeQuit()
        }
    }

    /// Snapshot the shells' directories on the way out of a quit, so the next
    /// launch resumes them. A quit deferred by an exit guard skips the terminal
    /// prompt entirely, so shells can still be alive here; the prompt-confirmed
    /// path already snapshotted and killed them, leaving the rail empty, so
    /// this doesn't overwrite that snapshot.
    func snapshotTerminalsForQuit() {
        if !terminals.tabs.isEmpty {
            rememberTerminalDirectories()
        }
        persistWindowState()
    }

    // MARK: - Feature running

    /// Open or run a feature from a launch surface (launchpad or sidebar),
    /// recording the engagement for adaptive ranking. Instant/toggle actions
    /// that need no screen fire in place (recorded inside `run`); everything
    /// else opens its detail pane.
    func openFeature(_ feature: FeatureDef) {
        if feature.firesWithoutScreen {
            Task { await run(feature: feature, params: [:]) }
        } else {
            noteFeatureUse(feature.id)
            requestFeature(feature.id)
        }
    }

    /// Record one engagement with a feature, persisted for adaptive launchpad
    /// ranking across launches.
    func noteFeatureUse(_ featureID: String) {
        usageStats.record(featureID, at: Date())
        persistUsage()
    }

    /// Run a feature. `explicitTargets` overrides the device-bar selection —
    /// the Quick Actions panel passes its own pick (or run-on-all fan-out)
    /// since `targetSerials`' run-all gating keys off the active tab, which is
    /// meaningless with no window. Returns the per-serial outcomes so a
    /// caller fanning out to several devices can aggregate them —
    /// `lastResults` only keeps the last one.
    @discardableResult
    func run(
        feature: FeatureDef,
        params: [String: FeatureValue],
        on explicitTargets: [String]? = nil
    ) async -> [(serial: String, result: FeatureResult)] {
        isRunningFeature = true
        defer { isRunningFeature = false }
        Telemetry.shared.trackFeatureUsed(feature.id, kind: feature.kind.rawValue)
        noteFeatureUse(feature.id)

        // A screenshot from a quick path (sidebar ⏎, global hotkey, menu bar)
        // captures and saves straight to the capture folder; the Screenshot
        // view instead opens the capture in the editor and saves on demand.
        if feature.id == "screenshot" {
            await runScreenshot()
            return []
        }
        // Bug reports zip into the capture folder with no save panel — the
        // one-time folder ask covers them like every other silent save.
        if feature.id == "bug-report" {
            confirmCaptureFolderOnce()
        }

        var params = params
        // A state-override fired without an explicit target flips its current
        // state — so a sidebar tap, hotkey, or ⌘T toggles it in place with no
        // detail screen (the sidebar switch reflects the result).
        if feature.isStateOverride, params["on"] == nil, let kind = feature.overrideKind {
            params["on"] = .bool(!activeOverrides.contains { $0.kind == kind })
        }
        if feature.needsBundle {
            guard let bundle = selectedBundle else {
                showToast(Toast(message: "Pick a saved bundle first.", ok: false))
                return []
            }
            params["packageId"] = .string(bundle.packageId)
        } else if params["packageId"] == nil, let bundle = selectedBundle {
            // Optional context for features like bug-report that include app
            // info when a bundle happens to be selected.
            params["packageId"] = .string(bundle.packageId)
        }

        let engine = env.engine
        let outcomes: [(serial: String, result: FeatureResult)] = await CommandLog.userInitiated {
            if !feature.needsDevice {
                let result = await engine.run(featureID: feature.id, serial: "", params: params)
                self.lastResults[feature.id] = (result, Date())
                self.show(result)
                return [("", result)]
            }

            let targets = explicitTargets ?? self.targetSerials
            guard !targets.isEmpty else {
                self.showToast(Toast(message: "No device connected.", ok: false))
                return []
            }
            var outcomes: [(serial: String, result: FeatureResult)] = []
            for serial in targets {
                let result = await engine.run(
                    featureID: feature.id, serial: serial,
                    platform: self.platform(for: serial), params: params
                )
                self.lastResults[feature.id] = (result, Date())
                outcomes.append((serial, result))
                if targets.count > 1 {
                    let label = self.devices.first { $0.serial == serial }?.label ?? serial
                    self.show(FeatureResult(
                        ok: result.ok,
                        message: "\(label): \(result.message)",
                        copyText: result.copyText,
                        revealPath: result.revealPath
                    ))
                } else {
                    self.show(result)
                }
            }
            return outcomes
        }
        if feature.isStateOverride {
            await refreshOverrides()
        }
        return outcomes
    }

    private func show(_ result: FeatureResult) {
        // A result that carries copyText (Copy Device IP, Copy Foreground
        // Bundle ID, Copy Current Activity) lands on the clipboard immediately — the
        // point of these actions — so a sidebar click is all it takes.
        var message = result.message
        if let copyText = result.copyText {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyText, forType: .string)
            message += " · copied"
        }
        showToast(Toast(
            message: message,
            ok: result.ok,
            copyText: result.copyText,
            revealPath: result.revealPath
        ))
    }

    func showToast(_ toast: Toast) {
        toasts.append(toast)
        if toast.postsSystemNotification {
            // The bar entry reuses the toast's id, so the notification can
            // carry it and a click can open the bar on that exact row.
            SystemNotifier.postToast(toast, entry: toast.id)
        }
        if toast.important {
            notifications.insert(
                AppNotification(
                    id: toast.id,
                    message: toast.message,
                    level: toast.level,
                    copyText: toast.copyText,
                    revealPath: toast.revealPath,
                    action: toast.action,
                    date: Date()
                ),
                at: 0
            )
            if notifications.count > 200 {
                notifications.removeLast(notifications.count - 200)
            }
            if !showNotifications { unreadNotifications += 1 }
        }
        Task {
            try? await Task.sleep(for: .seconds(5))
            toasts.removeAll { $0.id == toast.id }
        }
    }

    func toggleNotifications() {
        showNotifications.toggle()
        if showNotifications { unreadNotifications = 0 }
        if !showNotifications { focusedNotification = nil }
    }

    /// Open the panel — the route a clicked macOS notification takes, so it
    /// must not close an already-open one the way `toggleNotifications` would.
    /// `entry` is the row to scroll to and flash; it is dropped when this
    /// window's history doesn't hold it, which happens when the notification
    /// was posted by a different window (the history is per window, the
    /// notification is per app).
    func openNotifications(focusing entry: UUID? = nil) {
        focusedNotification = notifications.contains { $0.id == entry } ? entry : nil
        showNotifications = true
        unreadNotifications = 0
    }

    func clearNotifications() {
        notifications.removeAll()
    }

    func dismissNotification(_ id: UUID) {
        notifications.removeAll { $0.id == id }
    }

    func dismissToast(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    /// Perform a notification's follow-up (the button on its toast / panel
    /// row).
    func performNotificationAction(_ action: NotificationAction) {
        #if !APPSTORE
        switch action {
        // No window needed for these — the download is silent and the
        // relaunch takes the app down anyway.
        case .updateNow: SparkleUpdater.shared.installAvailableUpdate()
        case .relaunchToUpdate: SparkleUpdater.shared.relaunchNow()
        case .showWhatsNew:
            // The changelog sheet hangs off the main window — make sure one
            // is up (the notification history is reachable in background
            // mode too).
            activateMainWindow()
            presentWhatsNew = true
        }
        #else
        _ = action
        #endif
    }

    // MARK: - Bundles

    var selectedBundle: AppBundle? {
        bundles.first { $0.id == selectedBundleId }
    }

    func addBundle(nickname: String, packageId: String) {
        selectBundle(core.addBundle(nickname: nickname, packageId: packageId).id)
    }

    /// Pick this window's target app. The choice is per-window; the core also
    /// records it as the default a newly opened window starts on.
    func selectBundle(_ id: String?) {
        selectedBundleId = id
        core.noteBundleSelected(id)
        persistWindowState()
    }

    /// Quick capture (sidebar ⏎, global hotkey, menu bar): grab and save
    /// straight to the capture folder — no dialog. An optional delay gives you
    /// time to arrange the device screen first. The Screenshot view itself uses
    /// `captureForEditor` instead, opening the shot for markup before saving.
    func runScreenshot(delaySeconds: Int = 0) async {
        guard let serial = targetSerials.first else {
            showToast(Toast(message: "No device connected.", ok: false))
            return
        }
        confirmCaptureFolderOnce()
        if delaySeconds > 0 {
            showToast(Toast(message: "Capturing in \(delaySeconds)s…", ok: true))
            try? await Task.sleep(for: .seconds(delaySeconds))
        }
        await CommandLog.userInitiated {
            do {
                let dir = try ScreenCaptureService.ensureCaptureDir()
                let dest = dir.appendingPathComponent("screenshot_\(ScreenCaptureService.stamp()).png")
                let file = try await withOperation("Capturing screenshot…") {
                    try await env.engine.captureScreenshot(
                        serial: serial, platform: platform(for: serial), to: dest
                    )
                }
                let result = FeatureResult(
                    ok: true, message: "Saved \(file.lastPathComponent)", revealPath: file.path)
                lastResults["screenshot"] = (result, Date())
                showToast(Toast(message: "Screenshot saved to \(dir.lastPathComponent)", ok: true, revealPath: file.path))
            } catch {
                lastResults["screenshot"] = (FeatureResult(ok: false, message: error.localizedDescription), Date())
                showToast(Toast(message: error.localizedDescription, ok: false))
            }
        }
    }

    /// Capture for the in-app editor — returns the image without writing it
    /// anywhere; the editor saves or copies on demand. The delay lets you
    /// arrange the device screen first.
    func captureForEditor(delaySeconds: Int = 0) async -> NSImage? {
        guard let serial = targetSerials.first else {
            showToast(Toast(message: "No device connected.", ok: false))
            return nil
        }
        if delaySeconds > 0 {
            showToast(Toast(message: "Capturing in \(delaySeconds)s…", ok: true))
            try? await Task.sleep(for: .seconds(delaySeconds))
        }
        let data: Data? = await CommandLog.userInitiated {
            do {
                return try await withOperation("Capturing screenshot…") {
                    try await env.engine.captureScreenshotData(serial: serial, platform: platform(for: serial))
                }
            } catch {
                showToast(Toast(message: error.localizedDescription, ok: false))
                return nil
            }
        }
        return data.flatMap { NSImage(data: $0) }
    }

    // MARK: - Quick actions

    /// Grab the package id of the app on the device screen and save/select
    /// it as a bundle in one step.
    func adoptForegroundApp() {
        guard let serial = targetSerials.first else {
            showToast(Toast(message: "No device connected.", ok: false))
            return
        }
        Task {
            await CommandLog.userInitiated {
                guard let packageId = try? await env.engine.inspection.getForegroundPackage(serial: serial) else {
                    showToast(Toast(message: "Couldn't read the foreground app — is the screen on?", ok: false))
                    return
                }
                if let existing = bundles.first(where: { $0.packageId == packageId }) {
                    selectBundle(existing.id)
                    showToast(Toast(message: "Selected \(existing.nickname)", ok: true))
                } else {
                    let nickname = packageId.split(separator: ".").last.map(String.init)?.capitalized ?? packageId
                    addBundle(nickname: nickname, packageId: packageId)
                    showToast(Toast(message: "Saved \(nickname) (\(packageId))", ok: true))
                }
            }
        }
    }

    func installAdbKeyboard() {
        guard let serial = targetSerials.first else { return }
        showToast(Toast(message: "Downloading ADBKeyboard…", ok: true))
        Task {
            await CommandLog.userInitiated {
                let result = await env.engine.adbKeyboard.install(serial: serial)
                showToast(Toast(message: result.message, ok: result.ok))
            }
        }
    }

    // MARK: - Persistence

    /// Persist this window's device choice. `runOnAll` rides the shared prefs
    /// (it's a single flag with no per-window meaning); the device itself is
    /// part of the window's record.
    func persistSelection() {
        let all = runOnAll
        Task { try? await env.stores.prefs.update { $0.runOnAll = all } }
        persistWindowState()
    }

    // MARK: - Forwarded to AppCore
    //
    // These keep `AppState`'s API whole so feature views never learn that the
    // app grew a second window. `@Observable` registers the read inside the
    // getter, so a change on the core re-renders every window.

    var devices: [Device] { core.devices }
    var availableAvds: [Avd] {
        get { core.availableAvds }
        set { core.availableAvds = newValue }
    }
    var availableSimulators: [Simulator] {
        get { core.availableSimulators }
        set { core.availableSimulators = newValue }
    }
    var deviceDetails: [String: DeviceDetails] { core.deviceDetails }
    var adbStatus: ToolStatus? { core.adbStatus }
    var adbMissing: Bool { core.adbMissing }
    var readyWirelessDevices: [Device] { core.readyWirelessDevices }
    var readyDeviceCount: Int { core.readyDeviceCount }

    var layout: LayoutState {
        get { core.layout }
        set { core.layout = newValue }
    }
    var didLoadLayout: Bool { core.didLoadLayout }
    var usageStats: UsageStats {
        get { core.usageStats }
        set { core.usageStats = newValue }
    }
    var bundles: [AppBundle] { core.bundles }
    var selectedRole: UserRole? { core.selectedRole }

    var reactotronSession: ReactotronSession { core.reactotronSession }
    var mcp: McpCoordinator { core.mcp }

    func deviceDisplayName(_ device: Device) -> String { core.deviceDisplayName(device) }
    func deviceTitle(_ device: Device) -> String { core.deviceTitle(device) }
    func platform(for serial: String) -> DevicePlatform { core.platform(for: serial) }
    func refreshDevices() { core.refreshDevices() }
    func refreshToolStatus() async { await core.refreshToolStatus() }
    func setForeground(_ active: Bool) { core.setForeground(active) }
    func setQuickPanelOpen(_ open: Bool) { core.setQuickPanelOpen(open) }
    func persistUsage() { core.persistUsage() }
    func updateBundle(_ bundle: AppBundle) { core.updateBundle(bundle) }
    func removeBundle(id: String) { core.removeBundle(id: id) }

    func chooseRole(_ role: UserRole?, includeReactNativeStack: Bool = false) {
        core.chooseRole(role, includeReactNativeStack: includeReactNativeStack)
    }
}
