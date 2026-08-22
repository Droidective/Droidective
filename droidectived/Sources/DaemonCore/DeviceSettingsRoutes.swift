import ADBKit
import Foundation

/// Wire shapes for the two device-state tables: Android's Developer Options
/// (`DeveloperSettingsService`) and the dev-time restrictions
/// (`RestrictionsService`).
///
/// The **definitions travel with the values**. `DeveloperSettingsService`
/// already holds one declarative table of what each toggle is called, what it
/// does and how it is written, and the Mac's panel renders straight from it —
/// so a client that hardcoded its own copy of the titles would be a second
/// table to keep in agreement, and the first one to drift silently. This is the
/// same reasoning that sends `FeatureDef` over `/v1/features/list` rather than
/// duplicating the registry.
///
/// What does *not* travel is which section a toggle belongs to. That is the
/// Mac's *view*, not the service's table, and display order is the client's
/// question — the same split `lib/sidebar.ts` makes for categories.
public enum DeviceSettingsProtocol {
    // MARK: - Developer Options

    /// Everything the panel reads in one round-trip.
    ///
    /// One request rather than two because the Mac's panel does not render
    /// until both have arrived — `DeveloperSettingsView` shows its progress
    /// spinner while either is missing — so two routes would only be two ways
    /// to be half-loaded.
    public struct DevState: Sendable, Equatable {
        /// Toggle id → whether the device reports it on.
        public let toggles: [String: Bool]
        /// Scale id → the device's current multiplier.
        public let scales: [String: Double]

        public init(toggles: [String: Bool], scales: [String: Double]) {
            self.toggles = toggles
            self.scales = scales
        }
    }

    /// One row: what it is *and* what it currently reads.
    public struct DevToggle: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        /// One line under the title — what flipping it does on the device.
        public let detail: String
        public let on: Bool
    }

    public struct DevScale: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let value: Double
    }

    public struct DevResponse: Codable, Equatable, Sendable {
        /// In `DeveloperSettingsService.toggles` order.
        public let toggles: [DevToggle]
        public let scales: [DevScale]
        /// The steps the picker offers, from the service rather than the
        /// client, so Developer Options' own set stays the single source.
        public let scaleChoices: [Double]
    }

    /// A write, once it has been matched against the service's tables.
    ///
    /// Carrying the *definition* rather than the id means resolution is the
    /// validation: an id no table knows cannot produce one of these, so there
    /// is no second lookup downstream that could fail differently.
    public enum DevWrite: Equatable, Sendable {
        case toggle(DevToggleDef, on: Bool)
        case scale(DevScaleDef, value: Double)
    }

    /// `on` for a toggle, `value` for a scale — which one is present is what
    /// picks the table to look the id up in.
    public struct DevWriteRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let id: String
        public let on: Bool?
        public let value: Double?

        public init(serial: String, id: String, on: Bool? = nil, value: Double? = nil) {
            self.serial = serial
            self.id = id
            self.on = on
            self.value = value
        }

        /// nil when the id is unknown, or when neither field says what to write.
        public var resolved: DevWrite? {
            if let on, let toggle = DeveloperSettingsService.toggles.first(where: { $0.id == id }) {
                return .toggle(toggle, on: on)
            }
            if let value, let scale = DeveloperSettingsService.animationScales
                .first(where: { $0.id == id })
            {
                return .scale(scale, value: value)
            }
            return nil
        }
    }

    // MARK: - Restrictions

    /// The restriction toggles, plus whether the root-only half is reachable.
    ///
    /// `hasRootShell` rides along because the Mac's screen loads both together
    /// and hides the Root section without one — a client that had to ask
    /// `/v1/device/root` separately would render the section, then take it away.
    public struct RestrictionsResponse: Codable, Equatable, Sendable {
        public let adbInstallVerification: Bool
        public let packageVerifier: Bool
        public let stayAwake: Bool
        public let hiddenApiEnforced: Bool
        /// nil when `getenforce` said neither — an unrooted device usually.
        public let selinuxEnforcing: Bool?
        public let hasRootShell: Bool

        public init(_ state: RestrictionsState, hasRootShell: Bool) {
            adbInstallVerification = state.adbInstallVerification
            packageVerifier = state.packageVerifier
            stayAwake = state.stayAwake
            hiddenApiEnforced = state.hiddenApiEnforced
            selinuxEnforcing = state.selinuxEnforcing
            self.hasRootShell = hasRootShell
        }
    }

    /// Which restriction a write targets. A closed set on the wire, so an
    /// unknown key is a 400 here rather than an unhandled case downstream.
    public enum RestrictionKey: String, Codable, CaseIterable, Sendable {
        case adbInstallVerification
        case packageVerifier
        case stayAwake
        case hiddenApiEnforced
        case selinuxEnforcing
    }

    public enum RestrictionWrite: Equatable, Sendable {
        case toggle(RestrictionKey, on: Bool)
        /// `mount -o rw,remount /` through `su`. Root-only, and not a toggle:
        /// there is nothing to turn back off.
        case remountSystemReadWrite
    }

    public struct RestrictionWriteRequest: Codable, Equatable, Sendable {
        public let serial: String
        /// A `RestrictionKey`, or `remount`.
        public let key: String
        public let on: Bool?

        public init(serial: String, key: String, on: Bool? = nil) {
            self.serial = serial
            self.key = key
            self.on = on
        }

        public static let remountKey = "remount"

        public var resolved: RestrictionWrite? {
            if key == Self.remountKey { return .remountSystemReadWrite }
            guard let on, let resolvedKey = RestrictionKey(rawValue: key) else { return nil }
            return .toggle(resolvedKey, on: on)
        }
    }

    public static let unknownSetting = DaemonProtocol.ErrorBody(
        code: "unknown_setting",
        message: "No such setting, or the request did not say what to write.")
}

