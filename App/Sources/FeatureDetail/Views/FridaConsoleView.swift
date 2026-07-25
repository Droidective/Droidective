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
                    .font(.app(.caption)).foregroundStyle(.textMuted)
            }
            Section("frida-gadget (non-rooted)") {
                Button(busy ? "Working…" : "Download frida-gadget (.so)") { Task { await downloadGadget(serial) } }
                    .disabled(busy)
                if let gadgetPath {
                    Text(gadgetPath).font(.app(.caption).monospaced()).foregroundStyle(.textMuted).textSelection(.enabled)
                    Text("Inject it into a repackaged APK (e.g. `objection patchapk`), then connect with `frida -U -n Gadget`.")
                        .font(.app(.caption)).foregroundStyle(.textMuted)
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
                Section { Text(status).font(.app(.callout)).foregroundStyle(.textMuted) }
            }
        }
        .formStyle(.grouped)
        .translucentListBackground()
    }

    // MARK: - Actions

    private func refresh() async {
        guard let serial else { return }
        do {
            // Both probes complete before anything is published, so a re-keyed
            // task (the device changed) writes neither half.
            let deviceArch = try await state.env.engine.frida.deviceArch(serial: serial)
            let running = try await state.env.engine.frida.isServerRunning(serial: serial)
            guard !Task.isCancelled else { return }
            arch = deviceArch
            serverRunning = running
        } catch {
            guard !Task.isCancelled else { return }
            status = error.localizedDescription
        }
    }

    private func startServer(_ serial: String) async {
        busy = true
        let progress = download
        defer { busy = false; progress.finish() }
        do {
            status = "Checking root access…"
            guard await state.env.engine.root.detect(serial: serial).hasRootShell else {
                let name = state.devices.first { $0.serial == serial }?.label ?? serial
                status = "frida-server needs a rooted device — \(name) is not rooted. "
                    + "Use frida-gadget below for non-rooted devices."
                return
            }
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
            try await CommandLog.userInitiated {
                _ = try await state.env.engine.frida.installServer(localPath: local, serial: serial)
                _ = try await state.env.engine.frida.startServer(serial: serial)
            }
            // pidof can lag the spawn — poll briefly before declaring failure.
            for _ in 0..<8 {
                serverRunning = try await state.env.engine.frida.isServerRunning(serial: serial)
                if serverRunning { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            status = serverRunning
                ? "frida-server is running — connect with `frida-ps -U`."
                : "frida-server didn't start — check `su` access on the device, then try again."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func stopServer(_ serial: String) async {
        busy = true
        defer { busy = false }
        do {
            try await CommandLog.userInitiated {
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
