import ADBKit
import Foundation

/// Wire shapes for Droidective for Android on a connected phone — the device
/// menu's Install / Update / Set Up Droidective on This Phone….
///
/// The derived answers travel with the raw ones: which permissions are
/// missing, what a run does about the app itself, and whether set-up still has
/// anything to do are ADBKit's decisions (`PhoneAppSetupStatus`, `PhoneAppStep`,
/// `PhoneAppOffer`), and a client re-deriving them would be a second opinion
/// that could drift from the Mac's.
public enum PhoneSetupProtocol {
    public struct Status: Codable, Equatable, Sendable {
        public let appInstalled: Bool
        public let appVersion: String?
        /// `ro.build.version.sdk`, read whether or not the app is there.
        public let sdk: Int?
        public let grantedPermissions: [String]
        public let missingPermissions: [String]
        public let shizukuInstalled: Bool
        public let shizukuRunning: Bool
        public let needsSetup: Bool
        /// The latest release's version, when GitHub answered.
        public let latestVersion: String?
        /// Why the latest release couldn't be found, when it couldn't.
        public let latestProblem: String?
        /// What a run does about the app before granting anything.
        public let step: Step
        /// Whether the sheet's button has anything to do: an install or update,
        /// or set-up left undone.
        public let hasWork: Bool
        /// What the device menu should offer after this read, so the sheet can
        /// hand the bar ADBKit's answer rather than the client deciding.
        public let offer: Offer?

        public enum Step: String, Codable, Equatable, Sendable {
            case install, update, none
        }

        public init(_ status: PhoneAppSetupStatus, latest: PhoneAppReleaseCheck.Lookup?) {
            appInstalled = status.appInstalled
            appVersion = status.appVersion
            sdk = status.sdk
            grantedPermissions = status.grantedPermissions
            missingPermissions = status.missingPermissions
            shizukuInstalled = status.shizukuInstalled
            shizukuRunning = status.shizukuRunning
            needsSetup = status.needsSetup
            latestVersion = latest?.release?.version
            if case .failed(let reason) = latest { latestProblem = reason } else { latestProblem = nil }
            switch PhoneAppStep.decide(status: status, latest: latest?.release) {
            case .install: step = .install
            case .update: step = .update
            case .none: step = .none
            }
            hasWork = step != .none || status.needsSetup
            offer = PhoneAppOffer.decide(status: status, latest: latest?.release).map(Offer.init)
        }
    }

    /// What the device menu offers one phone, with ADBKit's words for it.
    public struct Offer: Codable, Equatable, Sendable {
        public let kind: Kind
        public let menuTitle: String
        /// The installed and latest versions, for an update.
        public let from: String?
        public let to: String?

        public enum Kind: String, Codable, Equatable, Sendable {
            case install, update, setUp
        }

        public init(_ offer: PhoneAppOffer) {
            menuTitle = offer.menuTitle
            switch offer {
            case .install:
                (kind, from, to) = (.install, nil, nil)
            case .update(let installed, let latest):
                (kind, from, to) = (.update, installed, latest)
            case .setUp:
                (kind, from, to) = (.setUp, nil, nil)
            }
        }
    }

    /// `null` when there's nothing to offer, which is also the answer to a
    /// phone that couldn't be read: a menu entry is no place to report that.
    public struct OfferResponse: Codable, Equatable, Sendable {
        public let offer: Offer?

        public init(_ offer: PhoneAppOffer?) {
            self.offer = offer.map(Offer.init)
        }
    }

    /// One event of a `phonesetup` subscription: the stage the run is at, and
    /// finally `done` with the status read back and the first failing step's
    /// reason. A step the *phone* refused is a `done` with `failure` set and a
    /// status; a phone that couldn't be read at all is a `done` with only
    /// `failure`.
    public struct Progress: Codable, Equatable, Sendable {
        public let stage: String?
        public let done: Bool?
        public let status: Status?
        public let failure: String?

        public init(
            stage: String? = nil, done: Bool? = nil, status: Status? = nil, failure: String? = nil
        ) {
            self.stage = stage
            self.done = done
            self.status = status
            self.failure = failure
        }
    }
}

enum PhoneSetupRoutes {
    /// The phone read, and the latest release asked of GitHub beside it, at
    /// the sheet's freshness.
    static func status(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(DaemonProtocol.DeviceRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        async let latest = backend.latestPhoneAppRelease(maxAge: PhoneAppReleaseCheck.sheetMaxAge)
        let read: Result<PhoneAppSetupStatus, any Error>
        do {
            read = .success(try await backend.phoneSetupStatus(serial: request.serial))
        } catch {
            read = .failure(error)
        }
        let found = await latest
        switch read {
        case .success(let status):
            return (200, DaemonProtocol.encoded(PhoneSetupProtocol.Status(status, latest: found)))
        case .failure(let error):
            return unreadable(error)
        }
    }

    /// The device menu's entry. Never an error: `PhoneAppSetupService.offer`
    /// answers nil for a phone it couldn't read.
    static func offer(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(DaemonProtocol.DeviceRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        let offer = await backend.phoneSetupOffer(serial: request.serial)
        return (200, DaemonProtocol.encoded(PhoneSetupProtocol.OfferResponse(offer)))
    }

    /// The device could not be read at all. The message is the service's own —
    /// "Device is offline." — so the client shows it as the Mac's sheet does.
    private static func unreadable(_ error: any Error) -> DaemonProtocol.Answer {
        (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
            code: "adb_failed", message: error.localizedDescription, detail: "\(error)")))
    }
}
