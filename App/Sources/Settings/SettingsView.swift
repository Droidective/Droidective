import ADBKit
import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    /// The MCP tab rides the Reactotron feature: React Native and
    /// all-features users see it, as does anyone who added Reactotron to
    /// another role's set — other roles don't carry a tab for a feature
    /// they don't have.
    private var showsMcpTab: Bool {
        state.selectedRole == nil
            || state.selectedRole == .reactNativeDeveloper
            || state.enabledFeatures.contains { $0.id == "reactotron" }
    }

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            if showsMcpTab {
                McpSettingsView()
                    .tabItem { Label("MCP", systemImage: "sparkles") }
            }
            DoctorSettingsView()
                .tabItem { Label("Doctor", systemImage: "stethoscope") }
            ManagedToolsSettingsView()
                .tabItem { Label("Tools", systemImage: "shippingbox") }
            HotkeysSettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
        }
        .frame(width: 640)
        .frame(minHeight: 540)
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
    // A custom background overrides the theme picker: the appearance follows
    // the color's luminance, so text, controls, and system chrome resolve to
    // the readable variant on any background the user picks.
    if let rgb = customBackgroundRGB {
        NSApp.appearance = NSAppearance(named: BackgroundPalette.isLight(rgb) ? .aqua : .darkAqua)
        return
    }
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
    @AppStorage(quickPanelCloseAfterRunKey) private var closePanelAfterRun = false
    @State private var openAtLoginOn = false
    @State private var showMenuItems = false
    @State private var showQuickActionToggles = false
    #if !APPSTORE
    @ObservedObject private var updater = SparkleUpdater.shared

    /// "Version 3.3.0 (123)" — what a manual check compares against, so it
    /// sits beside the Check for Updates button.
    private var installedVersionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }

    /// Inline status beside the update button — the only place "you're up to
    /// date" appears, and it's manual-check-only by construction (background
    /// checks never enter `.checking`/`.upToDate`).
    private var updateStatus: String? {
        switch updater.phase {
        case .idle: return nil
        case .checking: return "Checking…"
        case .upToDate: return "You're up to date."
        case .available(let info): return "Version \(info.version) is available."
        case .downloading: return "Downloading…"
        case .readyToRelaunch(let info): return "Version \(info.version) is ready."
        case .installing: return "Installing…"
        }
    }
    #endif

    /// True when the login item is registered (enabled, or pending the user's
    /// approval in System Settings).
    ///
    /// Runs off the main actor deliberately: `SMAppService.status` is a
    /// synchronous round-trip to launchd, and on a cold or busy system it blocks
    /// long enough to trip the 2 s hang detector — reading it from the General
    /// tab's appearance stalled the whole app just for opening Settings
    /// (DROIDECTIVE-MAC-4G).
    private static func loginItemRegistered() async -> Bool {
        await Task.detached {
            let status = SMAppService.mainApp.status
            return status == .enabled || status == .requiresApproval
        }.value
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
                    Task { openAtLoginOn = await Self.loginItemRegistered() }
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
                Toggle("Close the panel after running an action", isOn: $closePanelAfterRun)
                Text("A successful action dismisses the panel right after its result shows; a failed one keeps it open so you can read the error.")
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
                Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloadsUpdates)
                Text("Droidective checks on launch and every hour either way. On: updates download silently and install when you relaunch (or quit). Off: you get a notification and updates wait for your go-ahead.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
                Toggle("Receive beta updates", isOn: $updater.receivesBetaUpdates)
                LabeledContent(installedVersionLabel) {
                    HStack(spacing: 8) {
                        if let status = updateStatus {
                            Text(status)
                                .font(.app(.footnote))
                                .foregroundStyle(.textMuted)
                        }
                        switch updater.phase {
                        case .readyToRelaunch:
                            Button("Relaunch to Update") { updater.relaunchNow() }
                        case .available:
                            Button("Update Now") { updater.installAvailableUpdate() }
                        case .idle, .checking, .upToDate, .downloading, .installing:
                            Button("Check for Updates…") { updater.checkForUpdates() }
                                // Greyed out while a check or download is in
                                // flight — same gate as the menu command.
                                .disabled(!updater.canCheckForUpdates)
                        }
                    }
                }
                Text("Updates are delivered via Sparkle from GitHub Releases. Beta builds arrive ahead of stable releases and may be rougher; switching beta off keeps the installed build until the next stable release.")
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
        .task { openAtLoginOn = await Self.loginItemRegistered() }
    }
}

