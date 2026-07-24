import Foundation

/// One adb-controllable Developer Options toggle — declarative,
/// FeatureRegistry-style, so the panel renders and reconciles from the table
/// and adding a toggle is one entry (the invariant tests keep it honest).
public struct DevToggleDef: Sendable, Identifiable, Equatable {
    public enum Backing: Sendable, Equatable {
        /// `settings put <namespace> <key> <value>`, read via `settings get`.
        case setting(namespace: String, key: String, on: String, off: String)
        /// `setprop <key> <value>`, read via `getprop`. UI-debug sysprops are
        /// picked up only after the SYSPROPS poke (`service call activity
        /// 1599295570`), which the service sends after every write.
        case sysprop(key: String, on: String, off: String)
    }

    public let id: String
    public let title: String
    /// One line under the title — what flipping it does on the device.
    public let detail: String
    public let backing: Backing
}

/// An animation-scale slot (Developer Options' three scale pickers).
public struct DevScaleDef: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    /// The `settings global` key holding the scale.
    public let key: String
}

/// Android's Developer Options, driven over adb: the UI-debugging overlays
/// (layout bounds, GPU overdraw, pointer feedback), app-lifecycle switches,
/// and the animation scales — everything here is a plain `settings put` or
/// `setprop`, no root. Values are read back from the device so the panel
/// shows ground truth, not remembered state.
public struct DeveloperSettingsService: Sendable {
    /// Binder code of `SYSPROPS_TRANSACTION` ('_SPR') — poking it makes every
    /// app re-read the debug sysprops, so overlay toggles repaint immediately
    /// instead of on the next app restart.
    static let syspropsPoke = "1599295570"

    public static let toggles: [DevToggleDef] = [
        DevToggleDef(
            id: "show-touches", title: "Show taps",
            detail: "Draw a dot under every touch on the device",
            backing: .setting(namespace: "system", key: "show_touches", on: "1", off: "0")
        ),
        DevToggleDef(
            id: "pointer-location", title: "Pointer location",
            detail: "Crosshair overlay tracking every pointer, with coordinates",
            backing: .setting(namespace: "system", key: "pointer_location", on: "1", off: "0")
        ),
        DevToggleDef(
            id: "layout-bounds", title: "Show layout bounds",
            detail: "Outline every view's clip bounds, margins, and padding",
            backing: .sysprop(key: "debug.layout", on: "true", off: "false")
        ),
        DevToggleDef(
            id: "gpu-overdraw", title: "Show GPU overdraw",
            detail: "Color areas by how often they're drawn per frame",
            backing: .sysprop(key: "debug.hwui.overdraw", on: "show", off: "false")
        ),
        DevToggleDef(
            id: "gpu-profile", title: "Profile GPU rendering",
            detail: "On-screen frame-time bars per visible app",
            backing: .sysprop(key: "debug.hwui.profile", on: "visual_bars", off: "false")
        ),
        DevToggleDef(
            id: "strict-mode", title: "Strict mode flash",
            detail: "Flash the screen when an app blocks its main thread",
            backing: .sysprop(key: "persist.sys.strictmode.visual", on: "1", off: "0")
        ),
        DevToggleDef(
            id: "force-rtl", title: "Force RTL layout",
            detail: "Lay every screen out right-to-left, any locale",
            backing: .setting(namespace: "global", key: "debug.force_rtl", on: "1", off: "0")
        ),
        DevToggleDef(
            id: "keep-activities", title: "Don't keep activities",
            detail: "Destroy every activity the moment it's left — surfaces state-restore bugs",
            backing: .setting(namespace: "global", key: "always_finish_activities", on: "1", off: "0")
        ),
    ]

    public static let animationScales: [DevScaleDef] = [
        DevScaleDef(id: "window-scale", title: "Window animation scale", key: "window_animation_scale"),
        DevScaleDef(id: "transition-scale", title: "Transition animation scale", key: "transition_animation_scale"),
        DevScaleDef(id: "animator-scale", title: "Animator duration scale", key: "animator_duration_scale"),
    ]

    /// The scale steps Developer Options offers (0 = animations off).
    public static let scaleChoices: [Double] = [0, 0.5, 1, 1.5, 2, 5, 10]

    let client: AdbClient

    public init(client: AdbClient) {
        self.client = client
    }

    // MARK: - Read

    /// Every toggle's current device state, keyed by toggle id.
    public func readToggles(serial: String) async -> [String: Bool] {
        var values: [String: Bool] = [:]
        for toggle in Self.toggles {
            let raw: String
            switch toggle.backing {
            case .setting(let namespace, let key, _, _):
                raw = (try? await client.run(
                    on: serial, ["shell", "settings", "get", namespace, key]))?.stdout ?? ""
            case .sysprop(let key, _, _):
                raw = (try? await client.run(on: serial, ["shell", "getprop", key]))?.stdout ?? ""
            }
            values[toggle.id] = Self.isOn(raw, toggle: toggle)
        }
        return values
    }

    /// Every animation scale's current value, keyed by scale id.
    public func readScales(serial: String) async -> [String: Double] {
        var values: [String: Double] = [:]
        for scale in Self.animationScales {
            let raw = (try? await client.run(
                on: serial, ["shell", "settings", "get", "global", scale.key]))?.stdout ?? ""
            values[scale.id] = Self.parseScale(raw)
        }
        return values
    }

    // MARK: - Write

    public func set(_ toggle: DevToggleDef, on: Bool, serial: String) async throws(AdbError) -> AdbResult {
        switch toggle.backing {
        case .setting(let namespace, let key, let onValue, let offValue):
            return try await client.run(
                on: serial, ["shell", "settings", "put", namespace, key, on ? onValue : offValue])
        case .sysprop(let key, let onValue, let offValue):
            let result = try await client.run(
                on: serial, ["shell", "setprop", key, on ? onValue : offValue])
            guard result.succeeded else { return result }
            // Repaint now: apps re-read the debug sysprops on this poke.
            return try await client.run(
                on: serial, ["shell", "service", "call", "activity", Self.syspropsPoke])
        }
    }

    public func setScale(_ scale: DevScaleDef, value: Double, serial: String) async throws(AdbError) -> AdbResult {
        try await client.run(
            on: serial,
            ["shell", "settings", "put", "global", scale.key, Self.scaleArgument(value)])
    }

    // MARK: - Pure parsing

    /// A toggle is on exactly when the device reports its `on` value
    /// (`settings get` prints `null` for a never-set key; `getprop` prints
    /// an empty line — both read as off).
    public static func isOn(_ raw: String, toggle: DevToggleDef) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch toggle.backing {
        case .setting(_, _, let on, _): return trimmed == on
        case .sysprop(_, let on, _): return trimmed == on
        }
    }

    /// `settings get` for a scale prints a float, or `null` when the user
    /// never changed it — the platform default is 1×.
    public static func parseScale(_ raw: String) -> Double {
        Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1.0
    }

    /// Whole numbers print bare ("2" not "2.0") to match how Developer
    /// Options itself stores them.
    static func scaleArgument(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
