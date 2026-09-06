import ADBKit
import SwiftUI

/// Identity for the pop-out mirror windows (the mirror control bar's window
/// button, and the Mirror Wall's per-tile "Open in Its Own Window").
enum MirrorWindow {
    static let windowID = "mirror"
    /// Environment feature id marking the window host — never a real tab id,
    /// so the window's leave guards can't collide with the in-tab mirror's.
    static let featureID = "scrcpy-window"
}

/// A pop-out screen mirror: the same live mirror, hosted in its own window so
/// it can sit beside the main workspace (or other apps) while the tabs do
/// something else. One window per device — it is pinned to the serial it was
/// opened for and does *not* follow the device bar, which is what lets several
/// stand side by side. The tab-host environment defaults keep it always
/// "active", and the distinct feature id still routes its recording guard
/// through the device-switch / quit prompts.
struct MirrorWindowView: View {
    @Environment(AppState.self) private var state
    /// The device this window mirrors, from the window's presented value. nil
    /// when macOS re-presents a window with no value (see `title`).
    let serial: String?

    var body: some View {
        ZStack {
            if let serial {
                if let device = state.devices.first(where: { $0.serial == serial && $0.isReady }) {
                    ScreenMirrorView(pinnedSerial: device.serial)
                        .environment(\.tabFeatureID, MirrorWindow.featureID)
                } else {
                    // A serial that isn't connected: the device was unplugged,
                    // or macOS restored the window from a previous launch.
                    ContentUnavailableView(
                        "Device not connected",
                        systemImage: "iphone.slash",
                        description: Text(
                            "\(serial) isn’t connected. Plug it in, or close this window."))
                }
            } else {
                ContentUnavailableView(
                    "No device",
                    systemImage: "iphone.slash",
                    description: Text("Open a mirror window from a device’s mirror controls."))
            }
        }
        .navigationTitle(title)
        .frame(minWidth: 320, minHeight: 480)
        .background(MirrorWindowRegistrar(serial: serial))
    }

    private var title: String {
        guard let serial else { return "Screen Mirror" }
        let device = state.devices.first { $0.serial == serial }
        return "Mirror · \(device.map(state.deviceDisplayName) ?? serial)"
    }
}

/// Registers this window with `AppCore` for the lifetime it's on screen: its
/// device becomes a claim (so no wall tile or tab starts a second encoder on
/// it), and its `NSWindow` is what "Arrange Mirror Windows" moves.
private struct MirrorWindowRegistrar: View {
    @Environment(AppState.self) private var state
    let serial: String?

    var body: some View {
        WindowAccessor { window in
            // Droidective restores its own windows, and a pop-out mirror is not
            // one of them: it exists because someone asked for this device now.
            // AppKit's saved-state restoration brought them back at launch
            // instead — before any workspace existed, so the window had no owner
            // to read its adb client from, and a device nobody asked about got
            // an encoder during launch. Saved state also lives outside the
            // bundle, so reinstalling the app never cleared it. Same opt-out the
            // workspace windows take in `AppCore.bind`.
            window.isRestorable = false
            guard let serial else { return }
            state.core.noteMirrorWindow(serial: serial, window: window)
        }
        .frame(width: 0, height: 0)
        .onDisappear {
            guard let serial else { return }
            state.core.forgetMirrorWindow(serial: serial)
        }
    }
}

/// Window ▸ Open Mirror in New Window.
///
/// A pop-out mirror had exactly one entry point people could find: the last
/// button on the mirror's control bar, which folds into the `⋯` overflow in a
/// narrow pane. A menu item is the surface someone actually goes looking in —
/// and, unlike a button inside the mirror, NSMenu sees its key equivalent
/// before the mirror's view swallows the event.
///
/// A `View` rather than a plain closure because `openWindow` is an environment
/// action, which only a view can read.
struct MirrorWindowCommands: View {
    let core: AppCore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // scrcpy can't mirror an iOS Simulator, so those never appear here.
        let devices = core.readyDevices.filter { $0.platform == .android }
        if devices.count > 1 {
            Menu("Open Mirror in New Window") {
                ForEach(devices) { device in
                    Button(core.deviceTitle(device)) { open(device.serial) }
                }
            }
        } else {
            Button("Open Mirror in New Window") {
                guard let only = devices.first else { return }
                open(only.serial)
            }
            .keyboardShortcut("m", modifiers: [.command, .control])
            .disabled(devices.isEmpty)
        }
    }

    private func open(_ serial: String) {
        core.frontmost?.prepareMirrorWindow(serial: serial)
        openWindow(id: MirrorWindow.windowID, value: serial)
    }
}
