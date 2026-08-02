import ADBKit
import SwiftUI

/// Routes the selected feature to its detail pane by kind.
struct FeatureDetailView: View {
    @Environment(AppState.self) private var state
    let featureID: String?

    var body: some View {
        // The window title is set once by the tab host from the active tab —
        // not here — because every open tab is mounted at once and per-view
        // `.navigationTitle`s would fight over the one window title.
        if featureID == "home" {
            HomeView()
        } else if featureID == "about" {
            AboutView()
        } else if featureID == "catalog" {
            CatalogView()
        } else if featureID == "apk-open" {
            ApkOpenView()
        } else if let featureID, let feature = FeatureRegistry.byID[featureID] {
            detail(for: feature)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HomeView()
        }
    }

    @ViewBuilder
    private func detail(for feature: FeatureDef) -> some View {
        if let device = state.selectedDevice, device.isReady,
           feature.needsDevice, !feature.platforms.contains(device.platform) {
            PlatformUnsupportedView(feature: feature, device: device)
        } else if let owner = busyElsewhereOwner(feature) {
            // Another window already runs this against the same device, and
            // the device side only has one of whatever it needs (see
            // `WorkspaceRegistry.exclusiveFeatureIDs`). Offer the two honest
            // choices instead of racing it.
            FeatureBusyElsewhereView(feature: feature, owner: owner)
        } else if feature.id == "screenshot" {
            ScreenshotView()
        } else {
            detailByKind(for: feature)
        }
    }

    private func busyElsewhereOwner(_ feature: FeatureDef) -> WorkspaceID? {
        guard case .featureOwnedElsewhere(let owner, _) =
            state.core.registry.conflict(opening: feature.id, in: state.id)
        else { return nil }
        return owner
    }

    @ViewBuilder
    private func detailByKind(for feature: FeatureDef) -> some View {
        switch feature.kind {
        case .view, .system:
            if let route = FeatureDetailRoute(rawValue: feature.id) {
                pane(for: route)
            } else {
                ComingSoonView(feature: feature)
            }
        case .instantAction:
            if FeatureEngine.implementedIDs.contains(feature.id) {
                InstantActionView(feature: feature)
            } else {
                ComingSoonView(feature: feature)
            }
        case .formAction:
            if feature.id == "send-text" {
                SendTextView(feature: feature)
            } else if FeatureEngine.implementedIDs.contains(feature.id) {
                FormActionView(feature: feature)
            } else {
                ComingSoonView(feature: feature)
            }
        case .toggleAction:
            if FeatureEngine.implementedIDs.contains(feature.id) {
                ToggleActionView(feature: feature)
            } else {
                ComingSoonView(feature: feature)
            }
        }
    }

    /// One pane per routed id. Exhaustive over `FeatureDetailRoute` on purpose
    /// — no `default` — so adding a case there fails the build until it has a
    /// view here, and the id strings stay in the enum alone.
    @ViewBuilder
    private func pane(for route: FeatureDetailRoute) -> some View {
        switch route {
        case .reactNative:
            ReactNativeView()
        case .reactotron:
            ReactotronView()
        case .jsConsole:
            JSConsoleView()
        case .simulate:
            SimulateView()
        case .connection:
            NetworkConnectionView()
        case .appManagement:
            AppManagementView()
        case .deepLink:
            DeepLinksView()
        case .logcat:
            LogcatView()
        case .iosLogs:
            SimulatorLogsView()
        case .permissions:
            PermissionsView()
        case .appInfo:
            AppInfoView()
        case .meminfo:
            MeminfoView()
        case .sandboxBrowser:
            SandboxBrowserView()
        case .deviceInfo:
            DeviceInfoView()
        case .rootStatus:
            RootStatusView()
        case .wifi:
            WiFiView()
        case .privateDns:
            PrivateDnsView()
        case .systemRestrictions:
            SystemRestrictionsView()
        case .devSettings:
            DeveloperSettingsView()
        case .screenRecord:
            ScreenRecordView()
        case .videoEditor:
            VideoEditorView()
        case .crashCatcher:
            CrashView()
        case .bugReport:
            BugReportView()
        case .wirelessAdb:
            WirelessAdbView()
        case .customCommands:
            CustomCommandsView()
        case .terminal:
            TerminalView()
        case .fileExplorer:
            FileExplorerView()
        case .apps:
            AppsExplorerView()
        case .installApp:
            InstallAppView()
        case .apkStudio:
            ApkStudioView()
        case .apkInspector:
            ApkInspectorView()
        case .apkSign:
            ApkSignView()
        case .apkDecompile:
            DecompileBrowserView()
        case .aabConvert:
            AabConvertView()
        case .fridaConsole:
            FridaConsoleView()
        case .emulators:
            EmulatorsView()
        case .performance:
            PerformanceView()
        case .networkSpeed:
            NetworkView()
        case .scrcpy:
            ScreenMirrorView()
        case .apiClient:
            ApiClientView()
        }
    }
}

struct ComingSoonView: View {
    let feature: FeatureDef

    var body: some View {
        ContentUnavailableView(
            feature.title,
            systemImage: feature.icon,
            description: Text("\(feature.subtitle ?? "")\n\nThis feature arrives in a later milestone.")
        )
    }
}

/// Shown when another window already runs this feature against the same
/// device and the device can only serve one — a second scrcpy session is a
/// second encoder, and a second Hermes CDP client silently kills the first.
///
/// Deliberately not an error: both ways out are one click. Focus goes to where
/// it's already running; Take Over stops it there first, so there's never a
/// moment with two live sessions.
struct FeatureBusyElsewhereView: View {
    @Environment(AppState.self) private var state
    let feature: FeatureDef
    let owner: WorkspaceID

    var body: some View {
        ContentUnavailableView {
            Label(feature.title, systemImage: feature.icon)
        } description: {
            Text(explanation)
        } actions: {
            HStack {
                Button("Focus \(state.core.registry.label(of: owner))") {
                    state.core.focusWindow(owner)
                }
                Button("Take Over Here") {
                    state.core.takeOverFeature(feature.id, from: owner)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var explanation: String {
        let deviceName = state.selectedDevice.map(state.deviceDisplayName) ?? "this device"
        return """
        \(state.core.registry.label(of: owner)) is already running \(feature.title) \
        for \(deviceName). \(reason)
        """
    }

    private var reason: String {
        switch feature.id {
        case "scrcpy", "screen-record":
            return "Two sessions would fight over the device's video encoder."
        case "js-console":
            return "The React Native inspector hands the target to one client at a time."
        default:
            return "The device can only serve one at a time."
        }
    }
}

/// Shown when the selected device's platform can't run the feature (an
/// adb-only feature with a simulator selected, or push simulation with an
/// Android device). Offers a one-click switch when a matching ready device
/// is already connected.
struct PlatformUnsupportedView: View {
    @Environment(AppState.self) private var state
    let feature: FeatureDef
    let device: Device

    var body: some View {
        ContentUnavailableView {
            Label(feature.title, systemImage: feature.icon)
        } description: {
            Text(explanation)
        } actions: {
            if let match = switchTarget {
                Button("Switch to \(match.label)") {
                    state.requestDevice(match.serial)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var explanation: String {
        switch device.platform {
        case .iosSimulator:
            return "\(feature.title) works with Android devices — \(device.label) is an iOS Simulator."
        case .android:
            return "\(feature.title) works with iOS Simulators — \(device.label) is an Android device."
        }
    }

    /// First ready device the feature *can* run against, if any.
    private var switchTarget: Device? {
        state.devices.first { $0.isReady && feature.platforms.contains($0.platform) }
    }
}
