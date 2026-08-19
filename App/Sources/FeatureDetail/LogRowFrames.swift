import AppKit
import SwiftUI

/// Where each visible row sits in a log feed, so a drag can tell which rows it
/// has crossed — a row only ever knows its own frame.
///
/// A plain reference box, deliberately *not* observable: rows report into it on
/// every scroll and layout pass, and holding this in `@State` would re-render the
/// feed per pixel. `LogTailViewV2` keeps its own measurements in one for the same
/// reason.
@MainActor final class LogRowFrames<ID: Hashable> {
    var frames: [ID: CGRect] = [:]

    /// The row whose band contains `y`. A drag that runs past the first or last
    /// row answers with the nearest one, so sweeping off the edge of the feed
    /// selects to the end instead of stopping where the pointer left the rows.
    func row(at y: CGFloat, among ids: [ID]) -> ID? {
        var nearest: (id: ID, distance: CGFloat)?
        for id in ids {
            guard let frame = frames[id] else { continue }
            if y >= frame.minY, y <= frame.maxY { return id }
            let distance = min(abs(y - frame.minY), abs(y - frame.maxY))
            if nearest == nil || distance < nearest!.distance { nearest = (id, distance) }
        }
        return nearest?.id
    }
}

extension View {
    /// Report this row's frame in the feed's coordinate space, for drag-select
    /// hit-testing. Paired with `.coordinateSpace(name:)` on the feed.
    func reportingRowFrame<ID: Hashable>(
        _ id: ID, in space: String, into frames: LogRowFrames<ID>
    ) -> some View {
        background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(space))
                Color.clear
                    .onAppear { frames.frames[id] = frame }
                    .onChange(of: frame) { _, new in frames.frames[id] = new }
            }
        }
    }
}

/// How a click means to change a selection, read from the modifiers the event
/// carried. SwiftUI's tap gesture doesn't report them, and composing one gesture
/// per modifier makes the plain tap's precedence depend on gesture order — so the
/// event's own flags are read as the tap is handled.
enum LogRowClick {
    /// ⌘: add or drop this row, leaving the rest alone.
    case toggle
    /// ⇧: take the range from the last row picked.
    case extend
    /// No modifier: the row's own business (expand/collapse), and any selection
    /// is dropped.
    case plain

    init(modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            self = .toggle
        } else if modifiers.contains(.shift) {
            self = .extend
        } else {
            self = .plain
        }
    }

    static var current: LogRowClick { LogRowClick(modifiers: NSEvent.modifierFlags) }
}
