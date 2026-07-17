import SwiftUI

/// Continuous scroll measurements for `LogTailViewV2`. A plain reference box —
/// deliberately *not* observable — so per-pixel geometry updates land here
/// without re-rendering the feed; only the derived `LogScrollEdges` below is
/// SwiftUI state, and it's written only when an edge actually flips.
@MainActor
private final class TailMeasure {
    var geometry = TailGeometry()
    /// Last content height reported to PerfLog, so geometry logging fires on
    /// meaningful jumps instead of per pixel.
    var lastLoggedContentHeight: CGFloat = -1
}

/// The v2 log scroller, shared by every streaming feed (JS Console, Reactotron;
/// Logcat's NSTextView pane mirrors its behavior through the same controls).
///
/// - `entries` are in display order (top → bottom); `newestEdge` says which end
///   new lines land on. A feed with a reverse-order control flips both together
///   (reversed entries + the other edge) — every mechanic below is edge-agnostic.
/// - While the viewport is parked at the newest edge it follows new lines; the
///   instant the user scrolls away it pauses (their reading wins) and new lines
///   keep rendering without shifting what they're looking at; returning to the
///   edge resumes.
/// - Jump-to-top / jump-to-bottom buttons overlay the feed; each hides at its
///   own edge, both hide when the feed is empty or too short to scroll.
/// - `.bottom`-feed content shorter than the viewport is stretched to fill it
///   with the rows pinned at the visual top — a handful of lines must not sit
///   under a screen of empty space. Structural layout never switches (the
///   stretch is a `minHeight` that overflowing content makes a no-op).
/// - `focusID` scrolls an externally-selected row (e.g. a ⌘F match) into view.
///
/// Tailing is decided by the `.scrollPosition` *binding*, not the measured
/// offset: the system writes the binding only for real scrolls (an append keeps
/// the anchored row), so a streaming burst can't flip it. Deciding from the
/// offset looked equivalent but wasn't — every append displaces the content for
/// a frame before the follower catches up, which blinked the jump button once
/// per line and, under load, paused tailing outright.
///
/// Performance: rows are always laid out **newest-first**, so the newest line
/// rests at the scroll view's offset 0. For `newestEdge == .bottom` the view is
/// flipped vertically so it still *reads* oldest-top / newest-bottom. That turns
/// tailing into "scroll to the first row" (offset 0 — cheap) instead of "scroll
/// to the last row of a huge lazy list", which forces a full layout pass — the
/// 20–30s stall a big connect-time replay burst would otherwise cause. Combined
/// with `LazyVStack`, it stays smooth with a full ring buffer. The same layout
/// keeps scrolled-away reading glitch-free: appends land past the viewport's
/// newest side and ring-trims drop rows past its oldest side, so neither moves
/// the rows on screen.
struct LogTailViewV2<Data: RandomAccessCollection, Row: View>: View
    where Data.Element: Identifiable {

    let entries: Data
    var newestEdge: VerticalEdge = .bottom
    /// Optional externally-driven scroll target (e.g. a ⌘F search match). Jumping
    /// to a row other than the newest pauses tailing (so an incoming line can't
    /// yank the view back off the match); returning to the edge resumes. Callers
    /// that don't need it leave it nil.
    var focusID: Data.Element.ID? = nil
    /// When set, the feed lays out at this fixed width and rides inside a
    /// horizontal scroll view — rows wider than the viewport are reached by
    /// scrolling the pane, not by truncating. Tail-follow writes go through
    /// `.scrollPosition` with a nil anchor, so they never touch the horizontal
    /// offset. Pass `max(viewportWidth, widestRow)` so the feed always fills
    /// the pane. On `.bottom` feeds the flip would render the horizontal
    /// indicator mirrored at the pane's top edge, so it's hidden there —
    /// two-finger panning still scrolls horizontally.
    var contentWidth: CGFloat? = nil
    @ViewBuilder var row: (Data.Element) -> Row

    /// The row pinned at the scroll's leading (offset-0) edge. Drives
    /// `.scrollPosition` for three things: keeping the viewport stable when rows
    /// are inserted at the newest edge, programmatically following the newest
    /// line while tailing, and — because the system writes it back only on real
    /// scrolls — telling a user scroll apart from streaming displacement.
    @State private var leadingID: Data.Element.ID?
    /// True while the user is parked on the newest row (tailing). Ruled by the
    /// `leadingID` binding; jump/focus actions set it eagerly so an append can't
    /// yank the view before the scroll lands.
    @State private var isTailing = true
    /// Derived edge state for the jump buttons — written only when a value
    /// flips, so scrolling and streaming don't re-render the feed.
    @State private var edges = LogScrollEdges()
    @State private var measure = TailMeasure()

    /// The newest entry: `.bottom` feeds arrive at the end of `entries`, `.top`
    /// feeds at the front. Either way it becomes the first row laid out below.
    private var newestID: Data.Element.ID? {
        newestEdge == .bottom ? entries.last?.id : entries.first?.id
    }

    /// The oldest entry — always the *last* row in the newest-first layout.
    private var oldestID: Data.Element.ID? {
        newestEdge == .bottom ? entries.first?.id : entries.last?.id
    }

    /// The viewport height, mirrored into state (guarded, half-point
    /// tolerance) so short `.bottom` feeds can stretch their content to fill
    /// it — see the `minHeight` note on `orderedRows` below.
    @State private var fillHeight: CGFloat = 0

    /// -1 flips `.bottom` feeds so a newest-first layout reads newest-at-bottom.
    private var flip: CGFloat { newestEdge == .bottom ? -1 : 1 }

    /// The `.bottom` flip mirrors the whole scroll view, which would draw the
    /// horizontal indicator upside down at the pane's top edge — hide it in
    /// that mode (the vertical indicator mirrors consistently with the flipped
    /// content, so it stays).
    private var horizontalIndicatorVisibility: ScrollIndicatorVisibility {
        newestEdge == .bottom && contentWidth != nil ? .hidden : .automatic
    }

    var body: some View {
        ScrollViewReader { proxy in
            // One scroll view for both axes — nested scroll views don't
            // forward cross-axis wheel/trackpad events on macOS, which left a
            // wrapping horizontal scroller unreachable by scrolling.
            ScrollView(contentWidth == nil ? .vertical : [.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) { orderedRows }
                    .scrollTargetLayout()
                    // The fixed feed width (widest row) when horizontal
                    // scrolling is on; a nil width is a no-op.
                    .frame(width: contentWidth, alignment: .leading)
                    // Short feeds: stretch the content to the viewport so a
                    // handful of lines reads from the visual top instead of
                    // floating in empty space (a two-axis scroll view centers
                    // undersized content vertically). `.bottom` pins the rows
                    // at the content's *end* — the flip renders that at the
                    // visual top; `.top` pins them at the start. A no-op once
                    // the content overflows, so the layout never switches
                    // structure.
                    .frame(
                        minHeight: fillHeight > 0 ? fillHeight : nil,
                        alignment: newestEdge == .bottom ? .bottom : .top
                    )
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("logtail")) }) { frame in
                        measure.geometry.contentLeadingOffset = frame.minY
                        measure.geometry.contentHeight = frame.height
                        syncEdges()
                    }
            }
            .coordinateSpace(name: "logtail")
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                measure.geometry.viewportHeight = height
                syncEdges()
                if abs(fillHeight - height) > 0.5 { fillHeight = height }
            }
            // Let a row scroll its own header into view (e.g. when an object is
            // expanded). In the flipped newest-at-bottom layout the per-row flip
            // puts a row's header at its internal *bottom*, so `.bottom` lands it
            // at the visible top; `.top` does that for the un-flipped layout.
            // No animation — the caller may re-issue this as rows lay out, and
            // snapping straight to the settled position avoids visible drift.
            .environment(\.logTailScrollToHeader) { id in
                proxy.scrollTo(id, anchor: newestEdge == .bottom ? .bottom : .top)
            }
            // A row the user starts reading (e.g. expands) can pause tailing
            // without moving the viewport: the anchored row stays put and new
            // lines land past the newest edge, so the stream can't scroll the
            // row away. Resume is the usual affordances — the jump button or
            // scrolling back to the newest edge.
            .environment(\.logTailPauseFollow) { setTailing(false) }
            // .top = first row = newest. In two-axis mode the anchor must be
            // nil: .top is UnitPoint(x: 0.5, y: 0), and 2D anchoring re-centers
            // the wide anchored row horizontally on every tail-follow write —
            // nil scrolls minimally, which still pins the newest (topmost) row
            // vertically and never touches the horizontal offset.
            .scrollPosition(id: $leadingID, anchor: contentWidth == nil ? .top : nil)
            .scrollIndicators(horizontalIndicatorVisibility, axes: .horizontal)
            .scaleEffect(x: 1, y: flip, anchor: .center)    // identity for .top feeds
            .onAppear { leadingID = newestID }
            .onChange(of: leadingID) { _, id in
                // Only real scrolls land here: appends keep the anchored row
                // (no write), and the follower writes `newestID` (a no-op flip).
                // Scrolling off the newest row pauses tailing; scrolling back
                // onto it resumes. A nil write (anchored row removed by a clear)
                // decides nothing — the feed-restart handler below does.
                guard let id else { return }
                setTailing(id == newestID)
            }
            .onChange(of: newestID) { old, newest in
                // A feed (re)starting from empty always tails — a clear while
                // paused must not leave the next stream un-followed.
                if old == nil { setTailing(true) }
                if isTailing, let newest {
                    leadingID = newest   // cheap: first row, offset 0
                } else if let anchored = leadingID, !entries.contains(where: { $0.id == anchored }) {
                    // The anchored row was cleared/trimmed away while paused —
                    // without a live anchor the scroll view can park the
                    // viewport in empty space past the content. Snap back to
                    // the newest edge and resume tailing.
                    setTailing(true)
                    leadingID = newest
                }
            }
            .onChange(of: focusID) { _, id in
                guard let id else { return }
                // Move via the binding, not `scrollTo` — the scroll view keeps
                // anchoring to the binding's row on every content change, so a
                // proxy scroll gets yanked back to the old anchor by the next
                // append. Pausing is implied: the binding write lands in the
                // `leadingID` observer above.
                setTailing(id == newestID)
                withAnimation(.easeInOut(duration: 0.15)) { leadingID = id }
            }
            .overlay {
                LogJumpControls(
                    edges: edges,
                    enabled: !entries.isEmpty,
                    newestEdge: newestEdge,
                    onJumpToTop: { jump(to: .top) },
                    onJumpToBottom: { jump(to: .bottom) }
                )
            }
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

    private func setTailing(_ tailing: Bool) {
        if isTailing != tailing { isTailing = tailing }
        syncEdges()
    }

    private func syncEdges() {
        var derived = measure.geometry.edges(newestEdge: newestEdge)
        // The newest side is ruled by the tailing state, not the instantaneous
        // offset: every append displaces the content for a frame before the
        // follower catches up, and an offset-driven edge would blink the button
        // once per streamed line.
        if newestEdge == .top {
            derived.atTop = isTailing
        } else {
            derived.atBottom = isTailing
        }
        if derived != edges { edges = derived }
        logGeometryIfNotable()
    }

    /// PerfLog trace for the blank-canvas investigation: content height vs
    /// entry count exposes inflated lazy estimates, and offset shows where the
    /// viewport is parked. Logged on ≥500pt content-height jumps only.
    private func logGeometryIfNotable() {
        let geometry = measure.geometry
        guard abs(geometry.contentHeight - measure.lastLoggedContentHeight) > 500 else { return }
        measure.lastLoggedContentHeight = geometry.contentHeight
        PerfLog.feed.info("""
            geometry: content=\(Int(geometry.contentHeight), privacy: .public) \
            viewport=\(Int(geometry.viewportHeight), privacy: .public) \
            offset=\(Int(geometry.contentLeadingOffset), privacy: .public) \
            entries=\(entries.count, privacy: .public) \
            fill=\(Int(fillHeight), privacy: .public)
            """)
    }

    /// Both jumps move by SETTING the binding — never `proxy.scrollTo`, whose
    /// move the scroll view undoes on the next append (it keeps anchoring to
    /// the binding's row on every content change). Anchoring the oldest row's
    /// top clamps to the far end of the scroll, and the binding then holds the
    /// viewport there while new lines stream in. Snap, no animation: an
    /// animated far scroll lays out every lazy row it passes, and its
    /// intermediate binding write-backs would pause a just-started tail.
    private func jump(to edge: VerticalEdge) {
        if edge == newestEdge {
            setTailing(true)
            leadingID = newestID
        } else {
            setTailing(false)
            leadingID = oldestID
        }
    }
}

/// A row can call this to scroll its own header into view (e.g. right after
/// expanding a large object), so growth doesn't leave the viewport at the
/// object's end. Injected by `LogTailViewV2` with the correct anchor for its
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

/// A row can call this to pause tail-follow in place — used when the user
/// starts reading a row (expands it), so streaming appends can't scroll it
/// away. Injected by `LogTailViewV2`; a no-op outside one.
private struct LogTailPauseKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var logTailPauseFollow: @MainActor () -> Void {
        get { self[LogTailPauseKey.self] }
        set { self[LogTailPauseKey.self] = newValue }
    }
}
