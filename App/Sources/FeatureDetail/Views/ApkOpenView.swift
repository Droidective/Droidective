import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Finder-opened APKs backing the `apk-open` tab. In-memory like the APK
/// Studio session; the tab itself may be restored empty after a relaunch, so
/// the view keeps a drop-zone empty state.
@MainActor @Observable
final class ApkOpenSession {
    var urls: [URL] = []
}

/// The screen a double-clicked (or "Open With") APK lands on — a workspace
/// tab, deliberately not a registry feature: it exists only when a file
/// arrives. Shows what each APK is (aapt2 badging), installs on the selected
/// device(s) with live per-device status, and hands single APKs to APK Studio.
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
                Button("Open in APK Studio") { openStudio(url, tab: .inspect) }
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
        Button("Install all \(urls.count) APKs") { install(urls) }
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
            Text("Drop an APK here")
                .font(.app(.title3).weight(.medium))
            Text("Double-clicking an .apk in Finder lands on this screen too.")
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
        .dropDestination(for: URL.self) { dropped, _ in
            let apks = dropped.filter { $0.pathExtension.lowercased() == "apk" }
            guard !apks.isEmpty else { return false }
            state.apkOpen.urls = apks
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    // MARK: - Actions

    private func installing(_ url: URL) -> Bool {
        state.installJobs.contains { $0.apkURL == url && $0.isRunning }
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
