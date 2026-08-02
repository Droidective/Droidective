import ADBKit
import AppKit
@preconcurrency import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    @MainActor static let globalLaunch = Self("globalLaunch")
    @MainActor static let quickActions = Self("quickActions")
}

/// Bridges KeyboardShortcuts (Carbon RegisterEventHotKey — no Accessibility
/// permission needed) to feature execution. Per-feature names are dynamic:
/// "feature-<id>".
@MainActor
enum HotkeyManager {
    private static var installed = false

    static func featureName(_ featureID: String) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("feature-\(featureID)")
    }

    /// Register listeners for the global hotkey and every feature. Must run
    /// *after* the app finishes launching: Carbon installs its hot-key event
    /// handler on the dispatcher target live at first registration, so doing
    /// this in App.init() (before the event loop is up) leaves every shortcut
    /// silently dead. Called from RootView.onAppear instead. Idempotent — that
    /// can fire again when a window is reopened, and re-running would append
    /// duplicate handlers (the library appends, never replaces).
    ///
    /// Hotkeys are app-wide, so they resolve the target window when they fire
    /// rather than capturing one: whichever window is in front is the one that
    /// runs the action, on its own device.
    static func install(core: AppCore) {
        guard !installed else { return }
        installed = true
        KeyboardShortcuts.onKeyUp(for: .globalLaunch) { [weak core] in
            core?.activateAnyWindow()
        }
        KeyboardShortcuts.onKeyUp(for: .quickActions) { [weak core] in
            guard let state = core?.frontmost else { return }
            QuickActionsPanel.toggle(state: state)
        }
        for feature in FeatureRegistry.all {
            KeyboardShortcuts.onKeyUp(for: featureName(feature.id)) { [weak core] in
                guard let state = core?.frontmost else { return }
                if feature.kind == .instantAction || feature.kind == .toggleAction {
                    Task { await state.run(feature: feature, params: [:]) }
                } else {
                    state.activateMainWindow()
                    state.requestFeature(feature.id)
                }
            }
        }
    }
}