/// Theme, accent color, fonts, and the inline how-it-works notes.
struct AppearanceSettingsView: View {
    @AppStorage("theme") private var theme = "dark"
    @AppStorage(accentColorDefaultsKey) private var accentHex = ""
    @AppStorage(backgroundColorDefaultsKey) private var backgroundHex = ""
    @AppStorage(textColorDefaultsKey) private var textHex = ""
    @AppStorage(appFontFamilyDefaultsKey) private var fontFamily = ""
    @AppStorage(appFontSizeScaleDefaultsKey) private var fontSizeScale = 1.0
    @AppStorage(windowOpacityDefaultsKey) private var windowOpacity = 1.0
    @AppStorage(windowBlurDefaultsKey) private var windowBlur = 0.6
    @AppStorage(windowGrainDefaultsKey) private var windowGrain = 0.0
    @State private var hexDraft = ""
    @State private var hexInvalid = false
    @State private var bgHexDraft = ""
    @State private var bgHexInvalid = false
    @State private var textHexDraft = ""
    @State private var textHexInvalid = false
    #if DEBUG
    @AppStorage(DevMetrics.overlayEnabledKey) private var showDevMetrics = true
    #endif

    /// One-click accent presets; the leading nil swatch is the bundled default.
    private static let presetAccents: [(name: String, hex: String)] = [
        ("Mint", "#00C7BE"), ("Teal", "#64D2FF"), ("Blue", "#0A84FF"),
        ("Indigo", "#5E5CE6"), ("Purple", "#BF5AF2"), ("Pink", "#FF375F"),
        ("Red", "#FF453A"), ("Orange", "#FF9F0A"), ("Yellow", "#FFD60A"),
    ]

    /// One-click background presets; the leading nil swatch is the stock
    /// graphite/lab palette. Dark roots first, two light ones at the end.
    private static let presetBackgrounds: [(name: String, hex: String)] = [
        ("Slate", "#0F172A"), ("Midnight", "#0D1B2A"), ("Espresso", "#211A16"),
        ("Forest", "#0C1F17"), ("Plum", "#1B1023"), ("Steel", "#1C2126"),
        ("Paper", "#F7F3EC"), ("Mist", "#EEF1F5"),
    ]

