import Foundation

/// Which toolchain talks to a device: adb for Android, `xcrun simctl` for
/// iOS Simulators. Platform is a property of the *device*, not a mode — the
/// device bar mixes both and features adapt to the selection.
public enum DevicePlatform: String, Sendable, Codable {
    case android
    case iosSimulator = "ios-simulator"
}

public struct Device: Sendable, Equatable, Identifiable, Codable {
    public let serial: String
    /// adb state string: "device", "offline", "unauthorized", … Simulators
    /// normalize their "Booted" state to "device" so readiness is uniform.
    public let state: String
    public let model: String?
    public let product: String?
    public let transportId: String?
    /// Friendly display label, e.g. "Pixel 7 (3f2a)".
    public let label: String
    public let isWireless: Bool
    public let platform: DevicePlatform

    public init(
        serial: String,
        state: String,
        model: String?,
        product: String?,
        transportId: String?,
        label: String,
        isWireless: Bool,
        platform: DevicePlatform = .android
    ) {
        self.serial = serial
        self.state = state
        self.model = model
        self.product = product
        self.transportId = transportId
        self.label = label
        self.isWireless = isWireless
        self.platform = platform
    }

    public var id: String { serial }
    public var isReady: Bool { state == "device" }
}
