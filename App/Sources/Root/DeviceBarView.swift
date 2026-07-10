import ADBKit
import SwiftUI

/// Persistent device context above the detail pane, on a single row: the device
/// pill with the bundle picker right beside it, then the flexible middle and the
/// trailing actions. The device and app are shown as prominent pills (status
/// dot + bold name) so the active target is unmistakable.
struct DeviceBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(sidebarAutoHideDefaultsKey) private var sidebarAutoHide = false
    @State private var showBundleManager = false
    @State private var showInstalledApps = false
    @State private var refreshSpin = 0.0

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 10) {
            Button {
                state.toggleSidebarMode()
            } label: {
                Image(systemName: sidebarAutoHide ? "sidebar.leading" : "sidebar.left")
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconButtonStyle())
            .help(sidebarAutoHide
                ? "Pin the sidebar (auto-hide is on — hover the left edge to peek)"
                : "Auto-hide the sidebar (⌘B shows it on demand)")
            .accessibilityLabel("Toggle sidebar auto-hide")

            // Device and bundle are matching icon + pill pairs: identical inner
            // spacing, and both pills draw their own background (no hidden
            // control insets), so every gap on the bar reads uniform.
            HStack(spacing: 10) {
                Image(systemName: deviceStatusIcon)
                    .foregroundStyle(deviceStatusColor)
                    .help(deviceStatusHelp)
                deviceControl
                if let device = selectedDevice, device.isWireless {
                    disconnectControl(device)
                }
            }

            // Only when the selected feature actually works with an app bundle.
            if bundlePickerVisible {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(bundleIconColor)
                    bundleControl
                }
            }

            // Flexible middle pushes trailing controls right.
            HStack(spacing: 8) {
                OverridesPillView()
                if state.adbMissing {
                    Label("adb not found", systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.footnote))
                        .foregroundStyle(.orange)
                    Button(state.installingTool == .adb ? "Installing…" : "Install") {
                        state.installTool(.adb)
                    }
                    .controlSize(.mini)
                    .disabled(state.installingTool != nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if state.readyDeviceCount > 1, state.activeFeatureSupportsRunAll {
                    Toggle(isOn: $state.runOnAll) {
                        Label("Run on all", systemImage: "square.stack.3d.up.fill")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(state.recordingActive)
                    .onChange(of: state.runOnAll) { state.persistSelection() }
                    .help("Run this feature on every connected device")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.6)) { refreshSpin += 360 }
                    state.refreshDevices()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .rotationEffect(.degrees(refreshSpin))
                }
                .buttonStyle(IconButtonStyle())
                .help("Refresh devices")
                .accessibilityLabel("Refresh devices")

                NotificationBell()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bgSurface)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .sheet(isPresented: $showBundleManager) {
            BundleManagerView()
        }
        .sheet(isPresented: $showInstalledApps) {
            InstalledAppsPickerView()
        }
    }

    private var selectedDevice: Device? {
        state.devices.first { $0.serial == state.selectedSerial }
    }

    // MARK: - Device pill

    @ViewBuilder
    private var deviceControl: some View {
        @Bindable var state = state
        Menu {
            if state.devices.isEmpty {
                Text("No devices connected")
            }
            ForEach(state.devices) { device in
                Button {
                    state.requestDevice(device.serial)
                } label: {
                    if device.serial == state.selectedSerial {
                        Label(state.deviceTitle(device), systemImage: "checkmark")
                    } else {
                        Text(state.deviceTitle(device))
                    }
                }
            }
            let launchable = state.availableAvds.filter { $0.runningSerial == nil }
            if !launchable.isEmpty {
                Section("Start an emulator") {
                    ForEach(launchable) { avd in
                        Button {
                            state.launchEmulator(avd)
                        } label: {
                            Label(avd.displayName, systemImage: "play.circle")
                        }
                    }
                }
            }
            if !state.availableSimulators.isEmpty {
                Section("Start an iOS Simulator") {
                    ForEach(state.availableSimulators) { simulator in
                        Button {
                            state.bootSimulator(simulator)
                        } label: {
                            Label("\(simulator.name) · \(simulator.runtime)", systemImage: "play.circle")
                        }
                    }
                }
            }
            Divider()
            Button {
                state.requestFeature("emulators")
            } label: {
                Label("Manage emulators & simulators…", systemImage: "square.stack.3d.up")
            }
            Button {
                state.refreshDevices()
            } label: {
                Label("Refresh devices", systemImage: "arrow.triangle.2.circlepath")
            }
        } label: {
            devicePill
        }
        // Borderless (not the default pop-up button) so the label renders as
        // real SwiftUI content: a pop-up button flattens its title to the
        // control's own tint and ignores `.foregroundStyle`, leaving the title
        // white-on-white in light mode. The pill background + border below give
        // back the boxed button affordance the borderless style drops — both
        // derived from the resolved title color, so they adapt to light and dark.
        .menuStyle(.borderlessButton)
        // Cap-and-truncate rather than `.fixedSize()`: a rigid pill made the
        // whole bar incompressible, so a narrow pane (or a bundle pill on top)
        // pushed the bar past the window and clipped it on both edges. A max
        // width lets a long device label truncate and the bar shrink to fit.
        .frame(maxWidth: 200, alignment: .leading)
        .controlSize(.large)
        .foregroundStyle(pillTextColor)
        // The borderless pop-up tints its title with the control accent (the
        // bundled green asset, which ignores a custom accent) — tint it with
        // the intended title color so `.foregroundStyle` actually shows.
        .tint(pillTextColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(pillTextColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(pillTextColor.opacity(0.18)))
        .disabled(state.effectiveRunOnAll || state.recordingActive)
        .help(state.recordingActive ? "Stop the recording to change the device" : "Switch the active device")
        .task(id: state.devices.map(\.serial).joined()) {
            await state.refreshAvds()
            await state.refreshSimulators()
        }
    }

    /// Title/chevron color for the device pill, pre-resolved to a concrete value
    /// for the current scheme so it stays visible in both modes — see
    /// `Color.resolved(_:for:)`.
    private var pillTextColor: Color { Color.resolved("TextMain", for: colorScheme) }

    /// The status color lives on the leading icon (outside the menu); the title
    /// here is just the device label. Its color comes from `pillTextColor` on
    /// the menu so the chevron matches too.
    private var devicePill: some View {
        Text(selectedDevice.map(state.deviceTitle) ?? "No device connected")
            .fontWeight(.semibold)
            .lineLimit(1)
    }

    private var deviceStatusColor: Color {
        guard let device = selectedDevice else { return Color("TextMuted") }
        // Ready rides the accent (it doubles as the bar's active marker);
        // trouble states keep their semaphore colors.
        if device.isReady { return .brandAccent }
        if device.state == "unauthorized" { return .orange }
        return .red
    }

    /// A booted iOS Simulator gets the Apple mark so the platform in charge
    /// of the bar is unmistakable at a glance.
    private var deviceStatusIcon: String {
        selectedDevice?.platform == .iosSimulator ? "apple.logo" : "iphone"
    }

    private var bundleIconColor: Color {
        state.selectedBundle == nil ? Color("TextMuted") : .brandAccent
    }

    private var deviceStatusHelp: String {
        guard let device = selectedDevice else { return "No device connected" }
        if device.isReady { return "\(device.label) — connected" }
        if device.state == "unauthorized" { return "\(device.label) — accept the prompt on the device" }
        return "\(device.label) — \(device.state)"
    }

    // MARK: - Disconnect

    private func disconnectControl(_ device: Device) -> some View {
        Menu {
            Button("Disconnect \(device.label)") {
                state.disconnectWireless(target: device.serial)
            }
            if state.readyWirelessDevices.count > 1 {
                Button("Disconnect all wireless") {
                    state.disconnectWireless(target: nil)
                }
            }
        } label: {
            Image(systemName: "wifi.slash")
        } primaryAction: {
            state.disconnectWireless(target: device.serial)
        }
        .fixedSize()
        .controlSize(.large)
        .tint(.red)
        .help("Disconnect \(device.label)")
        .disabled(state.recordingActive)
    }

    /// True when the selected feature works with an app bundle. Custom
    /// commands (commands may require one) and logcat (its app filter is
    /// driven by saved bundles) are included.
    private var bundlePickerVisible: Bool {
        guard let id = state.activeTabID,
              let feature = FeatureRegistry.byID[id] else { return false }
        return feature.needsBundle
            || feature.id == "custom-commands"
            || feature.id == "logcat"
            || feature.id == "performance"
    }

    // MARK: - Bundle pill

    /// One menu does everything: pick (auto-selects), add from the device's
    /// installed apps, grab the on-screen app, add manually, manage.
    private var bundleControl: some View {
        Menu {
            ForEach(state.bundles) { bundle in
                Button {
                    state.selectBundle(bundle.id)
                } label: {
                    if bundle.id == state.selectedBundleId {
                        Label("\(bundle.nickname) — \(bundle.packageId)", systemImage: "checkmark")
                    } else {
                        Text("\(bundle.nickname) — \(bundle.packageId)")
                    }
                }
            }
            if !state.bundles.isEmpty {
                Divider()
            }
            Button {
                showInstalledApps = true
            } label: {
                Label("Add from installed apps", systemImage: "plus.app")
            }
            .disabled(state.targetSerials.isEmpty)
            Button {
                state.adoptForegroundApp()
            } label: {
                Label("Use app on device screen", systemImage: "scope")
            }
            .disabled(state.targetSerials.isEmpty)
            Button {
                showBundleManager = true
            } label: {
                Label("Add manually / manage…", systemImage: "slider.horizontal.3")
            }
        } label: {
            bundlePill
        }
        // Borderless with a hand-drawn pill, exactly like the device control —
        // the default pop-up button carries its own leading inset, which made
        // the icon→pill gap read wider than the device pair's.
        .menuStyle(.borderlessButton)
        // Same cap-and-truncate as the device pill (not `.fixedSize()`) so the
        // bundle pair can compress instead of forcing the whole bar off-screen.
        .frame(maxWidth: 240, alignment: .leading)
        .controlSize(.large)
        .foregroundStyle(pillTextColor)
        // Same accent-asset tinting escape as the device pill above.
        .tint(pillTextColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(pillTextColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(pillTextColor.opacity(0.18)))
        .disabled(state.recordingActive)
        .help(state.recordingActive ? "Stop the recording to change the app bundle" : "Choose the target app")
    }

    private var bundlePill: some View {
        HStack(spacing: 7) {
            if let bundle = state.selectedBundle {
                Text(bundle.nickname)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    // The nickname is the identifier — when the pill is squeezed
                    // narrow, let the package id truncate first.
                    .layoutPriority(1)
                Text(bundle.packageId)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Choose app bundle…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
