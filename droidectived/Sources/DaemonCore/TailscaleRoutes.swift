import ADBKit
import Foundation

/// Wire shapes for Tailscale mode — the device menu's Tailscale section.
///
/// The derived answers travel, as they do for phone set-up: which peers are
/// worth offering (online Android ones adb does not already list), the line
/// to show when there are none, and the warning "Prepare for Tailscale" asks
/// with. A client restating any of them would be a second opinion, and the
/// warning is a security one.
public enum TailscaleProtocol {
    public struct Status: Codable, Equatable, Sendable {
        /// False when this machine has no Tailscale CLI. The menu then has no
        /// Tailscale section, and every other field is empty.
        public let installed: Bool
        /// "standalone" or "appBundle" — which CLI was found.
        public let flavor: String?
        /// tailscaled's `BackendState`; nil when it could not be reached.
        public let backendState: String?
        public let running: Bool
        /// The line the section shows instead of a list, when there is one.
        public let notice: String?
        /// Online Android peers not already in adb's device list, by name.
        public let peers: [TailscalePeer]
        /// What "Prepare for Tailscale" says before it runs.
        public let prepareWarning: String

        public init(_ status: TailscaleStatus?, devices: [Device]) {
            installed = status != nil
            flavor = status?.flavor.rawValue
            backendState = status?.backendState
            running = status?.isRunning ?? false
            notice = status?.notice
            peers = status.map { TailscalePeers.connectable($0.androidPeers, devices: devices) } ?? []
            prepareWarning = TailscaleService.prepareWarning
        }
    }

    public static let badPeer = DaemonProtocol.ErrorBody(
        code: "bad_tailscale_peer",
        message: "The request did not name a peer with a tailnet IPv4 address.")
}

enum TailscaleRoutes {
    /// Reads the tailnet and the device list together, so a phone already
    /// connected is not offered again.
    static func status(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        let status = await backend.tailscaleStatus()
        let devices = status == nil ? [] : await backend.listDevices()
        return (200, DaemonProtocol.encoded(TailscaleProtocol.Status(status, devices: devices)))
    }

    /// Connects one peer. The address must be a tailnet one: this route is
    /// Tailscale mode's, and `/v1/wireless/action` already connects anything
    /// else.
    static func connect(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let peer = try? JSONDecoder().decode(TailscalePeer.self, from: body) else {
            return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest))
        }
        guard TailscalePeers.isTailnetAddress(peer.ipv4) else {
            return (400, DaemonProtocol.encoded(TailscaleProtocol.badPeer))
        }
        do {
            return answer(try await backend.connectTailscale(peer))
        } catch {
            return failed(error)
        }
    }

    static func prepare(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(DaemonProtocol.DeviceRequest.self, from: body),
              !request.serial.isEmpty
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            return answer(try await backend.prepareForTailscale(serial: request.serial))
        } catch {
            return failed(error)
        }
    }

    /// A command adb ran and refused is a 200 carrying `ok: false`, the split
    /// every action route keeps; only adb itself missing is a 502.
    private static func answer(_ result: FeatureResult) -> DaemonProtocol.Answer {
        (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(result)))
    }

    private static func failed(_ error: any Error) -> DaemonProtocol.Answer {
        (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
            code: "adb_failed", message: error.localizedDescription, detail: "\(error)")))
    }
}
