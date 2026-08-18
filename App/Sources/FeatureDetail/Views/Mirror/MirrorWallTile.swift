import ADBKit
import SwiftUI

/// One device in the Mirror Wall: the live video, a caption strip naming the
/// device, and a menu with the per-device actions. Interactive like the
/// full-pane mirror — clicking the video taps the device and moves the wall's
/// focus to it (AppKit makes the clicked video view first responder, so keys
/// and ⌘C/⌘V follow the click on their own).
///
/// The caption strip is the tile's drag handle, deliberately: `.onDrag` on the
/// video would turn every swipe on the device into a tile drag.
struct MirrorWallTile: View {
    /// Why a tile isn't streaming here, when it isn't the user's own choice.
    /// Every case is the same fact — something else already mirrors this device,
    /// and the device has one encoder — differing only in where to send the user.
    enum Blocked: Equatable {
        /// This device is showing in its own pop-out window.
        case poppedOut
        /// This window's own Mirror Screen tab has it (the wall handed it over).
        case mirrorTab
        /// Another workspace window is mirroring it.
        case otherWindow(WorkspaceID)
    }

    /// Which edge a dragged tile would be inserted at, drawn as a guideline.
    enum DropEdge {
        case leading
        case trailing
    }

    @Environment(AppState.self) private var state
    let device: Device
    let wall: MirrorWallModel
    let blocked: Blocked?
    let dropEdge: DropEdge?
    /// The drag payload for this tile, attached to the caption strip.
    let dragItem: () -> NSItemProvider
    let onScreenshot: () -> Void
    let onPopOut: () -> Void
    let onBringBack: () -> Void
    let onOpenFullMirror: () -> Void

    private var model: MirrorViewModel? { wall.stream(device.serial) }
    private var isFocused: Bool { wall.focused == device.serial }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let model {
                    MirrorVideoView(
                        renderer: model.renderer,
                        videoSize: model.videoSize,
                        onTouch: { action, point in
                            if action == .down { wall.focus(device.serial) }
                            model.touch(action, at: point)
                        },
                        onKeycode: { keycode, action in model.key(keycode, action) },
                        onText: { model.text($0) },
                        onPaste: { model.pasteToDevice() },
                        onCopy: { model.copyFromDevice(cut: false) },
                        onCut: { model.copyFromDevice(cut: true) })
                }
                statusOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            caption
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? Color.accentColor : Color.primary.opacity(0.12),
                              lineWidth: isFocused ? 2 : 1)
        }
        .overlay(alignment: dropEdge == .trailing ? .trailing : .leading) {
            if dropEdge != nil {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
    }

    // MARK: - Status

    @ViewBuilder private var statusOverlay: some View {
        switch blocked {
        case .poppedOut:
            card(icon: "macwindow", text: "Showing in its own window.") {
                Button("Focus") { state.core.focusMirrorWindow(device.serial) }
                Button("Bring Back") { onBringBack() }
                    .buttonStyle(.borderedProminent)
            }
        case .mirrorTab:
            card(icon: "display", text: "Showing in the Mirror Screen tab.") {
                Button("Go to Mirror Screen") { onOpenFullMirror() }
                Button("Bring Back") { onBringBack() }
                    .buttonStyle(.borderedProminent)
            }
        case let .otherWindow(owner):
            card(
                icon: "macwindow.on.rectangle",
                text: "Mirroring in \(state.core.registry.label(of: owner))."
            ) {
                Button("Focus \(state.core.registry.label(of: owner))") {
                    state.core.focusWindow(owner)
                }
                .buttonStyle(.borderedProminent)
            }
        case nil:
            unblockedStatus
        }
    }

    @ViewBuilder private var unblockedStatus: some View {
        if wall.isPaused(device.serial) {
            card(icon: "pause.circle", text: "Paused.") {
                Button("Stream") { wall.togglePause(device.serial) }
                    .buttonStyle(.borderedProminent)
            }
        } else if let model {
            switch model.status {
            case .connecting:
                ProgressView().controlSize(.small).tint(.white)
            case let .failed(message):
                card(icon: "exclamationmark.triangle", text: message) {
                    Button("Reconnect") { wall.reconnect(device.serial) }
                        .buttonStyle(.borderedProminent)
                }
            case .stopped:
                card(icon: "stop.circle", text: "Mirror stopped.") {
                    Button("Reconnect") { wall.reconnect(device.serial) }
                        .buttonStyle(.borderedProminent)
                }
            case .streaming:
                EmptyView()
            }
        }
    }

    private func card(
        icon: String, text: String, @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.app(.title3))
            Text(text)
                .font(.app(.caption))
                .multilineTextAlignment(.center)
            HStack(spacing: 6) { actions() }
                .controlSize(.small)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }

    // MARK: - Caption

    private var caption: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusTint)
                .frame(width: 6, height: 6)

            Text(state.deviceDisplayName(device))
                .font(.app(.caption))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            actionsMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture { wall.focus(device.serial) }
        .onDrag { dragItem() }
        .help("Drag to rearrange")
    }

    private var statusTint: Color {
        if blocked != nil { return .orange }
        if wall.isPaused(device.serial) { return .secondary }
        switch model?.status {
        case .streaming: return .green
        case .failed: return .red
        case .stopped: return .secondary
        case .connecting, nil: return .yellow
        }
    }

    private var actionsMenu: some View {
        Menu {
            Section("Device") {
                Button("Back") { model?.tapKey(4) }
                Button("Home") { model?.tapKey(3) }
                Button("Recent Apps") { model?.tapKey(187) }
            }
            .disabled(model?.status != .streaming)

            Divider()

            Button("Screenshot…") { onScreenshot() }
                .disabled(model?.status != .streaming)
            Button(wall.isPaused(device.serial) ? "Stream" : "Pause") {
                wall.togglePause(device.serial)
            }
            .disabled(blocked != nil)

            Divider()

            // Both blocks a tile can take itself out of: its own window, and
            // this window's Mirror Screen tab. Closing whichever holds the
            // device hands it straight back to the wall.
            if blocked == .poppedOut || blocked == .mirrorTab {
                Button("Bring Back Into the Wall") { onBringBack() }
            } else {
                Button("Open in Its Own Window") { onPopOut() }
                    .disabled(blocked != nil)
            }
            Button("Open in Mirror Screen") { onOpenFullMirror() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.app(.caption))
                .frame(width: 18, height: 14)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Device keys, screenshot, and window options")
    }
}
