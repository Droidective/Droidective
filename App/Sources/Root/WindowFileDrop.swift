import ADBKit
import SwiftUI

/// The catch-all under every feature: a file dropped on a screen that has
/// nothing to do with it still lands somewhere useful.
///
/// An APK on Reactotron opens the package screen; a video opens the editor;
/// anything else copies to the selected device. Nothing is silently swallowed,
/// and the overlay says which of those is about to happen before the button
/// comes up — a file that teleports the user into another tab with no
/// explanation is worse than one that does nothing.
///
/// **Where this goes matters.** Drop targeting has two different rules and
/// they were learned separately: a region in a deeper *view* (an overlay, a
/// feature's own zone, a hidden keep-alive tab's) beats one on an ancestor,
/// but among modifiers stacked on the *same* view the outermost wins. So this
/// is applied last on the pane content — after the tab-drag target it must
/// out-rank — while the tab shield stays an overlay, which is a child and
/// therefore still beats it whenever a tab drag is in flight.
struct WindowFileDropModifier: ViewModifier {
    @Environment(AppState.self) private var state
    /// Only the tab on screen offers the fallback. A hidden keep-alive tab
    /// keeps every region it registers, and one more full-pane target per
    /// mounted tab is exactly how a drop ends up somewhere nobody can see.
    let isActive: Bool
    @State private var hovering: [DroppedPath] = []

    func body(content: Content) -> some View {
        if isActive { dropping(content) } else { content }
    }

    private func dropping(_ content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                let dropped = DragPasteboard.paths(from: urls)
                hovering = []
                guard !dropped.isEmpty else { return false }
                state.routeDrop(dropped)
                return true
            } isTargeted: { targeted in
                // `isTargeted` says something is over the view, never what —
                // the drag pasteboard is where the names come from.
                hovering = targeted ? DragPasteboard.droppedPaths() : []
            }
            .overlay {
                if let announcement = RoutedDrop.announcement(
                    for: hovering, hasDevice: state.targetSerials.first != nil) {
                    DropAnnouncementView(announcement: announcement, inset: 18)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hovering.isEmpty)
    }
}

/// The sentence a routed drop shows while it is still in the air.
enum RoutedDrop {
    static func announcement(for dropped: [DroppedPath], hasDevice: Bool) -> DropAnnouncement? {
        guard !dropped.isEmpty else { return nil }
        return FileDropRouter.announcement(
            for: FileDropRouter.routes(for: dropped, hasDevice: hasDevice))
    }
}

