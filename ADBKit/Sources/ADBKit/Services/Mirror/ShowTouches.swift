import Foundation

/// Android's "Show taps" developer setting — the dot the device draws under
/// every physical touch, on the display itself, so it's visible in the
/// mirror and in recordings. The mirror's toggle writes the system setting
/// directly (`settings put system show_touches`): instant, no session
/// restart, works mid-recording. Note that Android renders the dot only for
/// physical touches on the device — taps injected by clicking the mirror
/// don't draw it.
public struct ShowTouches: Sendable {
    let client: AdbClient

    public init(client: AdbClient) {
        self.client = client
    }

    public func set(_ on: Bool, serial: String) async throws(AdbError) {
        _ = try await client.run(
            on: serial, ["shell", "settings", "put", "system", "show_touches", on ? "1" : "0"])
    }
}
