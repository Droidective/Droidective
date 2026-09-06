import ADBKit
import SwiftUI

/// A feature's own file drop zone, with everything it can't use handed to the
/// window's router instead of dropped on the floor.
///
/// Why every feature zone needs this rather than just returning `false`: a drop
/// goes to the *deepest* region under the cursor and never falls through to an
/// ancestor, and a hidden keep-alive tab keeps its drop regions registered. So
/// a pane that declines a file doesn't give the window-level router a turn — it
/// swallows the drop, and it does so whether or not that pane is the one on
/// screen. Before this, a video dragged onto Reactotron went nowhere because
/// an APK Studio tab happened to be open behind it.
///
/// The hover state follows the same split: a file this feature would take
/// lights its own drop zone, and anything else gets the router's announcement,
/// so the pane never glows "drop your APK here" at a `.mp4`.
struct FeatureFileDrop: ViewModifier {
    @Environment(AppState.self) private var state
    /// The subset of a drop this feature wants, in the order it arrived.
    let claims: ([URL]) -> [URL]
    /// Take the claimed files.
    let perform: ([URL]) -> Void
    /// Drives the feature's own drop-zone highlight.
    var isTargeted: (Bool) -> Void = { _ in }

    @State private var routing: [DroppedPath] = []

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                routing = []
                isTargeted(false)
                let mine = claims(urls)
                if !mine.isEmpty {
                    perform(mine)
                    return true
                }
                let dropped = DragPasteboard.paths(from: urls)
                guard !dropped.isEmpty else { return false }
                state.routeDrop(dropped)
                return true
            } isTargeted: { targeted in
                guard targeted else {
                    routing = []
                    isTargeted(false)
                    return
                }
                let hovering = DragPasteboard.droppedPaths()
                let mine = claims(hovering.map { URL(fileURLWithPath: $0.path) })
                routing = mine.isEmpty ? hovering : []
                isTargeted(!mine.isEmpty)
            }
            .overlay {
                if let announcement = routedAnnouncement {
                    DropAnnouncementView(announcement: announcement, inset: 18)
                }
            }
    }

    private var routedAnnouncement: DropAnnouncement? {
        guard !routing.isEmpty else { return nil }
        return FileDropRouter.announcement(
            for: FileDropRouter.routes(
                for: routing, hasDevice: state.targetSerials.first != nil))
    }
}

extension View {
    /// See `FeatureFileDrop`.
    func featureFileDrop(
        claims: @escaping ([URL]) -> [URL],
        perform: @escaping ([URL]) -> Void,
        isTargeted: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(FeatureFileDrop(claims: claims, perform: perform, isTargeted: isTargeted))
    }

    /// The common case: a feature that takes one file of a given extension.
    func featureFileDrop(
        extension ext: String,
        perform: @escaping (URL) -> Void,
        isTargeted: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        featureFileDrop(
            claims: { urls in
                urls.first { $0.pathExtension.lowercased() == ext }.map { [$0] } ?? []
            },
            perform: { urls in urls.first.map(perform) },
            isTargeted: isTargeted)
    }
}
