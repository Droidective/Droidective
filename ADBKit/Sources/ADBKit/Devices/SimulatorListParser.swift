import Foundation

/// One simulator from `simctl list -j devices` — any runtime, any state.
public struct Simulator: Sendable, Equatable, Identifiable {
    public let udid: String
    public let name: String
    /// simctl state string: "Booted", "Shutdown", "Booting", …
    public let state: String
    /// Human runtime label parsed from the runtime key, e.g. "iOS 18.2".
    public let runtime: String
    /// False when the runtime was removed (e.g. by an Xcode update) — the
    /// simulator exists but can't boot.
    public let isAvailable: Bool
    /// When simctl last booted this simulator; nil for one never booted.
    /// The recency signal behind the device bar's short "most used" list.
    public let lastBootedAt: Date?

    public init(
        udid: String, name: String, state: String, runtime: String,
        isAvailable: Bool, lastBootedAt: Date? = nil
    ) {
        self.udid = udid
        self.name = name
        self.state = state
        self.runtime = runtime
        self.isAvailable = isAvailable
        self.lastBootedAt = lastBootedAt
    }

    public var id: String { udid }
    public var isBooted: Bool { state == "Booted" }
}

/// Parses `xcrun simctl list -j devices` JSON into `Simulator` values, and
/// maps booted ones into bar `Device`s.
public enum SimulatorListParser {
    private struct Payload: Decodable {
        let devices: [String: [Entry]]
    }

    private struct Entry: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool?
        let lastBootedAt: String?
    }

    /// simctl emits plain ISO8601 ("2026-07-04T05:12:30Z").
    private static func bootDate(_ raw: String?) -> Date? {
        raw.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// All simulators, sorted by runtime (newest first) then name for a stable
    /// list. Returns [] for malformed JSON — discovery treats that as "none",
    /// not an error.
    public static func parse(_ json: String) -> [Simulator] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)) else {
            return []
        }
        var simulators: [Simulator] = []
        for (runtimeKey, entries) in payload.devices {
            let runtime = runtimeLabel(runtimeKey)
            for entry in entries {
                simulators.append(Simulator(
                    udid: entry.udid,
                    name: entry.name,
                    state: entry.state,
                    runtime: runtime,
                    isAvailable: entry.isAvailable ?? true,
                    lastBootedAt: bootDate(entry.lastBootedAt)
                ))
            }
        }
        simulators.sort { lhs, rhs in
            if lhs.runtime != rhs.runtime {
                return lhs.runtime.localizedStandardCompare(rhs.runtime) == .orderedDescending
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return simulators
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-18-2" → "iOS 18.2". An
    /// unrecognized key passes through unchanged rather than guessing.
    static func runtimeLabel(_ key: String) -> String {
        guard let raw = key.split(separator: ".").last, raw.contains("-") else { return key }
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count >= 2, parts.dropFirst().allSatisfy({ Int($0) != nil }) else {
            return key
        }
        return "\(parts[0]) \(parts.dropFirst().joined(separator: "."))"
    }

    /// The short bootable list for the device-bar menu: available, shut-down
    /// simulators the user has actually booted before, most recent first —
    /// Xcode installs ~30 sims and the menu shouldn't list them all (the
    /// Emulators screen does). A user who never booted one gets the first
    /// `limit` in default order so the section isn't empty on day one.
    public static func quickPicks(_ simulators: [Simulator], limit: Int = 5) -> [Simulator] {
        let bootable = simulators.filter { !$0.isBooted && $0.isAvailable }
        let used = bootable
            .filter { $0.lastBootedAt != nil }
            .sorted { ($0.lastBootedAt ?? .distantPast) > ($1.lastBootedAt ?? .distantPast) }
        let picks = used.isEmpty ? bootable : used
        return Array(picks.prefix(limit))
    }

    /// Booted, available simulators as device-bar `Device`s. State normalizes
    /// to "device" so `isReady` works uniformly across platforms.
    public static func devices(from simulators: [Simulator]) -> [Device] {
        simulators
            .filter { $0.isBooted && $0.isAvailable }
            .map { sim in
                Device(
                    serial: sim.udid,
                    state: "device",
                    model: sim.name,
                    product: sim.runtime,
                    transportId: nil,
                    label: sim.name,
                    isWireless: false,
                    platform: .iosSimulator
                )
            }
    }
}
