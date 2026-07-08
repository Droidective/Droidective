import SwiftUI

/// Identity for the pop-out mirror window (the mirror control bar's window
/// button opens it).
enum MirrorWindow {
    static let windowID = "mirror"
    /// Environment feature id marking the window host — never a real tab id,
    /// so the window's leave guards can't collide with the in-tab mirror's.
    static let featureID = "scrcpy-window"
}

/// The pop-out screen mirror: the same live mirror, hosted in its own window
/// so it can sit beside the main workspace (or other apps) while the tabs do
/// something else. It follows the device-bar selection exactly like the
/// in-tab mirror. The tab-host environment defaults keep it always "active",
/// and the distinct feature id still routes its recording guard through the
/// device-switch / quit prompts.
struct MirrorWindowView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScreenMirrorView()
            .environment(\.tabFeatureID, MirrorWindow.featureID)
            .navigationTitle(state.selectedDevice.map { "Mirror · \($0.label)" } ?? "Screen Mirror")
            .frame(minWidth: 320, minHeight: 480)
    }
}
