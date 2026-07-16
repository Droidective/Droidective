import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Install an APK onto the selected device(s): drag an `.apk` onto the drop zone
/// or pick one with the file button. Reinstalls with `adb install -r` (keeps
/// data), and installs on every targeted device when run-on-all is on. Installs
/// run in the background (leaving this screen doesn't cancel them) with live
/// per-device status below the drop zone. APKs double-clicked in Finder land on
/// their own opened-APK screen instead.
struct InstallAppView: View {
    @Environment(AppState.self) private var state
    @State private var dropTargeted = false
    /// APKs this screen kicked off — scopes the status rows to its own work.
    @State private var launched: [URL] = []

    private var targets: [Device] {
        state.devices.filter { state.targetSerials.contains($0.serial) }
    }

    private var installing: Bool {
        state.installJobs.contains { launched.contains($0.apkURL) && $0.isRunning }
    }

    var body: some View {
        VStack(spacing: 16) {
            dropZone
            InstallJobRows(urls: launched, showsApkName: launched.count > 1)
                .frame(maxWidth: 380)
            targetSummary
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: 600, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: installing ? "arrow.down.circle.dotted" : "arrow.down.app")
                .font(.app(size: 46))
                .foregroundStyle(.brandAccent)
            Text(installing ? "Installing…" : "Drag an APK here")
                .font(.app(.title3).weight(.medium))
            Button("Choose APK…") { pickAndInstall() }
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
        .dropDestination(for: URL.self) { urls, _ in
            let apks = urls.filter { $0.pathExtension.lowercased() == "apk" }
            guard !apks.isEmpty else { return false }
            install(apks)
            return true
        } isTargeted: { dropTargeted = $0 }
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
        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]
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
        state.startInstall(urls, onSerials: serials)
    }
}
