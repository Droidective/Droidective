import ADBKit
import SwiftUI

/// Version, SDK, install dates, APK size — and a one-click APK pull.
struct AppInfoView: View {
    @Environment(AppState.self) private var state
    @State private var info: AppInfo?
    @State private var pulling = false

    var body: some View {
        Group {
            if state.selectedBundle == nil {
                ContentUnavailableView(
                    "No bundle selected", systemImage: "shippingbox",
                    description: Text("Select a bundle to see its app info.")
                )
            } else if state.targetSerials.isEmpty {
                ContentUnavailableView(
                    "No device connected", systemImage: "iphone.slash",
                    description: Text("Connect a device to read app info.")
                )
            } else if let info {
                if info.installed {
                    details(info)
                } else {
                    ContentUnavailableView(
                        "Not installed", systemImage: "shippingbox",
                        description: Text("\(state.selectedBundle?.packageId ?? "The app") isn't installed on this device.")
                    )
                }
            } else {
                ProgressView("Reading app info…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(state.selectedBundleId ?? "")|\(state.targetSerials.first ?? "")") {
            await load()
        }
    }

    private func details(_ info: AppInfo) -> some View {
        HubColumn {
            HubSection("App info") {
                HubRowList(
                    [
                        ("Version", info.versionName),
                        ("Version Code", info.versionCode),
                        ("Target SDK", info.targetSdk),
                        ("Min SDK", info.minSdk),
                        ("First Install", info.firstInstall),
                        ("Last Update", info.lastUpdate),
                    ]
                    + (info.apkSizeBytes.map {
                        [("APK Size", ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))]
                    } ?? [])
                )
            }

            HubSection("APK") {
                Button { pullApk() } label: {
                    Label(pulling ? "Pulling…" : "Pull APK", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(pulling)
            }
        }
    }

    private func load() async {
        info = nil
        guard let serial = state.targetSerials.first,
              let packageId = state.selectedBundle?.packageId else { return }
        let result = await CommandLog.userInitiated {
            (try? await state.env.engine.inspection.getAppInfo(serial: serial, packageId: packageId)) ?? .notInstalled
        }
        guard !Task.isCancelled else { return }
        info = result
    }

    private func pullApk() {
        guard let serial = state.targetSerials.first,
              let packageId = state.selectedBundle?.packageId else { return }
        guard let dest = state.askSaveLocation(suggestedName: "\(packageId).apk") else { return }
        pulling = true
        Task {
            await CommandLog.userInitiated {
                do {
                    let saved = try await state.withFileProgress(
                        "Pulling APK…", destination: dest, expectedBytes: info?.apkSizeBytes
                    ) {
                        try await state.env.engine.inspection.pullApk(serial: serial, packageId: packageId, to: dest)
                    }
                    state.showToast(Toast(message: Self.pulledApkToast(saved), ok: true, revealPath: dest.path))
                } catch {
                    state.showToast(Toast(message: error.localizedDescription, ok: false))
                }
            }
            pulling = false
        }
    }

    /// "APK saved" for a single-file app; spells out the split count for an
    /// App Bundle install so the extra files next to the chosen one aren't a
    /// surprise. Shared with the Apps explorer's pull.
    static func pulledApkToast(_ saved: [URL]) -> String {
        let splits = saved.count - 1
        guard splits > 0 else { return "APK saved" }
        return "APK + \(splits) split\(splits == 1 ? "" : "s") saved"
    }
}
