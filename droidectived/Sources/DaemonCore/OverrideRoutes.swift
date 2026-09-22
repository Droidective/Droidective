import ADBKit
import Foundation

/// Wire shapes for the device-state overrides.
///
/// A pass-through over `OverridesService`, which is where the interesting part
/// lives: an override is *reconciled* against the device rather than trusted
/// from the record, because a proxy someone cleared in Settings is not an
/// override any more and a screen that said it was would be lying.
public enum OverrideProtocol {
    public struct ActiveOverride: Codable, Equatable, Sendable {
        /// An `OverrideKind` raw value — "proxy", "layout", "battery", "demo",
        /// "animation", "locale", "darkMode".
        public let kind: String
        /// A human-readable name for the kind, sent rather than derived so a
        /// client does not keep a second copy of the seven labels.
        public let label: String
        /// What it is currently set to, as the device reports it.
        public let value: String
        /// Milliseconds since the epoch, as the record has it.
        public let setAt: Double

        public init(_ override: ADBKit.ActiveOverride) {
            kind = override.kind.rawValue
            label = override.kind.label
            value = override.value
            setAt = override.setAt
        }
    }

    public struct ActiveResponse: Codable, Equatable, Sendable {
        public let overrides: [ActiveOverride]
        public init(overrides: [ActiveOverride]) { self.overrides = overrides }
    }

    public struct ResetRequest: Codable, Equatable, Sendable {
        public let serial: String
        /// One kind, or nil for all of them — the shape the Mac's two buttons
        /// need, and one route rather than two nearly identical ones.
        public let kind: String?

        public init(serial: String, kind: String?) {
            self.serial = serial
            self.kind = kind
        }
    }

    public static let unknownKind = DaemonProtocol.ErrorBody(
        code: "unknown_override",
        message: "No such override.",
        detail: "known kinds: \(OverrideKind.allCases.map(\.rawValue).joined(separator: ", "))")
}

/// Reading and clearing the overrides in effect on a device.
enum OverrideRoutes {
    /// `{"serial": …}`, the shape `/v1/apps/list` already takes.
    static func active(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(AppProtocol.ListRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            let active = try await backend.activeOverrides(serial: request.serial)
            return (200, DaemonProtocol.encoded(OverrideProtocol.ActiveResponse(
                overrides: active.map(OverrideProtocol.ActiveOverride.init))))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "Could not read the overrides.",
                detail: "\(error)")))
        }
    }

    static func reset(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(OverrideProtocol.ResetRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }

        // A named kind has to be one this daemon knows. Falling back to "all"
        // for an unrecognised name would clear six overrides nobody asked
        // about, which is the one mistake here that cannot be undone by
        // pressing the button again.
        var kind: OverrideKind?
        if let named = request.kind {
            guard let resolved = OverrideKind(rawValue: named) else {
                return (400, DaemonProtocol.encoded(OverrideProtocol.unknownKind))
            }
            kind = resolved
        }

        do {
            try await backend.resetOverrides(serial: request.serial, kind: kind)
            return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(FeatureResult(
                ok: true,
                message: kind.map { "\($0.label) reset" } ?? "All overrides reset"))))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "Could not reset the overrides.",
                detail: "\(error)")))
        }
    }
}
