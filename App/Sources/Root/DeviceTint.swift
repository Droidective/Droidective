import ADBKit
import SwiftUI

/// A stable color per device, so two windows side by side are told apart at a
/// glance instead of by reading their titles. Only ever a *hint*: it accents
/// the device pill and the window's status dot, never the whole chrome, so the
/// user's chosen accent still owns the interface.
///
/// The index math is `WorkspaceRegistry.tintIndex` (pure, tested) — djb2 over
/// the serial, so a device keeps its color across relaunches.
enum DeviceTint {
    /// Deliberately not including green: that's the brand accent, and a device
    /// tinted the same as every prominent button would read as "selected"
    /// rather than "this device".
    private static let palette: [Color] = [
        .blue, .orange, .purple, .pink, .teal, .indigo,
    ]

    static func color(for serial: String) -> Color {
        palette[WorkspaceRegistry.tintIndex(for: serial, paletteSize: palette.count)]
    }
}
