import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the Quick Actions panel — a Raycast-style floating
/// mini app summoned by a global hotkey (or the menu bar). The root shows a
/// grid of everything runnable in place (instant/toggle actions, in-panel
/// forms, saved custom commands, Manage Apps / Emulators / Install APK) with
/// an "Open in Droidective" list below for the full-app screens. Esc pops a
/// screen; at the root it closes. A session resumes where it left off when
/// reopened within the Settings ▸ Quick Actions window (default 5 minutes).
@MainActor
enum QuickActionsPanel {
    static func toggle(state: AppState) {
        let controller = FloatingPanelController.quickActions
        if controller.isVisible {
            controller.close()
            return
        }
        resetSessionIfExpired()
        present(state: state)
    }

    /// APKs double-clicked in Finder land here (via `InstallInbox`): the panel
    /// opens straight on the APK options screen — install in place, or take
    /// the file into APK Studio / the Install App screen.
    static func showAPKOptions(_ urls: [URL], state: AppState) {
        guard !urls.isEmpty else { return }
        // Same expiry rule as toggle — a stale session's device pick (worst
        // case a stale "All devices") must not govern this install.
        resetSessionIfExpired()
        let memory = QuickPanelMemory.shared
        memory.stack = [.apk(urls)]
        memory.closedAt = nil
        let controller = FloatingPanelController.quickActions
        // Rebuild if already up — the view seeds its screen stack at init.
        if controller.isVisible { controller.close() }
        // The app activation that delivered the APK can shuffle key windows
        // for a beat; don't let that churn dismiss the panel it opens.
        controller.holdsThroughResign = true
        present(state: state)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            controller.holdsThroughResign = false
        }
    }

    /// Clear the resumable session once it's older than the Settings ▸ Quick
    /// Actions window (0 = never resume).
    private static func resetSessionIfExpired() {
        let memory = QuickPanelMemory.shared
        let minutes = UserDefaults.standard.object(forKey: quickPanelResumeMinutesKey) as? Int ?? 5
        let expired = memory.closedAt.map { Date().timeIntervalSince($0) > Double(minutes) * 60 } ?? true
        if minutes <= 0 || expired { memory.reset() }
    }

    private static func present(state: AppState) {
        // While backgrounded the device poll is widened, so the list can be
        // stale — refresh once on open.
        state.refreshDevices()
        let controller = FloatingPanelController.quickActions
        controller.onClosed = { QuickPanelMemory.shared.closedAt = Date() }
        controller.show { close in
            QuickActionsView(onClose: close)
                .environment(state)
                .tint(.brandAccent)
        }
    }
}

/// One screen of the panel's push-navigation stack.
enum QuickScreen: Equatable {
    case root
    /// A form action's in-panel input screen (feature id).
    case form(String)
    /// Installed apps on the selected device.
    case apps
    /// Per-app verbs (open / stop / clear / uninstall …).
    case appActions(packageId: String, display: String)
    /// AVDs + iOS Simulators to boot (running ones select their device).
    case emulators
    /// Interstitial before a device-scoped action when several devices are
    /// connected; `allowAll` offers the ⌘⏎ run-on-all path.
    case pickDevice(allowAll: Bool)
    /// Options for APKs opened from Finder: install in place, or hand them to
    /// APK Studio / the Install App screen in the main window.
    case apk([URL])
}

/// The panel's session state, kept outside the view so closing (click-away,
/// auto-close after a run) and reopening within the resume window lands back
/// on the same screen with the same device choice.
@MainActor
final class QuickPanelMemory {
    static let shared = QuickPanelMemory()

    var stack: [QuickScreen] = []
    /// The serial from the most recent device interstitial (or Switch
    /// Device) — the target for device-scoped screens (Manage Apps) and the
    /// footer. Stored as the serial, not a flag, so a device that
    /// disconnected while the panel was closed falls back visibly instead of
    /// silently retargeting. Actions themselves re-ask before every run.
    var pickedSerial: String?
    /// The exact serials approved by an "All devices" pick. Fan-outs use this
    /// ∩ currently-ready, so a device plugged in *after* the approval is
    /// never targeted by it.
    var approvedAllSerials: [String]?
    var closedAt: Date?

    func reset() {
        stack = []
        pickedSerial = nil
        approvedAllSerials = nil
        closedAt = nil
    }
}

/// What a panel run produced. The footer renders the message plus Copy /
/// Reveal-in-Finder affordances when the result carries them — the panel's
/// equivalent of the in-app result toasts.
struct QuickRunOutcome {
    var message: String
    var ok: Bool
    var copyText: String?
    var revealPath: String?

    init(message: String, ok: Bool, copyText: String? = nil, revealPath: String? = nil) {
        self.message = message
        self.ok = ok
        self.copyText = copyText
        self.revealPath = revealPath
    }

    init(result: FeatureResult) {
        self.init(
            message: result.message, ok: result.ok,
            copyText: result.copyText, revealPath: result.revealPath
        )
    }
}

