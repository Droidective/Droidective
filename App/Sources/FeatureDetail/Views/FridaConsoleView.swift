import ADBKit
import SwiftUI

/// Prepares a device for Frida: matches its architecture, downloads the right
/// frida-server / frida-gadget from GitHub releases, and (on a rooted device)
/// pushes and runs frida-server. You then connect with your own frida CLI
/// (`frida -U …`) — Droidective handles the fiddly device-side setup.
struct FridaConsoleView: View {
    @Environment(AppState.self) private var state
    @State private var arch: String?
    @State private var serverRunning = false
    @State private var status: String?
    @State private var busy = false
    @State private var gadgetPath: String?
    @State private var download = DownloadState()

    private var serial: String? { state.targetSerials.first }

    var body: some View {
        Group {
            if let serial { console(serial) } else { noDevice }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: serial) { await refresh() }
    }

    private var noDevice: some View {
        NoDeviceView("Connect a device to set up Frida.")
    }

    private func console(_ serial: String) -> some View {
        Form {
            Section("Device") {
                LabeledContent("Architecture", value: arch ?? "unknown")
                LabeledContent("frida-server", value: serverRunning ? "running" : "stopped")
            }
            Section("frida-server (rooted device)") {
                Button(busy ? "Working…" : "Download & start frida-server") { Task { await startServer(serial) } }
                    .buttonStyle(.borderedProminent).disabled(busy)
                Button("Stop frida-server") { Task { await stopServer(serial) } }
                    .disabled(busy || !serverRunning)
                Text("Then connect from a terminal: `frida-ps -U` or `frida -U -n <app>`.")
                    .font(.caption).foregroundStyle(.textMuted)
            }
            Section("frida-gadget (non-rooted)") {
                Button(busy ? "Working…" : "Download frida-gadget (.so)") { Task { await downloadGadget(serial) } }
                    .disabled(busy)
                if let gadgetPath {
                    Text(gadgetPath).font(.caption.monospaced()).foregroundStyle(.textMuted).textSelection(.enabled)
                    Text("Inject it into a repackaged APK (e.g. `objection patchapk`), then connect with `frida -U -n Gadget`.")
                        .font(.caption).foregroundStyle(.textMuted)
                }
            }
            if download.active {
                Section {
                    if let fraction = download.fraction {
                        ProgressView(value: fraction) { Text(download.label ?? "Downloading…") }
                    } else {
                        ProgressView { Text(download.label ?? "Downloading…") }
                    }
                }
            }
            if let status {
                Section { Text(status).font(.callout).foregroundStyle(.textMuted) }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func refresh() async {
        guard let serial else { return }
        do {
            arch = try await state.env.engine.frida.deviceArch(serial: serial)
            serverRunning = try await state.env.engine.frida.isServerRunning(serial: serial)
        } catch {
            status = error.localizedDescription
        }
    }

    private func startServer(_ serial: String) async {
        busy = true
        let progress = download
        defer { busy = false; progress.finish() }
        do {
            status = "Resolving device architecture…"
            guard let deviceArch = try await state.env.engine.frida.deviceArch(serial: serial) else {
                status = "Couldn't determine a supported device architecture."
                return
            }
            arch = deviceArch
            progress.begin("Downloading frida-server (\(deviceArch))…")
            let onProgress: @Sendable (Double) -> Void = { value in Task { @MainActor in progress.update(value) } }
            let local = try await state.env.engine.managedTools.install(.fridaServer, arch: deviceArch, onProgress: onProgress)
            progress.finish()
            let version = await state.env.engine.managedTools.installedVersion(.fridaServer) ?? ""
            state.showToast(Toast(message: "Downloaded frida-server \(version)", ok: true, copyText: local, revealPath: local))
            status = "Pushing and starting frida-server…"
            try await CommandLog.userInitiated(feature: "frida-console") {
                _ = try await state.env.engine.frida.installServer(localPath: local, serial: serial)
                _ = try await state.env.engine.frida.startServer(serial: serial)
            }
            serverRunning = try await state.env.engine.frida.isServerRunning(serial: serial)
            status = serverRunning ? "frida-server is running." : "Started — confirm with `frida-ps -U`. A rooted device is required."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func stopServer(_ serial: String) async {
        busy = true
        defer { busy = false }
        do {
            try await CommandLog.userInitiated(feature: "frida-console") {
                _ = try await state.env.engine.frida.stopServer(serial: serial)
            }
            serverRunning = try await state.env.engine.frida.isServerRunning(serial: serial)
            status = "Stopped frida-server."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func downloadGadget(_ serial: String) async {
        busy = true
        let progress = download
        defer { busy = false; progress.finish() }
        do {
            guard let deviceArch = try await state.env.engine.frida.deviceArch(serial: serial) else {
                status = "Couldn't determine a supported device architecture."
                return
            }
            arch = deviceArch
            progress.begin("Downloading frida-gadget (\(deviceArch))…")
            let onProgress: @Sendable (Double) -> Void = { value in Task { @MainActor in progress.update(value) } }
            let path = try await state.env.engine.managedTools.install(.fridaGadget, arch: deviceArch, onProgress: onProgress)
            gadgetPath = path
            let version = await state.env.engine.managedTools.installedVersion(.fridaGadget) ?? ""
            state.showToast(Toast(message: "Downloaded frida-gadget \(version)", ok: true, copyText: path, revealPath: path))
            status = "Downloaded frida-gadget."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }
}
