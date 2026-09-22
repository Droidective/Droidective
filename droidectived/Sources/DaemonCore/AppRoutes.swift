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
        /// Disabled for this user — `pm disable-user`, reversible.
        public let disabled: Bool
        /// Uninstalled for this user but still on the system image, so
        /// restorable with `cmd package install-existing`. A package that is
        /// gone for good is not in the list at all.
        public let removed: Bool

        public init(_ listing: AppListing, lifecycle: AppLifecycle? = nil) {
            packageId = listing.packageId
            displayName = listing.displayName
            versionName = listing.versionName
            isSystem = listing.isSystem
            // Absent means ordinary: a package the lifecycle read did not
            // mention is installed and enabled, which is the state every app
            // is in until something changes it.
            disabled = lifecycle?.disabled ?? false
            removed = lifecycle?.removed ?? false
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

    /// Disable, enable, remove-for-user or restore one package.
    ///
    /// Separate from `ControlRequest` because these are not
    /// `AppControlService.AppAction`s: they change what the package *is* for
    /// this user rather than what it is doing, and both directions of both
    /// verbs are reversible — which is why they are a flag rather than four
    /// action ids.
    public struct LifecycleRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let packageId: String
        /// Exactly one of these, which is what picks the verb.
        public let disabled: Bool?
        public let removed: Bool?

        public init(serial: String, packageId: String, disabled: Bool?, removed: Bool?) {
            self.serial = serial
            self.packageId = packageId
            self.disabled = disabled
            self.removed = removed
        }
    }

    /// What to say about a lifecycle write.
    ///
    /// `pm` reports a refusal on stdout with exit code 0 as often as not —
    /// "Failure [not installed for 0]" — so the text is what carries the
    /// answer, and an empty one means it simply did it.
    public static func lifecycleMessage(_ result: AdbResult) -> String {
        let said = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !said.isEmpty { return said }
        let complained = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !complained.isEmpty { return complained }
        return result.exitCode == 0 ? "Done." : "The package manager refused."
    }

    /// Whether `pm` refused while still exiting 0.
    ///
    /// It does that routinely — "Failure [not installed for 0]" on a package
    /// that was never removed — and taking the exit code at its word would
    /// report a refusal as a success.
    public static func saidFailure(_ result: AdbResult) -> Bool {
        (result.stdout + result.stderr).contains("Failure")
    }

    public static let unknownLifecycle = DaemonProtocol.ErrorBody(
        code: "unknown_lifecycle",
        message: "Say which lifecycle change to make.",
        detail: "send exactly one of `disabled` or `removed`")

    public static let unknownAction = DaemonProtocol.ErrorBody(
        code: "unknown_action",
        message: "No such app action.",
        detail: "known actions: \(actions.map(\.id).joined(separator: ", "))")
}

/// The lifecycle route: disable, enable, remove for this user, restore.
///
/// Its own helper rather than a case in the server's switch because the
/// interesting part is a decision — which of two writes a body asks for, and
/// what to do when it asks for neither or both — and that is worth testing
/// without a socket.
enum AppRoutes {
    static func lifecycle(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(AppProtocol.LifecycleRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }

        // Exactly one, so a body naming both cannot run two writes and report
        // one of them — and a body naming neither is a mistake rather than a
        // no-op that looks like success.
        let result: AdbResult
        do {
            switch (request.disabled, request.removed) {
            case let (disabled?, nil):
                result = try await backend.setAppDisabled(
                    serial: request.serial, packageId: request.packageId, disabled)
            case let (nil, removed?):
                result = try await backend.setAppRemoved(
                    serial: request.serial, packageId: request.packageId, removed)
            default:
                return (400, DaemonProtocol.encoded(AppProtocol.unknownLifecycle))
            }
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "The app lifecycle change failed.",
                detail: "\(error)")))
        }

        return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(FeatureResult(
            ok: result.exitCode == 0 && !AppProtocol.saidFailure(result),
            message: AppProtocol.lifecycleMessage(result)))))
    }
}
