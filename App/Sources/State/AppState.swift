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
    /// Whether this mirrors to a macOS notification when the app is
    /// backgrounded. Defaults to `important`; install per-APK toasts opt out
    /// because the batch posts one summary instead.
    let notifiesWhenBackgrounded: Bool

    init(
        message: String,
        ok: Bool,
        level: Level? = nil,
        copyText: String? = nil,
        revealPath: String? = nil,
        action: NotificationAction? = nil,
        important: Bool? = nil,
        notifiesWhenBackgrounded: Bool? = nil
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
        self.notifiesWhenBackgrounded = notifiesWhenBackgrounded ?? resolvedImportant
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

@MainActor
@Observable
final class AppState {
    let env: AppEnvironment

    /// APK Studio's loaded-APK session. In-memory, so it resumes across
    /// navigation within a run and is cleared when the app quits (the decompiled
    /// cache is wiped alongside it — see `AppDelegate.applicationWillTerminate`).
    let apkStudio = ApkStudioSession()

    /// The Finder-opened-APK screen's files (the `apk-open` workspace tab —
    /// deliberately not a registry feature; it exists only when a file
    /// arrives). In-memory like the studio session.
    let apkOpen = ApkOpenSession()

    /// Everything connected, both platforms: adb devices first, then booted
    /// iOS Simulators. Rebuilt whenever either monitor publishes.
    var devices: [Device] = []
    /// The two platform streams, merged into `devices` — kept separately so
    /// one monitor's update never drops the other's list.
    private var androidDevices: [Device] = []
    private var simulatorDevices: [Device] = []
    /// Android Studio AVDs, for launching an emulator straight from the device
    /// bar. Refreshed when the connected set changes (see `refreshAvds`); ones
    /// with a `runningSerial` are already in `devices`.
    var availableAvds: [Avd] = []
    /// Xcode iOS Simulators not currently booted, for the device-bar "Start a
    /// simulator" section — the AVD list's simctl twin.
    var availableSimulators: [Simulator] = []
    /// Switch via `requestDevice(_:)`, not direct assignment — that routes the
    /// change through the leave guard so an active recording isn't lost.
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

    /// The tab id being dragged in a strip, or nil when no drag is in flight —
    /// shared so a pane can offer a drop target for moving/splitting tabs.
    var draggingTabID: String?

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
    var layout = LayoutState()
    /// Per-feature usage tally (persisted), used to re-rank the launchpad's
    /// curated feature order by how the user actually works.
    var usageStats = UsageStats()
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
    /// The Reactotron server + timeline, owned here (not by the view) so leaving
    /// the feature can keep the connection alive and return to an intact session.
    let reactotronSession: ReactotronSession

    /// The JS Console (Hermes CDP) session — owned here so its log buffer and
    /// connection survive leaving the feature, like the Reactotron session.
    let jsConsoleSession: JSConsoleSession

    /// The Terminal feature's shells — owned here so every tab's PTY session
    /// and scrollback survive leaving the feature.
    let terminals = TerminalManager()

    /// With auto-hide on (Settings ▸ Appearance), the sidebar rides over the
    /// content instead of sitting in the layout; this is that overlay's
    /// visibility, driven by the left-edge hover zone and ⌘B.
    var sidebarOverlayShown = false

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

    var bundles: [AppBundle] = []
    var selectedBundleId: String?
    var adbStatus: ToolStatus?
    /// An `.aab` opened from Finder (double-click / Open With), staged for the
    /// AAB to APK feature. The view consumes (clears) it once shown.
    var pendingConvertAAB: URL?
    /// Set by RootView so hotkeys/menu bar can reopen a closed main window.
    var openMainWindow: (() -> Void)?
    /// The real app delegate (the adaptor instance, wired in `ADTApp.body`) —
    /// `NSApp.delegate` is SwiftUI's wrapper on macOS, so casting it fails.
    weak var appDelegate: AppDelegate?
    /// The main window, resolved by RootView's `WindowAccessor`. Held by
    /// *reference* because identifiers can't be trusted across a close:
    /// SwiftUI re-stamps its own (`main-AppWindow-1`) over our tag, which
    /// broke the ⌘W tab-close monitor after a close → reopen cycle.
    weak var mainWindow: NSWindow?
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
    /// Per-serial enrichment for the device picker (version, battery).
    var deviceDetails: [String: DeviceDetails] = [:]
    /// Serials already reported to analytics this session, so `device_connected`
    /// fires once per device (the serial is used only locally, never sent).
    private var reportedDeviceSerials: Set<String> = []

    /// Bring the app forward, reopening the main window if it was closed. When
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
    }

    private func bringMainWindowFront() {
        NSApp.activate(ignoringOtherApps: true)
        // The tracked reference first (identifiers are unreliable across a
        // close); the structural fallback excludes panels, whose KeyablePanel
        // overrides `canBecomeMain` to true.
        let window = mainWindow
            ?? NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        setForeground(true)
    }

    var adbMissing: Bool { adbStatus?.installed == false }

    private var deviceStreamTask: Task<Void, Never>?
    private var simulatorStreamTask: Task<Void, Never>?
    /// Set the moment the user picks a role this session, so `bootstrap`'s
    /// async layout load can't overwrite the just-seeded curation.
    private var roleChosenThisSession = false

    /// False until `bootstrap` has loaded the persisted layout. Until then the
    /// in-memory `layout` is still the default, so persisting it would clobber
    /// the user's saved layout — `persistLayout` no-ops while this is false.
    private(set) var didLoadLayout = false
    /// Feature opens that arrived before the layout finished loading (e.g. an
    /// APK double-clicked in Finder on cold launch). Replayed after restore.
    private var pendingFeatureOpens: [String] = []

    init(env: AppEnvironment) {
        self.env = env
        let savedStep = UserDefaults.standard.object(forKey: "fontScaleStep") as? Int ?? Self.defaultScaleIndex
        fontScaleStep = min(max(savedStep, 0), Self.scales.count - 1)
        reactotronSession = ReactotronSession(client: env.client)
        jsConsoleSession = JSConsoleSession(adb: env.client)
        reactotronSession.app = self
        jsConsoleSession.app = self
        // Typing `exit` (or a shell crash) closes that tab like the × does.
        // The contains-check drops late callbacks racing a killAll teardown.
        terminals.onShellExited = { [weak self] id in
            guard let self, self.terminals.tabs.contains(where: { $0.id == id }) else { return }
            self.closeTerminalShell(id)
        }
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        let prefs = await env.stores.prefs.load()
        selectedSerial = prefs.selectedSerial
        runOnAll = prefs.runOnAll
        selectedBundleId = prefs.selectedBundleId
        let loadedLayout = await env.stores.layout.load()
        // A brand-new user can pick a role — which seeds `layout` — while these
        // async store loads are still in flight; don't clobber that seed.
        var layoutChanged = false
        if !roleChosenThisSession {
            layout = loadedLayout
            layoutChanged = layout.adoptNewDefaults()
            layoutChanged = layout.adoptAllEnabled() || layoutChanged
            layoutChanged = layout.adoptNewRoleFeatures() || layoutChanged
            // Reopen the tabs from the last session (idle — recordings/streams
            // don't resume). Falls back to a single Home tab for a new user or a
            // layout written before tabs existed.
            restoreTabs(from: layout)
        }
        didLoadLayout = true
        // Replay feature opens that raced the load (e.g. openAPKs from Finder),
        // then persist for the first time now that `layout` is authoritative.
        for id in pendingFeatureOpens {
            workspace.open(id)
        }
        // Persist if defaults were adopted, an open raced the load, or a role was
        // seeded while loading (chooseRole's persistTabs no-op'd before load).
        if layoutChanged || !pendingFeatureOpens.isEmpty || roleChosenThisSession {
            persistTabs()
        }
        pendingFeatureOpens = []
        usageStats = await env.stores.usage.load()
        bundles = await env.stores.bundles.load()

        // Subscribe both device streams before the tool probe: adb detection
        // can spend seconds in the login shell, and the bar shouldn't sit
        // empty that long (the simulator poll doesn't need adb at all).
        deviceStreamTask = Task { [weak self, monitor = env.monitor] in
            // This Task inherits AppState's @MainActor isolation, so the loop
            // body already runs on the main actor — no extra hop needed.
            for await devices in await monitor.updates() {
                guard let self else { break }
                self.androidDevices = devices
                self.devicesChanged(self.androidDevices + self.simulatorDevices)
            }
        }
        simulatorStreamTask = Task { [weak self, monitor = env.simulatorMonitor] in
            for await simulators in await monitor.updates() {
                guard let self else { break }
                self.simulatorDevices = simulators
                self.devicesChanged(self.androidDevices + self.simulatorDevices)
            }
        }
        await refreshToolStatus()
    }

    func refreshToolStatus() async {
        adbStatus = await env.engine.toolDetection.detectAdb()
    }

    private func devicesChanged(_ devices: [Device]) {
        // The role scopes which platforms exist for this user: iOS Developer
        // sees only simulators, the Android-first roles only adb devices, and
        // "all features" both. Filter here — the single merge point — so the
        // bar, pickers, and run targets all agree.
        let platforms = FeatureRegistry.visiblePlatforms(for: selectedRole)
        let devices = devices.filter { platforms.contains($0.platform) }
        self.devices = devices
        // The Reactotron session outlives its view ("keep connection alive"),
        // so tunnel recovery for (re)appearing devices must hook in here, not
        // in the view.
        reactotronSession.deviceListChanged()
        let ready = devices.filter(\.isReady)
        // "Run on all" only makes sense with more than one device.
        if ready.count <= 1, runOnAll {
            runOnAll = false
            persistSelection()
        }
        let before = selectedSerial
        if let selectedSerial, !devices.contains(where: { $0.serial == selectedSerial }) {
            self.selectedSerial = ready.first?.serial
        } else if selectedSerial == nil {
            selectedSerial = ready.first?.serial
        }
        // Refetch overrides when the selection changed, or once when the
        // selected device becomes ready — not on every unrelated device-list
        // change (an empty override set is the common steady state, so
        // "empty" alone can't mean "never loaded").
        let readySelected = selectedDevice?.isReady == true
        if selectedSerial != before || (readySelected && overridesFetchedForSerial != selectedSerial) {
            Task { await refreshOverrides() }
        }
        // Picker enrichment reads getprop over adb — Android only; a
        // simulator's runtime label already rides in `Device.product`.
        for device in ready
        where device.platform == .android && deviceDetails[device.serial] == nil
            && !deviceDetailsFetching.contains(device.serial) {
            deviceDetailsFetching.insert(device.serial)
            Task {
                let details = await DeviceDetails.fetch(client: env.client, serial: device.serial)
                deviceDetails[device.serial] = details
                deviceDetailsFetching.remove(device.serial)
                reportDeviceConnected(device)
            }
        }
    }

    /// Serials with a `DeviceDetails.fetch` in flight, so a device-list change
    /// mid-fetch doesn't spawn a duplicate getprop probe.
    private var deviceDetailsFetching: Set<String> = []

    /// Emit an anonymous `device_connected` once per device this session (no
    /// serial leaves the machine — it's only the local dedup key). Android
    /// only — simulators skip the details fetch that triggers it.
    private func reportDeviceConnected(_ device: Device) {
        guard reportedDeviceSerials.insert(device.serial).inserted else { return }
        Telemetry.shared.trackDeviceConnected(
            isEmulator: device.serial.hasPrefix("emulator-"),
            isWireless: device.isWireless
        )
    }

    /// The device's human name: a running emulator shows its AVD name
    /// ("Medium Tablet") — every emulator otherwise carries the same generic
    /// system-image model ("sdk gphone64 arm64") — and everything else keeps
    /// its adb label.
    func deviceDisplayName(_ device: Device) -> String {
        if device.serial.hasPrefix("emulator-"),
           let avd = availableAvds.first(where: { $0.runningSerial == device.serial }) {
            return avd.displayName
        }
        return device.label
    }

    /// Picker label with enrichment: "Pixel 7 (005F) · Android 14 · 82%",
    /// or "iPhone 16 Pro · iOS 18.2 · Simulator" for a booted simulator.
    func deviceTitle(_ device: Device) -> String {
        guard device.isReady else {
            return device.state == "unauthorized"
                ? "\(deviceDisplayName(device)) — accept the prompt on the device"
                : "\(deviceDisplayName(device)) — \(device.state)"
        }
        var parts = [deviceDisplayName(device)]
        switch device.platform {
        case .android:
            if let details = deviceDetails[device.serial] {
                if let version = details.androidVersion { parts.append("Android \(version)") }
                if let battery = details.batteryLevel { parts.append("\(battery)%") }
            }
        case .iosSimulator:
            if let runtime = device.product { parts.append(runtime) }
            parts.append("Simulator")
        }
        return parts.joined(separator: " · ")
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

    /// Toolchain for a serial in the current device set — Android when unknown
    /// (a device that just disconnected mid-run was adb-backed in every
    /// existing flow).
    func platform(for serial: String) -> DevicePlatform {
        devices.first { $0.serial == serial }?.platform ?? .android
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

    func refreshDevices() {
        Task { await env.monitor.invalidate() }
        Task { await env.simulatorMonitor.invalidate() }
    }

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

    /// Ready devices that are wireless (serial is ip:port) — eligible for
    /// the device bar's Disconnect control.
    var readyWirelessDevices: [Device] {
        devices.filter { $0.isReady && $0.isWireless }
    }

    var readyDeviceCount: Int {
        devices.filter(\.isReady).count
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
        enum Target: Equatable { case closeTab(String), device(String), quit }
        var target: Target
        /// Flips true when the user chooses "Stop & save": the active view runs
        /// its own save, then calls `finishExitSave()`. The dialog hides while
        /// the save is in flight.
        var saving = false
    }

    /// Register (or replace) the leave guard for a tab. A protected view calls
    /// this when losable work begins, and `clearExitGuard` when it ends.
    func setExitGuard(_ value: ExitGuard) { exitGuards[value.featureID] = value }

    /// Clear the guard identified by `id`, wherever it's keyed — so a torn-down
    /// view can't wipe a guard a newer view just registered (ids are unique).
    func clearExitGuard(_ id: UUID) {
        exitGuards = exitGuards.filter { $0.value.id != id }
    }

    /// The guard the pending leave confirmation is about: the closing tab's
    /// guard, or any active guard when switching device / quitting.
    var pendingGuard: ExitGuard? {
        switch pendingExit?.target {
        case .closeTab(let id): return exitGuards[id]
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
        case .closeTab(let id): return id == featureID
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
        workspace.open(id)
        if didLoadLayout {
            persistTabs()
        } else {
            // The layout hasn't finished loading; record the open so bootstrap
            // can replay and persist it without a default layout clobbering disk.
            pendingFeatureOpens.append(id)
        }
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
                terminals.killAll()
                quitNow()
            } else {
                cancelDeferredQuit()
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

    /// Split the workspace: move `id` into a new second pane.
    func splitTab(_ id: String) {
        workspace.split(id)
        persistTabs()
    }

    private func performClose(_ id: String) {
        workspace.close(id)
        stopBackgroundWork(for: id)
        persistTabs()
    }

    /// Closing a tab fully stops that feature's background work. Most features
    /// stop when their view unmounts (their `.task` is cancelled on close), but a
    /// few sessions are owned here and kept alive across tab *switches* — so
    /// closing their tab has to tear them down explicitly. A feature is open in at
    /// most one tab, so once it's closed no other tab still needs it.
    private func stopBackgroundWork(for id: String) {
        if id == "reactotron", reactotronSession.isRunning {
            Task { await reactotronSession.stop() }
        }
        if id == "js-console" {
            jsConsoleSession.stop()
            Task { await jsConsoleSession.removeReverseTunnels() }
        }
        if id == "terminal" {
            terminals.killAll()
        }
    }

    private func persistTabs() {
        layout.tabGroups = workspace.groups.map { TabGroupState(tabs: $0.openTabs, activeTab: $0.activeTab) }
        layout.focusedGroup = workspace.focusedGroup
        persistLayout()
    }

    /// Reopen persisted panes (idle — live sessions don't resume). All the
    /// trimming/validation invariants live in `Workspace`; this just supplies the
    /// registry validity check and the Home fallback.
    private func restoreTabs(from layout: LayoutState) {
        workspace = Workspace(
            restoring: layout.tabGroups ?? [],
            focusedGroup: layout.focusedGroup,
            fallback: "home",
            isValidID: Self.isValidTabID
        )
    }

    /// Ids that can back a tab: every registry feature plus the standalone
    /// Home / About / Catalog screens and the Finder-opened-APK screen.
    private static func isValidTabID(_ id: String) -> Bool {
        FeatureRegistry.byID[id] != nil || ["home", "about", "catalog", "apk-open"].contains(id)
    }

    private var isForeground = true
    private var quickPanelOpen = false

    /// Widen device polling while the app is backgrounded so an idle, hidden
    /// window stops spawning `adb devices` / `simctl list` every few seconds;
    /// restore it on foreground.
    func setForeground(_ active: Bool) {
        isForeground = active
        applyPollInterval()
    }

    /// An open Quick Actions panel needs a fresh device list even while the
    /// app is backgrounded, so it counts as foreground for the poll rate.
    func setQuickPanelOpen(_ open: Bool) {
        quickPanelOpen = open
        applyPollInterval()
        // The panel's device rows name emulators by their AVD
        // (`deviceDisplayName`) — refresh the AVD↔serial mapping on open, so
        // it's right even when the main window (whose device bar usually
        // keeps it fresh) has been closed all along.
        if open {
            Task { await refreshAvds() }
        }
    }

    private func applyPollInterval() {
        let active = isForeground || quickPanelOpen
        let interval: Duration = active ? .seconds(2) : .seconds(10)
        Task { [monitor = env.monitor] in await monitor.setPollInterval(interval) }
        let simInterval: Duration = active ? .seconds(3) : .seconds(15)
        Task { [monitor = env.simulatorMonitor] in await monitor.setPollInterval(simInterval) }
    }

    /// The main window closed with background mode on (Settings ▸ General).
    /// Stop the kept-alive sessions — terminal shells, the Reactotron server,
    /// JS-console reverse tunnels — so no feature process outlives the UI
    /// (view-owned work like recordings and log streams already dies with its
    /// view), and widen device polling. The tabs stay in the workspace, so
    /// reopening the window restores them idle.
    func enterBackground() {
        for id in openFeatureIDs {
            stopBackgroundWork(for: id)
        }
        setForeground(false)
    }

    /// Switch the active device, or hold it behind a confirmation when a guard
    /// is active.
    func requestDevice(_ serial: String) {
        guard serial != selectedSerial else { return }
        if exitGuards.isEmpty {
            selectedSerial = serial
            persistSelection()
        } else {
            pendingExit = PendingExit(target: .device(serial))
        }
    }

    /// Called from `applicationShouldTerminate`. Returns true to quit now; false
    /// means losable work is in flight — the leave prompt is shown and the
    /// resolution drives termination (see `quitNow` / `cancelExit`).
    func requestQuit() -> Bool {
        if !exitGuards.isEmpty {
            pendingExit = PendingExit(target: .quit)
            return false
        }
        // Live shells are losable work too: quitting kills them all, so it
        // gets the same confirmation closing the Terminal tab does.
        if !terminals.tabs.isEmpty {
            terminalClosePrompt = .quit
            return false
        }
        return true
    }

    /// "Discard" / "Discard changes": drop the at-risk work and run the deferred
    /// navigation. A tab close clears just that tab's guard (and its view aborts
    /// in `.onDisappear` as it unmounts); a device-switch / quit leaves every
    /// tab, so clear them all and let each view abort.
    func discardAndExit() {
        switch pendingExit?.target {
        case .closeTab(let id): exitGuards[id] = nil
        case .device, .quit: exitGuards.removeAll()
        case nil: break
        }
        performPendingExit()
    }

    /// "Keep recording" / "Keep editing": abandon the pending navigation.
    func cancelExit() {
        let wasQuit = pendingExit?.target == .quit
        pendingExit = nil
        if wasQuit { cancelDeferredQuit() }
    }

    /// Abandon a quit `applicationShouldTerminate` deferred: clear the
    /// delegate's in-quit flag first, so a later window close still routes
    /// through background mode instead of being mistaken for quit teardown.
    private func cancelDeferredQuit() {
        appDelegate?.isQuitting = false
        NSApp.reply(toApplicationShouldTerminate: false)
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
        case .device(let serial): selectedSerial = serial; persistSelection()
        case .quit: quitNow()
        }
    }

    /// Finish a deferred quit: tear down a kept-alive Reactotron session (as the
    /// normal quit path does), then let termination proceed.
    private func quitNow() {
        Task {
            if reactotronSession.isRunning { await reactotronSession.stopForQuit() }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
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
        if toast.notifiesWhenBackgrounded {
            SystemNotifier.postToastIfBackgrounded(toast)
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

    // MARK: - Role

    /// Apply the user's role choice (first-run or "Change role"): curate the
    /// enabled set + sidebar order to that role, or keep everything on for
    /// `nil` ("show me everything"). Persists and lands on the launchpad.
    func chooseRole(_ role: UserRole?) {
        let isChange = layout.selectedRole != nil
        Telemetry.shared.trackRoleChosen(role?.rawValue ?? "all", isChange: isChange)
        Telemetry.shared.applyRole(role?.rawValue)
        if let role {
            layout.seedRole(role)
        } else {
            layout.seedEverything()
        }
        roleChosenThisSession = true
        // Re-apply the role's platform visibility: drop devices the new role
        // can't see and refresh the device-bar launch lists (a hidden
        // platform's list empties, which removes its menu section).
        devicesChanged(androidDevices + simulatorDevices)
        Task {
            await refreshAvds()
            await refreshSimulators()
        }
        // Start the freshly-chosen role on a single Home tab, no split. The
        // reset drops every open tab without routing through performClose, so
        // stop each one's background work explicitly — otherwise kept-alive
        // sessions (terminal shells, the Reactotron server) leak with no UI
        // left to reach them.
        for id in workspace.groups.flatMap(\.openTabs) {
            stopBackgroundWork(for: id)
        }
        workspace.reset()
        persistTabs()
        presentRolePicker = false
    }

    /// The user's current role, nil when they chose "show me everything".
    var selectedRole: UserRole? {
        layout.selectedRole.flatMap(UserRole.init(rawValue:))
    }

    private func persistUsage() {
        let snapshot = usageStats
        Task {
            try? await env.stores.usage.save(snapshot)
        }
    }

    // MARK: - Bundles

    var selectedBundle: AppBundle? {
        bundles.first { $0.id == selectedBundleId }
    }

    func addBundle(nickname: String, packageId: String) {
        let bundle = AppBundle(
            nickname: nickname.isEmpty ? packageId : nickname,
            packageId: packageId,
            createdAt: Date().timeIntervalSince1970 * 1000
        )
        bundles.append(bundle)
        selectBundle(bundle.id)
        persistBundles()
    }

    func updateBundle(_ bundle: AppBundle) {
        guard let index = bundles.firstIndex(where: { $0.id == bundle.id }) else { return }
        bundles[index] = bundle
        persistBundles()
    }

    func removeBundle(id: String) {
        bundles.removeAll { $0.id == id }
        if selectedBundleId == id {
            selectBundle(bundles.first?.id)
        }
        persistBundles()
    }

    func selectBundle(_ id: String?) {
        selectedBundleId = id
        Task {
            try? await env.stores.prefs.update { $0.selectedBundleId = id }
        }
    }

    private func persistBundles() {
        let snapshot = bundles
        Task {
            try? await env.stores.bundles.save(snapshot)
        }
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

    func persistSelection() {
        let serial = selectedSerial
        let all = runOnAll
        Task {
            try? await env.stores.prefs.update {
                $0.selectedSerial = serial
                $0.runOnAll = all
            }
        }
    }
}
