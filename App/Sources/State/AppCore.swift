import ADBKit
import AppKit
import Foundation
import Observation
import SwiftUI

/// Everything that belongs to the *app*, not to a window.
///
/// Droidective is multi-window: each window is a device-scoped workspace with
/// its own `AppState` (selection, tabs, terminals, consoles). What can only
/// exist once lives here — the single `adb devices` poll, the tool caches, the
/// persisted feature curation, and the two port-bound listeners (the Reactotron
/// relay on 9090, MCP on 4567).
///
/// `AppState` keeps its full public API by forwarding to this, so feature views
/// read `state.devices` / `state.layout` exactly as they did when there was one
/// window. `@Observable` registers the access inside the forwarding getter, so
/// a change here re-renders every window.
@MainActor
@Observable
final class AppCore {
    /// The app has exactly one. Windows are created against it by
    /// `WorkspaceHost`, which can't be handed an injected value.
    static let shared = AppCore()

    let env: AppEnvironment

    // MARK: - Devices (one poll, however many windows)

    /// Everything connected, both platforms: adb devices first, then booted
    /// iOS Simulators. Rebuilt whenever either monitor publishes.
    var devices: [Device] = []
    /// The two platform streams, merged into `devices` — kept separately so
    /// one monitor's update never drops the other's list.
    private var androidDevices: [Device] = []
    private var simulatorDevices: [Device] = []
    /// Android Studio AVDs, for launching an emulator straight from the device
    /// bar. Ones with a `runningSerial` are already in `devices`.
    var availableAvds: [Avd] = []
    /// Xcode iOS Simulators not currently booted, for the device-bar "Start a
    /// simulator" section — the AVD list's simctl twin.
    var availableSimulators: [Simulator] = []
    /// Per-serial enrichment for the device picker (version, battery).
    var deviceDetails: [String: DeviceDetails] = [:]
    var adbStatus: ToolStatus?
    var adbMissing: Bool { adbStatus?.installed == false }

    /// Serials with a `DeviceDetails.fetch` in flight, so a device-list change
    /// mid-fetch doesn't spawn a duplicate getprop probe.
    private var deviceDetailsFetching: Set<String> = []
    /// Serials already reported to analytics this session, so `device_connected`
    /// fires once per device (the serial is used only locally, never sent).
    private var reportedDeviceSerials: Set<String> = []
    private var deviceStreamTask: Task<Void, Never>?
    private var simulatorStreamTask: Task<Void, Never>?

    // MARK: - App-wide persisted state

    /// Feature curation (enabled set, order, favorites, role) plus the
    /// per-window records. Shared by every window: turning a feature off in one
    /// turns it off everywhere, which is what users expect of a preference.
    var layout = LayoutState()
    /// False until `bootstrap` has loaded the persisted layout. Until then the
    /// in-memory `layout` is still the default, so persisting it would clobber
    /// the user's saved layout — `persistLayout` no-ops while this is false.
    private(set) var didLoadLayout = false
    var usageStats = UsageStats()
    /// The saved app bundles. The *list* is shared; which one a window has
    /// picked is per-window (`AppState.selectedBundleId`).
    var bundles: [AppBundle] = []
    /// The bundle id a brand-new window starts on — the last one chosen
    /// anywhere, so opening a second window lands on the same app.
    private(set) var lastSelectedBundleId: String?

    // MARK: - Shared sessions

    /// The Reactotron relay: one listener on port 9090 for the whole app, so
    /// every window's Reactotron tab shows the same timeline. Device-agnostic
    /// by nature — the RN app dials the Mac.
    let reactotronSession: ReactotronSession
    /// Settings ▸ MCP: serves the relay's data to AI agents over localhost.
    let mcp = McpCoordinator()

    // MARK: - Windows

    /// Who owns which device and which exclusive feature is live where — the
    /// pure model behind the device picker's "open in Window 2" and the
    /// mirror/console collision banners.
    private(set) var registry = WorkspaceRegistry()
    /// Live workspaces by id. `AppState` instances are owned here, not by
    /// `@State`, so a SwiftUI view re-init can never drop a window's tabs.
    private var workspaces: [WorkspaceID: AppState] = [:]
    /// The window that last became key — where menu-bar actions, global
    /// hotkeys and Finder opens land.
    private(set) var frontmostID: WorkspaceID?
    /// Set by `RootView`: opens another window of the main `WindowGroup`.
    var openWorkspaceWindow: (() -> Void)?
    /// Persisted windows waiting to be claimed by a workspace as its windows
    /// come up. Claimed in order, so window 2 restores window 2's tabs.
    private var pendingRestores: [WindowState] = []
    /// Workspaces created before the layout finished loading — they restore in
    /// `bootstrap`, once `pendingRestores` is populated.
    private var awaitingRestore: [WorkspaceID] = []
    /// Guards the one-time app-wide launch wiring (hotkeys, telemetry, the
    /// event monitors) so it runs once rather than once per window.
    private var didPerformLaunchSetup = false

