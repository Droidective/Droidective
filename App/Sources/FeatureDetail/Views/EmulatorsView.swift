import ADBKit
import AppKit
import SwiftUI

/// Android Studio AVDs and Xcode iOS Simulators: launch (normal / cold boot /
/// wipe data for AVDs; boot for simulators), see which are running, and stop
/// them. Booted ones join the device bar through normal polling.
struct EmulatorsView: View {
    @Environment(AppState.self) private var state
    @State private var avds: [Avd]?
    @State private var simulators: [Simulator]?
    @State private var emulatorMissing = false
    @State private var simctlMissing = false
    @State private var reloadToken = 0
    @State private var wipeTarget: Avd?
    @State private var showAllSimulators = false

    /// The role decides which platforms this screen shows at all: iOS
    /// Developer sees only the simulators section (titled "Simulators"),
    /// the Android-first roles only the AVDs ("Emulators"), and "all
    /// features" both. The load skips the hidden platform entirely.
    private var visiblePlatforms: Set<DevicePlatform> {
        FeatureRegistry.visiblePlatforms(for: state.selectedRole)
    }
    private var showsAndroid: Bool { visiblePlatforms.contains(.android) }
    private var showsSimulators: Bool { visiblePlatforms.contains(.iosSimulator) }

    private static let collapsedSimulatorCount = 5

