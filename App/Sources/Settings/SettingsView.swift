import ADBKit
import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            DoctorSettingsView()
                .tabItem { Label("Doctor", systemImage: "stethoscope") }
            ManagedToolsSettingsView()
                .tabItem { Label("Tools", systemImage: "shippingbox") }
            HotkeysSettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
        }
        .frame(width: 560)
        .frame(minHeight: 460)
        // Esc closes the Settings window. A zero-opacity button carrying the
        // Cancel (Esc) key equivalent fires regardless of which control holds
        // focus — more reliable here than .onExitCommand.
        .background {
            Button("") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

/// Applies the stored theme. Safe only once NSApplication exists — call it
/// from view lifecycle (RootView/Settings onAppear), never from App.init().
@MainActor
func applyStoredTheme() {
    switch UserDefaults.standard.string(forKey: "theme") {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "auto": NSApp.appearance = nil
    // "dark" — and the default when unset, so new users get dark.
    default: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("showMenuBarExtra") private var showMenuBar = true
    @AppStorage(keepRunningInBackgroundKey) private var keepRunningInBackground = true
    @AppStorage(quickPanelResumeMinutesKey) private var quickPanelResumeMinutes = 5
    @State private var openAtLoginOn = false
    @State private var showMenuItems = false
    @State private var showQuickActionToggles = false

    /// True when the login item is registered (enabled, or pending the user's
    /// approval in System Settings).
    private func loginItemRegistered() -> Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    /// Registers/unregisters the app as a macOS login item. The toggle is backed
    /// by `openAtLoginOn` (the user's intent) rather than a live `status` read —
    /// `register`/`unregister` don't update `status` synchronously, so reading it
    /// each render snapped the toggle back to its old value.
    private var openAtLogin: Binding<Bool> {
        Binding(
            get: { openAtLoginOn },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                        if SMAppService.mainApp.status == .requiresApproval {
                            state.showToast(Toast(
                                message: "Added — approve Droidective in System Settings ▸ General ▸ Login Items.",
                                ok: true
                            ))
                        }
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    openAtLoginOn = enabled
                } catch {
                    state.showToast(Toast(message: "Couldn't update Open at Login: \(error.localizedDescription)", ok: false))
                    openAtLoginOn = loginItemRegistered()
                }
            }
        )
    }

    private var roleBinding: Binding<UserRole?> {
        Binding(get: { state.selectedRole }, set: { state.chooseRole($0) })
    }

    var body: some View {
        Form {
            Section("Role") {
                Picker("Role", selection: roleBinding) {
                    Text("All features").tag(Optional<UserRole>.none)
                    ForEach(UserRole.allCases) { role in
                        Text(role.label).tag(Optional(role))
                    }
                }
                Text("Curates which features start visible — switching re-curates your set. Nothing is deleted; add any feature back from Home or the catalog.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
                Button("Open the role picker…") {
                    state.activateMainWindow()
                    state.presentRolePicker = true
                }
            }

            Section("Startup") {
                Toggle("Open at login", isOn: openAtLogin)
            }

            Section("Background") {
                Toggle("Keep running in the background", isOn: $keepRunningInBackground)
                Text("Closing the window hides Droidective from the Dock and stops running feature work — including terminal shells. The menu bar icon, global hotkeys, and the Quick Actions panel stay available; quit fully with ⌘Q.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }

            Section("Quick Actions") {
                Picker("Resume where I left off", selection: $quickPanelResumeMinutes) {
                    Text("Off").tag(0)
                    Text("For 1 minute").tag(1)
                    Text("For 5 minutes").tag(5)
                    Text("For 15 minutes").tag(15)
                    Text("For 1 hour").tag(60)
                }
                Text("Reopening the panel within this window returns to the screen and device you had — after that it starts fresh. Open the panel with its global hotkey (record one in the Hotkeys tab) or from the menu bar icon.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
                DisclosureGroup(isExpanded: $showQuickActionToggles) {
                    Text("Switched-off actions leave the panel's action grid — right-clicking a tile in the panel hides it too. Custom commands are managed on the Custom Commands screen.")
                        .font(.app(.footnote))
                        .foregroundStyle(.textMuted)
                        .padding(.vertical, 6)
                    ForEach(state.quickPanelEligibleActions) { feature in
                        Toggle(feature.title, isOn: Binding(
                            get: { !state.quickPanelHiddenIDs.contains(feature.id) },
                            set: { state.setQuickPanelActionShown(feature.id, shown: $0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                } label: {
                    Button { showQuickActionToggles.toggle() } label: {
                        Text("Actions shown in the panel")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            #if !APPSTORE
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { SparkleUpdater.shared.automaticallyChecksForUpdates },
                    set: { SparkleUpdater.shared.automaticallyChecksForUpdates = $0 }
                ))
                Text("Updates are delivered via Sparkle from GitHub Releases.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }
            #endif

            Section("Menu bar") {
                Toggle("Show menu bar icon", isOn: $showMenuBar)
                if showMenuBar {
                    DisclosureGroup(isExpanded: $showMenuItems) {
                        Text("When none are selected, your pinned features (or enabled instant actions) are shown. Screenshot and Mirror Screen always appear.")
                            .font(.app(.footnote))
                            .foregroundStyle(.textMuted)
                            .padding(.vertical, 6)
                        ForEach(state.enabledFeatures) { feature in
                            Toggle(feature.title, isOn: Binding(
                                get: { state.isInMenuBar(feature.id) },
                                set: { state.setMenuBarItem(feature.id, included: $0) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    } label: {
                        Button { showMenuItems.toggle() } label: {
                            Text("Items shown in the menu")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        }
        .formStyle(.grouped)
        .onAppear { openAtLoginOn = loginItemRegistered() }
    }
}

/// Theme, accent color, fonts, and the inline how-it-works notes.
struct AppearanceSettingsView: View {
    @AppStorage("theme") private var theme = "dark"
    @AppStorage(accentColorDefaultsKey) private var accentHex = ""
    @AppStorage("showFeatureNotes") private var showFeatureNotes = false
    @AppStorage(appFontFamilyDefaultsKey) private var fontFamily = ""
    @AppStorage(appFontSizeScaleDefaultsKey) private var fontSizeScale = 1.0
    @State private var hexDraft = ""
    @State private var hexInvalid = false
    #if DEBUG
    @AppStorage(DevMetrics.overlayEnabledKey) private var showDevMetrics = true
    #endif

    /// One-click accent presets; the leading nil swatch is the bundled default.
    private static let presetAccents: [(name: String, hex: String)] = [
        ("Mint", "#00C7BE"), ("Teal", "#64D2FF"), ("Blue", "#0A84FF"),
        ("Indigo", "#5E5CE6"), ("Purple", "#BF5AF2"), ("Pink", "#FF375F"),
        ("Red", "#FF453A"), ("Orange", "#FF9F0A"), ("Yellow", "#FFD60A"),
    ]

    /// The accent ColorPicker reads/writes the stored hex; an empty value shows
    /// (and resets to) the bundled default.
    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(hex: accentHex) ?? Color("BrandAccent") },
            set: { accentHex = $0.hexString ?? "" })
    }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $theme) {
                    Text("Dark").tag("dark")
                    Text("Auto").tag("auto")
                    Text("Light (Beta)").tag("light")
                }
                .pickerStyle(.segmented)
                .onChange(of: theme) { applyStoredTheme() }
                if theme == "light" {
                    Text("Light mode is in beta — a few screens are still being tuned for it.")
                        .font(.app(.footnote))
                        .foregroundStyle(.textMuted)
                }
            }

            Section("Accent") {
                LabeledContent("Presets") {
                    HStack(spacing: 7) {
                        accentSwatch(name: "Droidective green (default)", hex: nil)
                        ForEach(Self.presetAccents, id: \.hex) { preset in
                            accentSwatch(name: preset.name, hex: preset.hex)
                        }
                    }
                }
                LabeledContent("Custom") {
                    HStack(spacing: 8) {
                        ColorPicker("", selection: accentBinding, supportsOpacity: false).labelsHidden()
                        TextField("Hex code", text: $hexDraft, prompt: Text("#34C759"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 110)
                            .onSubmit { commitHex() }
                        if !accentHex.isEmpty {
                            Button("Reset") { setAccent("") }
                        }
                    }
                }
                if hexInvalid {
                    Text("Enter a hex color like #34C759 (or the short #3C5).")
                        .font(.app(.footnote))
                        .foregroundStyle(.orange)
                }
                Text("Recolors buttons, toggles, selection, and active icons across the app. Pick a preset, use the color well, or type a hex code and press ⏎.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }

            Section("Font") {
                Picker("Font", selection: $fontFamily) {
                    Text("System (San Francisco)").tag("")
                    if !FontCatalog.standardFamilies.isEmpty {
                        Divider()
                        ForEach(FontCatalog.standardFamilies, id: \.self) { family in
                            Text(family).font(.custom(family, size: 13)).tag(family)
                        }
                    }
                    if !FontCatalog.otherFamilies.isEmpty {
                        Divider()
                        ForEach(FontCatalog.otherFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                }
                Picker("Text size", selection: $fontSizeScale) {
                    Text("Small").tag(0.9)
                    Text("Default").tag(1.0)
                    Text("Large").tag(1.1)
                    Text("Extra large").tag(1.25)
                }
                Text("Applies across the app — code and log views keep their monospaced font, and the terminal keeps its own. ⌘= / ⌘- additionally zoom the whole window.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }

            Section("Feature notes") {
                Toggle("Show how-it-works notes", isOn: $showFeatureNotes)
                Text("The info text beneath each feature, above the command bar.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }

            #if DEBUG
            Section("Developer") {
                Toggle("Show self-metrics overlay", isOn: $showDevMetrics)
                Text("A floating panel (top-right) with Droidective's own memory, CPU, and network throughput. Debug builds only.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }
            #endif
        }
        .formStyle(.grouped)
        .onAppear { hexDraft = accentHex }
        // Reflect swatch/color-well changes into the hex field so it always
        // shows the effective value.
        .onChange(of: accentHex) { hexDraft = accentHex }
    }

    /// A one-click accent circle; nil hex is the bundled default. The selected
    /// swatch carries a checkmark.
    private func accentSwatch(name: String, hex: String?) -> some View {
        let color = hex.flatMap { Color(hex: $0) } ?? Color("BrandAccent")
        let isSelected = accentHex == (hex ?? "")
        return Button { setAccent(hex ?? "") } label: {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.app(size: 9, weight: .bold))
                            .foregroundStyle(color.contrastingForeground)
                    }
                }
                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private func setAccent(_ hex: String) {
        accentHex = hex
        hexDraft = hex
        hexInvalid = false
    }

    /// Validate and store the typed hex (empty resets to the default),
    /// normalized to "#RRGGBB" so swatch selection matches it.
    private func commitHex() {
        let trimmed = hexDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            setAccent("")
            return
        }
        guard let color = Color(hex: trimmed), let normalized = color.hexString else {
            hexInvalid = true
            return
        }
        setAccent(normalized)
    }
}

/// Telemetry consent plus where local captures and the command log live.
struct PrivacySettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage(ScreenCaptureService.captureFolderDefaultsKey) private var captureFolderPath = ""
    @State private var showCommandLog = false
    @State private var confirmClearLog = false

    private var captureFolderDisplay: String {
        captureFolderPath.isEmpty
            ? "~/Downloads/Droidective (default)"
            : (captureFolderPath as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        Form {
            Section("Telemetry") {
                Toggle("Send anonymous crash reports", isOn: Binding(
                    get: { Telemetry.shared.crashReportingEnabled },
                    set: { Telemetry.shared.setCrashReporting($0) }
                ))
                Toggle("Share anonymous usage analytics", isOn: Binding(
                    get: { Telemetry.shared.analyticsEnabled },
                    set: { Telemetry.shared.setAnalytics($0) }
                ))
                Text("Crash reports help fix bugs; analytics shows which tools get used. Both are anonymous — no device data, file paths, or command contents are ever sent.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }

            Section("Data & Storage") {
                LabeledContent("Captures & pulls") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(captureFolderDisplay)
                            .font(.app(.callout))
                            .foregroundStyle(.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 8) {
                            Button("Change…") {
                                if let url = state.askSaveFolder(prompt: "Choose folder") {
                                    captureFolderPath = url.path
                                }
                            }
                            if !captureFolderPath.isEmpty {
                                Button("Reset") { captureFolderPath = "" }
                            }
                            Button("Open in Finder") {
                                if let dir = try? ScreenCaptureService.ensureCaptureDir() {
                                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                                }
                            }
                        }
                    }
                }
                LabeledContent("Command log") {
                    HStack {
                        Button("View…") { showCommandLog = true }
                        Button("Clear") { confirmClearLog = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCommandLog) {
            CommandLogView()
        }
        .confirmationDialog(
            "Clear the command log?",
            isPresented: $confirmClearLog,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                Task {
                    await state.env.commandLog.clear()
                    state.showToast(Toast(message: "Command log cleared", ok: true))
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all recorded commands.")
        }
    }
}

/// Setup Doctor: verifies the external toolchain (adb / emulator), shows each
/// tool's version and path, and points at the install source when one is
/// missing. scrcpy and ffmpeg aren't listed — the app bundles them.
struct DoctorSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var report: [Tool: ToolStatus] = [:]
    @State private var detecting = false

    private struct Check {
        let tool: Tool
        let name: String
        let purpose: String
    }

    private static let checks: [Check] = [
        Check(tool: .adb, name: "adb", purpose: "Required — powers every device action"),
        Check(tool: .emulator, name: "emulator", purpose: "Launch & manage Android emulators"),
    ]

    /// Missing tools that actually block features.
    private var blockingMissing: [Tool] {
        Self.checks
            .filter { report[$0.tool]?.installed == false }
            .map(\.tool)
    }

    var body: some View {
        Form {
            Section { summary }
            Section("Toolchain") {
                ForEach(Self.checks, id: \.tool) { check in
                    ToolRow(check: check, status: report[check.tool])
                }
            }
            Section {
                Button {
                    Task { await redetect() }
                } label: {
                    Label(detecting ? "Checking…" : "Re-check setup", systemImage: "arrow.clockwise")
                }
                .disabled(detecting)
            }
        }
        .formStyle(.grouped)
        .task { await redetect() }
    }

    @ViewBuilder
    private var summary: some View {
        if report.isEmpty {
            Label("Checking your setup…", systemImage: "stethoscope")
                .foregroundStyle(.textMuted)
        } else if blockingMissing.isEmpty {
            Label("All set — every required tool is installed.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.brandAccent)
        } else {
            let n = blockingMissing.count
            Label(
                "\(n) tool\(n == 1 ? "" : "s") missing — some features won't work until installed.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
    }

    /// One compact row: a status icon + the tool name, expandable to reveal
    /// version, path, and (when missing) the install hint. Uses a separate
    /// struct so each row owns its own isExpanded state, enabling a full-width
    /// Button label that makes the entire row tappable (not just the chevron).
    private struct ToolRow: View {
        let check: Check
        let status: ToolStatus?
        @State private var isExpanded = false

        var body: some View {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(check.purpose)
                        .font(.app(.callout))
                        .foregroundStyle(.textMuted)
                    if let status {
                        if let version = status.version {
                            detailRow("Version", version)
                        }
                        if let path = status.path {
                            detailRow("Path", path)
                        }
                        if !status.installed {
                            Text(status.installHint)
                                .font(.app(.callout))
                                .foregroundStyle(.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Button { isExpanded.toggle() } label: {
                    HStack(spacing: 8) {
                        statusIcon(status)
                        Text(check.name)
                        Spacer()
                        if let status, !status.installed {
                            Text("not installed")
                                .font(.app(.caption))
                                .foregroundStyle(.textMuted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        @ViewBuilder
        private func statusIcon(_ status: ToolStatus?) -> some View {
            if let status {
                Image(systemName: status.installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(status.installed ? Color.brandAccent : Color.orange)
            } else {
                ProgressView().controlSize(.small)
            }
        }

        @ViewBuilder
        private func detailRow(_ label: String, _ value: String) -> some View {
            HStack(alignment: .top, spacing: 8) {
                Text(label)
                    .foregroundStyle(.textMuted)
                    .frame(width: 56, alignment: .leading)
                Text(value)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.app(.callout))
        }
    }

    private func redetect() async {
        detecting = true
        await state.env.locator.clearCache()
        report = await state.env.engine.toolDetection.detectAll()
        // Keep the device-bar adb gate in sync with what the Doctor just found.
        await state.refreshToolStatus()
        detecting = false
    }
}

struct HotkeysSettingsView: View {
    @Environment(AppState.self) private var state

    /// Hidden (disabled) features that still carry a recorded shortcut. They're
    /// off the sidebar but their hotkey keeps firing, so they need a home here
    /// to stay unbindable.
    private var orphanedShortcuts: [FeatureDef] {
        let shown = Set(state.sidebarFeatures.map(\.id))
        return FeatureRegistry.all.filter {
            !shown.contains($0.id)
                && KeyboardShortcuts.getShortcut(for: HotkeyManager.featureName($0.id)) != nil
        }
    }

    var body: some View {
        Form {
            Section("Global") {
                LabeledContent("Show Droidective") {
                    HotkeyRecorderField(name: .globalLaunch)
                }
                LabeledContent("Quick Actions panel") {
                    HotkeyRecorderField(name: .quickActions)
                }
            }
            // Mirrors the sidebar: enabled features in their sidebar order.
            Section("Features") {
                ForEach(state.sidebarFeatures) { feature in
                    LabeledContent(feature.title) {
                        HotkeyRecorderField(name: HotkeyManager.featureName(feature.id))
                    }
                }
            }
            let orphans = orphanedShortcuts
            if !orphans.isEmpty {
                Section("Hidden features with shortcuts") {
                    ForEach(orphans) { feature in
                        LabeledContent(feature.title) {
                            HotkeyRecorderField(name: HotkeyManager.featureName(feature.id))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 360)
    }
}
