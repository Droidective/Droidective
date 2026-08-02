import ADBKit
import Foundation

/// Launching an emulator or iOS Simulator from the device bar — list what's
/// installed and boot one. The booted device joins `devices` through normal
/// polling, so these only kick it off and report the result.
extension AppState {
    /// The lists themselves are app-wide (one `emulator -list-avds` however
    /// many windows ask); the launch/stop verbs stay here so their toasts land
    /// in the window the user acted from.
    func refreshAvds() async { await core.refreshAvds() }
    func refreshSimulators() async { await core.refreshSimulators() }

    /// Boot `avd` detached; it appears in the device list once it comes online.
    func launchEmulator(_ avd: Avd) {
        Task {
            let result = await env.engine.emulators.launch(avd: avd.name)
            showToast(Toast(message: result.message, ok: result.ok))
        }
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

    /// Gracefully stop a running emulator (`adb emu kill`); it leaves the
    /// device bar once polling notices, and the AVD list re-tags it stopped.
    func stopEmulator(serial: String, name: String) {
        Task {
            await CommandLog.userInitiated {
                let result = (try? await env.engine.emulators.stop(serial: serial))
                    ?? FeatureResult(ok: false, message: "adb not found")
                showToast(Toast(message: result.ok ? "Stopping \(name)…" : result.message, ok: result.ok))
            }
            try? await Task.sleep(for: .seconds(2))
            refreshDevices()
            await refreshAvds()
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