struct QuickActionsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme

    let onClose: () -> Void

    @State private var stack: [QuickScreen]
    @State private var query = ""
    @State private var highlighted = 0
    @State private var commands: [CustomCommand] = []
    /// Installed packages of the selected device; nil while loading.
    @State private var installedApps: [String]?
    /// Row id of the action in flight (drives its spinner), nil when idle.
    @State private var runningRowID: String?
    /// Destructive row armed by a first ⏎, awaiting the confirming second.
    @State private var armedRowID: String?
    /// The action held while the device interstitial is up.
    @State private var pendingAction: QuickRow.Action?
    /// This session's explicit device pick; nil until the interstitial ran.
    @State private var pickedSerial: String?
    /// The serials approved by an "All devices" pick, nil otherwise.
    @State private var approvedAllSerials: [String]?
    /// True while the Emulators screen's AVD/simulator refresh is in flight.
    @State private var emulatorsLoading = false
    /// Outcome of the last action run from the panel, shown in the footer.
    @State private var lastRun: QuickRunOutcome?
    @FocusState private var searchFocused: Bool

    @MainActor init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let memory = QuickPanelMemory.shared
        _stack = State(initialValue: memory.stack)
        _pickedSerial = State(initialValue: memory.pickedSerial)
        _approvedAllSerials = State(initialValue: memory.approvedAllSerials)
    }

    private static let digitKeys: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8"]
    private static let gridColumns = 5

    private var accentText: Color { Color.brandAccent.contrastingForeground(for: colorScheme) }

    private var screen: QuickScreen { stack.last ?? .root }

    private var isRoot: Bool { stack.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            Divider()
            footer
        }
        .frame(width: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background { shortcutButtons }
        .onExitCommand { escape() }
        .task {
            let loaded = await state.env.stores.customCommands.load()
            guard !Task.isCancelled else { return }
            commands = loaded
        }
        .task(id: taskKey) { await loadScreenData() }
        .onAppear {
            // Focus must land after the panel becomes key — setting it
            // synchronously in onAppear loses the race.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                searchFocused = true
            }
        }
        .onChange(of: query) {
            highlighted = 0
            armedRowID = nil
        }
    }

    // MARK: - Navigation

    private func push(_ next: QuickScreen) {
        stack.append(next)
        query = ""
        highlighted = 0
        armedRowID = nil
        lastRun = nil
        syncMemory()
        refocusSearch()
    }

    private func pop() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
        query = ""
        highlighted = 0
        armedRowID = nil
        pendingAction = nil
        lastRun = nil
        syncMemory()
        refocusSearch()
    }

    /// Esc pops one screen; at the root it dismisses the panel.
    private func escape() {
        if stack.isEmpty {
            onClose()
        } else {
            pop()
        }
    }

    /// Mirror the navigation/device state into the session memory, so a
    /// close → reopen within the resume window restores it. A pending device
    /// interstitial isn't kept — its held action doesn't survive the view.
    private func syncMemory() {
        let memory = QuickPanelMemory.shared
        memory.stack = stack.filter {
            if case .pickDevice = $0 { return false }
            return true
        }
        memory.pickedSerial = pickedSerial
        memory.approvedAllSerials = approvedAllSerials
    }

    private func refocusSearch() {
        guard !isFormScreen else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            searchFocused = true
        }
    }

    private var isFormScreen: Bool {
        if case .form = screen { return true }
        return false
    }

    private var formFeature: FeatureDef? {
        if case .form(let id) = screen { return FeatureRegistry.byID[id] }
        return nil
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        HStack(spacing: 12) {
            if stack.isEmpty {
                Image(systemName: "bolt.fill")
                    .font(.app(.title))
                    .foregroundStyle(.brandAccent)
            } else {
                Button(action: pop) {
                    Image(systemName: "chevron.left")
                        .font(.app(.title2).weight(.semibold))
                        .foregroundStyle(.textMuted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back (esc)")
            }
            if let feature = formFeature {
                Text(feature.title)
                    .font(.app(.title))
                Spacer()
                Image(systemName: feature.icon)
                    .font(.app(.title2))
                    .foregroundStyle(.brandAccent)
            } else {
                TextField(searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.app(.title))
                    .focused($searchFocused)
                    .onSubmit { if let row = highlightedRow { activate(row) } }
                    .onKeyPress(.downArrow) { moveVertical(1); return .handled }
                    .onKeyPress(.upArrow) { moveVertical(-1); return .handled }
                    .onKeyPress(.leftArrow) { moveHorizontal(-1) }
                    .onKeyPress(.rightArrow) { moveHorizontal(1) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var searchPlaceholder: String {
        switch screen {
        case .root: return "Run a quick action…"
        case .apps: return "Search installed apps…"
        case .appActions(_, let display): return display
        case .emulators: return "Boot an emulator or simulator…"
        case .pickDevice: return "Pick a device for this action…"
        case .apk(let urls):
            return urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) APKs"
        case .form: return ""
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if let feature = formFeature {
            Divider()
            QuickActionFormView(
                feature: feature,
                targetsProvider: { explicitTargets(for: $0) },
                onFinish: finish
            )
        } else if isRoot {
            Divider()
            rootContent
        } else {
            let rows = flatItems
            if !rows.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, index: index, isHighlighted: index == highlighted, showsDigitHint: true)
                            .onTapGesture { activate(row) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(index == highlighted ? [.isButton, .isSelected] : .isButton)
                            .accessibilityLabel(row.title)
                    }
                }
                .padding(6)
            } else {
                Divider()
                Text(emptyMessage)
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                    .padding(14)
            }
        }
    }

    /// The root: a grid of in-panel actions, then the open-in-app list. Fixed
    /// height with everything reachable by scrolling — the grid holds every
    /// action, not a truncated top-8.
    private var rootContent: some View {
        let grid = rootGridItems
        let appOpeners = rootAppItems
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !grid.isEmpty {
                        sectionLabel("Quick actions")
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(), spacing: 8),
                                count: Self.gridColumns
                            ),
                            spacing: 8
                        ) {
                            ForEach(Array(grid.enumerated()), id: \.element.id) { index, row in
                                gridTile(row, isHighlighted: index == highlighted)
                                    .id(row.id)
                                    .onTapGesture { activate(row) }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(index == highlighted ? [.isButton, .isSelected] : .isButton)
                                    .accessibilityLabel(row.title)
                            }
                        }
                    }
                    if !appOpeners.isEmpty {
                        sectionLabel("Open in Droidective")
                            .padding(.top, grid.isEmpty ? 0 : 4)
                        VStack(spacing: 0) {
                            ForEach(Array(appOpeners.enumerated()), id: \.element.id) { offset, row in
                                let index = grid.count + offset
                                rowView(row, index: index, isHighlighted: index == highlighted, showsDigitHint: false)
                                    .id(row.id)
                                    .onTapGesture { activate(row) }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(index == highlighted ? [.isButton, .isSelected] : .isButton)
                                    .accessibilityLabel(row.title)
                            }
                        }
                    }
                    if grid.isEmpty && appOpeners.isEmpty {
                        Text(query.isEmpty ? "Nothing to run yet" : "No matching actions")
                            .font(.app(.callout))
                            .foregroundStyle(.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
            .frame(height: 400)
            .onChange(of: highlighted) {
                let items = flatItems
                guard items.indices.contains(highlighted) else { return }
                proxy.scrollTo(items[highlighted].id)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.app(.caption).weight(.semibold))
            .foregroundStyle(.textMuted)
            .padding(.horizontal, 4)
    }

    private var emptyMessage: String {
        switch screen {
        case .apps where panelTargetSerial == nil: return "Connect a device to manage its apps"
        case .apps where installedApps == nil: return "Loading apps…"
        case .apps: return "No matching apps"
        case .emulators where emulatorsLoading: return "Looking for emulators and simulators…"
        case .emulators: return "No emulators or simulators found"
        case .pickDevice: return "No ready devices"
        default: return query.isEmpty ? "Nothing to run yet" : "No matching actions"
        }
    }

    // MARK: - Rows

    /// One grid tile or list row, and what activating it does.
    struct QuickRow: Identifiable {
        enum Action {
            case runCommand(CustomCommand)
            case runFeature(FeatureDef)
            case push(QuickScreen)
            case openInApp(FeatureDef)
            /// Install APK from the grid: ask for files first.
            case installAPK
            /// Install these specific files (the Finder-opened APK screen).
            case installFiles([URL])
            /// Load an APK into APK Studio on `tab` and open the main window.
            case openStudio(tab: ApkStudioTab, url: URL)
            /// Stage the files in the main window's Install App screen.
            case stageInstallScreen([URL])
            case appVerb(AppControlService.AppAction, packageId: String)
            case launchAvd(Avd)
            case bootSimulator(Simulator)
            /// Switch the app's selection (Switch Device screen, running
            /// emulator rows).
            case selectDevice(serial: String, label: String)
            /// Resolve the interstitial, then perform the held action.
            case chooseDevice(serial: String, label: String)
            case chooseAllDevices
        }

        let id: String
        let icon: String
        let title: String
        var subtitle: String?
        /// Small trailing tag, e.g. "Running" / "Booted".
        var badge: String?
        var destructive = false
        /// Renders a › chevron: activating navigates instead of running.
        var pushes = false
        let action: Action
    }

    /// Every navigable item of the current screen, in highlight order. The
    /// root is grid + open-in-app list; sub-screens are flat lists.
    private var flatItems: [QuickRow] {
        switch screen {
        case .root: return rootGridItems + rootAppItems
        case .apps: return appRows
        case .appActions(let packageId, _): return appActionRows(packageId)
        case .emulators: return Array(emulatorRows.prefix(8))
        case .pickDevice: return pickDeviceRows
        case .apk(let urls): return apkRows(urls)
        case .form: return []
        }
    }

    private var highlightedRow: QuickRow? {
        let rows = flatItems
        return rows.indices.contains(highlighted) ? rows[highlighted] : nil
    }

    /// The grid: saved commands, the panel's own screens, and every
    /// implemented instant/toggle/form action (hub members included).
    private var rootGridItems: [QuickRow] {
        var rows: [QuickRow] = PaletteSearch.commands(commands, query: query).map { command in
            QuickRow(
                id: "command:\(command.id)", icon: "terminal",
                title: command.name, subtitle: command.command,
                action: .runCommand(command)
            )
        }
        rows += nativeRows
        rows += PaletteSearch.quickActions(
            query: query,
            implemented: FeatureEngine.implementedIDs,
            enabled: state.layout.effectiveEnabledIDs,
            favorites: state.layout.favorites
        )
        .map { feature in
            QuickRow(
                id: "feature:\(feature.id)", icon: feature.icon,
                title: feature.title, subtitle: feature.subtitle,
                pushes: feature.kind == .formAction,
                action: feature.kind == .formAction
                    ? .push(.form(feature.id))
                    : .runFeature(feature)
            )
        }
        guard query.isEmpty else { return rows }
        // Pinned tiles lead the whole grid — native screens included, in the
        // favorites' own order — ahead of commands and the registry order.
        let favorites = state.layout.favorites
        var pinned: [QuickRow] = []
        var rest: [QuickRow] = []
        for row in rows {
            if let id = pinnableFeatureID(of: row), favorites.contains(id) {
                pinned.append(row)
            } else {
                rest.append(row)
            }
        }
        pinned.sort { lhs, rhs in
            let li = pinnableFeatureID(of: lhs).flatMap(favorites.firstIndex) ?? .max
            let ri = pinnableFeatureID(of: rhs).flatMap(favorites.firstIndex) ?? .max
            return li < ri
        }
        return pinned + rest
    }

    /// Full-app screens below the grid — everything that can't run in a
    /// panel opens the main window instead. The panel's native screens
    /// replace their in-app counterparts here, and it mirrors the app: only
    /// enabled features (per the user's role/catalog curation) appear.
    private var rootAppItems: [QuickRow] {
        let covered: Set<String> = ["apps", "emulators", "install-app"]
        let enabled = state.layout.effectiveEnabledIDs
        return PaletteSearch.features(
            query: query,
            enabled: enabled,
            favorites: state.layout.favorites
        )
        .filter {
            ($0.kind == .view || $0.kind == .system)
                && !covered.contains($0.id) && enabled.contains($0.id)
        }
        .map { feature in
            QuickRow(
                id: "open:\(feature.id)", icon: feature.icon,
                title: feature.title, subtitle: feature.subtitle,
                action: .openInApp(feature)
            )
        }
    }

    /// The panel's own sub-screens and actions, searchable alongside the
    /// rest. Each fronts a registry feature and follows its enabledness, so
    /// the panel mirrors the app's role/catalog curation here too.
    private var nativeRows: [QuickRow] {
        let enabled = state.layout.effectiveEnabledIDs
        var rows: [QuickRow] = []
        if enabled.contains("apps"), matchesNative(title: "Manage Apps", keywords: [
            "apps", "app", "packages", "manage", "open", "force stop",
            "clear data", "clear cache", "uninstall",
        ]) {
            rows.append(QuickRow(
                id: "screen:apps", icon: "square.grid.3x3",
                title: "Manage Apps",
                subtitle: "Open, force-stop, clear cache/data, uninstall",
                pushes: true, action: .push(.apps)
            ))
        }
        if enabled.contains("emulators"), matchesNative(title: "Emulators", keywords: [
            "emulator", "simulator", "avd", "boot", "launch", "virtual",
        ]) {
            rows.append(QuickRow(
                id: "screen:emulators", icon: "play.display",
                title: "Emulators",
                subtitle: "Boot an Android emulator or iOS Simulator",
                pushes: true, action: .push(.emulators)
            ))
        }
        if enabled.contains("install-app"),
           matchesNative(title: "Install APK", keywords: ["install", "apk", "sideload", "package"]) {
            rows.append(QuickRow(
                id: "native:install", icon: "arrow.down.app",
                title: "Install APK",
                subtitle: "Pick .apk files and install them",
                action: .installAPK
            ))
        }
        return rows
    }

    private func matchesNative(title: String, keywords: [String]) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(needle)
            || keywords.contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    /// Installed apps, saved bundles pinned first — mirroring how the device
    /// bar treats bundles as the apps you actually work on. O(1) nickname
    /// lookups and an early cap: with hundreds of packages this recomputes
    /// per keystroke, so no per-package bundle scans and no rows built past
    /// what the list shows.
    private var appRows: [QuickRow] {
        guard let installedApps else { return [] }
        let nicknames = Dictionary(
            state.bundles.map { ($0.packageId, $0.nickname) },
            uniquingKeysWith: { first, _ in first }
        )
        let pinned = installedApps.filter { nicknames[$0] != nil }
        let rest = installedApps.filter { nicknames[$0] == nil }
        let matching = (pinned + rest).filter { packageId in
            guard !query.isEmpty else { return true }
            return packageId.localizedCaseInsensitiveContains(query)
                || AppListing.displayName(for: packageId).localizedCaseInsensitiveContains(query)
                || (nicknames[packageId]?.localizedCaseInsensitiveContains(query) ?? false)
        }
        return matching.prefix(8).map { packageId in
            let display = nicknames[packageId] ?? AppListing.displayName(for: packageId)
            return QuickRow(
                id: "app:\(packageId)", icon: "app.badge",
                title: display,
                subtitle: packageId,
                badge: nicknames[packageId] != nil ? "saved" : nil,
                pushes: true,
                action: .push(.appActions(packageId: packageId, display: display))
            )
        }
    }

    /// One row per `AppAction` case — the exhaustive switches make a new verb
    /// in ADBKit a compile error here instead of a silently missing row.
    private func appActionRows(_ packageId: String) -> [QuickRow] {
        AppControlService.AppAction.allCases
            .filter { query.isEmpty || Self.verbTitle($0).localizedCaseInsensitiveContains(query) }
            .map { verb in
                QuickRow(
                    id: "verb:\(verb.rawValue):\(packageId)", icon: Self.verbIcon(verb),
                    title: Self.verbTitle(verb), subtitle: packageId,
                    destructive: verb.isDestructive,
                    action: .appVerb(verb, packageId: packageId)
                )
            }
    }

    private static func verbTitle(_ verb: AppControlService.AppAction) -> String {
        switch verb {
        case .open: return "Open"
        case .stop: return "Force Stop"
        case .minimize: return "Minimize"
        case .clearCache: return "Clear Cache"
        case .clearData: return "Clear Data"
        case .uninstall: return "Uninstall"
        }
    }

    private static func verbIcon(_ verb: AppControlService.AppAction) -> String {
        switch verb {
        case .open: return "play.circle"
        case .stop: return "stop.circle"
        case .minimize: return "chevron.down.circle"
        case .clearCache: return "eraser"
        case .clearData: return "eraser.fill"
        case .uninstall: return "trash"
        }
    }

    /// AVDs then iOS Simulators. Idle ones boot; running/booted ones switch
    /// the selection to their device instead.
    private var emulatorRows: [QuickRow] {
        var rows: [QuickRow] = state.availableAvds.map { avd in
            if let serial = avd.runningSerial {
                return QuickRow(
                    id: "avd:\(avd.name)", icon: "memorychip",
                    title: avd.displayName, subtitle: "Android emulator",
                    badge: "Running",
                    action: .selectDevice(serial: serial, label: avd.displayName)
                )
            }
            return QuickRow(
                id: "avd:\(avd.name)", icon: "memorychip",
                title: avd.displayName, subtitle: "Android emulator",
                action: .launchAvd(avd)
            )
        }
        rows += state.availableSimulators.filter(\.isAvailable).map { simulator in
            if simulator.state == "Booted" {
                return QuickRow(
                    id: "sim:\(simulator.udid)", icon: "iphone",
                    title: simulator.name, subtitle: simulator.runtime,
                    badge: "Booted",
                    action: .selectDevice(serial: simulator.udid, label: simulator.name)
                )
            }
            return QuickRow(
                id: "sim:\(simulator.udid)", icon: "iphone",
                title: simulator.name, subtitle: simulator.runtime,
                action: .bootSimulator(simulator)
            )
        }
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var readyDevices: [Device] { state.devices.filter(\.isReady) }

    /// Ready-device serials in bar order — the input `PanelTargeting` resolves
    /// the panel's target(s) from.
    private var readySerials: [String] { readyDevices.map(\.serial) }

    private var matchingReadyDevices: [Device] {
        readyDevices.filter {
            query.isEmpty || state.deviceTitle($0).localizedCaseInsensitiveContains(query)
        }
    }

    /// What you can do with Finder-opened APKs: install right here, or hand
    /// them to APK Studio (inspect/decompile/sign) or the Install App screen.
    /// The studio takes one APK — with several, it gets the first.
    private func apkRows(_ urls: [URL]) -> [QuickRow] {
        guard let first = urls.first else { return [] }
        let name = urls.count == 1 ? first.lastPathComponent : "\(urls.count) APKs"
        var rows = [QuickRow(
            id: "apk:install", icon: "arrow.down.app",
            title: "Install", subtitle: "Install \(name) on a device",
            action: .installFiles(urls)
        )]
        let studioTabs: [(String, ApkStudioTab)] = [
            ("apk-inspector", .inspect),
            ("apk-decompile", .decompile),
            ("apk-sign", .sign),
        ]
        // Loading this APK replaces whatever APK Studio already has open —
        // if a different session is loaded, ask for the confirming second ⏎
        // like the destructive app verbs do.
        let clobbersStudio = state.apkStudio.apk.map { $0 != first } ?? false
        rows += studioTabs.compactMap { featureID, tab in
            guard let feature = FeatureRegistry.byID[featureID] else { return nil }
            return QuickRow(
                id: "apk:\(featureID)", icon: feature.icon,
                title: feature.title,
                subtitle: clobbersStudio
                    ? "Replaces the APK loaded in APK Studio"
                    : "\(first.lastPathComponent) in APK Studio",
                destructive: clobbersStudio,
                action: .openStudio(tab: tab, url: first)
            )
        }
        rows.append(QuickRow(
            id: "apk:install-screen", icon: "square.grid.3x3",
            title: "Open in App",
            subtitle: "Stage \(name) with the full device picker",
            action: .stageInstallScreen(urls)
        ))
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// The interstitial's rows — one per ready device, no persistent-selection
    /// badge (each action picks afresh). Run-on-all lives in the footer (⌘⏎),
    /// not the list.
    private var pickDeviceRows: [QuickRow] {
        matchingReadyDevices.map { device in
            QuickRow(
                id: "pick:\(device.serial)",
                icon: device.platform == .iosSimulator ? "iphone" : "iphone.gen3",
                title: device.label,
                subtitle: state.deviceTitle(device),
                action: .chooseDevice(serial: device.serial, label: device.label)
            )
        }
    }

    // MARK: - Row rendering

    private func gridTile(_ row: QuickRow, isHighlighted: Bool) -> some View {
        VStack(spacing: 6) {
            if runningRowID == row.id {
                ProgressView().controlSize(.small).frame(height: 26)
            } else {
                Image(systemName: row.icon)
                    .font(.app(.title2))
                    .frame(height: 26)
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(accentText) : AnyShapeStyle(.brandAccent))
            }
            Text(row.title)
                .font(.app(.caption))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            isHighlighted ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.quaternary.opacity(0.5)),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(alignment: .topTrailing) {
            if isPinned(row) {
                Image(systemName: "pin.fill")
                    .font(.app(size: 8))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(accentText.opacity(0.8)) : AnyShapeStyle(.brandAccent))
                    .padding(4)
            }
        }
        .foregroundStyle(isHighlighted ? accentText : .primary)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .help(row.subtitle ?? row.title)
    }

    private func isPinned(_ row: QuickRow) -> Bool {
        pinnableFeatureID(of: row).map { state.layout.favorites.contains($0) } ?? false
    }

    private func rowView(
        _ row: QuickRow, index: Int, isHighlighted: Bool, showsDigitHint: Bool
    ) -> some View {
        let isArmed = armedRowID == row.id
        // Destructive rows keep their danger color when highlighted (a red
        // fill instead of the accent), and an armed row says so on the row
        // itself — the footer warning alone was easy to miss.
        let highlightFill: AnyShapeStyle = row.destructive
            ? AnyShapeStyle(Color.red)
            : AnyShapeStyle(.brandAccent)
        return HStack(spacing: 10) {
            if runningRowID == row.id {
                ProgressView().controlSize(.small).frame(width: 22)
            } else {
                Image(systemName: row.icon)
                    .frame(width: 22)
                    .foregroundStyle(iconStyle(row, isHighlighted: isHighlighted))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .foregroundStyle(row.destructive && !isHighlighted ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.app(.caption))
                        .foregroundStyle(isHighlighted ? accentText.opacity(0.75) : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isPinned(row) {
                Image(systemName: "pin.fill")
                    .font(.app(.caption2))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(accentText.opacity(0.8)) : AnyShapeStyle(.brandAccent))
            }
            if isArmed {
                Text("⏎ to confirm")
                    .font(.app(.caption2).weight(.semibold))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(accentText) : AnyShapeStyle(.orange))
            } else if let badge = row.badge {
                Text(badge)
                    .font(.app(.caption2))
                    .foregroundStyle(isHighlighted ? accentText.opacity(0.75) : .secondary)
            }
            if case .openInApp = row.action {
                Image(systemName: "arrow.up.forward.app")
                    .font(.app(.caption))
                    .foregroundStyle(isHighlighted ? accentText.opacity(0.75) : .secondary)
            }
            if row.pushes {
                Image(systemName: "chevron.right")
                    .font(.app(.caption))
                    .foregroundStyle(isHighlighted ? accentText.opacity(0.75) : .secondary)
            }
            if showsDigitHint, index < 8 {
                KeyHint("⌘\(index + 1)", prominent: isHighlighted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isHighlighted ? highlightFill : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .foregroundStyle(isHighlighted ? accentText : .primary)
        .contentShape(Rectangle())
    }

    private func iconStyle(_ row: QuickRow, isHighlighted: Bool) -> AnyShapeStyle {
        if isHighlighted { return AnyShapeStyle(accentText) }
        if row.destructive { return AnyShapeStyle(.red) }
        return AnyShapeStyle(.brandAccent)
    }

    /// Hidden buttons backing ⌘1–8 jumps, ⌘P pin/unpin, and — only while the
    /// interstitial offers it, so it can't collide with the form's ⌘⏎ Run —
    /// ⌘⏎ run-on-all.
    private var shortcutButtons: some View {
        ZStack {
            ForEach(Array(Self.digitKeys.enumerated()), id: \.offset) { index, key in
                Button("") {
                    let rows = flatItems
                    if rows.indices.contains(index) { activate(rows[index]) }
                }
                .keyboardShortcut(key, modifiers: .command)
            }
            Button("") {
                if let id = pinnableFeatureID(of: highlightedRow) {
                    state.toggleFavorite(id)
                }
            }
            .keyboardShortcut("p", modifiers: .command)
            if case .pickDevice(allowAll: true) = screen {
                Button("") { perform(.chooseAllDevices) }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Screen data

    /// Re-keys per screen + device, so entering Apps loads the package list
    /// and Emulators refreshes AVDs/simulators. The Apps key must use
    /// `panelTargetSerial` — the exact device `loadScreenData` loads — so a
    /// target change (a picked device disconnecting, a deferred switch landing)
    /// re-fires the load instead of leaving a stale list from the old device.
    private var taskKey: String {
        switch screen {
        case .apps: return "apps:\(panelTargetSerial ?? "")"
        case .emulators: return "emulators"
        default: return "static"
        }
    }

    private func loadScreenData() async {
        switch screen {
        case .apps:
            installedApps = nil
            guard let serial = panelTargetSerial else {
                installedApps = []
                return
            }
            // User-initiated navigation, so it belongs in the Command Log
            // like the panel's other adb calls.
            let packages = await CommandLog.userInitiated {
                (try? await state.env.engine.appControl.listInstalledPackages(serial: serial)) ?? []
            }
            guard !Task.isCancelled else { return }
            installedApps = packages.sorted()
        case .emulators:
            emulatorsLoading = true
            // Independent probes (emulator -list-avds vs simctl list) — run
            // them together instead of paying the sum of both spawns.
            async let avds: Void = state.refreshAvds()
            async let simulators: Void = state.refreshSimulators()
            _ = await (avds, simulators)
            emulatorsLoading = false
        default:
            break
        }
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        HStack(spacing: 10) {
            if runningRowID != nil {
                ProgressView().controlSize(.small)
                Text("Running…")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            } else if let armedRowID, let row = flatItems.first(where: { $0.id == armedRowID }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Press ⏎ again to \(row.title.lowercased()) — this can't be undone")
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if let lastRun {
                Image(systemName: lastRun.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(lastRun.ok ? Color.brandAccent : Color.orange)
                Text(lastRun.message)
                    .font(.app(.caption))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let path = lastRun.revealPath {
                    Button("Open in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .buttonStyle(.link)
                    .font(.app(.caption))
                    .help("Show in Finder")
                }
                if let copyText = lastRun.copyText {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                    }
                    .buttonStyle(.link)
                    .font(.app(.caption))
                }
            } else if let context = footerContext {
                Label(context.text, systemImage: context.icon)
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            if case .pickDevice(allowAll: true) = screen {
                Button {
                    perform(.chooseAllDevices)
                } label: {
                    footerHint("⌘⏎", "All devices")
                }
                .buttonStyle(.plain)
                .help("Run on every connected device")
            }
            if let id = pinnableFeatureID(of: highlightedRow) {
                footerHint("⌘P", state.layout.favorites.contains(id) ? "Unpin" : "Pin")
            }
            footerHint("⏎", isFormScreen ? "Run" : "Select")
            footerHint("esc", stack.isEmpty ? "Close" : "Back")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// The footer's left-side context, shown only where a device scope is in
    /// play: which device Manage Apps is listing, and what a form's ⏎ will
    /// target. The root shows nothing — every action picks its device.
    private var footerContext: (text: String, icon: String)? {
        switch screen {
        case .apps, .appActions:
            guard let device = panelTargetDevice else {
                return ("No device connected", "iphone.gen3")
            }
            return (
                state.deviceTitle(device),
                device.platform == .iosSimulator ? "iphone" : "iphone.gen3"
            )
        case .form:
            if let approved = effectiveApprovedSerials, approved.count > 1 {
                return ("All devices (\(approved.count))", "square.stack.3d.down.right")
            }
            guard let device = panelTargetDevice else {
                return ("No device connected", "iphone.gen3")
            }
            return (
                state.deviceTitle(device),
                device.platform == .iosSimulator ? "iphone" : "iphone.gen3"
            )
        default:
            return nil
        }
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyHint(key)
            Text(label).font(.app(.caption2)).foregroundStyle(.textMuted)
        }
    }

    private var panelTargetDevice: Device? {
        panelTargetSerial.flatMap { serial in state.devices.first { $0.serial == serial } }
    }

    /// The feature id ⌘P pins/unpins for this row. The panel's native screens
    /// map to the registry features they replace (Manage Apps → `apps`,
    /// Emulators → `emulators`, Install APK → `install-app`), so pinning them
    /// shares the app's favorites like everything else. Only rows with no
    /// registry counterpart (commands, apps, devices, verbs) aren't pinnable.
    private func pinnableFeatureID(of row: QuickRow?) -> String? {
        switch row?.action {
        case .runFeature(let feature): return feature.id
        case .push(.form(let id)): return id
        case .push(.apps): return "apps"
        case .push(.emulators): return "emulators"
        case .installAPK: return "install-app"
        case .openInApp(let feature): return feature.id
        default: return nil
        }
    }

    // MARK: - Highlight movement

    /// ↑/↓: 2D through the root grid, then row-by-row through the list
    /// below; plain ±1 with wraparound on sub-screens.
    private func moveVertical(_ direction: Int) {
        armedRowID = nil
        guard isRoot else {
            let count = flatItems.count
            guard count > 0 else { return }
            highlighted = (highlighted + direction + count) % count
            return
        }
        let gridCount = rootGridItems.count
        let total = gridCount + rootAppItems.count
        guard total > 0 else { return }
        var index = min(highlighted, total - 1)
        if direction > 0 {
            if index < gridCount {
                let below = index + Self.gridColumns
                if below < gridCount {
                    index = below
                } else if gridCount < total {
                    index = gridCount
                }
            } else if index + 1 < total {
                index += 1
            }
        } else {
            if index >= gridCount {
                index = index == gridCount ? max(gridCount - 1, 0) : index - 1
            } else if index >= Self.gridColumns {
                index -= Self.gridColumns
            }
        }
        highlighted = index
    }

    /// ←/→ step through the root grid, searching or not — arrow keys own
    /// grid navigation (Raycast-style); the query caret cedes to them.
    private func moveHorizontal(_ direction: Int) -> KeyPress.Result {
        guard isRoot else { return .ignored }
        let total = rootGridItems.count + rootAppItems.count
        guard total > 0 else { return .ignored }
        armedRowID = nil
        highlighted = min(max(highlighted + direction, 0), total - 1)
        return .handled
    }

    // MARK: - Activation

    private func activate(_ row: QuickRow) {
        guard runningRowID == nil else { return }
        // Destructive verbs take two ⏎s: the first arms, the second runs.
        if row.destructive, armedRowID != row.id {
            armedRowID = row.id
            return
        }
        armedRowID = nil
        // Several devices and no choice yet: ask first, hold the action.
        let choice = deviceChoice(for: row.action)
        if choice.needed {
            pendingAction = row.action
            push(.pickDevice(allowAll: choice.allowAll))
            return
        }
        perform(row.action)
    }

    // MARK: - Device targeting

    /// The serials an "All devices" approval still covers (approved ∩ ready) —
    /// the footer's "All devices (N)" count reads this. See `PanelTargeting`.
    private var effectiveApprovedSerials: [String]? {
        PanelTargeting.approvedTargets(approved: approvedAllSerials, ready: readySerials)
    }

    /// The single device a panel action targets: the session pick, else the
    /// device-bar selection, else the first ready device. See `PanelTargeting`.
    private var panelTargetSerial: String? {
        PanelTargeting.singleTarget(
            picked: pickedSerial, selected: state.selectedSerial, ready: readySerials
        )
    }

    /// Explicit targets for `AppState.run(feature:params:on:)` — always the
    /// panel's own single pick or "All devices" fan-out, never the device
    /// bar's `targetSerials` (whose run-on-all state belongs to the hidden main
    /// window, and whose selection can lag a guard-deferred switch). An "All
    /// devices" pick fans out any device feature, not just `supportsRunAll`
    /// ones, since the panel loops explicit targets. See `PanelTargeting`.
    private func explicitTargets(for feature: FeatureDef) -> [String]? {
        PanelTargeting.runTargets(
            needsDevice: feature.needsDevice, picked: pickedSerial,
            selected: state.selectedSerial, approved: approvedAllSerials, ready: readySerials
        )
    }

    /// Whether this action needs the device interstitial, and whether that
    /// interstitial offers "All devices" (only where fan-out is supported).
    /// With several devices connected, every device-scoped action asks —
    /// each pick scopes just the action it precedes (verbs inside Manage
    /// Apps inherit the pick that opened the list).
    private func deviceChoice(for action: QuickRow.Action) -> (needed: Bool, allowAll: Bool) {
        guard readyDevices.count > 1 else { return (false, false) }
        switch action {
        case .runFeature(let feature):
            return (feature.needsDevice, feature.needsDevice)
        case .push(.form(let id)):
            guard let feature = FeatureRegistry.byID[id] else { return (false, false) }
            return (feature.needsDevice, feature.needsDevice)
        case .push(.apps):
            // The apps list is inherently one device's.
            return (true, false)
        case .runCommand(let command):
            let scoped = command.kind == .adb || command.command.contains("{serial}")
            return (scoped, scoped)
        case .installAPK, .installFiles:
            return (true, true)
        default:
            return (false, false)
        }
    }

    private func perform(_ action: QuickRow.Action) {
        switch action {
        case .runCommand(let command):
            run(command)
        case .runFeature(let feature):
            run(feature)
        case .push(let next):
            push(next)
        case .openInApp(let feature):
            onClose()
            state.activateMainWindow()
            state.requestFeature(feature.id)
        case .installAPK:
            pickAndInstallAPKs()
        case .installFiles(let urls):
            install(urls)
        case .openStudio(let tab, let url):
            // Load the studio session before opening — the studio view renders
            // whatever `apkStudio.apk` holds, on the chosen tab.
            state.apkStudio.apk = url
            state.apkStudio.signInput = nil
            state.apkStudio.tab = tab
            onClose()
            state.activateMainWindow()
            state.requestFeature("apk-studio")
        case .stageInstallScreen(let urls):
            onClose()
            state.openAPKs(urls)
        case .appVerb(let verb, let packageId):
            run(verb, packageId: packageId)
        case .launchAvd(let avd):
            state.launchEmulator(avd)
            finish(QuickRunOutcome(message: "Launching \(avd.displayName)…", ok: true))
        case .bootSimulator(let simulator):
            state.bootSimulator(simulator)
            finish(QuickRunOutcome(message: "Booting \(simulator.name)…", ok: true))
        case .selectDevice(let serial, let label):
            // The panel target is carried explicitly (`pickedSerial`) — the
            // device-bar switch is a courtesy and may defer behind an exit
            // guard, so nothing here depends on it landing.
            pickedSerial = serial
            approvedAllSerials = nil
            state.requestDevice(serial)
            syncMemory()
            if !stack.isEmpty { pop() }
            finish(QuickRunOutcome(message: "Now targeting \(label)", ok: true))
        case .chooseDevice(let serial, _):
            pickedSerial = serial
            approvedAllSerials = nil
            state.requestDevice(serial)
            resumePendingAfterPick()
        case .chooseAllDevices:
            approvedAllSerials = readyDevices.map(\.serial)
            pickedSerial = nil
            resumePendingAfterPick()
        }
    }

    /// Leave the interstitial and carry out the action it was holding.
    private func resumePendingAfterPick() {
        let held = pendingAction
        pendingAction = nil
        syncMemory()
        pop()
        if let held { perform(held) }
    }

    private func run(_ feature: FeatureDef) {
        // `state.run` reports these preconditions only via toast (it doesn't
        // write `lastResults`), so check them here where the panel can say so.
        if feature.needsDevice, panelTargetSerial == nil {
            lastRun = QuickRunOutcome(message: "No device connected.", ok: false)
            return
        }
        if feature.needsBundle, state.selectedBundle == nil {
            lastRun = QuickRunOutcome(message: "Pick a saved bundle first.", ok: false)
            return
        }
        runningRowID = "feature:\(feature.id)"
        lastRun = nil
        Task {
            let started = Date()
            await state.run(feature: feature, params: [:], on: explicitTargets(for: feature))
            let fresh = state.lastResults[feature.id].flatMap { entry in
                entry.at >= started ? QuickRunOutcome(result: entry.result) : nil
            }
            finish(fresh ?? QuickRunOutcome(message: "Done", ok: true))
        }
    }

    private func run(_ command: CustomCommand) {
        if command.needsBundle, state.selectedBundle == nil {
            lastRun = QuickRunOutcome(message: "Pick a saved bundle first.", ok: false)
            return
        }
        // Device-scoped commands honor an "All devices" approval (the footer
        // advertises it); shell commands without {serial} run once.
        let deviceScoped = command.kind == .adb || command.command.contains("{serial}")
        let targets: [String] = deviceScoped
            ? PanelTargeting.fanOut(
                picked: pickedSerial, selected: state.selectedSerial,
                approved: approvedAllSerials, ready: readySerials
            )
            : (panelTargetSerial.map { [$0] } ?? [])
        if command.kind == .adb, targets.isEmpty {
            lastRun = QuickRunOutcome(message: "No device connected.", ok: false)
            return
        }
        runningRowID = "command:\(command.id)"
        lastRun = nil
        let bundleId = state.selectedBundle?.packageId
        Task {
            var okCount = 0
            var lastResult = FeatureResult(ok: false, message: "\(command.name) didn't run")
            for serial in targets.isEmpty ? [""] : targets {
                let result = await CommandLog.userInitiated {
                    await state.env.engine.customCommands.run(
                        command: command, bundleId: bundleId, serial: serial
                    )
                }
                if result.ok { okCount += 1 }
                lastResult = result
                // Mirror the Custom Commands screen: results land in the
                // notifications history too, not just this transient footer.
                let label = state.devices.first { $0.serial == serial }?.label
                state.showToast(Toast(
                    message: targets.count > 1 ? "\(label ?? serial): \(result.message)" : result.message,
                    ok: result.ok
                ))
            }
            if targets.count > 1 {
                finish(QuickRunOutcome(
                    message: "\(command.name) — ok on \(okCount) of \(targets.count) devices",
                    ok: okCount == targets.count
                ))
            } else {
                finish(QuickRunOutcome(result: lastResult))
            }
        }
    }

    private func run(_ verb: AppControlService.AppAction, packageId: String) {
        // Single device by design — the app list itself came from one device.
        guard let serial = panelTargetSerial else {
            lastRun = QuickRunOutcome(message: "No device connected.", ok: false)
            return
        }
        runningRowID = "verb:\(verb.rawValue):\(packageId)"
        lastRun = nil
        Task {
            let result = await CommandLog.userInitiated {
                do {
                    return try await state.env.engine.appControl.control(
                        serial: serial, packageId: packageId, action: verb
                    )
                } catch {
                    return FeatureResult(ok: false, message: error.localizedDescription)
                }
            }
            if verb == .uninstall, result.ok {
                installedApps?.removeAll { $0 == packageId }
            }
            finish(QuickRunOutcome(result: result))
        }
    }

    /// Pick .apk files, then install them. The file dialog takes key focus,
    /// so the panel holds itself open across it.
    private func pickAndInstallAPKs() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [UTType(filenameExtension: "apk")].compactMap { $0 }
        picker.allowsMultipleSelection = true
        picker.message = "Choose APKs to install"
        let controller = FloatingPanelController.quickActions
        controller.holdsThroughResign = true
        NSApp.activate(ignoringOtherApps: true)
        let confirmed = picker.runModal() == .OK
        controller.holdsThroughResign = false
        controller.makeKey()
        refocusSearch()
        guard confirmed, !picker.urls.isEmpty else { return }
        install(picker.urls)
    }

    /// Install APKs on the panel's target device(s) — one device, or the
    /// serials an "All devices" pick approved.
    private func install(_ urls: [URL]) {
        let serials = PanelTargeting.fanOut(
            picked: pickedSerial, selected: state.selectedSerial,
            approved: approvedAllSerials, ready: readySerials
        )
        guard !serials.isEmpty else {
            lastRun = QuickRunOutcome(message: "No device connected.", ok: false)
            return
        }
        runningRowID = "native:install"
        lastRun = nil
        Task {
            let outcome = await state.installAPKs(urls, onSerials: serials)
            finish(QuickRunOutcome(
                message: outcome.report.components(separatedBy: "\n").first ?? "Install finished",
                ok: outcome.ok
            ))
        }
    }

    /// Show the outcome in the footer. The panel stays up — chain more
    /// actions, use the result's Reveal/Copy, and leave with Esc.
    private func finish(_ outcome: QuickRunOutcome) {
        runningRowID = nil
        lastRun = outcome
    }
}