/// The four device-state routes.
///
/// Separate from `DaemonServer` for the reason `FileRoutes` and `CrashRoutes`
/// are: its `respond` stays a table of routes, and these are testable without a
/// socket.
enum DeviceSettingsRoutes {
    static func developerRead(body: Data, backend: any DaemonBackend) async
        -> DaemonProtocol.Answer
    {
        guard let request = try? JSONDecoder().decode(
            DaemonProtocol.DeviceRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        // Best-effort by construction, as the service is: a key the device
        // refuses reads as its default rather than failing the whole panel.
        let state = await backend.developerSettings(serial: request.serial)
        return (200, DaemonProtocol.encoded(response(for: state)))
    }

    /// The service's tables joined to the device's answers, in table order.
    static func response(for state: DeviceSettingsProtocol.DevState)
        -> DeviceSettingsProtocol.DevResponse
    {
        DeviceSettingsProtocol.DevResponse(
            toggles: DeveloperSettingsService.toggles.map {
                DeviceSettingsProtocol.DevToggle(
                    id: $0.id, title: $0.title, detail: $0.detail,
                    on: state.toggles[$0.id] ?? false)
            },
            scales: DeveloperSettingsService.animationScales.map {
                DeviceSettingsProtocol.DevScale(
                    id: $0.id, title: $0.title,
                    // 1× is the platform default, and what `parseScale`
                    // answers for a key the user never changed.
                    value: state.scales[$0.id] ?? 1.0)
            },
            scaleChoices: DeveloperSettingsService.scaleChoices)
    }

    static func developerWrite(body: Data, backend: any DaemonBackend) async
        -> DaemonProtocol.Answer
    {
        guard let request = try? JSONDecoder().decode(
            DeviceSettingsProtocol.DevWriteRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        guard let write = request.resolved else {
            return (400, DaemonProtocol.encoded(DeviceSettingsProtocol.unknownSetting))
        }
        do {
            let result = try await backend.writeDeveloperSetting(serial: request.serial, write)
            return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(outcome(result))))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "Could not change the setting.",
                detail: "\(error)")))
        }
    }

    static func restrictionsRead(body: Data, backend: any DaemonBackend) async
        -> DaemonProtocol.Answer
    {
        guard let request = try? JSONDecoder().decode(
            DaemonProtocol.DeviceRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        let state = await backend.restrictions(serial: request.serial)
        let rooted = await backend.rootStatus(serial: request.serial).hasRootShell
        return (200, DaemonProtocol.encoded(
            DeviceSettingsProtocol.RestrictionsResponse(state, hasRootShell: rooted)))
    }

    static func restrictionsWrite(body: Data, backend: any DaemonBackend) async
        -> DaemonProtocol.Answer
    {
        guard let request = try? JSONDecoder().decode(
            DeviceSettingsProtocol.RestrictionWriteRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        guard let write = request.resolved else {
            return (400, DaemonProtocol.encoded(DeviceSettingsProtocol.unknownSetting))
        }
        do {
            let result = try await backend.writeRestriction(serial: request.serial, write)
            return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(outcome(result))))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "Could not change the restriction.",
                detail: "\(error)")))
        }
    }

    /// A non-zero adb exit is the *device's* answer, so it goes out as a 200
    /// carrying `ok: false` and adb's own words — the same rule
    /// `/v1/actions/run` follows, and what lets one client error path cover
    /// both. The Mac shows exactly this text in its failure toast.
    private static func outcome(_ result: AdbResult) -> FeatureResult {
        guard !result.succeeded else { return FeatureResult(ok: true, message: "Applied") }
        let detail = result.stderr.isEmpty ? result.stdout : result.stderr
        return FeatureResult(ok: false, message: "Failed — \(detail)")
    }
}
