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

    /// The row at the scroll's leading (offset-0) edge — the newest side. nil
    /// before the first layout.
    @State private var leadingID: Data.Element.ID?
    /// True while the newest line sits at that edge (the user is tailing). Updated
    /// only from real position changes, so an append — which moves the "newest" id
    /// before the binding catches up — can't flip it falsely.
    @State private var isTailing = true
    /// Distance the content has been scrolled from the newest edge. `leadingID`
    /// alone only changes once a whole (possibly tall) row scrolls past the edge,
    /// so scrolling *within* the newest row wouldn't register as "scrolled away";
    /// this catches that so tailing pauses on any real scroll.
    @State private var atNewestEdge = true

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
            .scrollPosition(id: $leadingID, anchor: .top)   // .top = first row = newest
            .scaleEffect(x: 1, y: flip, anchor: .center)    // identity for .top feeds
            .onAppear { leadingID = newestID }
            .onChange(of: leadingID) { recomputeTailing() }
            .onPreferenceChange(TailOffsetKey.self) { minY in
                let atEdge = abs(minY) <= Self.edgeTolerance
                if atEdge != atNewestEdge {
                    atNewestEdge = atEdge
                    recomputeTailing()
                }
            }
            .onChange(of: newestID) { _, newest in
                if isTailing, let newest { leadingID = newest }   // cheap: first row, offset 0
            }
            .onChange(of: newestEdge) { atNewestEdge = true; isTailing = true; leadingID = newestID }
            .onChange(of: focusID) { _, id in
                guard let id else { return }
                // `scrollTo` doesn't write back into `leadingID`, so stop tailing
                // here unless the target *is* the newest row — otherwise the next
                // append would fire the follower and snap us off the match.
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

    /// Tail only when the newest row is the leading row *and* the content is
    /// parked at the newest edge — so scrolling within a tall newest row still
    /// pauses following.
    private func recomputeTailing() {
        isTailing = (leadingID == newestID) && atNewestEdge
    }

    /// Rows laid out newest-first. `.bottom` feeds reverse the display order and
    /// un-flip each row (the scroll view flip above mirrors the whole stack).
    @ViewBuilder private var orderedRows: some View {
        if newestEdge == .bottom {
            ForEach(entries.reversed()) { entry in
                row(entry).scaleEffect(x: 1, y: -1, anchor: .center)
            }
        } else {
            ForEach(entries) { entry in
                row(entry)
            }
        }
    }

    private var jumpButton: some View {
        Button {
            atNewestEdge = true
            withAnimation(.easeOut(duration: 0.25)) { leadingID = newestID }
        } label: {
            Image(systemName: newestEdge == .bottom ? "arrow.down" : "arrow.up")
                .font(.system(size: 15, weight: .semibold))
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