    var body: some View {
        Group {
            if avds == nil && simulators == nil {
                ProgressView("Reading virtual devices…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if (avds ?? []).isEmpty, (simulators ?? []).isEmpty {
                ContentUnavailableView(
                    "No virtual devices",
                    systemImage: "play.display",
                    description: Text(emptyStateAdvice)
                )
            } else {
                list
            }
        }
        // Re-resolves running state as devices come and go, or when a role
        // change re-scopes which platforms the screen shows.
        .task(id: "\(state.devices.map(\.serial).joined())|\(reloadToken)|\(state.selectedRole?.rawValue ?? "all")") {
            await load()
        }
    }

    private var emptyStateAdvice: String {
        var advice: [String] = []
        if showsAndroid {
            advice.append(
                emulatorMissing
                    ? "Install the Android Emulator from Android Studio → SDK Manager → SDK Tools."
                    : "Create a virtual device in Android Studio → Device Manager, then refresh."
            )
        }
        if showsSimulators {
            advice.append(
                simctlMissing
                    ? "Install Xcode for iOS Simulators."
                    : "Add iOS Simulators from Xcode → Window → Devices and Simulators."
            )
        }
        return advice.joined(separator: "\n")
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\((avds ?? []).count + (simulators ?? []).count) virtual devices")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
                Spacer()
                Button {
                    reloadToken += 1
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
            .padding(8)
            Divider()

            List {
                emulatorsSection
                simulatorsSection
            }
        }
        .confirmationDialog(
            "Wipe all data on \(wipeTarget?.displayName ?? "")? Apps, accounts, and settings on the AVD are erased.",
            isPresented: Binding(get: { wipeTarget != nil }, set: { if !$0 { wipeTarget = nil } })
        ) {
            Button("Wipe & Launch", role: .destructive) {
                if let avd = wipeTarget {
                    launch(avd, options: EmulatorService.LaunchOptions(wipeData: true))
                }
                wipeTarget = nil
            }
            Button("Cancel", role: .cancel) { wipeTarget = nil }
        }
    }

    @ViewBuilder
    private var emulatorsSection: some View {
        if let avds, !avds.isEmpty {
            Section("Android emulators") {
                ForEach(avds) { avdRow($0) }
            }
        }
    }

    @ViewBuilder
    private var simulatorsSection: some View {
        if let simulators, !simulators.isEmpty {
            let ordered = SimulatorListParser.prioritized(simulators)
            // A simulator-only role gets the full list; alongside the (short)
            // AVD list the (long) simulator list is cut behind "Show all".
            let expanded = !showsAndroid || showAllSimulators
            let visible = expanded ? ordered : Array(ordered.prefix(Self.collapsedSimulatorCount))
            Section("iOS Simulators") {
                ForEach(visible) { simulatorRow($0) }
                if ordered.count > Self.collapsedSimulatorCount, showsAndroid {
                    Button {
                        showAllSimulators.toggle()
                    } label: {
                        Label(
                            showAllSimulators
                                ? "Show fewer"
                                : "Show all \(ordered.count) simulators",
                            systemImage: showAllSimulators ? "chevron.up" : "chevron.down"
                        )
                        .font(.app(.footnote))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.brandAccent)
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func avdRow(_ avd: Avd) -> some View {
        HStack {
            Image(systemName: avd.runningSerial != nil ? "play.display" : "display")
                .foregroundStyle(avd.runningSerial != nil ? .brandAccent : .textMuted)
            VStack(alignment: .leading, spacing: 1) {
                Text(avd.displayName)
                if let serial = avd.runningSerial {
                    Text("Running — \(serial)")
                        .font(.app(.footnote))
                        .foregroundStyle(.brandAccent)
                }
            }
            Spacer()

            if let serial = avd.runningSerial {
                Button("Stop") {
                    stop(serial: serial, name: avd.displayName)
                }
                .controlSize(.small)
            } else {
                Button("Launch") {
                    launch(avd, options: EmulatorService.LaunchOptions())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Menu {
                    Button("Cold Boot (skip snapshot)") {
                        launch(avd, options: EmulatorService.LaunchOptions(coldBoot: true))
                    }
                    Button("Wipe Data & Launch…", role: .destructive) {
                        wipeTarget = avd
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { if let serial = avd.runningSerial { focus(serial: serial) } }
        .help(avd.runningSerial != nil ? "Click to bring the emulator window to the front" : "")
    }

    private func simulatorRow(_ simulator: Simulator) -> some View {
        HStack {
            Image(systemName: simulator.isBooted ? "play.display" : "display")
                .foregroundStyle(simulator.isBooted ? .brandAccent : .textMuted)
            VStack(alignment: .leading, spacing: 1) {
                Text(simulator.name)
                Text(simulator.isBooted ? "Booted — \(simulator.runtime)" : simulator.runtime)
                    .font(.app(.footnote))
                    .foregroundStyle(simulator.isBooted ? .brandAccent : .textMuted)
            }
            Spacer()

            if !simulator.isAvailable {
                Text("Runtime missing")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            } else if simulator.isBooted {
                Button("Shut Down") {
                    state.shutdownSimulator(simulator)
                    scheduleReload()
                }
                .controlSize(.small)
            } else {
                Button("Boot") {
                    state.bootSimulator(simulator)
                    scheduleReload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
    }

    /// Boot/shutdown state flips a moment after simctl returns — refresh once
    /// it settles (the device-bar poll covers stragglers).
    private func scheduleReload() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            reloadToken += 1
        }
    }

    private func load() async {
        emulatorMissing = !(await state.env.engine.emulators.emulatorInstalled())
        let loadedAvds: [Avd]
        if emulatorMissing || !showsAndroid {
            loadedAvds = []
        } else {
            loadedAvds = await CommandLog.userInitiated {
                await state.env.engine.emulators.listAvds(devices: state.devices)
            }
        }
        simctlMissing = !state.env.engine.simctl.available
        let loadedSimulators = simctlMissing || !showsSimulators
            ? []
            : await CommandLog.userInitiated { await state.env.engine.simulators.listAll() }
                .filter(\.isAvailable)
        guard !Task.isCancelled else { return }
        avds = loadedAvds
        simulators = loadedSimulators
    }

    private func launch(_ avd: Avd, options: EmulatorService.LaunchOptions) {
        // Remember the emulator windows already up, so post-launch focus targets
        // the one we're starting rather than an existing emulator.
        let existing = Set(emulatorApps().map(\.processIdentifier))
        Task {
            let ok = await CommandLog.userInitiated {
                let result = await state.env.engine.emulators.launch(avd: avd.name, options: options)
                state.showToast(Toast(message: result.message, ok: result.ok))
                // The device monitor picks the emulator up once adb sees it.
                return result.ok
            }
            if ok { await focusNewEmulator(excluding: existing) }
        }
    }

    /// Running Android-emulator GUI processes. The emulator runs as a
    /// `qemu-system-*` binary under the SDK's `emulator/` directory.
    private func emulatorApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            let path = app.executableURL?.path.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            return path.contains("/emulator/") || path.contains("qemu-system") || name.contains("qemu")
        }
    }

    /// Focus the specific emulator for `serial`. Its console port (the number in
    /// `emulator-5554`) is held by exactly that qemu process, so `lsof` maps the
    /// serial to the right pid — and the right window — even with several
    /// emulators running. Falls back to any emulator if the lookup misses.
    private func focus(serial: String) {
        Task {
            let pid = await state.env.engine.emulators.consolePID(serial: serial)
            if let pid, let app = NSRunningApplication(processIdentifier: pid) {
                app.activate(options: .activateAllWindows)
            } else {
                for app in emulatorApps() { app.activate(options: .activateAllWindows) }
            }
        }
    }

    /// The emulator window appears a few seconds after launch — poll briefly and
    /// focus the freshly-spawned process (one not in `existing`).
    private func focusNewEmulator(excluding existing: Set<pid_t>) async {
        for _ in 0..<25 {
            if let fresh = emulatorApps().first(where: { !existing.contains($0.processIdentifier) }) {
                fresh.activate(options: .activateAllWindows)
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func stop(serial: String, name: String) {
        Task {
            await CommandLog.userInitiated {
                let result = (try? await state.env.engine.emulators.stop(serial: serial))
                    ?? FeatureResult(ok: false, message: "adb not found")
                state.showToast(Toast(message: result.ok ? "Stopping \(name)…" : result.message, ok: result.ok))
            }
            try? await Task.sleep(for: .seconds(2))
            state.refreshDevices()
            reloadToken += 1
        }
    }
}
