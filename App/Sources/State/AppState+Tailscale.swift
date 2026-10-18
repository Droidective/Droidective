import ADBKit
import Foundation

/// Tailscale mode from the device bar: connect a phone on the user's tailnet,
/// and prepare a USB phone to be reached that way. The tailnet itself is
/// app-wide (`AppCore.tailscale`); the verbs live here so their toasts land in
/// the window the user acted from.
extension AppState {
    func refreshTailscale() async { await core.refreshTailscale() }

    /// The tailnet's Android phones worth offering: online, and not already in
    /// adb's device list under their tailnet serial.
    var connectableTailscalePeers: [TailscalePeer] {
        guard let tailscale else { return [] }
        return TailscalePeers.connectable(tailscale.androidPeers, devices: devices)
    }

    /// The selected device, when "Prepare for Tailscale" applies to it
    /// (`TailscaleService.canPrepare`).
    var tailscalePrepareCandidate: Device? {
        devices.first { $0.serial == selectedSerial }.flatMap {
            TailscaleService.canPrepare($0) ? $0 : nil
        }
    }

    func connectTailscale(_ peer: TailscalePeer) {
        let tailscale = env.engine.tailscale
        Task {
            await CommandLog.userInitiated {
                let result: FeatureResult
                do {
                    result = try await tailscale.connect(peer)
                } catch {
                    result = FeatureResult(ok: false, message: error.localizedDescription)
                }
                Telemetry.shared.trackTailscaleAction(.connect, ok: result.ok)
                showToast(Toast(message: result.message, ok: result.ok, important: true))
            }
            refreshDevices()
            await refreshTailscale()
        }
    }

    /// `adb tcpip 5555` on the phone — only ever after the user has read
    /// `TailscaleService.prepareWarning` and confirmed.
    func prepareForTailscale(serial: String) {
        let tailscale = env.engine.tailscale
        Task {
            await CommandLog.userInitiated {
                let result: FeatureResult
                do {
                    result = try await tailscale.prepare(serial: serial)
                } catch {
                    result = FeatureResult(ok: false, message: error.localizedDescription)
                }
                Telemetry.shared.trackTailscaleAction(.prepare, ok: result.ok)
                showToast(Toast(message: result.message, ok: result.ok, important: true))
            }
        }
    }
}
