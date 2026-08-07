import ADBKit
import Foundation

/// Wire shapes for the Android emulator: list AVDs, launch, stop, wipe.
///
/// iOS Simulators are deliberately absent. The Mac's Emulators screen lists
/// them in a second section, but they are `xcrun simctl` against an Apple
/// toolchain — the one thing the tracker names as genuinely unportable — so
/// the section simply does not exist here rather than existing and being
/// permanently empty.
public enum EmulatorProtocol {
    public struct Avd: Codable, Equatable, Sendable {
        public let name: String
        /// The Mac's `displayName`: underscores read as spaces. Sent rather
        /// than derived so both apps name an AVD the same way.
        public let displayName: String
        /// The adb serial, when this AVD is running right now.
        public let runningSerial: String?

        public init(_ avd: ADBKit.Avd) {
            name = avd.name
            displayName = avd.displayName
            runningSerial = avd.runningSerial
        }
    }

    public struct ListResponse: Codable, Equatable, Sendable {
        public let avds: [Avd]
        /// False when the emulator binary is not on this machine. The screen
        /// says where to get it rather than showing an empty list, which would
        /// read as "you have no AVDs".
        public let installed: Bool
    }

    /// What can be done to an AVD.
    ///
    /// A closed set, resolved before anything reaches a process: an unknown
    /// verb is a 400 here rather than an unhandled case downstream.
    public enum Action: String, Codable, CaseIterable, Sendable {
        case launch
        /// Launch skipping the snapshot — the Mac's "Cold Boot".
        case coldBoot
        /// Erase the AVD's data in place. Destructive; the UI confirms first.
        case wipeData
        /// Console stop, then boot again.
        case relaunch
        case stop
    }

    public struct ActionRequest: Codable, Equatable, Sendable {
        /// The AVD name. Empty for `stop`, which identifies by serial.
        public let avd: String?
        /// Required by `stop` and `relaunch`, which act on a running instance.
        public let serial: String?
        public let action: String

        public init(avd: String? = nil, serial: String? = nil, action: String) {
            self.avd = avd
            self.serial = serial
            self.action = action
        }

        public var resolvedAction: Action? { Action(rawValue: action) }

        /// Whether this request carries what its verb needs.
        ///
        /// Checked here rather than downstream because the two failure modes
        /// are different requests, not different device answers: stopping
        /// without a serial and launching without a name are both the client's
        /// mistake.
        public var isComplete: Bool {
            switch resolvedAction {
            case .stop: return serial?.isEmpty == false
            case .relaunch: return serial?.isEmpty == false && avd?.isEmpty == false
            case .launch, .coldBoot, .wipeData: return avd?.isEmpty == false
            case nil: return false
            }
        }
    }

    public static let badEmulatorRequest = DaemonProtocol.ErrorBody(
        code: "bad_emulator_request",
        message: "Unknown action, or the request did not name an AVD or a serial.")
}

/// The two emulator routes.
enum EmulatorRoutes {
    static func list(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        let (avds, installed) = await backend.emulators()
        return (200, DaemonProtocol.encoded(EmulatorProtocol.ListResponse(
            avds: avds.map(EmulatorProtocol.Avd.init), installed: installed)))
    }

    static func action(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            EmulatorProtocol.ActionRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        guard let action = request.resolvedAction, request.isComplete else {
            return (400, DaemonProtocol.encoded(EmulatorProtocol.badEmulatorRequest))
        }
        do {
            let result = try await backend.emulatorAction(
                action, avd: request.avd ?? "", serial: request.serial ?? "")
            return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(result)))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "emulator_failed", message: "The emulator command failed.",
                detail: "\(error)")))
        }
    }
}
