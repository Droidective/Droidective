import ADBKit
import Foundation

/// Launching an emulator or iOS Simulator from the device bar — list what's
/// installed and boot one. The booted device joins `devices` through normal
/// polling, so these only kick it off and report the result.
extension AppState {
    /// Refresh `availableAvds` from `emulator -list-avds`, tagging which are
    /// already running. A no-op (clears the list) when the SDK emulator is absent.
    func refreshAvds() async {
        guard FeatureRegistry.visiblePlatforms(for: selectedRole).contains(.android),
              await env.engine.emulators.emulatorInstalled() else {
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

    /// Refresh `availableSimulators` — the short recently-used list for the
    /// device-bar menu (Xcode installs ~30 sims; the Emulators screen lists
    /// them all). Empty without Xcode.
    func refreshSimulators() async {
        guard FeatureRegistry.visiblePlatforms(for: selectedRole).contains(.iosSimulator) else {
            availableSimulators = []
            return
        }
        availableSimulators = SimulatorListParser.quickPicks(await env.simulatorMonitor.list())
    }

    /// Boot a simulator; it joins the device bar once simctl reports it Booted.
    func bootSimulator(_ simulator: Simulator) {
        Task {
            await CommandLog.userInitiated {
                do {
                    let result = try await env.engine.simulators.boot(udid: simulator.udid)
                    showToast(Toast(message: result.ok ? "\(simulator.name) booted" : result.message, ok: result.ok))
                } catch {
                    showToast(Toast(message: error.localizedDescription, ok: false))
                }
            }
            await env.simulatorMonitor.invalidate()
        }
    }

    /// Shut a simulator down; it leaves the device bar on the next poll.
    func shutdownSimulator(_ simulator: Simulator) {
        Task {
            await CommandLog.userInitiated {
                do {
                    let result = try await env.engine.simulators.shutdown(udid: simulator.udid)
                    showToast(Toast(message: result.ok ? "\(simulator.name) shut down" : result.message, ok: result.ok))
                } catch {
                    showToast(Toast(message: error.localizedDescription, ok: false))
                }
            }
            await env.simulatorMonitor.invalidate()
        }
    }
}
