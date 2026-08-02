import Foundation

/// Stable identity for one workspace window. A window is a device-scoped
/// workspace: its own selected device, tabs, terminals and console sessions.
/// The id is persisted (`WindowState.id`), so a relaunch rebinds a restored
/// window to the workspace it had.
public struct WorkspaceID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// A fresh id. Random rather than sequential so a window closed and
    /// reopened never collides with a persisted entry that outlived it.
    public static func generate() -> WorkspaceID {
        WorkspaceID(UUID().uuidString)
    }

    public var description: String { rawValue }

    // Encoded as a bare string so the persisted layout stays readable by hand.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// What stops a window from taking a device or opening a feature, because
/// another window already has it.
public enum WorkspaceConflict: Sendable, Equatable {
    /// Another window is already pointed at this device. Selecting it here is
    /// allowed but opt-in — the default is to focus that window instead.
    case deviceOwnedElsewhere(WorkspaceID)
    /// Another window already runs an *exclusive* feature against this device
    /// (see `WorkspaceRegistry.exclusiveFeatureIDs`). Two of these on one
    /// device fight over a single device-side resource.
    case featureOwnedElsewhere(WorkspaceID, featureID: String)
}

/// Which window owns which device, and which exclusive feature is live where.
///
/// Pure and value-typed: the App layer keeps one of these on `AppCore` and
/// mirrors each window's selection / open tabs into it, so every "is this
/// device taken?" question is answered by tested logic rather than by walking
/// live view state.
///
/// Entry order is creation order, which is also the window numbering the UI
/// shows ("Window 2").
public struct WorkspaceRegistry: Sendable, Equatable {
    /// One window's registered facts. Deliberately minimal — anything the
    /// conflict rules don't read stays in the App layer's `AppState`.
    public struct Entry: Sendable, Equatable, Identifiable {
        public var id: WorkspaceID
        /// The device this window is pointed at, nil when nothing is selected.
        public var serial: String?
        /// Feature ids currently open as tabs in this window.
        public var openFeatureIDs: Set<String>

        public init(
            id: WorkspaceID,
            serial: String? = nil,
            openFeatureIDs: Set<String> = []
        ) {
            self.id = id
            self.serial = serial
            self.openFeatureIDs = openFeatureIDs
        }
    }

    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    // MARK: - Exclusivity

    /// Features that must not run twice against one device. Everything else
    /// duplicates safely: two `adb logcat`s, two `dumpsys` readers or two file
    /// browsers on one device are independent.
    ///
    /// - `scrcpy` / `scrcpy-window` / `screen-record` drive scrcpy's device-side
    ///   server; a second session is a second H.264 encoder on the same
    ///   hardware, which drops frames or stalls on mid-range devices.
    /// - `js-console` speaks CDP through the React Native inspector proxy,
    ///   which hands a target to the newest client and *silently kills* the
    ///   previous one — a second window would break the first with no error.
    /// - `frida-console` runs one `frida-server` process on one device port.
    ///
    /// Not listed: `reactotron`, whose relay is a single app-wide listener on
    /// the Mac shared by every window by design (both show one timeline).
    ///
    /// `scrcpy-window` is the pop-out mirror's pseudo-id (`MirrorWindow
    /// .featureID`), not a registry feature — it shares the encoder with
    /// `scrcpy`, so it carries the same exclusivity.
    public static let exclusiveFeatureIDs: Set<String> = [
        "scrcpy", "scrcpy-window", "screen-record", "js-console", "frida-console",
    ]

    public static func isExclusive(_ featureID: String) -> Bool {
        exclusiveFeatureIDs.contains(featureID)
    }

    // MARK: - Window tint

