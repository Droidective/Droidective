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
    /// AVD name → the relaunch stage in flight, so the row can report it and
    /// the button can't be pressed twice.
    @State private var relaunching: [String: EmulatorRelaunchPhase] = [:]

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
    /// How long a relaunch waits for the console port to free before giving
    /// up. An emulator with a large snapshot takes several seconds to exit.
    private static let shutdownWaitSeconds = 20

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
            .translucentListBackground()
        }
        .confirmationDialog(
            "Wipe all data on \(wipeTarget?.displayName ?? "")? Apps, accounts, settings, and snapshots on the AVD are erased.",
            isPresented: Binding(get: { wipeTarget != nil }, set: { if !$0 { wipeTarget = nil } })
        ) {
            Button("Wipe Data", role: .destructive) {
                if let avd = wipeTarget { wipe(avd) }
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

            if let phase = relaunching[avd.name] {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(phase.label)
                        .font(.app(.footnote))
                        .foregroundStyle(.textMuted)
                }
            } else if let serial = avd.runningSerial {
                Button("Relaunch") {
                    relaunch(avd, serial: serial)
                }
                .controlSize(.small)
                .help("Stop the emulator and boot it again")
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
                    Button("Wipe Data…", role: .destructive) {
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

    /// Wipe a stopped AVD's data in place — no launch. The row's Launch
    /// button is unchanged, so wiping and starting stay separate choices.
    private func wipe(_ avd: Avd) {
        Task {
            let result = await state.env.engine.emulators.wipeData(avd: avd.name)
            state.showToast(Toast(message: result.message, ok: result.ok))
        }
    }

    /// Stop the running emulator, wait for its console port to free (so the
    /// relaunch can't come up as a second serial), then boot the same AVD.
    ///
    /// Every stage reports: the row carries a spinner and the phase's label,
    /// because the shutdown wait alone runs to `shutdownWaitSeconds` and used
    /// to show nothing at all. A failed stop and a shutdown that never
    /// finishes both stop here with a reason instead of booting into a
    /// conflict, and the button is unavailable while one is in flight — it
    /// was re-clickable, and a second click meant two stops and two boots.
    private func relaunch(_ avd: Avd, serial: String) {
        guard relaunching[avd.name] == nil else { return }
        // Remembered before anything stops, so the post-boot focus targets the
        // process we start rather than another emulator already up.
        let existing = Set(emulatorApps().map(\.processIdentifier))
        relaunching[avd.name] = .stopping
        Task {
            defer { relaunching[avd.name] = nil }

            let stopped = await CommandLog.userInitiated {
                (try? await state.env.engine.emulators.stop(serial: serial))
                    ?? FeatureResult(ok: false, message: "adb not found")
            }
            guard stopped.ok else {
                state.showToast(Toast(
                    message: EmulatorRelaunchPhase.stopFailed(
                        name: avd.displayName, reason: stopped.message),
                    ok: false
                ))
                return
            }

            var freed = false
            for second in 0..<Self.shutdownWaitSeconds {
                relaunching[avd.name] = .waitingForShutdown(secondsElapsed: second)
                if await state.env.engine.emulators.consolePID(serial: serial) == nil {
                    freed = true
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
            state.refreshDevices()
            guard freed else {
                reloadToken += 1
                state.showToast(Toast(
                    message: EmulatorRelaunchPhase.shutdownTimedOut(
                        name: avd.displayName, seconds: Self.shutdownWaitSeconds),
                    ok: false
                ))
                return
            }

            relaunching[avd.name] = .booting
            let ok = await CommandLog.userInitiated {
                let result = await state.env.engine.emulators.launch(
                    avd: avd.name, options: EmulatorService.LaunchOptions())
                state.showToast(Toast(
                    message: result.ok ? "Relaunching \(avd.displayName)…" : result.message,
                    ok: result.ok
                ))
                return result.ok
            }
            reloadToken += 1
            // Its own task so the row's spinner clears now rather than after
            // the window-focus poll, which runs for as long as 25s.
            if ok {
                Task { await focusNewEmulator(excluding: existing) }
            }
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
