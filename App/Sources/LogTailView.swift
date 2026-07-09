import SwiftUI

/// A log viewer with directional smart-tailing, shared by every streaming feed
/// (Logcat, Reactotron, JS Console).
///
/// - `entries` are in display order (top → bottom); `newestEdge` says which end
///   new lines land on, so the same view tails *down* (newest at bottom) or *up*
///   (newest at top) — the auto-scroll target follows the newest line.
/// - While the user is parked at the newest edge it follows new lines; the
///   instant they scroll away it pauses (their reading wins); returning to the
///   edge resumes. A "jump to newest" button shows only while paused.
/// - `focusID` scrolls an externally-selected row (e.g. a ⌘F match) into view.
///
/// Performance: rows are always laid out **newest-first**, so the newest line
/// rests at the scroll view's offset 0. For `newestEdge == .bottom` the view is
/// flipped vertically so it still *reads* oldest-top / newest-bottom. That turns
/// tailing into "scroll to the first row" (offset 0 — cheap) instead of "scroll
/// to the last row of a huge lazy list", which forces a full layout pass — the
/// 20–30s stall a big connect-time replay burst would otherwise cause. Combined
/// with `LazyVStack`, it stays smooth with a full ring buffer.
struct LogTailView<Data: RandomAccessCollection, Row: View>: View
    where Data.Element: Identifiable {

    let entries: Data
    var newestEdge: VerticalEdge = .bottom
    /// Optional externally-driven scroll target (e.g. a ⌘F search match). Jumping
    /// to a row other than the newest pauses tailing (so an incoming line can't
    /// yank the view back off the match); returning to the edge resumes. Callers
    /// that don't need it leave it nil.
    var focusID: Data.Element.ID? = nil
    @ViewBuilder var row: (Data.Element) -> Row

    /// The row pinned at the scroll's leading (offset-0) edge. Drives
    /// `.scrollPosition` for two things: keeping the viewport stable when rows are
    /// inserted at the newest edge, and programmatically following the newest line
    /// while tailing. It is *not* consulted to decide whether we're tailing — that
    /// is the offset's job (below), because this binding lags and the follow
    /// overwrites it, which used to race an append into snapping the view back.
    @State private var leadingID: Data.Element.ID?
    /// True while the content is parked at the newest edge (the user is tailing).
    /// Derived solely from the measured scroll offset: content-top at the edge
    /// (`minY ≈ 0`) *is* the newest row parked at the edge, in either flip mode, so
    /// one signal decides it — no coupling with the laggy `leadingID` binding.
    @State private var isTailing = true

    /// How far (points) the content may sit from the newest edge and still count
    /// as "parked at the edge", covering sub-pixel rounding and a tail auto-scroll.
    private static var edgeTolerance: CGFloat { 24 }

    /// The newest entry: `.bottom` feeds arrive at the end of `entries`, `.top`
    /// feeds at the front. Either way it becomes the first row laid out below.
    private var newestID: Data.Element.ID? {
        newestEdge == .bottom ? entries.last?.id : entries.first?.id
    }

    /// -1 flips `.bottom` feeds so a newest-first layout reads newest-at-bottom.
    private var flip: CGFloat { newestEdge == .bottom ? -1 : 1 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) { orderedRows }
                    .scrollTargetLayout()
                    .background(
                        GeometryReader { geo in
                            // Content top relative to the scroll view; ~0 at the
                            // newest edge, growing in magnitude as the user scrolls
                            // away. Sign flips with the layout flip, so compare the
                            // magnitude.
                            Color.clear.preference(
                                key: TailOffsetKey.self,
                                value: geo.frame(in: .named("logtail")).minY
                            )
                        }
                    )
            }
            .coordinateSpace(name: "logtail")
            // Let a row scroll its own header into view (e.g. when an object is
            // expanded). In the flipped newest-at-bottom layout the per-row flip
            // puts a row's header at its internal *bottom*, so `.bottom` lands it
            // at the visible top; `.top` does that for the un-flipped layout.
            // No animation — the caller may re-issue this as rows lay out, and
            // snapping straight to the settled position avoids visible drift.
            .environment(\.logTailScrollToHeader) { id in
                proxy.scrollTo(id, anchor: newestEdge == .bottom ? .bottom : .top)
            }
            .scrollPosition(id: $leadingID, anchor: .top)   // .top = first row = newest
            .scaleEffect(x: 1, y: flip, anchor: .center)    // identity for .top feeds
            .onAppear { leadingID = newestID }
            .onPreferenceChange(TailOffsetKey.self) { minY in
                // The offset is the single source of truth for tailing: at the
                // newest edge the content top sits at ~0; any real scroll away
                // grows its magnitude past the tolerance and pauses following.
                let atEdge = abs(minY) <= Self.edgeTolerance
                if atEdge != isTailing { isTailing = atEdge }
            }
            .onChange(of: newestID) { _, newest in
                if isTailing, let newest { leadingID = newest }   // cheap: first row, offset 0
            }
            .onChange(of: newestEdge) { isTailing = true; leadingID = newestID }
            .onChange(of: focusID) { _, id in
                guard let id else { return }
                // `scrollTo` doesn't write back into `leadingID`, so stop tailing
                // here unless the target *is* the newest row — otherwise the next
                // append would fire the follower and snap us off the match. The
                // offset settles this once the scroll lands, but set it eagerly so
                // an append in the interim can't yank us off the match.
                isTailing = (id == newestID)
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
            .overlay(alignment: newestEdge == .bottom ? .bottomTrailing : .topTrailing) {
                if !isTailing {
                    jumpButton
                        .padding(16)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.2), value: isTailing)
        }
    }

    /// Rows laid out newest-first. `.bottom` feeds reverse the display order and
    /// un-flip each row (the scroll view flip above mirrors the whole stack). The
    /// per-row flip is wrapped in a `VStack` so it applies to one settled view: a
    /// `row` builder returning multiple views (e.g. a row + `Divider`) is a bare
    /// `TupleView`, and `scaleEffect` on that doesn't un-flip cleanly, which left
    /// the rows upside-down.
    @ViewBuilder private var orderedRows: some View {
        if newestEdge == .bottom {
            ForEach(entries.reversed()) { entry in
                VStack(spacing: 0) { row(entry) }
                    .scaleEffect(x: 1, y: -1, anchor: .center)
            }
        } else {
            ForEach(entries) { entry in
                row(entry)
            }
        }
    }

    private var jumpButton: some View {
        Button {
            isTailing = true
            withAnimation(.easeOut(duration: 0.25)) { leadingID = newestID }
        } label: {
            Image(systemName: newestEdge == .bottom ? "arrow.down" : "arrow.up")
                .font(.app(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.tint, in: Circle())
                .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help("Jump to the newest logs")
        .accessibilityLabel("Jump to newest")
    }
}

/// Content-top offset of a `LogTailView` scroll, in its "logtail" coordinate
/// space — used to detect scroll-away within a tall newest row.
private struct TailOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A row can call this to scroll its own header into view (e.g. right after
/// expanding a large object), so growth doesn't leave the viewport at the
/// object's end. Injected by `LogTailView` with the correct anchor for its
/// layout; a no-op outside one.
private struct LogTailScrollKey: EnvironmentKey {
    static let defaultValue: @MainActor (AnyHashable) -> Void = { _ in }
}

extension EnvironmentValues {
    var logTailScrollToHeader: @MainActor (AnyHashable) -> Void {
        get { self[LogTailScrollKey.self] }
        set { self[LogTailScrollKey.self] = newValue }
    }
}
