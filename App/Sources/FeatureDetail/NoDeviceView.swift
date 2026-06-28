import ADBKit
import SwiftUI

/// The "connect a device" empty state for features that need one. The copy is
/// tailored per feature — so it never reads as a generic screen — by passing a
/// message or a feature to derive one. Matches the `ContentUnavailableView` look
/// the bespoke device views (Logcat, Apps, Mirror…) already use.
struct NoDeviceView: View {
    let message: String

    init(_ message: String) { self.message = message }
    init(feature: FeatureDef) { self.message = connectDeviceHint(for: feature) }

    var body: some View {
        ContentUnavailableView(
            "No device connected", systemImage: "iphone.slash", description: Text(message)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A device-specific "Connect a device to …" line for `feature`. The generic
/// action views (instant/form/toggle) share one screen, so they look the copy up
/// here; anything not listed falls back to a title-derived line, so every feature
/// still reads specifically rather than showing one generic message.
func connectDeviceHint(for feature: FeatureDef) -> String {
    deviceHints[feature.id] ?? "Connect a device to use \(feature.title)."
}

private let deviceHints: [String: String] = [
    "send-text": "Connect a device to send text.",
    "reverse-port": "Connect a device to reverse a port to it.",
    "rn-dev-host": "Connect a device to set its dev server host.",
    "network-toggles": "Connect a device to toggle its radios.",
    "http-proxy": "Connect a device to set an HTTP proxy.",
    "fake-battery": "Connect a device to fake its battery level.",
    "layout-overrides": "Connect a device to change its font & density.",
    "locale": "Connect a device to change its locale.",
    "monkey": "Connect a device to run the Monkey stress test.",
    "reload-js": "Connect a device to reload the JS bundle.",
    "open-dev-menu": "Connect a device to open the React Native dev menu.",
    "process-death": "Connect a device to simulate process death.",
    "screenshot": "Connect a device to capture a screenshot.",
    "current-activity": "Connect a device to copy its current activity.",
    "foreground-package": "Connect a device to copy the foreground package.",
    "get-ip": "Connect a device to copy its IP address.",
    "dark-mode": "Connect a device to toggle dark mode.",
    "animation-scale": "Connect a device to change its animation scale.",
    "demo-mode": "Connect a device to enter demo mode.",
]
