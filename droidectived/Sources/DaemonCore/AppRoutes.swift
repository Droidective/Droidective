import ADBKit
import Foundation

/// Wire shapes for the installed-app surface.
///
/// Like the action routes, these are a thin pass-through: `AppsExplorerService`
/// does the listing and `AppControlService` the verbs, so the daemon adds no
/// knowledge of its own about what an app is or what may be done to one.
public enum AppProtocol {
    public struct ListRequest: Codable, Equatable, Sendable {
        public let serial: String
        public init(serial: String) { self.serial = serial }
    }

    /// One installed app.
    ///
    /// A DTO rather than `AppListing` itself: that type is not `Codable`, and
    /// its `displayName` is a computed property that would not survive
    /// encoding. Sending the name means a client does not have to reimplement
    /// the package-id → title rule and then drift from it.
    public struct AppSummary: Codable, Equatable, Sendable {
        public let packageId: String
        public let displayName: String
        public let versionName: String?
        public let isSystem: Bool

        public init(_ listing: AppListing) {
            packageId = listing.packageId
            displayName = listing.displayName
            versionName = listing.versionName
            isSystem = listing.isSystem
        }
    }

    /// A verb the daemon accepts, carrying the registry's own destructive
    /// flag. Sent rather than left to the client, for the same reason
    /// `isDestructive` rides on a feature: a client that keeps its own copy
    /// of which verbs are dangerous will eventually disagree with the one
    /// that actually runs them.
    public struct ActionDescriptor: Codable, Equatable, Sendable {
        public let id: String
        public let isDestructive: Bool
    }

    public struct ListResponse: Codable, Equatable, Sendable {
        public let apps: [AppSummary]
        /// Shipped with the list because the two are always wanted together:
        /// there is nothing to act on before the apps arrive.
        public let actions: [ActionDescriptor]

        public init(apps: [AppSummary], actions: [ActionDescriptor] = AppProtocol.actions) {
            self.apps = apps
            self.actions = actions
        }
    }

    public struct ControlRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let packageId: String
        /// An `AppControlService.AppAction` raw value: "open", "restart",
        /// "stop", "minimize", "clearCache", "clearData", "uninstall".
        public let action: String

        public init(serial: String, packageId: String, action: String) {
            self.serial = serial
            self.packageId = packageId
            self.action = action
        }

        /// `nil` for a verb this daemon does not know, so it is refused rather
        /// than silently treated as something else.
        public var resolvedAction: AppControlService.AppAction? {
            AppControlService.AppAction(rawValue: action)
        }
    }

    /// Which app is in front, when one is.
    ///
    /// Nullable rather than an error: the launcher is in front more often than
    /// not, and "nothing worth naming" is a real answer rather than a failure
    /// to report. The caller decides what to do with it — a debug tool's
    /// restart uses it as a *guess*, which is why it never stands alone.
    public struct ForegroundResponse: Codable, Equatable, Sendable {
        public let packageId: String?

        public init(packageId: String?) {
            self.packageId = packageId
        }
    }

    /// The verbs a client may offer, so a UI renders the set the daemon
    /// actually accepts instead of a hardcoded list that can drift.
    public static var actions: [ActionDescriptor] {
        AppControlService.AppAction.allCases.map {
            ActionDescriptor(id: $0.rawValue, isDestructive: $0.isDestructive)
        }
    }

    public static let unknownAction = DaemonProtocol.ErrorBody(
        code: "unknown_action",
        message: "No such app action.",
        detail: "known actions: \(actions.map(\.id).joined(separator: ", "))")
}
