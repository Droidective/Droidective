import ADBKit
import SwiftUI

/// The color of a window's device icon.
///
/// The app has one accent, and it stays that way: the first window's icon is
/// always `.brandAccent`, so a single-window session looks exactly as it did
/// before multi-window, and opening a second window never repaints the first.
/// Each *additional* window takes a color from this palette instead, on the
/// device-status icon alone — enough to tell two bars apart at a glance,
/// without turning the interface a different color.
///
/// The slot is `WorkspaceRegistry.tintIndex(ofWindow:paletteSize:)` (pure,
/// tested): by window position, so two windows can't collide.
enum DeviceTint {
    /// Deliberately excludes green: that's the brand accent the first window
    /// uses, and a second window tinted the same would defeat the point.
    private static let palette: [Color] = [
        .blue, .orange, .purple, .pink, .teal, .indigo,
    ]

    /// nil for the first window — the caller falls back to the app accent.
    static func color(forWindow ordinal: Int) -> Color? {
        WorkspaceRegistry.tintIndex(ofWindow: ordinal, paletteSize: palette.count)
            .map { palette[$0] }
    }
}