    /// Palette slot for a window's device icon, or nil to use the app accent.
    ///
    /// The first window always gets nil: the app has one accent, and a lone
    /// window has nothing to be told apart from. Only the *additional* windows
    /// take a color, so opening a second one never repaints the first.
    /// Assigned by position rather than hashed from the serial, so two windows
    /// can't land on the same color.
    public static func tintIndex(ofWindow ordinal: Int, paletteSize: Int) -> Int? {
        guard ordinal > 1, paletteSize > 0 else { return nil }
        return (ordinal - 2) % paletteSize
    }

    // MARK: - Queries

    public subscript(id: WorkspaceID) -> Entry? {
        entries.first { $0.id == id }
    }

    public var ids: [WorkspaceID] { entries.map(\.id) }

    public var count: Int { entries.count }

    /// 1-based position in creation order — the "Window 2" the UI shows.
    /// nil for an unregistered id.
    public func ordinal(of id: WorkspaceID) -> Int? {
        entries.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    /// How another window is named in menus and conflict copy. Deliberately
    /// the ordinal and not the device: every place this appears is *about* a
    /// device ("Pixel 8 Pro — in …"), so repeating the device name would say
    /// nothing, and a same-device collision has no other way to point at the
    /// right window.
    public func label(of id: WorkspaceID) -> String {
        guard let ordinal = ordinal(of: id) else { return "another window" }
        return "Window \(ordinal)"
    }

    /// The window currently pointed at `serial`, ignoring `excluding` (the
    /// window doing the asking). nil when the device is free.
    public func owner(ofDevice serial: String, excluding: WorkspaceID? = nil) -> WorkspaceID? {
        entries.first { $0.id != excluding && $0.serial == serial }?.id
    }

    /// The window running `featureID` against `serial`, ignoring `excluding`.
    /// Only exclusive features can conflict, so anything else is always nil —
    /// callers don't have to pre-filter.
    public func owner(
        ofFeature featureID: String, on serial: String, excluding: WorkspaceID? = nil
    ) -> WorkspaceID? {
        guard Self.isExclusive(featureID) else { return nil }
        return entries.first {
            $0.id != excluding && $0.serial == serial && $0.openFeatureIDs.contains(featureID)
        }?.id
    }

    /// What would block `id` from opening `featureID` right now: another
    /// window already running it against the same device. A feature that needs
    /// no device, or one nobody else has open, is unblocked.
    public func conflict(opening featureID: String, in id: WorkspaceID) -> WorkspaceConflict? {
        guard let serial = self[id]?.serial else { return nil }
        guard let other = owner(ofFeature: featureID, on: serial, excluding: id) else { return nil }
        return .featureOwnedElsewhere(other, featureID: featureID)
    }

    /// What would block `id` from selecting `serial`: another window already
    /// showing that device. Selecting anyway is allowed (the caller decides);
    /// this only reports the fact.
    public func conflict(selecting serial: String, in id: WorkspaceID) -> WorkspaceConflict? {
        guard let other = owner(ofDevice: serial, excluding: id) else { return nil }
        return .deviceOwnedElsewhere(other)
    }

    /// Serials no window is pointed at — what "New Window for Device…" offers
    /// first, so the common case opens a genuinely new workspace.
    public func unclaimed(from serials: [String]) -> [String] {
        let taken = Set(entries.compactMap(\.serial))
        return serials.filter { !taken.contains($0) }
    }

    // MARK: - Mutation

    /// Add a window (no-op if already registered, so a re-entrant bind is safe).
    public mutating func register(_ id: WorkspaceID) {
        guard !entries.contains(where: { $0.id == id }) else { return }
        entries.append(Entry(id: id))
    }

    public mutating func remove(_ id: WorkspaceID) {
        entries.removeAll { $0.id == id }
    }

    /// Point a window at a device. Registers the window if it's new, so the
    /// App layer never has to order its calls.
    public mutating func setDevice(serial: String?, for id: WorkspaceID) {
        register(id)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].serial = serial
    }

    public mutating func setOpenFeatures(_ featureIDs: Set<String>, for id: WorkspaceID) {
        register(id)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].openFeatureIDs = featureIDs
    }
}
