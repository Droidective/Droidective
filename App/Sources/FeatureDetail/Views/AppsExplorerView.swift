import ADBKit
import AppKit
import SwiftUI

/// Every installed app (user + system) with search across name, version,
/// and bundle id. Selecting one shows its info, permission count, and live
/// permission toggles.
struct AppsExplorerView: View {
    @Environment(AppState.self) private var state
    @Environment(\.tabFeatureID) private var tabFeatureID
    @Environment(\.colorScheme) private var colorScheme

    /// The list and what the user has done with it, held by the window rather
    /// than by this view: re-reading every installed app because a tab moved is
    /// a wait for something already on screen. See `AppsExplorerModel`.
    private var model: AppsExplorerModel {
        state.featureState(AppsExplorerModel.self, for: tabFeatureID) { AppsExplorerModel() }
    }

    private var apps: [AppListing]? {
        get { model.apps }
        nonmutating set { model.apps = newValue }
    }
    private var states: [String: AppLifecycle] {
        get { model.states }
        nonmutating set { model.states = newValue }
    }
    private var search: String {
        get { model.search }
        nonmutating set { model.search = newValue }
    }
    private var scope: Scope {
        get { model.scope }
        nonmutating set { model.scope = newValue }
    }
    private var selectedPackage: String? {
        get { model.selectedPackage }
        nonmutating set { model.selectedPackage = newValue }
    }
    private var notRemovable: Set<String> {
        get { model.notRemovable }
        nonmutating set { model.notRemovable = newValue }
    }

    private typealias Scope = AppsScope

    private var serial: String { state.targetSerials.first ?? "" }

    private var visibleApps: [AppListing] {
        (apps ?? []).filter { app in
            switch scope {
            case .all: break
            case .user: if app.isSystem { return false }
            case .system: if !app.isSystem { return false }
            }
            return app.matches(search)
        }
    }

    var body: some View {
        Group {
            if state.targetSerials.isEmpty {
                ContentUnavailableView(
                    "No device connected", systemImage: "iphone.slash",
                    description: Text("Connect a device to browse its apps.")
                )
            } else {
                content
            }
        }
        .task(id: state.targetSerials.first ?? "") {
            // A tab that moved brings the list with it. Only a device it hasn't
            // read yet is worth the round trips.
            guard model.apps == nil || model.loadedSerial != serial else { return }
            await loadApps()
        }
    }

    // Plain HStack, not HSplitView: NSSplitView ignores SwiftUI safe-area
    // insets, so the search/filter row and the detail's top rows rendered
    // underneath the device bar.
    private var content: some View {
        GeometryReader { geo in
            // In a narrow split pane the old fixed 320pt list starved the
            // detail — the list now cedes width proportionally (never below
            // 230pt, never above 320) so both columns stay usable.
            let listWidth = max(230, min(320, geo.size.width * 0.4))
            HStack(spacing: 0) {
                listColumn(width: listWidth)

                Divider()

                detailColumn
            }
        }
    }