    /// The accent ColorPicker reads/writes the stored hex; an empty value shows
    /// (and resets to) the bundled default.
    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(hex: accentHex) ?? Color("BrandAccent") },
            set: { accentHex = $0.hexString ?? "" })
    }

    /// The background ColorPicker, same contract as the accent's.
    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { Color(hex: backgroundHex) ?? Color("BgRoot") },
            set: { backgroundHex = $0.hexString ?? "" })
    }

    /// The text-color ColorPicker, same contract as the accent's.
    private var textBinding: Binding<Color> {
        Binding(
            get: { Color(hex: textHex) ?? Color("TextMain") },
            set: { textHex = $0.hexString ?? "" })
    }

    /// The color the primary text actually sits on: the custom background if
    /// one is set, else the stock root asset resolved for the effective
    /// appearance. Used only to gauge text contrast.
    private var effectiveBackgroundRGB: BackgroundPalette.RGB? {
        if let custom = customBackgroundRGB { return custom }
        let name: NSAppearance.Name =
            theme == "light" ? .aqua
            : theme == "dark" ? .darkAqua
            : (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .darkAqua)
        guard let appearance = NSAppearance(named: name), let nc = NSColor(named: "BgRoot") else {
            return nil
        }
        var rgb: BackgroundPalette.RGB?
        appearance.performAsCurrentDrawingAppearance {
            if let s = nc.usingColorSpace(.sRGB) {
                rgb = BackgroundPalette.RGB(
                    red: s.redComponent, green: s.greenComponent, blue: s.blueComponent)
            }
        }
        return rgb
    }

    /// Non-blocking readability nudge: a custom text color whose contrast on the
    /// effective background falls below the comfortable threshold. nil (no
    /// warning) unless a custom text color is set and genuinely low-contrast.
    private var textContrastWarning: String? {
        guard let text = customTextRGB, let bg = effectiveBackgroundRGB,
              TextPalette.contrastRatio(text, bg) < TextPalette.minComfortableContrast
        else { return nil }
        return "This color may be hard to read on your background — the contrast is low. It's still applied."
    }

    /// One Window-section slider row: label, slider, live percent readout.
    private func effectSlider(
        _ label: String, value: Binding<Double>, in range: ClosedRange<Double>, percent: Double
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 56, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int((percent * 100).rounded()))%")
                .font(.app(.callout).monospacedDigit())
                .foregroundStyle(.textMuted)
                .frame(width: 44, alignment: .trailing)
        }
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
                .disabled(!backgroundHex.isEmpty)
                if !backgroundHex.isEmpty {
                    Text("Overridden by your custom background below — light/dark follows that color. Reset the background to use the theme.")
                        .font(.app(.footnote))
                        .foregroundStyle(.textMuted)
                } else if theme == "light" {
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

            Section("Background") {
                LabeledContent("Presets") {
                    HStack(spacing: 7) {
                        backgroundSwatch(name: "Graphite (default)", hex: nil)
                        ForEach(Self.presetBackgrounds, id: \.hex) { preset in
                            backgroundSwatch(name: preset.name, hex: preset.hex)
                        }
                    }
                }
                LabeledContent("Custom") {
                    HStack(spacing: 8) {
                        ColorPicker("", selection: backgroundBinding, supportsOpacity: false).labelsHidden()
                        TextField("Hex code", text: $bgHexDraft, prompt: Text("#0D1B2A"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 110)
                            .onSubmit { commitBackgroundHex() }
                        if !backgroundHex.isEmpty {
                            Button("Reset") { setBackground("") }
                        }
                    }
                }
                if bgHexInvalid {
                    Text("Enter a hex color like #0D1B2A (or the short #123).")
                        .font(.app(.footnote))
                        .foregroundStyle(.orange)
                }
                Text("Repaints every pane, card, and bar; hairlines and the light/dark text treatment adapt to the color automatically. The Terminal and JS Console keep their console-dark surfaces, and the Window sliders below still turn it to glass.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }

            Section("Text") {
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
                LabeledContent("Color") {
                    HStack(spacing: 8) {
                        ColorPicker("", selection: textBinding, supportsOpacity: false).labelsHidden()
                        TextField("Hex code", text: $textHexDraft, prompt: Text("#ECECEC"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 110)
                            .onSubmit { commitTextHex() }
                        if !textHex.isEmpty {
                            Button("Reset") { setText("") }
                        }
                    }
                }
                if textHexInvalid {
                    Text("Enter a hex color like #ECECEC (or the short #EEE).")
                        .font(.app(.footnote))
                        .foregroundStyle(.orange)
                } else if let warning = textContrastWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.app(.footnote))
                        .foregroundStyle(.orange)
                }
                Text("Sets the primary text color; subtitles and muted labels are derived from it automatically. Font applies across the app — code and log views keep their monospaced font, and the terminal keeps its own. ⌘= / ⌘- additionally zoom the whole window.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }

            Section("Window") {
                effectSlider(
                    "Opacity", value: $windowOpacity, in: WindowEffects.opacityRange,
                    percent: WindowEffects.clamped(windowOpacity))
                effectSlider(
                    "Blur", value: $windowBlur, in: 0...1,
                    percent: WindowEffects.clampedAmount(windowBlur))
                    .disabled(!WindowEffects.isTranslucent(windowOpacity))
                effectSlider(
                    "Grain", value: $windowGrain, in: 0...1,
                    percent: WindowEffects.clampedAmount(windowGrain))
                Text("Below 100% opacity the main window turns to glass — what's behind shows through every pane, softened by Blur. Grain films the window with texture at any opacity.")
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
        .onAppear {
            hexDraft = accentHex
            bgHexDraft = backgroundHex
            textHexDraft = textHex
        }
        // Reflect swatch/color-well changes into the hex fields so they always
        // show the effective value; a background change also re-derives the
        // appearance (light/dark follows the color).
        .onChange(of: accentHex) { hexDraft = accentHex }
        .onChange(of: backgroundHex) {
            bgHexDraft = backgroundHex
            applyStoredTheme()
        }
        .onChange(of: textHex) { textHexDraft = textHex }
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

    /// A one-click background circle; nil hex is the stock palette. The
    /// selected swatch carries a checkmark.
    private func backgroundSwatch(name: String, hex: String?) -> some View {
        let color = hex.flatMap { Color(hex: $0) } ?? Color("BgRoot")
        let isSelected = backgroundHex == (hex ?? "")
        return Button { setBackground(hex ?? "") } label: {
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

    private func setBackground(_ hex: String) {
        backgroundHex = hex
        bgHexDraft = hex
        bgHexInvalid = false
    }

    /// The background twin of `commitHex` — empty resets to the stock palette.
    private func commitBackgroundHex() {
        let trimmed = bgHexDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            setBackground("")
            return
        }
        guard let color = Color(hex: trimmed), let normalized = color.hexString else {
            bgHexInvalid = true
            return
        }
        setBackground(normalized)
    }

    private func setText(_ hex: String) {
        textHex = hex
        textHexDraft = hex
        textHexInvalid = false
    }

    /// The text-color twin of `commitHex` — empty resets to the stock tokens.
    private func commitTextHex() {
        let trimmed = textHexDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            setText("")
            return
        }
        guard let color = Color(hex: trimmed), let normalized = color.hexString else {
            textHexInvalid = true
            return
        }
        setText(normalized)
    }
}

/// Telemetry consent plus where local captures and the command log live.
struct PrivacySettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage(ScreenCaptureService.captureFolderDefaultsKey) private var captureFolderPath = ""
    @AppStorage(reactotronAllowLANKey) private var reactotronAllowLAN = true
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

            Section("Network") {
                Toggle("Accept Reactotron connections from your network", isOn: $reactotronAllowLAN)
                    .onChange(of: reactotronAllowLAN) {
                        Task { await state.reactotronSession.networkScopeChanged() }
                    }
                Text("On (like the official Reactotron app), devices on your Wi-Fi can reach the :9090 server — needed when the app loads its bundle over the network. Off, only localhost connects (USB via adb reverse, emulators, iOS Simulators). Changing this restarts the server; reload your app to reconnect.")
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
        .map(state.presented)
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
