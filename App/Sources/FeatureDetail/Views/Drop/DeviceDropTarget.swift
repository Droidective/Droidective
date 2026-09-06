import ADBKit
import SwiftUI

/// A package drop waiting on the install prompt.
struct PendingInstallDrop: Identifiable, Equatable {
    let id = UUID()
    let paths: [String]
    let serial: String
    let deviceName: String
    let destination: String
}

/// Makes a device surface — the mirror pane, a Mirror Wall tile, a pop-out
/// window — accept dropped files.
///
/// Two rules this modifier exists to keep:
///
/// * **The drop region is a child that only exists while the surface is on
///   screen.** A hidden keep-alive tab keeps its drop regions registered, and
///   a region deeper than the window-level router wins over it (CLAUDE.md,
///   drop routing) — so a merely-open mirror tab would swallow drops meant for
///   whatever is actually showing. Branching an *overlay* rather than the
///   modifier chain keeps `MirrorVideoView`'s identity, so the display layer
///   is never orphaned by the branch.
/// * **The overlay never takes a click.** It draws and nothing else; the drop
///   region is a `Color.clear` behind it with no gesture, so mouse-to-touch
///   still reaches the video's AppKit view.
struct DeviceDropTarget: ViewModifier {
    @Environment(AppState.self) private var state
    /// The device this surface owns. Deliberately not `targetSerials`: a wall
    /// tile and a pop-out each show a device the bar isn't pointed at, and
    /// run-on-all must never turn one drop into six.
    let serial: String?
    let deviceName: String
    /// Whether the surface is actually on screen.
    let isActive: Bool
    /// Insets the dashed frame — a tile is small enough that the full-bleed
    /// margin the full pane uses eats the caption.
    var inset: CGFloat = 14

    @State private var pending: PendingInstallDrop?

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive, let serial {
                    DeviceDropZone(
                        deviceName: deviceName, inset: inset,
                        onDrop: { dropped in accept(dropped, serial: serial) })
                }
            }
            .sheet(item: $pending) { request in
                InstallDropSheet(request: request)
            }
    }

    /// Copies start straight away; packages stop at the prompt, which is where
    /// the version comparison and the override live.
    private func accept(_ dropped: [DroppedPath], serial: String) {
        let plan = FileDropRouter.plan(dropped)
        guard !plan.isEmpty else { return }
        state.startDroppedCopies(plan, serial: serial)
        guard !plan.installs.isEmpty else { return }
        pending = PendingInstallDrop(
            paths: plan.installs, serial: serial,
            deviceName: deviceName, destination: plan.destination)
    }
}

/// The drop region itself, plus the sentence it shows while a drag is over it.
private struct DeviceDropZone: View {
    let deviceName: String
    let inset: CGFloat
    let onDrop: ([DroppedPath]) -> Void

    @State private var hovering: [DroppedPath] = []

    var body: some View {
        Color.clear
            .dropDestination(for: URL.self) { urls, _ in
                let dropped = DragPasteboard.paths(from: urls)
                hovering = []
                guard !dropped.isEmpty else { return false }
                onDrop(dropped)
                return true
            } isTargeted: { targeted in
                // `isTargeted` says something is over the view, never what —
                // the drag pasteboard is where the names come from.
                hovering = targeted ? DragPasteboard.droppedPaths() : []
            }
            .overlay {
                if !hovering.isEmpty {
                    DropAnnouncementView(announcement: announcement, inset: inset)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hovering.isEmpty)
    }

    private var announcement: DropAnnouncement {
        FileDropRouter.announcement(
            for: FileDropRouter.plan(hovering), deviceName: deviceName)
    }
}

extension View {
    /// See `DeviceDropTarget`.
    func deviceDropTarget(
        serial: String?, deviceName: String, isActive: Bool, inset: CGFloat = 14
    ) -> some View {
        modifier(DeviceDropTarget(
            serial: serial, deviceName: deviceName, isActive: isActive, inset: inset))
    }
}
