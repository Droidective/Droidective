import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Finder-opened packages backing the `apk-open` tab. In-memory like the
/// APK Studio session; the tab itself may be restored empty after a relaunch,
/// so the view keeps a drop-zone empty state.
@MainActor @Observable
final class ApkOpenSession {
    var urls: [URL] = []
}

/// The screen a double-clicked (or "Open With") app package lands on — a
/// workspace tab, deliberately not a registry feature: it exists only when a
/// file arrives. Shows what each package is (aapt2 badging for a plain APK,
/// name and size for a split bundle), installs on the selected device(s) with
/// live per-device status, and hands plain APKs to APK Studio, which works on
/// one APK and can't read a bundle container.
struct ApkOpenView: View {
    @Environment(AppState.self) private var state
    @State private var apkInfos: [URL: ApkInfo] = [:]
    @State private var dropTargeted = false

    private var urls: [URL] { state.apkOpen.urls }

    private var targets: [Device] {
        state.devices.filter { state.targetSerials.contains($0.serial) }
    }

    var body: some View {
        Group {
            if urls.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(urls, id: \.self) { apkCard($0) }
                        if urls.count > 1 { installAll }
                        targetSummary
                    }
                    .padding(24)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: urls) { await inspect() }
    }

    // MARK: - Cards

    private func apkCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.app(size: 30))
                    .foregroundStyle(.brandAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(apkInfos[url]?.label ?? url.lastPathComponent)
                        .font(.app(.title3).weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle(for: url))
                        .font(.app(.caption))
                        .foregroundStyle(.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            InstallJobRows(urls: [url])
            HStack(spacing: 10) {
                Button("Install") { install([url]) }
                    .buttonStyle(.borderedProminent)
                    .disabled(targets.isEmpty || installing(url))
                if AppPackageFormat.detect(fileName: url.lastPathComponent) == .apk {
                    Button("Open in APK Studio") { openStudio(url, tab: .inspect) }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.borderSubtle, lineWidth: 1)
        }
    }

    private var installAll: some View {
        Button("Install all \(urls.count) packages") { install(urls) }
            .buttonStyle(.borderedProminent)
            .disabled(targets.isEmpty || urls.contains(where: installing))
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

    /// The tab can be restored (or revisited) with nothing loaded — offer the
    /// same drop-in the Finder route provides.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.app")
                .font(.app(size: 46))
                .foregroundStyle(.brandAccent)
            Text("Drop an app package here")
                .font(.app(.title3).weight(.medium))
            Text("APK, APKS, XAPK, or APKM — double-clicking one in Finder lands here too.")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    dropTargeted ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.borderSubtle),
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [7])
                )
                .padding(20)
        }
        .featureFileDrop(
            claims: InstallablePackage.filter,
            perform: { state.apkOpen.urls = $0 },
            isTargeted: { dropTargeted = $0 })
    }

    // MARK: - Actions

    private func installing(_ url: URL) -> Bool {
        state.installJobs.contains { $0.packageURL == url && $0.isRunning }
    }

    private func install(_ urls: [URL]) {
        let serials = targets.map(\.serial)
        guard !serials.isEmpty else { return }
        state.startInstall(urls, onSerials: serials)
    }

    private func openStudio(_ url: URL, tab: ApkStudioTab) {
        state.apkStudio.apk = url
        state.apkStudio.signInput = nil
        state.apkStudio.tab = tab
        state.requestFeature("apk-studio")
    }

    private func inspect() async {
        var resolved: [URL: ApkInfo] = [:]
        for url in urls {
            resolved[url] = await state.env.engine.appInstall.inspect(apkPath: url.path)
        }
        guard !Task.isCancelled else { return }
        apkInfos = resolved
    }

    private func subtitle(for url: URL) -> String {
        guard let info = apkInfos[url] else { return url.lastPathComponent }
        var parts: [String] = [url.lastPathComponent]
        if let package = info.packageName { parts.append(package) }
        if let version = info.versionName { parts.append("v\(version)") }
        if let target = info.targetSdk { parts.append("SDK \(target)") }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(info.fileSizeBytes), countStyle: .file))
        return parts.joined(separator: " · ")
    }
}
