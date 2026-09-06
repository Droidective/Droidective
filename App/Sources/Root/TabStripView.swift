import ADBKit
import SwiftUI
import UniformTypeIdentifiers

/// One editor pane's tab strip. Tabs scroll sideways when they overflow (‹ ›
/// arrows appear); the active one is highlighted and kept in view. A recording
/// tab shows a pulsing red dot. A trailing + opens the search palette. Tabs drag
/// to reorder within the pane, or onto the other pane / the split zone to move.
struct TabStripView: View {
    @Environment(AppState.self) private var state
    /// Which editor group (pane) this strip drives.
    let group: Int
    /// Measured widths for overflow detection and drop-side (before/after) math.
    @State private var chipWidths: [String: CGFloat] = [:]
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    /// The content's live horizontal scroll offset (0 = fully left). The ‹ ›
    /// arrows derive the first visible tab from this, so they step from where
    /// the strip *actually* is — a stored index went stale the moment the user
    /// trackpad-scrolled or the active tab auto-centered, making the first
    /// arrow click a no-op.
    @State private var scrollOffset: CGFloat = 0
    /// Where the insertion guideline shows during a reorder drag (nil = none).
    @State private var dropSlot: TabDropSlot?

    /// Home never renders as a chip — it rides the permanent house button at
    /// the strip's start instead, so it can't be closed away or lost in the
    /// tab overflow.
    private var tabIDs: [String] { state.openTabIDs(inGroup: group).filter { $0 != "home" } }
    private var activeID: String? { state.activeTab(inGroup: group) }
    /// The tabs are wider than the visible strip — show the ‹ › scroll arrows.
    private var overflowing: Bool { contentWidth > viewportWidth + 1 }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                if group == 0 {
                    homeButton
                        .padding(.horizontal, 6)
                    Divider().frame(height: 20)
                }
                if overflowing {
                    scrollArrow("chevron.left", by: -1, help: "Scroll tabs left", proxy)
                    Divider().frame(height: 20)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabIDs, id: \.self) { id in
                            chip(id)
                        }
                        newTabButton
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .background(widthReader { contentWidth = $0 })
                    .background(scrollOffsetReader)
                    // Slide chips into place on reorder (and when tabs
                    // open/close) instead of snapping.
                    .animation(.easeInOut(duration: 0.15), value: tabIDs)
                }
                .coordinateSpace(name: "tabStrip")
                .frame(maxWidth: .infinity)
                .background(widthReader { viewportWidth = $0 })
                .onChange(of: activeID) { _, id in
                    // Bring this pane's active tab into view when it changes off-screen.
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                }

                if overflowing {
                    Divider().frame(height: 20)
                    scrollArrow("chevron.right", by: 1, help: "Scroll tabs right", proxy)
                }
            }
        }
        .frame(height: 36)
        .background(.bgSurface)
        .overlay(alignment: .bottom) { Divider() }
        // The strip's dead space (past the last chip, around the + button) is
        // a drop target too: dropping there appends the tab to this pane —
        // the natural way to drag a tab across a split. Chip drops sit deeper,
        // so precise before/after placement still wins over this catch-all.
        .onDrop(of: [.workspaceTab], delegate: TabPaneDrop(
            state: state,
            onDrop: { drag in
                state.acceptTabDrop(drag, on: .strip(group: group, before: nil))
            }
        ))
        // A drop that lands outside this strip's chips (the pane content, dead
        // strip space, the other pane) never reaches the chips' drop delegates,
        // so their `setSlot(nil)` cleanup can't run and the insertion guideline
        // stayed painted. The drag's single source of truth is `draggingTabID` —
        // clear the slot whenever it resets, wherever the drop landed.
        .onChange(of: state.anyTabDrag) { _, drag in
            if drag == nil { dropSlot = nil }
        }
    }

    /// Reports the content's minX in the strip's coordinate space — 0 when fully
    /// left, negative as the strip scrolls right.
    private var scrollOffsetReader: some View {
        GeometryReader { geo in
            Color.clear.onChange(of: geo.frame(in: .named("tabStrip")).minX, initial: true) { _, minX in
                scrollOffset = -minX
            }
        }
    }

    /// The index of the first chip whose trailing edge is inside the viewport,
    /// computed from the measured chip widths and the live scroll offset.
    private var firstVisibleIndex: Int {
        var x: CGFloat = 8 // leading padding
        for (index, id) in tabIDs.enumerated() {
            let width = chipWidths[id] ?? 0
            if x + width > scrollOffset + 1 { return index }
            x += width + 4 // chip spacing
        }
        return max(tabIDs.count - 1, 0)
    }

    /// Nudge the horizontal scroll by a few tabs (single click) — reveals hidden
    /// tabs without changing which tab is focused.
    private func scrollArrow(_ icon: String, by direction: Int, help: String, _ proxy: ScrollViewProxy) -> some View {
        Button {
            let ids = tabIDs
            guard !ids.isEmpty else { return }
            let target = min(max(firstVisibleIndex + direction * 3, 0), ids.count - 1)
            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(ids[target], anchor: .leading) }
        } label: {
            Image(systemName: icon)
                .font(.app(.caption).weight(.semibold))
                .foregroundStyle(.textMuted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func chip(_ id: String) -> some View {
        TabChip(
            title: Self.title(id, role: state.selectedRole),
            icon: Self.icon(id),
            isActive: id == activeID,
            isRecording: state.tabIsRecording(id),
            onSelect: { state.requestFeature(id) },
            onClose: { state.closeTab(id) }
        )
        .id(id)
        .background(widthReader { chipWidths[id] = $0 })
        .overlay(alignment: .leading) { guideline(visible: dropSlot == TabDropSlot(targetID: id, after: false)) }
        .overlay(alignment: .trailing) { guideline(visible: dropSlot == TabDropSlot(targetID: id, after: true)) }
        // While this chip rides the cursor as the drag image, fade the
        // stationary original so the tab doesn't read as duplicated.
        .opacity(state.draggingTabID == id ? 0.3 : 1)
        .modifier(TabChipDrag(
            id: id, title: Self.title(id, role: state.selectedRole), icon: Self.icon(id)))
        .onDrop(of: [.workspaceTab], delegate: TabReorderDrop(
            targetID: id,
            width: chipWidths[id] ?? 0,
            order: tabIDs,
            state: state,
            setSlot: { dropSlot = $0 },
            move: { drag, before in
                state.acceptTabDrop(drag, on: .strip(group: group, before: before))
            }
        ))
        .contextMenu { tabMenu(for: id) }
    }

    /// A thin accent bar between chips marking where a reordered tab will land.
    @ViewBuilder private func guideline(visible: Bool) -> some View {
        if visible {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.brandAccent)
                .frame(width: 2, height: 22)
        }
    }

    /// Reports a view's width via a background GeometryReader (the pattern the
    /// sidebar uses to measure rows).
    private func widthReader(_ update: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { geo in
            Color.clear.onChange(of: geo.size.width, initial: true) { _, width in update(width) }
        }
    }

    /// Right-click menu for a tab: move it to a window of its own or to another
    /// open one, move it across the split, or close it (or everything else in
    /// this pane).
    @ViewBuilder
    private func tabMenu(for id: String) -> some View {
        Button("Open in New Window") { state.beginHandoff(id, to: .newWindow(frame: nil)) }
            // A workspace whose only tab left would not be a move, it would be
            // the window moving — and the window already moves. Moving it into
            // an *existing* window is still allowed, so only this item is off.
            .disabled(!state.canDetachTabToNewWindow(id))
        let targets = state.handoffTargets
        if !targets.isEmpty {
            Menu("Move to Window") {
                ForEach(targets, id: \.id) { target in
                    Button(target.label) { state.beginHandoff(id, to: .window(target.id, slot: nil)) }
                }
            }
            .disabled(!state.canDetachTab(id))
        }
        Divider()
        if state.isSplit {
            Button("Move to Other Pane") { state.moveTab(id, toGroup: group == 0 ? 1 : 0) }
        } else {
            Button("Split: Move to New Pane") { state.splitTab(id) }
        }
        Divider()
        Button("Close Tab") { state.closeTab(id) }
        Button("Close Other Tabs") { state.closeOtherTabs(than: id, inGroup: group) }
            .disabled(tabIDs.count < 2)
    }

    /// The fixed Home entry leading the strip — an icon-only chip that opens
    /// (or re-focuses) Home; accented while Home is the active tab anywhere.
    private var homeButton: some View {
        Button {
            state.requestFeature("home")
        } label: {
            Image(systemName: "house")
                .font(.app(.callout).weight(.medium))
                .foregroundStyle(state.activeTabID == "home"
                    ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.textMuted))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(state.activeTabID == "home"
                            ? AnyShapeStyle(.brandAccent.opacity(0.14)) : AnyShapeStyle(.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Home — overview & getting started")
        .accessibilityLabel("Home")
    }

    private var newTabButton: some View {
        Button {
            // Focus this pane first so the chosen feature opens here, not in
            // whichever pane happened to be focused.
            state.focusGroup(group)
            state.openPalette?()
        } label: {
            Image(systemName: "plus")
                .font(.app(.callout).weight(.medium))
                .foregroundStyle(.textMuted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New tab (⌘T)")
    }

    /// Title shown on a tab chip — the role-presented registry title, or the
    /// standalone Home / Manage Features / About screens which aren't
    /// registry features.
    static func title(_ id: String, role: UserRole?) -> String {
        switch id {
        case "home": return "Home"
        case "catalog": return "Manage Features"
        case "about": return "About"
        case "apk-open": return "Install APK"
        default:
            return FeatureRegistry.byID[id]
                .map { FeatureRegistry.presented($0, for: role).title } ?? id
        }
    }

    static func icon(_ id: String) -> String {
        switch id {
        case "home": return "house"
        case "catalog": return "square.grid.2x2"
        case "about": return "info.circle"
        case "apk-open": return "arrow.down.app"
        default: return FeatureRegistry.byID[id]?.icon ?? "square"
        }
    }
}

/// One tab in the strip. The close button appears on hover (or when active) but
/// its width is always reserved, so the chip doesn't jump as the pointer moves.
private struct TabChip: View {
    let title: String
    let icon: String
    let isActive: Bool
    let isRecording: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            leading
            Text(title)
                .font(.app(.callout))
                .lineLimit(1)
                .foregroundStyle(isActive ? AnyShapeStyle(.textMain) : AnyShapeStyle(.textMuted))
            closeButton
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 28)
        .frame(maxWidth: 190)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? AnyShapeStyle(.brandAccent.opacity(0.14)) : AnyShapeStyle(.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Opens this tab")
    }

    @ViewBuilder private var leading: some View {
        if isRecording {
            // Pulsing red dot while the tab is recording (screen / mirror /
            // performance / network capture).
            Image(systemName: "circle.fill")
                .font(.app(size: 8))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
        } else {
            Image(systemName: icon)
                .font(.app(.caption))
                .foregroundStyle(isActive ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.textMuted))
        }
    }

    @ViewBuilder private var closeButton: some View {
        if hovering || isActive {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.app(size: 9, weight: .bold))
                    .foregroundStyle(.textMuted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // ⌘W closes the *active* tab, so only hint it on the active chip.
            .help(isActive ? "Close tab (⌘W)" : "Close tab")
            .accessibilityLabel("Close \(title)")
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }
}

/// Where the strip's insertion guideline sits: before or after a target chip.
struct TabDropSlot: Equatable {
    let targetID: String
    let after: Bool
}

/// Drop delegate for reordering tabs: dropping a dragged tab on a chip's left
/// half inserts it before that chip, on the right half after it, and reports the
/// insertion slot so the strip can draw a guideline. `move` is a no-op when the
/// ids resolve to the same slot (handled by `SidebarOrdering`).
///
/// The dragged id is read live from `AppState.draggingTabID`, never captured:
/// after a drop the chips shift under the stationary cursor and the dying drag
/// session can deliver one more dropEntered/dropUpdated to whichever chip lands
/// there — a frozen id would repaint the guideline that `performDrop` just
/// cleared. (The terminal rail's delegates read their manager live for the
/// same reason.)
private struct TabReorderDrop: DropDelegate {
    let targetID: String
    let width: CGFloat
    let order: [String]
    let state: AppState
    let setSlot: (TabDropSlot?) -> Void
    let move: (_ drag: TabDrag, _ beforeTargetID: String?) -> Void

    /// The app-wide drag, so a tab dragged from *another* window is accepted
    /// here too — not just this window's own reorders.
    private var drag: TabDrag? { state.anyTabDrag }

    func validateDrop(info: DropInfo) -> Bool { drag != nil }
    func dropEntered(info: DropInfo) { setSlot(slot(info)) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        setSlot(slot(info))
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { setSlot(nil) }

    func performDrop(info: DropInfo) -> Bool {
        setSlot(nil)
        guard let drag else { return false }
        // Dropping a tab on itself is a no-op — but only when it really is the
        // same tab in the same window. Two windows can each have a tab with
        // this id; moving one onto the other is a merge, not a no-op.
        guard drag.featureID != targetID || drag.source != state.id else {
            state.core.tabDrag = nil
            return false
        }
        let dropAfter = width > 0 && info.location.x > width / 2
        if dropAfter, let index = order.firstIndex(of: targetID) {
            // After the target = before the tab that follows it (or to the end).
            move(drag, order.indices.contains(index + 1) ? order[index + 1] : nil)
        } else {
            move(drag, targetID)
        }
        return true
    }

    /// The slot under the cursor — nil while over the dragged chip itself,
    /// and nil once the drag has ended (a trailing enter/update after the drop).
    private func slot(_ info: DropInfo) -> TabDropSlot? {
        guard let drag else { return nil }
        guard drag.featureID != targetID || drag.source != state.id else { return nil }
        return TabDropSlot(targetID: targetID, after: width > 0 && info.location.x > width / 2)
    }
}

/// Starts a chip's drag as an AppKit session (see `TabDragSource`) and, when it
/// is released away from every Droidective window, tears the tab off into a new
/// one at that point.
///
/// A `DragGesture` rather than `.onDrag`, because only an `NSDraggingSource`
/// reports whether a drop was accepted and where it landed. The item on the
/// pasteboard is unchanged, so every drop target still works exactly as before.
private struct TabChipDrag: ViewModifier {
    @Environment(AppState.self) private var state
    @Environment(\.displayScale) private var displayScale
    let id: String
    let title: String
    let icon: String
    @State private var starter = TabDragStarter()

    func body(content: Content) -> some View {
        content
            .background(TabDragSource(starter: starter))
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .local)
                    // `onChanged` fires continuously, so only the first one may
                    // start a session. The guard is the live drag itself rather
                    // than a local "already started" flag: SwiftUI's gesture is
                    // cancelled the moment AppKit's drag loop takes the mouse,
                    // so its `onEnded` cannot be relied on to re-arm anything —
                    // a flag latched on and the just-dragged chip became
                    // undraggable until its view was rebuilt. `tabDrag` is
                    // cleared by whichever drop took the tab, by the session
                    // reporting back, and failing both by `installDragJanitor`
                    // on the next mouse event, so it always re-arms.
                    .onChanged { value in
                        guard state.anyTabDrag == nil else { return }
                        begin(grabbedAt: value.startLocation)
                    }
            )
    }

    private func begin(grabbedAt point: CGPoint) {
        state.draggingTabID = id
        starter.begin(
            featureID: id,
            image: dragImage(),
            grabOffset: CGSize(width: point.x, height: point.y),
            canTearOff: state.canDetachTabToNewWindow(id),
            onEnded: { outcome in
                // Whatever happened, the drag is over: a drop target that took
                // it has already cleared this, and one that did not never will.
                state.core.tabDrag = nil
                guard state.canDetachTabToNewWindow(id),
                      TabDetachPolicy.shouldTearOff(
                          accepted: outcome.accepted,
                          cancelled: outcome.cancelled,
                          point: outcome.screenPoint,
                          windowFrames: outcome.windowFrames)
                else { return }
                state.beginHandoff(id, to: .newWindow(frame: tornOffFrame(outcome)))
            })
    }

    /// The chip itself, rendered once at drag start, so what rides the cursor
    /// is the tab rather than a system placeholder.
    private func dragImage() -> NSImage? {
        let renderer = ImageRenderer(content:
            TabChipGhost(title: title, icon: icon)
                .environment(\.colorScheme, state.nsWindow?.effectiveAppearance
                    .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light))
        renderer.scale = displayScale
        return renderer.nsImage
    }

    /// Where the new window goes: the same size as the one the tab came from,
    /// positioned so the chip lands back under the cursor, clamped onto the
    /// screen the drop happened on.
    private func tornOffFrame(_ outcome: TabDragOutcome) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(outcome.screenPoint) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let rect = TearOffFrame.frame(
            dropPoint: TearOffFrame.Point(
                x: outcome.screenPoint.x, y: outcome.screenPoint.y),
            grabOffset: TearOffFrame.Size(
                width: outcome.grabOffset.width, height: outcome.grabOffset.height),
            // The moved tab is the only one in the new window, so it lands in
            // the strip's *first* slot — not wherever this chip happened to
            // sit. The vertical inset is measured (the strip is at the same
            // height in both windows); the horizontal one is the fixed layout
            // offset of the first chip, and being a few points out is
            // imperceptible next to the clamp that keeps the window on screen.
            stripOrigin: TearOffFrame.Point(
                x: TabStripMetrics.firstChipInset, y: outcome.chipOriginInWindow.y),
            sourceSize: TearOffFrame.Size(
                width: outcome.sourceWindowFrame.width,
                height: outcome.sourceWindowFrame.height),
            screen: TearOffFrame.Rect(
                x: visible.minX, y: visible.minY,
                width: visible.width, height: visible.height),
            minimum: TearOffFrame.Size(
                width: TabStripMetrics.minimumWindowWidth,
                height: TabStripMetrics.minimumWindowHeight))
        return NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

/// Layout constants the tear-off geometry needs, named rather than inlined so
/// the numbers can be traced back to the views that produce them.
enum TabStripMetrics {
    /// Where the first chip's leading edge sits inside the window: the Home
    /// button (28 pt) with its 6 pt padding either side, the divider, and the
    /// scroll content's 8 pt leading padding.
    static let firstChipInset: Double = 6 + 28 + 6 + 1 + 8
    /// `WorkspaceHost.minWindowWidth`'s floor, and `RootView`'s minimum height.
    static let minimumWindowWidth: Double = 760
    static let minimumWindowHeight: Double = 480
}

/// A chip drawn purely to be rasterised as the drag image — the real one is a
/// `TabChip`, which is bound to live state a renderer has no business touching.
private struct TabChipGhost: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.app(.caption))
                .foregroundStyle(.brandAccent)
            Text(title)
                .font(.app(.callout))
                .lineLimit(1)
                .foregroundStyle(.textMain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 15)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(.bgSurface)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        )
        .padding(8)
    }
}

