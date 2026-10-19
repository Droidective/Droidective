import ADBKit
import Foundation

/// Wire shapes for setting up Droidective for Android on a connected phone —
/// the device menu's "Set Up Droidective on This Phone…".
///
/// The derived answers travel with the raw ones: which permissions are missing
/// and whether set-up still has anything to do are `PhoneAppSetupStatus`'s
/// decisions (Shizuku counts only when it is installed), and a client
/// re-deriving them would be a second opinion that could drift from the Mac's.
public enum PhoneSetupProtocol {
    public struct Status: Codable, Equatable, Sendable {
        public let appInstalled: Bool
        public let appVersion: String?
        public let grantedPermissions: [String]
        public let missingPermissions: [String]
        public let shizukuInstalled: Bool
        public let shizukuRunning: Bool
        public let needsSetup: Bool

        public init(_ status: PhoneAppSetupStatus) {
            appInstalled = status.appInstalled
            appVersion = status.appVersion
            grantedPermissions = status.grantedPermissions
            missingPermissions = status.missingPermissions
            shizukuInstalled = status.shizukuInstalled
            shizukuRunning = status.shizukuRunning
            needsSetup = status.needsSetup
        }
    }

    /// A set-up run: the status read back afterwards, and the first failing
    /// step's reason. A step the *phone* refused is a 200 with `failure` set,
    /// the split every route keeps — only an unreadable device is a 502.
    public struct RunResponse: Codable, Equatable, Sendable {
        public let status: Status
        public let failure: String?

        public init(_ outcome: PhoneAppSetupOutcome) {
            status = Status(outcome.status)
            failure = outcome.failure
        }
    }
}

enum PhoneSetupRoutes {
    static func status(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(DaemonProtocol.DeviceRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            let status = try await backend.phoneSetupStatus(serial: request.serial)
            return (200, DaemonProtocol.encoded(PhoneSetupProtocol.Status(status)))
        } catch {
            return unreadable(error)
        }
    }

    static func run(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(DaemonProtocol.DeviceRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            let outcome = try await backend.setUpPhone(serial: request.serial)
            return (200, DaemonProtocol.encoded(PhoneSetupProtocol.RunResponse(outcome)))
        } catch {
            return unreadable(error)
        }
    }

    /// The device could not be read at all. The message is the service's own —
    /// "Device is offline." — so the client shows it as the Mac's sheet does.
    private static func unreadable(_ error: any Error) -> DaemonProtocol.Answer {
        (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
            code: "adb_failed", message: error.localizedDescription, detail: "\(error)")))
    }
}
