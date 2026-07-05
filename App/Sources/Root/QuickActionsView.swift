import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the Quick Actions panel — a Raycast-style floating
/// mini app summoned by a global hotkey (or the menu bar). The root shows a
/// grid of everything runnable in place (instant/toggle actions, in-panel
/// forms, saved custom commands, Manage Apps / Emulators / Install APK) with
/// an "Open in Droidective" list below for the full-app screens. Esc, ⌫ on an
/// empty query, or `<` pops a screen; at the root Esc closes. A session
/// resumes where it left off when reopened within the Settings ▸ Quick
/// Actions window (default 5 minutes).
@MainActor
enum QuickActionsPanel {
    static func toggle(state: AppState) {
        let controller = FloatingPanelController.quickActions
        if controller.isVisible {
            controller.close()
            return
        }
        let memory = QuickPanelMemory.shared
        let minutes = UserDefaults.standard.object(forKey: quickPanelResumeMinutesKey) as? Int ?? 5
        let expired = memory.closedAt.map { Date().timeIntervalSince($0) > Double(minutes) * 60 } ?? true
        if minutes <= 0 || expired { memory.reset() }
        present(state: state)
    }

    /// APKs double-clicked in Finder land here (via `InstallInbox`): the panel
    /// opens straight on the APK options screen — install in place, or take
    /// the file into APK Studio / the Install App screen.
    static func showAPKOptions(_ urls: [URL], state: AppState) {
        guard !urls.isEmpty else { return }
        let memory = QuickPanelMemory.shared
        memory.stack = [.apk(urls)]
        memory.closedAt = nil
        let controller = FloatingPanelController.quickActions
        // Rebuild if already up — the view seeds its screen stack at init.
        if controller.isVisible { controller.close() }
        present(state: state)
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
    /// Pick which connected device the actions target.
    case devices
    /// Interstitial before a device-scoped action when several devices are
    /// connected; `allowAll` offers run-on-all for features that support it.
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
    var hasPickedDevice = false
    var runAllDevices = false
    var closedAt: Date?

    func reset() {
        stack = []
        hasPickedDevice = false
        runAllDevices = false
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
    /// This session's device choice: once made, actions stop asking.
    @State private var hasPickedDevice: Bool
    /// "All devices" was chosen — features that support run-on-all fan out.
    @State private var runAllDevices: Bool
    /// Outcome of the last action run from the panel, shown in the footer.
    @State private var lastRun: QuickRunOutcome?
    @FocusState private var searchFocused: Bool

    @MainActor init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let memory = QuickPanelMemory.shared
        _stack = State(initialValue: memory.stack)
        _hasPickedDevice = State(initialValue: memory.hasPickedDevice)
        _runAllDevices = State(initialValue: memory.runAllDevices)
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
        .task { commands = await state.env.stores.customCommands.load() }
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
        memory.hasPickedDevice = hasPickedDevice
        memory.runAllDevices = runAllDevices
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
                    .font(.title)
                    .foregroundStyle(.brandAccent)
            } else {
                Button(action: pop) {
                    Image(systemName: "chevron.left")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.textMuted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back (esc)")
            }
            if let feature = formFeature {
                Text(feature.title)
                    .font(.title)
                Spacer()
                Image(systemName: feature.icon)
                    .font(.title2)
                    .foregroundStyle(.brandAccent)
            } else {
                TextField(searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.title)
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
        case .devices: return "Switch device…"
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
                    .font(.callout)
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
                            .font(.callout)
                            .foregroundStyle(.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(10)
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(.textMuted)
            .padding(.horizontal, 4)
    }

    private var emptyMessage: String {
        switch screen {
        case .apps where state.targetSerials.isEmpty: return "Connect a device to manage its apps"
        case .apps where installedApps == nil: return "Loading apps…"
        case .apps: return "No matching apps"
        case .emulators: return "No emulators or simulators found"
        case .devices, .pickDevice: return "No ready devices"
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
        case .apps: return Array(appRows.prefix(8))
        case .appActions(let packageId, _): return appActionRows(packageId)
        case .emulators: return Array(emulatorRows.prefix(8))
        case .devices: return deviceRows
        case .pickDevice(let allowAll): return pickDeviceRows(allowAll: allowAll)
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
        rows += PaletteSearch.quickActions(query: query, implemented: FeatureEngine.implementedIDs)
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
        return rows
    }

    /// Full-app screens below the grid — everything that can't run in a
    /// panel opens the main window instead. The panel's native screens
    /// replace their in-app counterparts here.
    private var rootAppItems: [QuickRow] {
        let covered: Set<String> = ["apps", "emulators", "install-app"]
        return PaletteSearch.features(
            query: query,
            enabled: state.layout.effectiveEnabledIDs,
            favorites: state.layout.favorites
        )
        .filter { ($0.kind == .view || $0.kind == .system) && !covered.contains($0.id) }
        .map { feature in
            QuickRow(
                id: "open:\(feature.id)", icon: feature.icon,
                title: feature.title, subtitle: feature.subtitle,
                action: .openInApp(feature)
            )
        }
    }

    /// The panel's own sub-screens and actions, searchable alongside the rest.
    private var nativeRows: [QuickRow] {
        var rows: [QuickRow] = []
        if matchesNative(title: "Manage Apps", keywords: [
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
        if matchesNative(title: "Emulators", keywords: [
            "emulator", "simulator", "avd", "boot", "launch", "virtual",
        ]) {
            rows.append(QuickRow(
                id: "screen:emulators", icon: "play.display",
                title: "Emulators",
                subtitle: "Boot an Android emulator or iOS Simulator",
                pushes: true, action: .push(.emulators)
            ))
        }
        if matchesNative(title: "Install APK", keywords: ["install", "apk", "sideload", "package"]) {
            rows.append(QuickRow(
                id: "native:install", icon: "arrow.down.app",
                title: "Install APK",
                subtitle: "Pick .apk files and install them",
                action: .installAPK
            ))
        }
        if state.devices.filter(\.isReady).count > 1,
           matchesNative(title: "Switch Device", keywords: ["device", "switch", "select", "target"]) {
            rows.append(QuickRow(
                id: "screen:devices", icon: "arrow.triangle.2.circlepath",
                title: "Switch Device",
                subtitle: state.selectedDevice.map { "Now targeting \($0.label)" },
                pushes: true, action: .push(.devices)
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
    /// bar treats bundles as the apps you actually work on.
    private var appRows: [QuickRow] {
        guard let installedApps else { return [] }
        let bundleIDs = state.bundles.map(\.packageId)
        let pinned = bundleIDs.filter(installedApps.contains)
        let rest = installedApps.filter { !pinned.contains($0) }
        return (pinned + rest)
            .filter { packageId in
                guard !query.isEmpty else { return true }
                let nickname = state.bundles.first { $0.packageId == packageId }?.nickname
                return packageId.localizedCaseInsensitiveContains(query)
                    || Self.appDisplayName(packageId).localizedCaseInsensitiveContains(query)
                    || (nickname?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .map { packageId in
                let nickname = state.bundles.first { $0.packageId == packageId }?.nickname
                return QuickRow(
                    id: "app:\(packageId)", icon: "app.badge",
                    title: nickname ?? Self.appDisplayName(packageId),
                    subtitle: packageId,
                    badge: nickname != nil ? "saved" : nil,
                    pushes: true,
                    action: .push(.appActions(
                        packageId: packageId,
                        display: nickname ?? Self.appDisplayName(packageId)
                    ))
                )
            }
    }

    /// "com.foo.weather" → "Weather", like `AppListing.displayName`.
    private static func appDisplayName(_ packageId: String) -> String {
        packageId.split(separator: ".").last
            .map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? packageId
    }

    private func appActionRows(_ packageId: String) -> [QuickRow] {
        let verbs: [(AppControlService.AppAction, String, String)] = [
            (.open, "Open", "play.circle"),
            (.stop, "Force Stop", "stop.circle"),
            (.minimize, "Minimize", "chevron.down.circle"),
            (.clearCache, "Clear Cache", "eraser"),
            (.clearData, "Clear Data", "eraser.fill"),
            (.uninstall, "Uninstall", "trash"),
        ]
        return verbs
            .filter { query.isEmpty || $0.1.localizedCaseInsensitiveContains(query) }
            .map { verb, title, icon in
                QuickRow(
                    id: "verb:\(verb.rawValue):\(packageId)", icon: icon,
                    title: title, subtitle: packageId,
                    destructive: verb.isDestructive,
                    action: .appVerb(verb, packageId: packageId)
                )
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

    private var deviceRows: [QuickRow] {
        readyDevices
            .filter { query.isEmpty || state.deviceTitle($0).localizedCaseInsensitiveContains(query) }
            .map { device in
                QuickRow(
                    id: "device:\(device.serial)",
                    icon: device.platform == .iosSimulator ? "iphone" : "iphone.gen3",
                    title: device.label,
                    subtitle: state.deviceTitle(device),
                    badge: device.serial == state.selectedSerial ? "selected" : nil,
                    action: .selectDevice(serial: device.serial, label: device.label)
                )
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
        rows += studioTabs.compactMap { featureID, tab in
            guard let feature = FeatureRegistry.byID[featureID] else { return nil }
            return QuickRow(
                id: "apk:\(featureID)", icon: feature.icon,
                title: feature.title,
                subtitle: "\(first.lastPathComponent) in APK Studio",
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

    /// The interstitial's rows: optionally "All devices", then each device.
    private func pickDeviceRows(allowAll: Bool) -> [QuickRow] {
        var rows: [QuickRow] = []
        if allowAll, matchesNative(title: "All devices", keywords: ["all", "every"]) {
            rows.append(QuickRow(
                id: "pick:all", icon: "square.stack.3d.down.right",
                title: "All devices",
                subtitle: "Run on every connected device",
                action: .chooseAllDevices
            ))
        }
        rows += readyDevices
            .filter { query.isEmpty || state.deviceTitle($0).localizedCaseInsensitiveContains(query) }
            .map { device in
                QuickRow(
                    id: "pick:\(device.serial)",
                    icon: device.platform == .iosSimulator ? "iphone" : "iphone.gen3",
                    title: device.label,
                    subtitle: state.deviceTitle(device),
                    badge: device.serial == state.selectedSerial ? "selected" : nil,
                    action: .chooseDevice(serial: device.serial, label: device.label)
                )
            }
        return rows
    }

    // MARK: - Row rendering

    private func gridTile(_ row: QuickRow, isHighlighted: Bool) -> some View {
        VStack(spacing: 6) {
            if runningRowID == row.id {
                ProgressView().controlSize(.small).frame(height: 26)
            } else {
                Image(systemName: row.icon)
                    .font(.title2)
                    .frame(height: 26)
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(accentText) : AnyShapeStyle(.brandAccent))
            }
            Text(row.title)
                .font(.caption)
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
        .foregroundStyle(isHighlighted ? accentText : .primary)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .help(row.subtitle ?? row.title)
    }

    private func rowView(
        _ row: QuickRow, index: Int, isHighlighted: Bool, showsDigitHint: Bool
    ) -> some View {
        HStack(spacing: 10) {
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
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? accentText.opacity(0.75) : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let badge = row.badge {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(isHighlighted ? accentText.opacity(0.75) : .secondary)
            }
            if case .openInApp = row.action {
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundStyle(isHighlighted ? accentText.opacity(0.75) : .secondary)
            }
            if row.pushes {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(isHighlighted ? accentText.opacity(0.75) : .secondary)
            }
            if showsDigitHint, index < 8 {
                KeyHint("⌘\(index + 1)", prominent: isHighlighted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isHighlighted ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.clear),
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

    /// Hidden buttons backing ⌘1–8 jumps to the first eight items.
    private var shortcutButtons: some View {
        ZStack {
            ForEach(Array(Self.digitKeys.enumerated()), id: \.offset) { index, key in
                Button("") {
                    let rows = flatItems
                    if rows.indices.contains(index) { activate(rows[index]) }
                }
                .keyboardShortcut(key, modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Screen data

    /// Re-keys per screen + device, so entering Apps loads the package list
    /// and Emulators refreshes AVDs/simulators.
    private var taskKey: String {
        switch screen {
        case .apps: return "apps:\(state.targetSerials.first ?? "")"
        case .emulators: return "emulators"
        default: return "static"
        }
    }

    private func loadScreenData() async {
        switch screen {
        case .apps:
            installedApps = nil
            guard let serial = state.targetSerials.first else {
                installedApps = []
                return
            }
            let packages = (try? await state.env.engine.appControl.listInstalledPackages(serial: serial)) ?? []
            guard !Task.isCancelled else { return }
            installedApps = packages.sorted()
        case .emulators:
            await state.refreshAvds()
            await state.refreshSimulators()
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
                    .font(.caption)
                    .foregroundStyle(.textMuted)
            } else if let armedRowID, let row = flatItems.first(where: { $0.id == armedRowID }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Press ⏎ again to \(row.title.lowercased()) — this can't be undone")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if let lastRun {
                Image(systemName: lastRun.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(lastRun.ok ? Color.brandAccent : Color.orange)
                Text(lastRun.message)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let path = lastRun.revealPath {
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("Show in Finder")
                }
                if let copyText = lastRun.copyText {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } else if runAllDevices, readyDevices.count > 1 {
                Label("All devices (\(readyDevices.count))", systemImage: "square.stack.3d.down.right")
                    .font(.caption)
                    .foregroundStyle(.textMuted)
            } else {
                Label(
                    state.selectedDevice.map(state.deviceTitle) ?? "No device connected",
                    systemImage: state.selectedDevice?.platform == .iosSimulator
                        ? "iphone" : "iphone.gen3"
                )
                .font(.caption)
                .foregroundStyle(.textMuted)
                .lineLimit(1)
            }
            Spacer()
            footerHint("⏎", isFormScreen ? "Run" : "Select")
            footerHint("esc", stack.isEmpty ? "Close" : "Back")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyHint(key)
            Text(label).font(.caption2).foregroundStyle(.textMuted)
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

    /// ←/→ step through the root grid — only while the query is empty, so
    /// they keep moving the text caret while typing.
    private func moveHorizontal(_ direction: Int) -> KeyPress.Result {
        guard isRoot, query.isEmpty else { return .ignored }
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

    /// Whether this action needs the device interstitial, and whether that
    /// interstitial offers "All devices" (only where fan-out is supported).
    private func deviceChoice(for action: QuickRow.Action) -> (needed: Bool, allowAll: Bool) {
        guard readyDevices.count > 1, !hasPickedDevice else { return (false, false) }
        switch action {
        case .runFeature(let feature):
            return (feature.needsDevice, feature.supportsRunAll)
        case .push(.form(let id)):
            guard let feature = FeatureRegistry.byID[id] else { return (false, false) }
            return (feature.needsDevice, feature.supportsRunAll)
        case .push(.apps):
            return (true, false)
        case .runCommand(let command):
            return (command.kind == .adb || command.command.contains("{serial}"), false)
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
            state.requestDevice(serial)
            hasPickedDevice = true
            runAllDevices = false
            syncMemory()
            if !stack.isEmpty { pop() }
            finish(QuickRunOutcome(message: "Now targeting \(label)", ok: true))
        case .chooseDevice(let serial, _):
            state.requestDevice(serial)
            hasPickedDevice = true
            runAllDevices = false
            resumePendingAfterPick()
        case .chooseAllDevices:
            hasPickedDevice = true
            runAllDevices = true
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

    /// Fan-out targets for a feature when "All devices" is in effect (and the
    /// feature supports run-on-all); nil defers to the device-bar selection.
    private func explicitTargets(for feature: FeatureDef) -> [String]? {
        guard runAllDevices, feature.supportsRunAll else { return nil }
        var serials = readyDevices.map(\.serial)
        guard serials.count > 1 else { return nil }
        // Selected device first, mirroring `targetSerials`' ordering rule.
        if let selected = state.selectedSerial, let index = serials.firstIndex(of: selected) {
            serials.swapAt(0, index)
        }
        return serials
    }

    private func run(_ feature: FeatureDef) {
        // `state.run` reports these preconditions only via toast (it doesn't
        // write `lastResults`), so check them here where the panel can say so.
        if feature.needsDevice, state.targetSerials.isEmpty {
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
        let serial = state.targetSerials.first ?? ""
        if command.kind == .adb, serial.isEmpty {
            lastRun = QuickRunOutcome(message: "No device connected.", ok: false)
            return
        }
        runningRowID = "command:\(command.id)"
        lastRun = nil
        let bundleId = state.selectedBundle?.packageId
        Task {
            let result = await CommandLog.userInitiated {
                await state.env.engine.customCommands.run(
                    command: command, bundleId: bundleId, serial: serial
                )
            }
            // Mirror the Custom Commands screen: failures land in the
            // notifications history too, not just this transient footer.
            state.showToast(Toast(message: result.message, ok: result.ok))
            finish(QuickRunOutcome(result: result))
        }
    }

    private func run(_ verb: AppControlService.AppAction, packageId: String) {
        guard let serial = state.targetSerials.first else {
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

    /// Install APKs on the panel's target device(s) — one device, or all of
    /// them after an "All devices" pick.
    private func install(_ urls: [URL]) {
        let serials = runAllDevices
            ? readyDevices.map(\.serial)
            : Array(state.targetSerials.prefix(1))
        guard !serials.isEmpty else {
            lastRun = QuickRunOutcome(message: "No device connected.", ok: false)
            return
        }
        runningRowID = "native:install"
        lastRun = nil
        Task {
            let report = await state.installAPKs(urls, onSerials: serials)
            finish(QuickRunOutcome(
                message: report.components(separatedBy: "\n").first ?? "Install finished",
                ok: true
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