    private init() {
        env = AppEnvironment()
        reactotronSession = ReactotronSession(client: env.client)
        reactotronSession.core = self
        mcp.core = self
        // Both are app-wide, so they're wired to the core, not to a window;
        // only the relay's user-facing reporting follows the frontmost window
        // (see `noteFrontmost`).
        Task { await bootstrap() }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        let prefs = await env.stores.prefs.load()
        lastSelectedBundleId = prefs.selectedBundleId
        var loaded = await env.stores.layout.load()
        var changed = loaded.adoptNewDefaults()
        changed = loaded.adoptAllEnabled() || changed
        changed = loaded.adoptNewRoleFeatures() || changed
        // Fold a pre-multi-window layout's single workspace into one window,
        // inheriting the global device/bundle selection it was saved with.
        changed = loaded.adoptWindows(serial: prefs.selectedSerial, bundleId: prefs.selectedBundleId)
            || changed
        // A brand-new user can pick a role — which seeds `layout` — while this
        // load is in flight; don't clobber that seed. The windows array is
        // still adopted, since the role picker doesn't touch it.
        if roleChosenThisSession {
            layout.windows = loaded.windows
        } else {
            layout = loaded
        }
        didLoadLayout = true
        pendingRestores = layout.windows ?? []
        // Restore the windows that already came up while this was loading
        // (always at least the first one), then ask for the rest.
        for id in awaitingRestore {
            let saved = freshWorkspaces.contains(id) ? nil : claimPendingRestore()
            workspaces[id]?.restore(from: saved)
        }
        freshWorkspaces.removeAll()
        awaitingRestore = []
        openPendingRestoredWindowsOnce()
        if changed || roleChosenThisSession { persistLayout(force: true) }

        // MCP enabled in a previous run comes back up with the app.
        if mcp.isEnabled { mcp.applySettings() }
        usageStats = await env.stores.usage.load()
        bundles = await env.stores.bundles.load()

        // Subscribe both device streams before the tool probe: adb detection
        // can spend seconds in the login shell, and the bar shouldn't sit
        // empty that long (the simulator poll doesn't need adb at all).
        deviceStreamTask = Task { [weak self, monitor = env.monitor] in
            // This Task inherits AppCore's @MainActor isolation, so the loop
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

    /// True once the app-wide launch wiring has run; the second and later
    /// windows skip it.
    func claimLaunchSetup() -> Bool {
        guard !didPerformLaunchSetup else { return false }
        didPerformLaunchSetup = true
        observeKeyWindow()
        return true
    }

    /// Follow the key window so `frontmost` is always the one the user is
    /// working in — that's where the menu bar, global hotkeys and Finder opens
    /// land — and follow app activation for the poll rate.
    ///
    /// Activation is read from `NSApplication`, not from each window's
    /// `scenePhase`: with several windows those fire independently, and one
    /// going inactive would widen polling while another is being used.
    private func observeKeyWindow() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let state = self.workspace(for: window) else { return }
                self.noteFrontmost(state.id)
            }
        }
        for (name, active) in [
            (NSApplication.didBecomeActiveNotification, true),
            (NSApplication.didResignActiveNotification, false),
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setForeground(active) }
            }
        }
    }

    // MARK: - Workspace registry

    /// Which workspace a window presenting `presented` should show.
    ///
    /// The presented id is SwiftUI's handle on the window, not the workspace's
    /// identity — a window that comes up unasked (a background-mode reopen, or
    /// launch restoring last session) should step into a workspace that
    /// currently has no window rather than create an empty one beside it. The
    /// claim map makes the answer stable, so SwiftUI re-evaluating the host
    /// view always lands on the same workspace.
    func workspace(claiming presented: WorkspaceID) -> AppState {
        if let mapped = claims[presented], let state = workspaces[mapped] { return state }
        // Provisional: no registry entry, no restore, nothing written. SwiftUI
        // asks for content for windows it never shows — it persists presented
        // values across launches and re-presents stale ones — so a workspace
        // becomes real only when an `NSWindow` binds to it (`bind`). Restoring
        // here instead let a phantom swallow a real window's saved tabs.
        let state = AppState(core: self, id: .generate())
        workspaces[state.id] = state
        provisional.insert(state.id)
        claims[presented] = state.id
        return state
    }

    /// Presented window id → the workspace it shows. Released when the window
    /// closes, which is what lets the next window adopt a parked workspace.
    private var claims: [WorkspaceID: WorkspaceID] = [:]
    /// Workspaces handed to a view but not yet backed by a window. They own
    /// nothing — no registry entry, no persisted record — until they bind.
    private var provisional: Set<WorkspaceID> = []
    /// Windows the user explicitly asked for (⇧⌘N, "New Window for Device"),
    /// oldest first: each starts a *new* workspace instead of adopting a
    /// windowless one, and carries the device it was opened for. A queue
    /// rather than a keyed lookup because the window has no identity until it
    /// exists — `openWindow` creates one synchronously per call, and binds are
    /// serialised on the main actor, so first-asked is first-bound.
    private var pendingFreshWindows: [String?] = []
    /// Workspaces opened by an explicit request while the layout was still
    /// loading. `bootstrap`'s restore must not hand them a persisted window —
    /// the user asked for a *new* one, on a device they may have named.
    private var freshWorkspaces: Set<WorkspaceID> = []

    /// A real `NSWindow` came up. This is where a workspace becomes real:
    /// either the window steps into one that has been waiting for a window
    /// (last session's, at launch — or one parked by a background-mode close),
    /// or the provisional it was handed is promoted.
    func bind(_ window: NSWindow, to state: AppState) {
        // Drop identifiers of windows that are already gone. `ObjectIdentifier`
        // is the address, so a freshly allocated window can land on a closed
        // one's — and without this, the guard below would silently refuse to
        // bind it. A window that is genuinely mid-close is still in
        // `NSApp.windows`, so it survives the prune.
        closingWindows.formIntersection(Set(NSApp.windows.map(ObjectIdentifier.init)))
        // A window on its way out still gets re-rendered, and that render asks
        // for content — which would mint a workspace for a window nobody will
        // ever see, and (worse) make it look like a live window for the
        // park-or-destroy decision below.
        guard !closingWindows.contains(ObjectIdentifier(window)) else { return }
        // Droidective restores its own windows, from `LayoutState.windows`.
        // AppKit's saved-state restoration would *also* bring windows back,
        // with stale ids and before the layout has loaded. Opting out leaves
        // exactly one restorer. (Frame autosave is separate and still
        // remembers each window's position.)
        window.isRestorable = false
        // One window, one workspace. If this window was showing another
        // workspace, leaving that one marked as "has a window" would mean
        // nothing ever adopts it back; releasing it here is what lets the
        // adoption below hand it straight back.
        for other in workspaces.values where other !== state && other.nsWindow === window {
            other.nsWindow = nil
        }
        guard provisional.contains(state.id) else {
            // Already a real workspace — just (re)attach the window.
            attach(window, to: state)
            return
        }
        provisional.remove(state.id)
        var requestedSerial: String?
        var wantsFresh = false
        if !pendingFreshWindows.isEmpty {
            wantsFresh = true
            requestedSerial = pendingFreshWindows.removeFirst()
        }
        let hostToken = claims.first { $0.value == state.id }?.key
        // Adoption has to be able to repoint the host, or it would keep
        // resolving to the workspace just dropped and mint a new provisional
        // on every render.
        if !wantsFresh, let hostToken, let adopted = firstWindowlessWorkspace() {
            // Hand this window the workspace that was waiting for one and drop
            // the provisional. `claims` is observed, so the host view
            // re-renders onto the adopted workspace.
            workspaces[state.id] = nil
            claims[hostToken] = adopted.id
            attach(window, to: adopted)
            return
        }
        registry.register(state.id)
        if let requestedSerial {
            pendingWindowTargets[state.id] = requestedSerial
        }
        if wantsFresh { freshWorkspaces.insert(state.id) }
        if didLoadLayout {
            state.restore(from: wantsFresh ? nil : claimPendingRestore())
        } else {
            // The layout is still loading; `bootstrap` restores this workspace
            // once the persisted entries are known.
            awaitingRestore.append(state.id)
        }
        attach(window, to: state)
    }

    private func attach(_ window: NSWindow, to state: AppState) {
        state.nsWindow = window
        state.noteBound()
        noteFrontmost(state.id)
        // A real window exists now, so the rest of last session's windows can
        // safely be asked for.
        openPendingRestoredWindowsOnce()
    }

    /// A registered workspace with no window on screen, in creation order.
    private func firstWindowlessWorkspace() -> AppState? {
        registry.ids.lazy.compactMap { self.workspaces[$0] }.first { $0.nsWindow == nil }
    }

    /// The next persisted window to restore, or nil for a genuinely new window
    /// (opened by the user rather than reopened at launch).
    ///
    /// Claiming *removes* the entry: workspace ids are minted per session, so
    /// the claiming window immediately writes itself back under its own id.
    /// Leaving the old entry behind would grow the array by one window on
    /// every launch.
    private func claimPendingRestore() -> WindowState? {
        guard !pendingRestores.isEmpty else { return nil }
        let claimed = pendingRestores.removeFirst()
        layout.windows?.removeAll { $0.id == claimed.id }
        return claimed
    }

    /// Reopen the windows a previous session left behind, beyond the one the
    /// app started with. Fires exactly once, and only once a real window has
    /// bound — asking earlier raced the first window's own restore and opened
    /// one window too many.
    private var didOpenRestoredWindows = false

    private func openPendingRestoredWindowsOnce() {
        guard !didOpenRestoredWindows, didLoadLayout,
              let open = openWorkspaceWindow, !registry.entries.isEmpty
        else { return }
        didOpenRestoredWindows = true
        // Not marked fresh: each of these windows adopts the next workspace
        // waiting for one.
        for _ in 0..<pendingRestores.count {
            open()
        }
    }

    /// Called by every `RootView` as it appears. The opener is refreshed each
    /// time (a SwiftUI `openWindow` action captured from a window that has
    /// since closed is not a safe thing to keep).
    func windowOpenerReady(_ open: @escaping () -> Void) {
        openWorkspaceWindow = open
        openPendingRestoredWindowsOnce()
    }

    var allWorkspaces: [AppState] {
        registry.ids.compactMap { workspaces[$0] }
    }

    var workspaceCount: Int { workspaces.count }

    func workspace(id: WorkspaceID) -> AppState? { workspaces[id] }

    /// The workspace hosting `window`, for the app-wide event monitors that
    /// only get an `NSWindow` to go on.
    func workspace(for window: NSWindow?) -> AppState? {
        guard let window else { return nil }
        return workspaces.values.first { $0.nsWindow === window }
    }

    /// Where an app-wide action (menu bar, global hotkey, Finder open) lands:
    /// the last key window, falling back to any window at all.
    var frontmost: AppState? {
        frontmostID.flatMap { workspaces[$0] } ?? allWorkspaces.first
    }

    func noteFrontmost(_ id: WorkspaceID) {
        guard workspaces[id] != nil, frontmostID != id else { return }
        frontmostID = id
        // The shared relay reports through whichever window the user is
        // looking at — a Reactotron export toast belongs on screen, not in a
        // window that may be closed. (Its device list and MCP hookup ride
        // `core`, so they don't depend on any window at all.)
        reactotronSession.app = workspaces[id]
    }

    /// A window closed. Its sessions stop either way — nothing may run behind a
    /// closed window — but what happens to the workspace depends on whether it
    /// was the last one:
    ///
    /// - **Other windows remain**: the user is done with this one. Forget it and
    ///   drop its persisted entry.
    /// - **It was the last**: the app stays resident (menu bar, hotkeys, Quick
    ///   Actions). Park the workspace so reopening restores the same tabs, which
    ///   is what background mode has always done.
    /// Windows that have started closing. `windowWillClose` fires before the
    /// last renders, and those renders must not resurrect the workspace or
    /// create a new one.
    private var closingWindows: Set<ObjectIdentifier> = []

    /// An `NSWindow` is closing: tear down the workspace it was showing.
    func closeWindow(_ window: NSWindow) {
        closingWindows.insert(ObjectIdentifier(window))
        // Forget identifiers for windows that are gone, so the set can't grow
        // for the life of the process.
        let live = Set(NSApp.windows.map(ObjectIdentifier.init))
        closingWindows.formIntersection(live)
        guard let state = workspace(for: window) else { return }
        closeWorkspace(state.id)
    }

    func closeWorkspace(_ id: WorkspaceID) {
        guard let state = workspaces[id] else { return }
        state.tearDownForWindowClose()
        state.nsWindow = nil
        // Release the presented id, so the next window that comes up can adopt
        // this workspace instead of starting an empty one beside it.
        claims = claims.filter { $0.value != id }
        // Park rather than destroy when this was the last window on screen:
        // the app stays resident (menu bar, hotkeys, Quick Actions) and
        // reopening should come back to these tabs. Measured in *windows*, not
        // workspaces — a provisional that never got one must not count.
        let othersOnScreen = workspaces.values.contains { $0 !== state && $0.nsWindow != nil }
        guard othersOnScreen else {
            enterBackground()
            return
        }
        workspaces[id] = nil
        registry.remove(id)
        layout.removeWindow(id)
        persistLayout()
        if frontmostID == id {
            frontmostID = nil
            if let next = registry.ids.first { noteFrontmost(next) }
        }
    }

    /// Reopen a window for a parked workspace (background mode → Open
    /// Droidective). The id handed to SwiftUI is a fresh handle; the parked
    /// workspace is found by adoption, so this works even when SwiftUI ignores
    /// the value and opens a window of its own.
    func reopenWindow(for id: WorkspaceID) {
        openWorkspaceWindow?()
    }

    /// Open another window, optionally pointed at a specific device. Marked
    /// explicitly fresh, so it starts a new workspace rather than adopting a
    /// parked one; the new workspace picks the device up in `restore`.
    func openNewWindow(targeting serial: String? = nil) {
        pendingFreshWindows.append(serial)
        guard let openWorkspaceWindow else {
            pendingFreshWindows.removeLast()
            return
        }
        openWorkspaceWindow()
    }

    /// Device a not-yet-created window should open on (see `openNewWindow`).
    private var pendingWindowTargets: [WorkspaceID: String] = [:]

    /// The workspace the pop-out mirror windows belong to — set when one is
    /// popped out, so they read that window's adb client and toasts. The device
    /// each window shows rides in the window's own presented value, not here.
    var mirrorWindowOwner: WorkspaceID?

    /// Open pop-out mirror windows by device serial. Held by *reference* and
    /// weakly, for the same reason `AppState.nsWindow` is: SwiftUI re-stamps its
    /// own window identifiers, so they can't be matched across a close.
    private var mirrorWindows: [String: WeakWindow] = [:]

    private final class WeakWindow {
        weak var window: NSWindow?
        init(_ window: NSWindow?) { self.window = window }
    }

    var hasMirrorWindows: Bool { !liveMirrorWindows().isEmpty }

    /// Devices currently showing in a pop-out mirror window. The wall reads
    /// this directly rather than through the registry's claims, because those
    /// are keyed by the *owner* window — and the owner is usually the very
    /// window whose wall is asking, which would exclude itself.
    var mirrorWindowSerials: Set<String> {
        Set(mirrorWindows.filter { $0.value.window != nil }.keys)
    }

    /// Bring one device's pop-out mirror window forward.
    func focusMirrorWindow(_ serial: String) {
        mirrorWindows[serial]?.window?.makeKeyAndOrderFront(nil)
    }

    /// Close one device's pop-out mirror window — "Bring Back Into the Wall".
    /// Closing releases the claim (the window's own teardown), and the wall
    /// picks the device back up on its next reconcile.
    func closeMirrorWindow(_ serial: String) {
        mirrorWindows[serial]?.window?.close()
    }

    /// A pop-out mirror window appeared (or moved to a new NSWindow). Records
    /// the device as claimed so no wall tile or tab puts a second encoder on it.
    ///
    /// Re-reporting the window it already holds must change *nothing*.
    /// `WindowAccessor` reports on every view update, and this writes state the
    /// app scene reads — `RootView`'s body asks the registry for its window
    /// ordinal, the Window menu reads the entries — so an unconditional write
    /// invalidated the scene, which ran the update, which reported again: an
    /// endless SwiftUI update loop that beach-balled the app for as long as a
    /// pop-out mirror window was open. Same identity guard the workspace
    /// windows use in `RootView` (`state.nsWindow !== window`).
    func noteMirrorWindow(serial: String, window: NSWindow?) {
        guard mirrorWindows[serial]?.window !== window else { return }
        mirrorWindows[serial] = WeakWindow(window)
        publishMirrorWindowClaims()
    }

    /// A pop-out mirror window went away — its device is free again.
    func forgetMirrorWindow(serial: String) {
        guard mirrorWindows.removeValue(forKey: serial) != nil else { return }
        publishMirrorWindowClaims()
    }

    /// Tile the open pop-out mirror windows across the active screen — the
    /// starting grid for "Arrange Mirror Windows". They stay freely draggable
    /// afterwards; this only deals the first hand.
    func arrangeMirrorWindows() {
        let windows = liveMirrorWindows()
        guard !windows.isEmpty else { return }
        let screen = windows.first?.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let area = MirrorWall.TileFrame(
            x: visible.minX, y: visible.minY, width: visible.width, height: visible.height)
        let frames = MirrorWall.windowFrames(in: area, count: windows.count)
        for (window, frame) in zip(windows, frames) {
            window.setFrame(
                NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
                display: true, animate: false)
        }
    }

    /// Open mirror windows in serial order, dropping entries whose window has
    /// been released.
    private func liveMirrorWindows() -> [NSWindow] {
        mirrorWindows.keys.sorted().compactMap { mirrorWindows[$0]?.window }
    }

    /// Mirror the pop-out windows' devices into the registry, under the pop-out
    /// mirror's pseudo-id. All of them belong to one owner window, so one
    /// replace-the-set write covers every window.
    private func publishMirrorWindowClaims() {
        guard let owner = mirrorWindowOwner ?? registry.ids.first else { return }
        let serials = Set(mirrorWindows.filter { $0.value.window != nil }.keys)
        noteMirrorClaims(serials, featureID: MirrorWindow.featureID, in: owner)
    }

    func takeWindowTarget(_ id: WorkspaceID) -> String? {
        pendingWindowTargets.removeValue(forKey: id)
    }

    /// Bring `id`'s window forward — the device picker's "it's open over there"
    /// action, and what a conflict banner's Focus button does.
    func focusWindow(_ id: WorkspaceID) {
        guard let state = workspaces[id] else { return }
        state.activateMainWindow()
    }

    /// Bring *a* window forward — the menu bar's "Open Droidective", a
    /// notification click, a Dock relaunch. Prefers the last key window, and
    /// opens a fresh one when the app is resident with none.
    func activateAnyWindow() {
        if let frontmost {
            frontmost.activateMainWindow()
        } else {
            // No workspace at all (every window closed and released): rejoin
            // the Dock, then open one.
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
            openNewWindow()
        }
    }

    /// Mirror a window's device into the registry so the conflict rules see it.
    func noteSelection(_ serial: String?, in id: WorkspaceID) {
        registry.setDevice(serial: serial, for: id)
    }

    /// Mirror a window's open tabs into the registry (same reason as
    /// `noteSelection`).
    func noteOpenFeatures(_ ids: Set<String>, in id: WorkspaceID) {
        registry.setOpenFeatures(ids, for: id)
    }

    /// Mirror the devices a window mirrors *outside* its own selection — the
    /// Mirror Wall's live tiles and its pop-out mirror windows — so the
    /// conflict rules see them (`WorkspaceRegistry.Claim`). `featureID`'s
    /// previous claims for this window are replaced; other features' are kept.
    func noteMirrorClaims(_ serials: Set<String>, featureID: String, in id: WorkspaceID) {
        // Decide before writing: publishing the same claims again must not touch
        // the registry at all. Writing an equal value through `@Observable`
        // still invalidates every reader, and these are published from view
        // updates — see `claimsChange` and `noteMirrorWindow`.
        guard let claims = registry.claimsChange(replacing: featureID, with: serials, for: id)
        else { return }
        registry.setClaims(claims, for: id)
    }

    /// Whether any *other* window still has `featureID` open — the refcount
    /// behind "don't stop the shared Reactotron relay just because this window
    /// closed its tab".
    func featureIsOpenElsewhere(_ featureID: String, excluding id: WorkspaceID) -> Bool {
        registry.entries.contains { $0.id != id && $0.openFeatureIDs.contains(featureID) }
    }

    /// Resolve an exclusive-feature collision in this window's favour: close
    /// the tab in the window that holds it, which unmounts its view and stops
    /// the session, then let this window's own tab come up. Routed through
    /// `closeTab`, so an active recording over there still gets its own
    /// confirmation rather than being dropped silently.
    func takeOverFeature(_ featureID: String, from owner: WorkspaceID) {
        workspaces[owner]?.closeTab(featureID)
    }

    // MARK: - Device list

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
        // Each window reconciles its own selection: a window whose device left
        // falls back to a free one, and its overrides refetch.
        for state in allWorkspaces {
            state.reconcileSelection(among: devices)
        }
        // Picker enrichment reads getprop over adb — Android only; a
        // simulator's runtime label already rides in `Device.product`.
        for device in devices.filter(\.isReady)
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

    /// Toolchain for a serial in the current device set — Android when unknown
    /// (a device that just disconnected mid-run was adb-backed in every
    /// existing flow).
    func platform(for serial: String) -> DevicePlatform {
        devices.first { $0.serial == serial }?.platform ?? .android
    }

    func refreshDevices() {
        Task { await env.monitor.invalidate() }
        Task { await env.simulatorMonitor.invalidate() }
    }

    /// Ready devices that are wireless (serial is ip:port) — eligible for
    /// the device bar's Disconnect control.
    var readyWirelessDevices: [Device] {
        devices.filter { $0.isReady && $0.isWireless }
    }

    var readyDeviceCount: Int { devices.filter(\.isReady).count }

    var readyDevices: [Device] { devices.filter(\.isReady) }

    // MARK: - Polling

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
        // it's right even when every window has been closed all along.
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

    /// The last window closed. Every window has already torn its own sessions
    /// down (`closeWorkspace`); this just widens polling so no feature process
    /// or poll outlives the UI.
    func enterBackground() {
        setForeground(false)
    }

    // MARK: - Role

    /// Set the moment the user picks a role this session, so `bootstrap`'s
    /// async layout load can't overwrite the just-seeded curation.
    private var roleChosenThisSession = false

    /// The user's current role, nil when they chose "show me everything".
    var selectedRole: UserRole? {
        layout.selectedRole.flatMap(UserRole.init(rawValue:))
    }

    /// Apply the user's role choice (first-run or "Change role"): curate the
    /// enabled set + sidebar order to that role, or keep everything on for
    /// `nil`. Every window resets to a single Home tab — the role decides what
    /// exists, so a stale tab of a now-hidden feature would be a dead end.
    func chooseRole(_ role: UserRole?, includeReactNativeStack: Bool) {
        let isChange = layout.selectedRole != nil
        Telemetry.shared.trackRoleChosen(role?.rawValue ?? "all", isChange: isChange)
        Telemetry.shared.applyRole(role?.rawValue)
        if let role {
            layout.seedRole(role, includeReactNativeStack: includeReactNativeStack)
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
        // A role without Reactotron also loses the Settings ▸ MCP tab — a
        // running MCP server would have no visible off-switch, so turn it off
        // with the role switch (re-enable any time from a role that has the
        // feature). Before the reset loop: with the pref cleared,
        // `keepsRelayAlive` no longer exempts the Reactotron session.
        if mcp.isEnabled, role != nil, role != .reactNativeDeveloper,
           !(frontmost?.enabledFeatures.contains { $0.id == "reactotron" } ?? false) {
            UserDefaults.standard.set(false, forKey: mcpEnabledKey)
            mcp.applySettings()
        }
        for state in allWorkspaces {
            state.resetForRoleChange()
        }
    }

    // MARK: - Virtual devices

    /// Coalesces the AVD/simulator refresh: every window's device bar asks for
    /// one when the connected set changes, and `emulator -list-avds` is a
    /// process launch — one per change, not one per window.
    private var avdRefresh: Task<Void, Never>?
    private var simulatorRefresh: Task<Void, Never>?

    /// Refresh `availableAvds` from `emulator -list-avds`, tagging which are
    /// already running. A no-op (clears the list) when the SDK emulator is absent.
    func refreshAvds() async {
        if let avdRefresh { return await avdRefresh.value }
        let task = Task { [self] in
            guard FeatureRegistry.visiblePlatforms(for: selectedRole).contains(.android),
                  await env.engine.emulators.emulatorInstalled() else {
                availableAvds = []
                return
            }
            availableAvds = await env.engine.emulators.listAvds(devices: devices)
        }
        avdRefresh = task
        await task.value
        avdRefresh = nil
    }

    /// Refresh `availableSimulators` — the short recently-used list for the
    /// device-bar menu (Xcode installs ~30 sims; the Emulators screen lists
    /// them all). Empty without Xcode.
    func refreshSimulators() async {
        if let simulatorRefresh { return await simulatorRefresh.value }
        let task = Task { [self] in
            guard FeatureRegistry.visiblePlatforms(for: selectedRole).contains(.iosSimulator) else {
                availableSimulators = []
                return
            }
            availableSimulators = SimulatorListParser.quickPicks(await env.simulatorMonitor.list())
        }
        simulatorRefresh = task
        await task.value
        simulatorRefresh = nil
    }

    // MARK: - Quit

    /// `applicationShouldTerminate`: true to quit now, false when some window
    /// holds losable work. Windows are prompted one at a time — each
    /// resolution calls back into `resumeQuit`, which moves to the next.
    func requestQuit() -> Bool {
        resumeQuitChain()
    }

    /// A window finished its quit confirmation: prompt the next one, or quit.
    func resumeQuit() {
        if resumeQuitChain() { finishQuitNow() }
    }

    /// Prompts the first window with work at stake and returns false; true when
    /// every window is clear.
    private func resumeQuitChain() -> Bool {
        guard let blocked = allWorkspaces.first(where: \.blocksQuit) else { return true }
        // Bring the window holding the work forward, or its confirmation would
        // appear on a sheet the user can't see.
        blocked.activateMainWindow()
        blocked.beginQuitPrompt()
        return false
    }

    /// Every window is clear: snapshot each one's terminals, stop the shared
    /// listeners, flush the layout, and let termination proceed. Always defers
    /// the reply, so the layout write can never race process exit.
    func finishQuitNow() {
        for state in allWorkspaces {
            state.snapshotTerminalsForQuit()
        }
        Task {
            await mcp.stopForQuit()
            if reactotronSession.isRunning { await reactotronSession.stopForQuit() }
            // Mirror sessions own an `adb forward` tunnel each. Their views'
            // teardown is fire-and-forget, so at quit it never lands and the
            // tunnels stay registered in the adb server — six of them for a full
            // Mirror Wall. Tear them down here, where termination is already
            // deferred.
            await MirrorSessions.shared.stopAllForQuit()
            // Flush before termination — `persistLayout` saves through a
            // fire-and-forget Task, and that write racing process exit would
            // lose whatever this quit just recorded (the terminal-resume
            // snapshots above included).
            await flushLayout()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    /// Abandon a deferred quit: clear the delegate's in-quit flag first, so a
    /// later window close still routes through background mode instead of
    /// being mistaken for quit teardown. The updater must hear about it too — a
    /// quit it requested that got cancelled here would otherwise leave its pill
    /// on "Installing…" forever (that phase's only exit was this quit).
    func cancelQuit() {
        frontmost?.appDelegate?.isQuitting = false
        #if !APPSTORE
            SparkleUpdater.shared.noteQuitDeclined()
        #endif
        NSApp.reply(toApplicationShouldTerminate: false)
    }

    // MARK: - Bundles

    /// Add a bundle to the shared list and return it, so the calling window can
    /// select it.
    func addBundle(nickname: String, packageId: String) -> AppBundle {
        let bundle = AppBundle(
            nickname: nickname.isEmpty ? packageId : nickname,
            packageId: packageId,
            createdAt: Date().timeIntervalSince1970 * 1000
        )
        bundles.append(bundle)
        persistBundles()
        return bundle
    }

    func updateBundle(_ bundle: AppBundle) {
        guard let index = bundles.firstIndex(where: { $0.id == bundle.id }) else { return }
        bundles[index] = bundle
        persistBundles()
    }

    /// Remove a bundle everywhere. Windows that had it selected fall back to
    /// the first remaining one, matching the single-window behavior.
    func removeBundle(id: String) {
        bundles.removeAll { $0.id == id }
        persistBundles()
        for state in allWorkspaces where state.selectedBundleId == id {
            state.selectBundle(bundles.first?.id)
        }
    }

    func noteBundleSelected(_ id: String?) {
        lastSelectedBundleId = id
        Task { try? await env.stores.prefs.update { $0.selectedBundleId = id } }
    }

    private func persistBundles() {
        let snapshot = bundles
        Task { try? await env.stores.bundles.save(snapshot) }
    }

    // MARK: - Persistence

    /// Save the shared layout. No-ops until the persisted layout has loaded, so
    /// the in-memory default can't clobber the user's file.
    func persistLayout(force: Bool = false) {
        guard didLoadLayout || force else { return }
        let snapshot = layout
        Task { try? await env.stores.layout.save(snapshot) }
    }

    /// Flush the layout synchronously-ish before termination — `persistLayout`
    /// saves through a fire-and-forget Task, and that write racing process exit
    /// would lose whatever the quit just recorded.
    func flushLayout() async {
        guard didLoadLayout else { return }
        try? await env.stores.layout.save(layout)
    }

    func persistUsage() {
        let snapshot = usageStats
        Task { try? await env.stores.usage.save(snapshot) }
    }
}
