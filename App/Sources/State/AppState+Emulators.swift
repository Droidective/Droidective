import ADBKit
import Foundation

/// Launching an emulator from the device bar — list the Android Studio AVDs and
/// boot one. The booted emulator joins `devices` through normal polling, so this
/// only kicks it off and reports the result.
extension AppState {
    /// Refresh `availableAvds` from `emulator -list-avds`, tagging which are
    /// already running. A no-op (clears the list) when the SDK emulator is absent.
    func refreshAvds() async {
        guard await env.engine.emulators.emulatorInstalled() else {
            availableAvds = []
            return
        }
        availableAvds = await env.engine.emulators.listAvds(devices: devices)
    }

    /// Boot `avd` detached; it appears in the device list once it comes online.
    func launchEmulator(_ avd: Avd) {
        Task {
            let result = await env.engine.emulators.launch(avd: avd.name)
            showToast(Toast(message: result.message, ok: result.ok))
        }
    }
}