    private func listColumn(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Below ~300pt the search field + segmented scope + refresh no
            // longer share a row — the scope picker drops to its own line.
            if width < 300 {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        searchField
                        refreshButton
                    }
                    scopePicker
                }
                .padding(8)
            } else {
                HStack(spacing: 8) {
                    searchField
                    scopePicker.frame(width: 160)
                    refreshButton
                }
                .padding(8)
            }
            Divider()

            if let apps {
                if visibleApps.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(visibleApps) { app in
                        appRow(app)
                    }
                    .translucentListBackground()
                }
                HStack {
                    Text("\(visibleApps.count) of \(apps.count) apps")
                        .font(.app(.caption))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(6)
            } else {
                ProgressView("Reading apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width)
    }

    private var searchField: some View {
        TextField("Search name, version, or bundle…", text: searchBinding)
            .brandField()
    }

    private var searchBinding: Binding<String> {
        Binding(get: { search }, set: { search = $0 })
    }
    private var scopeBinding: Binding<Scope> {
        Binding(get: { scope }, set: { scope = $0 })
    }

    private var scopePicker: some View {
        Picker("", selection: scopeBinding) {
            ForEach(Scope.allCases, id: \.self) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }

    private var refreshButton: some View {
        Button {
            Task { await loadApps(showLoading: false) }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Refresh")
    }

    @ViewBuilder private var detailColumn: some View {
        if let selectedPackage {
            AppDetailPane(
                packageId: selectedPackage,
                lifecycle: states[selectedPackage],
                canUninstall: canUninstall(selectedPackage),
                onNotRemovable: { notRemovable.insert($0) },
                onChanged: { Task { await loadApps(showLoading: false) } }
            )
            .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView(
                "Select an app",
                systemImage: "square.grid.3x3",
                description: Text("Pick an app to see its info and permissions.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One app row with hand-drawn selection. The native `List(selection:)`
    /// highlight follows the control accent — the bundled green asset, which a
    /// custom accent can't recolor — so the row draws its own `.brandAccent`
    /// background instead.
    private func appRow(_ app: AppListing) -> some View {
        let isSelected = selectedPackage == app.packageId
        let accentText = Color.brandAccent.contrastingForeground(for: colorScheme)
        return Button { selectedPackage = app.packageId } label: {
            HStack(spacing: 8) {
                AppIconView(packageId: app.packageId, name: app.displayName, serial: serial)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(app.displayName)
                            .foregroundStyle(isSelected ? accentText : Color.primary)
                        if app.isSystem {
                            Text("system")
                                .font(.app(.caption2))
                                .foregroundStyle(isSelected ? accentText.opacity(0.8) : Color.textMuted)
                                .padding(.horizontal, 4)
                                .background(
                                    isSelected
                                        ? AnyShapeStyle(accentText.opacity(0.15))
                                        : AnyShapeStyle(SurfaceFillStyle()),
                                    in: Capsule()
                                )
                        }
                        lifecycleBadge(for: app.packageId)
                    }
                    Text("\(app.packageId)\(app.versionName.map { " · v\($0)" } ?? "")")
                        .font(.app(.footnote))
                        .foregroundStyle(isSelected ? accentText.opacity(0.8) : Color.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(Color.clear))
                .padding(.horizontal, 6)
        )
    }

    @ViewBuilder
    private func lifecycleBadge(for packageId: String) -> some View {
        if let lifecycle = states[packageId], lifecycle.removed {
            badge("removed", .red)
        } else if let lifecycle = states[packageId], lifecycle.disabled {
            badge("disabled", .orange)
        }
    }

    /// Whether to offer Uninstall. The framework package and auto-generated
    /// resource overlays are never removable; the rest are offered until an
    /// attempt proves otherwise.
    private func canUninstall(_ packageId: String) -> Bool {
        if notRemovable.contains(packageId) { return false }
        if packageId == "android" { return false }
        if packageId.contains("auto_generated_rro") || packageId.hasSuffix(".overlay") { return false }
        return true
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.app(.caption2))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func loadApps(showLoading: Bool = true) async {
        if showLoading {
            apps = nil
            selectedPackage = nil
        }
        guard let serial = state.targetSerials.first else { return }
        model.loadedSerial = serial
        let (listing, lifecycle) = await CommandLog.userInitiated {
            async let listing = try? state.env.engine.appsExplorer.listAll(serial: serial)
            async let lifecycle = state.env.engine.systemApps.states(serial: serial)
            return await (listing, lifecycle)
        }
        guard !Task.isCancelled else { return }
        let newApps = listing ?? []
        apps = newApps
        states = lifecycle
        // Drop a selection whose package no longer exists (e.g. just
        // uninstalled) so the detail pane doesn't linger on an app that's gone.
        if let selectedPackage, !newApps.contains(where: { $0.packageId == selectedPackage }) {
            self.selectedPackage = nil
        }
    }
}

/// Right pane: app info, permission count, and live permission toggles.
private struct AppDetailPane: View {
    @Environment(AppState.self) private var state
    let packageId: String
    var lifecycle: AppLifecycle?
    var canUninstall = true
    var onNotRemovable: (String) -> Void = { _ in }
    var onChanged: () -> Void = {}

    private var derivedName: String {
        packageId.split(separator: ".").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? packageId
    }

    @State private var info: AppInfo?
    @State private var permissions: [PermissionEntry]?
    @State private var showPermissions = false
    @State private var mutating = false
    @State private var pullingApk = false
    @State private var managing = false
    @State private var showFiles = false
    @State private var confirmingClearData = false
    @State private var confirmingUninstall = false

    private var serial: String { state.targetSerials.first ?? "" }

    var body: some View {
        HubColumn {
            HubSection("App info") {
                HStack(spacing: 12) {
                    AppIconView(packageId: packageId, name: derivedName, serial: state.targetSerials.first ?? "")
                        .frame(width: 40, height: 40)
                    Text(packageId)
                        .font(.app(.callout))
                        .textSelection(.enabled)
                }
                if let info, info.installed {
                    HubRowList(
                        [
                            ("Version", info.versionName),
                            ("Target SDK", info.targetSdk),
                            ("Min SDK", info.minSdk),
                            ("Last Update", info.lastUpdate),
                        ]
                        + (info.apkSizeBytes.map {
                            [("APK Size", ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))]
                        } ?? [])
                    )
                } else if info == nil {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Reading app info…").foregroundStyle(.textMuted)
                    }
                }
            }

            HubSection("Controls") {
                HStack(spacing: 8) {
                    Button { runControl(.open) } label: {
                        Label("Open", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Button { runControl(.restart) } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    Button { runControl(.stop) } label: {
                        Label("Force Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    Button { runControl(.clearCache) } label: {
                        Label("Clear Cache", systemImage: "internaldrive")
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(managing)
            }

            HubSection("Permissions") {
                if let permissions {
                    Toggle(isOn: $showPermissions) {
                        Text("Runtime permissions (\(permissions.count))")
                    }
                    .toggleStyle(.button)
                    if showPermissions {
                        if permissions.isEmpty {
                            Text("No runtime permissions declared.")
                                .foregroundStyle(.textMuted)
                        }
                        ForEach(permissions) { permission in
                            Toggle(isOn: Binding(
                                get: { permission.granted },
                                set: { setPermission(permission, granted: $0) }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(permission.shortName)
                                    Text(permission.name)
                                        .font(.app(.caption))
                                        .foregroundStyle(.textMuted)
                                }
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(mutating)
                            .opacity(mutating ? 0.5 : 1)
                        }
                        if mutating {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Updating…").foregroundStyle(.textMuted)
                            }
                        }
                    }
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Reading permissions…").foregroundStyle(.textMuted)
                    }
                }
            }

            HubSection("Files & APK") {
                Button {
                    pullApk()
                } label: {
                    Label(pullingApk ? "Pulling…" : "Pull APK", systemImage: "arrow.down.circle")
                }
                .disabled(pullingApk)
                Button {
                    showFiles = true
                } label: {
                    Label("Explore files", systemImage: "folder")
                }
            }

            HubSection("Manage") {
                if lifecycle?.removed == true {
                    Button {
                        manage { try await $0.setRemoved(serial: serial, packageId: packageId, false) }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.left")
                    }
                    .disabled(managing)
                } else {
                    let isDisabled = lifecycle?.disabled ?? false
                    Button {
                        manage { try await $0.setDisabled(serial: serial, packageId: packageId, !isDisabled) }
                    } label: {
                        Label(isDisabled ? "Enable" : "Disable", systemImage: isDisabled ? "eye" : "eye.slash")
                    }
                    .disabled(managing)
                    Button(role: .destructive) {
                        confirmingClearData = true
                    } label: {
                        Label("Clear Data", systemImage: "trash")
                    }
                    .disabled(managing)
                    if canUninstall {
                        Button(role: .destructive) {
                            confirmingUninstall = true
                        } label: {
                            Label("Uninstall", systemImage: "trash")
                        }
                        .disabled(managing)
                    }
                }
                if managing {
                    HStack { ProgressView().controlSize(.small); Text("Working…").foregroundStyle(.textMuted) }
                }
            }
        }
        .confirmationDialog(
            "Clear all data for \(packageId)? This signs you out and wipes local storage.",
            isPresented: $confirmingClearData
        ) {
            Button("Clear Data", role: .destructive) { runControl(.clearData) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Uninstall \(packageId)? This removes the app from the device.",
            isPresented: $confirmingUninstall
        ) {
            Button("Uninstall", role: .destructive) { uninstall() }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: "\(packageId)|\(state.targetSerials.first ?? "")") {
            await load()
        }
        .sheet(isPresented: $showFiles) {
            VStack(spacing: 0) {
                HStack {
                    Text("Files · \(packageId)")
                        .font(.app(.headline))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Done") { showFiles = false }
                }
                .padding(12)
                Divider()
                SandboxBrowserView(packageId: packageId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 580, height: 460)
        }
    }

    /// Uninstall-for-user, then read back the lifecycle to see what happened: a
    /// user app vanishes from the device (success), a system app stays on the
    /// image removed-for-user (success, restorable), and a protected package is
    /// still installed — flag it non-removable so the button disappears.
    private func uninstall() {
        managing = true
        Task {
            await CommandLog.userInitiated {
                do {
                    _ = try await state.env.engine.systemApps.setRemoved(serial: serial, packageId: packageId, true)
                    let entry = await state.env.engine.systemApps.states(serial: serial)[packageId]
                    switch SystemAppsService.uninstallOutcome(for: entry) {
                    case .removed:
                        state.showToast(Toast(message: "\(packageId) uninstalled", ok: true, important: true))
                    case .removedForUser:
                        state.showToast(Toast(message: "\(packageId) uninstalled for this user", ok: true, important: true))
                    case .stillInstalled:
                        onNotRemovable(packageId)
                        state.showToast(Toast(message: "Can't uninstall \(packageId) — it's protected. Disable it instead.", ok: false))
                    }
                } catch {
                    state.showToast(Toast(message: error.localizedDescription, ok: false))
                }
            }
            managing = false
            onChanged()
        }
    }

    private func manage(_ operation: @escaping (SystemAppsService) async throws -> AdbResult) {
        managing = true
        Task {
            await CommandLog.userInitiated {
                do {
                    let result = try await operation(state.env.engine.systemApps)
                    let ok = result.succeeded && !result.stdout.localizedCaseInsensitiveContains("failure")
                    let detail = result.stderr.isEmpty ? result.stdout : result.stderr
                    state.showToast(Toast(message: ok ? "\(packageId) updated" : "Failed — \(detail)", ok: ok))
                } catch {
                    state.showToast(Toast(message: error.localizedDescription, ok: false))
                }
            }
            managing = false
            onChanged()
        }
    }

    /// Lifecycle control (open, force-stop, clear cache/data) on the selected
    /// app — the actions the standalone "Manage App" screen used to host, now
    /// folded into the Apps explorer.
    private func runControl(_ action: AppControlService.AppAction) {
        managing = true
        Task {
            await CommandLog.userInitiated {
                let result = (try? await state.env.engine.appControl.control(
                    serial: serial, packageId: packageId, action: action
                )) ?? FeatureResult(ok: false, message: "adb not found")
                state.showToast(Toast(message: result.message, ok: result.ok))
            }
            managing = false
        }
    }

    private func load() async {
        info = nil
        permissions = nil
        guard let serial = state.targetSerials.first else { return }
        let (fetchedInfo, fetchedPermissions) = await CommandLog.userInitiated {
            async let infoResult = try? state.env.engine.inspection.getAppInfo(serial: serial, packageId: packageId)
            async let permissionsResult = try? state.env.engine.inspection.listPermissions(serial: serial, packageId: packageId)
            return await (infoResult, permissionsResult)
        }
        guard !Task.isCancelled else { return }
        info = fetchedInfo ?? .notInstalled
        permissions = fetchedPermissions ?? []
    }

    private func pullApk() {
        guard let serial = state.targetSerials.first else { return }
        guard let dest = state.askSaveLocation(suggestedName: "\(packageId).apk") else { return }
        pullingApk = true
        Task {
            await CommandLog.userInitiated {
                do {
                    let saved = try await state.withFileProgress(
                        "Pulling \(packageId)…", destination: dest, expectedBytes: info?.apkSizeBytes
                    ) {
                        try await state.env.engine.inspection.pullApk(serial: serial, packageId: packageId, to: dest)
                    }
                    state.showToast(Toast(message: AppInfoView.pulledApkToast(saved), ok: true, revealPath: dest.path))
                } catch {
                    state.showToast(Toast(message: error.localizedDescription, ok: false))
                }
            }
            pullingApk = false
        }
    }

    private func setPermission(_ permission: PermissionEntry, granted: Bool) {
        guard let serial = state.targetSerials.first else { return }
        mutating = true
        Task {
            await CommandLog.userInitiated {
                let result = (try? await state.env.engine.inspection.setPermission(
                    serial: serial, packageId: packageId, permission: permission.name, grant: granted
                )) ?? FeatureResult(ok: false, message: "adb not found")
                state.showToast(Toast(message: result.message, ok: result.ok))
            }
            let refreshed = try? await state.env.engine.inspection.listPermissions(serial: serial, packageId: packageId)
            permissions = refreshed ?? permissions
            mutating = false
        }
    }
}

/// App launcher icon with a monogram fallback. Real icons are streamed off the
/// device (only the icon entry, never the whole APK) and cached; apps that ship
/// no raster icon keep the monogram.
struct AppIconView: View {
    @Environment(AppState.self) private var state
    let packageId: String
    let name: String
    let serial: String

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                MonogramIcon(name: name, seed: packageId)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: packageId) { await load() }
    }

    private func load() async {
        // Reset to *this* package's cached icon (nil when it has none) so a
        // reused view never lingers on the previously shown app's icon.
        image = AppIconCache.shared.image(for: packageId)
        if image != nil { return }
        guard !serial.isEmpty, !AppIconCache.shared.didAttempt(packageId) else { return }
        let data = await state.env.engine.appIcons.iconData(serial: serial, packageId: packageId)
        AppIconCache.shared.markAttempted(packageId)
        guard !Task.isCancelled else { return }
        if let data, let loaded = NSImage(data: data) {
            AppIconCache.shared.store(loaded, for: packageId)
            image = loaded
        }
    }
}

/// Colored rounded square with the app's initial — the launcher-style fallback
/// shown until (or instead of) a real icon.
struct MonogramIcon: View {
    let name: String
    let seed: String

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color.gradient)
            .overlay(
                Text(initial)
                    .font(.app(size: 13, weight: .semibold))
                    .foregroundStyle(color.contrastingForeground)
                    .minimumScaleFactor(0.6)
            )
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    private var color: Color {
        // Deterministic hue from the package id — String.hashValue is randomized
        // per process, so roll a stable hash for a consistent color.
        let hash = seed.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return Color(hue: Double(abs(hash) % 360) / 360, saturation: 0.45, brightness: 0.65)
    }
}

/// Process-lifetime cache of decoded icons, shared across rows so scrolling
/// never refetches. `attempted` remembers icon-less apps so their rows don't
/// re-probe the device each time they reappear.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var images: [String: NSImage] = [:]
    private var attempted: Set<String> = []

    func image(for packageId: String) -> NSImage? { images[packageId] }
    func store(_ image: NSImage, for packageId: String) { images[packageId] = image }
    func didAttempt(_ packageId: String) -> Bool { attempted.contains(packageId) }
    func markAttempted(_ packageId: String) { attempted.insert(packageId) }
}
