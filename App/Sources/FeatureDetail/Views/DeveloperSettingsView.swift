import ADBKit
import SwiftUI

/// Android's Developer Options over adb — the UI-debugging overlays, layout
/// switches, and animation scales from `DeveloperSettingsService`'s
/// declarative table. Values load from the device (ground truth, not
/// remembered state); a toggle applies optimistically and resyncs on failure,
/// mirroring `SystemRestrictionsView`.
struct DeveloperSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var toggles: [String: Bool]?
    @State private var scales: [String: Double] = [:]
    @State private var refreshBusy = false

    private var serial: String { state.targetSerials.first ?? "" }
    private var engine: FeatureEngine { state.env.engine }

    var body: some View {
        Group {
            if state.targetSerials.isEmpty {
                ContentUnavailableView(
                    "No device connected", systemImage: "iphone.slash",
                    description: Text("Connect a device to change its developer settings.")
                )
            } else if toggles != nil {
                form
            } else {
                ProgressView("Reading developer settings…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: state.targetSerials.first ?? "") { await load() }
    }

    private var form: some View {
        HubColumn {
            HubSection("Input", accessory: {
                Button {
                    Task { await refresh() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(IconButtonStyle())
                    .help("Refresh from the device")
                    .disabled(refreshBusy)
            }) {
                toggleRows(ids: ["show-touches", "pointer-location"])
            }

            HubSection("Drawing") {
                toggleRows(ids: ["layout-bounds", "gpu-overdraw", "gpu-profile", "force-rtl"])
            }

            HubSection("Animations") {
                ForEach(DeveloperSettingsService.animationScales) { scale in
                    scaleRow(scale)
                }
            }

            HubSection("Apps") {
                toggleRows(ids: ["keep-activities", "strict-mode"])
            }
        }
    }

    /// The table's rows for one section, in the section's order. A typo'd id
    /// renders nothing — `sectionsCoverEveryToggle` in the logic tests would
    /// be overkill; the registry-style invariant lives on the service table.
    @ViewBuilder
    private func toggleRows(ids: [String]) -> some View {
        ForEach(ids, id: \.self) { id in
            if let toggle = DeveloperSettingsService.toggles.first(where: { $0.id == id }) {
                SwitchRow(toggle.title, subtitle: toggle.detail, isOn: binding(toggle))
            }
        }
    }

    private func scaleRow(_ scale: DevScaleDef) -> some View {
        HStack {
            Text(scale.title)
            Spacer()
            Picker("", selection: scaleBinding(scale)) {
                ForEach(DeveloperSettingsService.scaleChoices, id: \.self) { choice in
                    Text(choice == 0 ? "Off" : "\(choice.formatted())×").tag(choice)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    /// Optimistic per-toggle binding: flip the one row immediately, apply in
    /// the background, resync from the device only on failure.
    private func binding(_ toggle: DevToggleDef) -> Binding<Bool> {
        Binding(
            get: { toggles?[toggle.id] ?? false },
            set: { newValue in
                Task { @MainActor in
                    toggles?[toggle.id] = newValue
                    await apply {
                        try await engine.developerSettings.set(toggle, on: newValue, serial: serial)
                    }
                }
            }
        )
    }

    /// The picker writes values the device echoes back verbatim, so the
    /// optimistic value survives a reload.
    private func scaleBinding(_ scale: DevScaleDef) -> Binding<Double> {
        Binding(
            get: { scales[scale.id] ?? 1.0 },
            set: { newValue in
                Task { @MainActor in
                    scales[scale.id] = newValue
                    await apply {
                        try await engine.developerSettings.setScale(scale, value: newValue, serial: serial)
                    }
                }
            }
        )
    }

    private func apply(_ operation: @escaping @Sendable () async throws -> AdbResult) async {
        await CommandLog.userInitiated {
            do {
                let result = try await operation()
                if !result.succeeded {
                    let detail = result.stderr.isEmpty ? result.stdout : result.stderr
                    state.showToast(Toast(message: "Failed — \(detail)", ok: false))
                    await load()
                }
            } catch {
                state.showToast(Toast(message: error.localizedDescription, ok: false))
                await load()
            }
        }
    }

    private func refresh() async {
        refreshBusy = true
        defer { refreshBusy = false }
        await load()
    }

    private func load() async {
        guard !serial.isEmpty else { return }
        let loaded = await CommandLog.userInitiated { () -> ([String: Bool], [String: Double]) in
            let toggleValues = await engine.developerSettings.readToggles(serial: serial)
            let scaleValues = await engine.developerSettings.readScales(serial: serial)
            return (toggleValues, scaleValues)
        }
        guard !Task.isCancelled else { return }
        toggles = loaded.0
        scales = loaded.1
    }
}
