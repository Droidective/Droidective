import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Whether an install from the install screens opens the app afterwards. One
/// remembered choice shared by Install App, the opened-package screen and the
/// drop prompt, so the box reads the way it was last left wherever it shows.
let installOpensAppKey = "installOpensApp"

/// Install an app onto the selected device(s): drag an `.apk` — or a split
/// bundle (`.apks`, `.xapk`, `.apkm`) — onto the drop zone or pick one with the
/// file button. Reinstalls with `adb install -r` (keeps data), and installs on
/// every targeted device when run-on-all is on. A bundle is unpacked and
/// narrowed to the device's splits first, so the status line reports its stage.
/// Installs run in the background (leaving this screen doesn't cancel them);
/// each package gets a details card with live per-device status, and a plain
/// APK can go on to APK Studio from it. Packages double-clicked in Finder land
/// on their own opened-package screen instead.
struct InstallAppView: View {
    @Environment(AppState.self) private var state
    @AppStorage(installOpensAppKey) private var opensApp = false
    @State private var dropTargeted = false
    /// Packages this screen kicked off — scopes the cards to its own work.
    @State private var launched: [URL] = []

    private var targets: [Device] {
        state.devices.filter { state.targetSerials.contains($0.serial) }
    }

    private var installing: Bool {
        state.installJobs.contains { launched.contains($0.packageURL) && $0.isRunning }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dropZone
                VStack(spacing: 8) {
                    Toggle("Open after installing", isOn: $opensApp)
                        .toggleStyle(.checkbox)
                        .font(.app(.callout))
                    targetSummary
                }
                ForEach(launched, id: \.self) { url in
                    PackageDetailsCard(url: url) { actions(for: url) }
                }
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: installing ? "arrow.down.circle.dotted" : "arrow.down.app")
                .font(.app(size: 46))
                .foregroundStyle(.brandAccent)
            Text(installing ? "Installing…" : "Drag an app package here")
                .font(.app(.title3).weight(.medium))
            Text("APK · APKS · XAPK · APKM")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
            Button("Choose File…") { pickAndInstall() }
                .disabled(installing)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    dropTargeted ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.borderSubtle),
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [7])
                )
        }
        .featureFileDrop(
            claims: InstallablePackage.filter,
            perform: { install($0) },
            isTargeted: { dropTargeted = $0 })
    }

    /// A plain APK can go on to APK Studio; a bundle can't, since the studio
    /// reads one APK and not a container of them.
    @ViewBuilder private func actions(for url: URL) -> some View {
        if AppPackageFormat.detect(fileName: url.lastPathComponent) == .apk {
            Button("Open in APK Studio") { state.openInApkStudio(url) }
        }
    }

    @ViewBuilder private var targetSummary: some View {
        if targets.isEmpty {
            Label("Connect a device to install onto", systemImage: "iphone.slash")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
        } else {
            Text("Installs on \(targets.map(\.label).joined(separator: ", "))")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private func pickAndInstall() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = InstallablePackage.contentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, !panel.urls.isEmpty { install(panel.urls) }
    }

    private func install(_ urls: [URL]) {
        let serials = targets.map(\.serial)
        guard !urls.isEmpty, !serials.isEmpty else {
            state.showToast(Toast(message: "Connect a device first", ok: false))
            return
        }
        launched = urls
        state.startInstall(urls, onSerials: serials, opensApp: opensApp)
    }
}
