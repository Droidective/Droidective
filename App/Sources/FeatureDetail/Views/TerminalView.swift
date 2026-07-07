import ADBKit
import SwiftUI
import UniformTypeIdentifiers

/// The Terminal feature's open shells. Owned by `AppState` (like
/// `reactotronSession`) so every session, its scrollback, the tab names, and
/// the group layout survive leaving the feature. Each tab is an independent
/// PTY-backed zsh; where each tab sits (groups, order) lives in the pure
/// `TerminalTabs` model so the moves are unit-tested in ADBKit.
@MainActor
@Observable
final class TerminalManager {
    struct Tab: Identifiable {
        let id = UUID()
        var name: String
        let session: TerminalSession
    }

    private(set) var layout = TerminalTabs()
    private var tabsByID: [UUID: Tab] = [:]
    var activeID: UUID?
    private var counter = 0
    private var groupCounter = 0

    /// Set by `AppState`: a shell ended on its own (the user typed `exit`),
    /// so its tab should close through the same path as the × / ⌘W.
    var onShellExited: ((UUID) -> Void)?

    /// Every open tab in display order (groups top to bottom).
    var tabs: [Tab] {
        layout.allTabIDs.compactMap { tabsByID[$0] }
    }

    var activeTab: Tab? {
        activeID.flatMap { tabsByID[$0] }
    }

    func tab(_ id: UUID) -> Tab? { tabsByID[id] }

    /// The tabs of one group, in that group's order.
    func tabs(in group: TerminalTabs.Group) -> [Tab] {
        group.tabIDs.compactMap { tabsByID[$0] }
    }

    /// Open a fresh shell tab and focus it. It joins `group` when given, else
    /// the active tab's group, else lands loose — a fresh rail has no groups.
    func newTab(inGroup group: UUID? = nil) {
        counter += 1
        let tab = Tab(name: "Terminal \(counter)", session: TerminalSession())
        tab.session.onProcessExit = { [weak self] in self?.onShellExited?(tab.id) }
        tabsByID[tab.id] = tab
        let destination = group ?? activeID.flatMap { layout.groupID(ofTab: $0) }
        layout.add(tab: tab.id, toGroup: destination)
        // A new shell in a collapsed group would be invisible — reveal it.
        if let groupID = layout.groupID(ofTab: tab.id) {
            layout.setCollapsed(groupID, false)
        }
        activeID = tab.id
    }

    /// Kill the tab's shell and remove it. Focus falls to the neighbor that
    /// slid into its slot (mirroring the app's own tab-close behavior).
    func close(_ id: UUID) {
        guard let tab = tabsByID[id] else { return }
        let neighbor = layout.neighbor(of: id)
        tab.session.kill()
        layout.remove(tab: id)
        tabsByID[id] = nil
        if activeID == id { activeID = neighbor }
    }

    func rename(_ id: UUID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, tabsByID[id] != nil else { return }
        tabsByID[id]?.name = name
    }

    /// Kill every shell and clear the tabs — the Terminal feature tab was
    /// closed, and background shells without a UI would be orphans. The name
    /// counters reset so a reopened feature starts at "Terminal 1" again.
    func killAll() {
        for tab in tabsByID.values {
            tab.session.kill()
        }
        tabsByID.removeAll()
        layout = TerminalTabs()
        activeID = nil
        counter = 0
        groupCounter = 0
    }

    /// Focus the next (+1) / previous (-1) tab, wrapping across groups.
    func cycle(by offset: Int) {
        guard let current = activeID ?? layout.allTabIDs.first else { return }
        activeID = layout.tab(offset: offset, from: current)
    }

    // MARK: - Groups

    /// Wrap a tab in a new group, named "Group N" until the user renames it.
    /// Returns the group id so the view can open its rename dialog.
    @discardableResult
    func newGroup(containing tab: UUID) -> UUID? {
        groupCounter += 1
        return layout.newGroup(named: "Group \(groupCounter)", containing: tab)
    }

    func renameGroup(_ id: UUID, to name: String) {
        layout.renameGroup(id, to: name)
    }

    func toggleCollapsed(_ id: UUID) {
        guard let group = layout.group(id) else { return }
        layout.setCollapsed(id, !group.isCollapsed)
    }

    /// Kill every shell in the group and remove it. Focus falls off the last
    /// closed tab's neighbor like a single close does. (Each `close` empties
    /// the group a tab at a time; the model drops it once the last one goes.)
    func closeGroup(_ id: UUID) {
        for tabID in layout.group(id)?.tabIDs ?? [] {
            close(tabID)
        }
    }

    func moveTab(_ id: UUID, before target: UUID) {
        layout.move(tab: id, before: target)
    }

    func moveTab(_ id: UUID, toEndOfGroup group: UUID) {
        layout.move(tab: id, toEndOfGroup: group)
    }

    /// Drag a tab out to the end of the rail as a loose tab.
    func moveTabToLooseEnd(_ id: UUID) {
        layout.moveToLooseEnd(tab: id)
    }

    func moveGroup(_ id: UUID, before target: UUID) {
        layout.moveGroup(id, before: target)
    }

    func moveGroupToEnd(_ id: UUID) {
        layout.moveGroupToEnd(id)
    }

    /// Set by the menu bar (⇧⌘R) to ask the Terminal view to open its rename
    /// dialog for this tab; the view consumes and clears it.
    var renameRequestID: UUID?

    /// Ask the view to rename the focused tab.
    func requestRenameActiveTab() {
        renameRequestID = activeID
    }
}

/// A real multi-tab terminal: each tab is its own PTY-backed login shell
/// (SwiftTerm), with the selected device exported as ANDROID_SERIAL. Sessions
/// are listed in a collapsible left rail — loose (ungrouped) by default; a
/// right-click wraps a tab in a new group, tabs and groups drag-reorder and
/// interleave, and a group deletes itself once its last tab leaves. Every
/// session keeps running (scrollback intact) while you work in other features.
struct TerminalView: View {
    @Environment(AppState.self) private var state
    @State private var renaming: TerminalManager.Tab?
    @State private var renamingGroup: TerminalTabs.Group?
    @State private var renameDraft = ""
    @AppStorage("terminalRailCollapsed") private var railCollapsed = false
    /// The tab/group being dragged in the rail; rows live-reorder as the drag
    /// passes over them, so the drop itself only has to clear this.
    @State private var draggedTabID: UUID?
    @State private var draggedGroupID: UUID?

    private var terminals: TerminalManager { state.terminals }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            content
        }
        // A rail drag released outside the rail (over the shells, most often)
        // never reaches a rail drop delegate, which would leave the dragged
        // row stuck dimmed. Catch those here and clear the drag state — only
        // a target while a rail drag is in flight, so it never swallows text
        // drops headed for the terminal.
        .onDrop(of: [.plainText], delegate: TabDragCancelCatch(
            isDragging: draggedTabID != nil || draggedGroupID != nil,
            clear: {
                draggedTabID = nil
                draggedGroupID = nil
            }
        ))
        // A first visit opens a shell right away — an empty terminal screen
        // with a lone + button would just be a speed bump.
        .task {
            if terminals.tabs.isEmpty { terminals.newTab() }
        }
        // The menu bar's Rename Terminal… (⇧⌘R) can't reach this view's dialog
        // state directly — it posts a request on the manager instead.
        .onChange(of: terminals.renameRequestID) { _, id in
            guard let id, let tab = terminals.tab(id) else { return }
            terminals.renameRequestID = nil
            beginRename(tab)
        }
        .alert("Rename terminal", isPresented: renameBinding) {
            TextField("Name", text: $renameDraft)
            Button("Rename") {
                if let tab = renaming { terminals.rename(tab.id, to: renameDraft) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Give this shell a name that says what it's for.")
        }
        .alert("Rename group", isPresented: renameGroupBinding) {
            TextField("Name", text: $renameDraft)
            Button("Rename") {
                if let group = renamingGroup { terminals.renameGroup(group.id, to: renameDraft) }
                renamingGroup = nil
            }
            Button("Cancel", role: .cancel) { renamingGroup = nil }
        } message: {
            Text("Name this group of shells.")
        }
    }

    /// Bindings the alerts can dismiss without losing which target they held.
    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    private var renameGroupBinding: Binding<Bool> {
        Binding(
            get: { renamingGroup != nil },
            set: { if !$0 { renamingGroup = nil } }
        )
    }

    // MARK: - Rail

    @ViewBuilder
    private var rail: some View {
        if railCollapsed {
            collapsedRail
        } else {
            expandedRail
        }
    }

    /// The thin strip the rail collapses to: expand + new-shell, nothing else.
    private var collapsedRail: some View {
        VStack(spacing: 6) {
            railButton("sidebar.left", help: "Show the terminal list") {
                railCollapsed = false
            }
            railButton("plus", help: "New terminal") {
                terminals.newTab()
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .frame(width: 32)
        .background(.bgSurface)
    }

    private var expandedRail: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 2) {
                        // Loose tabs and groups interleave in one ordered list;
                        // a tab dragged out of a group lands where it's dropped.
                        ForEach(terminals.layout.entries) { entry in
                            switch entry {
                            case .tab(let id):
                                if let tab = terminals.tab(id) { tabRow(tab, indented: false) }
                            case .group(let group):
                                groupHeader(group)
                                if !group.isCollapsed {
                                    ForEach(terminals.tabs(in: group)) { tab in
                                        tabRow(tab, indented: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)

                    // The empty tail below the rows: dropping a drag here
                    // lands it at the very end (loose). A bounded zone, not the
                    // whole scroll view — a whole-view target also caught the
                    // drag crossing the gaps between rows and teleported it.
                    Color.clear
                        .frame(minHeight: 56)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onDrop(of: [.plainText], delegate: RailTailDropDelegate(
                            terminals: terminals,
                            draggedTabID: $draggedTabID, draggedGroupID: $draggedGroupID
                        ))
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }

            Divider()

            HStack(spacing: 4) {
                railButton("plus", help: "New terminal") {
                    terminals.newTab()
                }
                Spacer()
                railButton("sidebar.left", help: "Hide the terminal list") {
                    railCollapsed = true
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 210)
        .background(.bgSurface)
    }

    private func railButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(.textMuted)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func groupHeader(_ group: TerminalTabs.Group) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                .foregroundStyle(.textMuted)
            Text(group.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.textMuted)
            Text("\(group.tabIDs.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRenameGroup(group) }
        .onTapGesture { terminals.toggleCollapsed(group.id) }
        .contextMenu {
            Button("New Terminal Here") { terminals.newTab(inGroup: group.id) }
            Button("Rename…") { beginRenameGroup(group) }
            Divider()
            Button("Close Group") { state.closeTerminalGroup(group.id) }
        }
        .opacity(draggedGroupID == group.id ? 0.4 : 1)
        .onDrag {
            draggedGroupID = group.id
            return NSItemProvider(object: "group:\(group.id.uuidString)" as NSString)
        }
        .onDrop(of: [.plainText], delegate: GroupHeaderDropDelegate(
            group: group.id, terminals: terminals,
            draggedTabID: $draggedTabID, draggedGroupID: $draggedGroupID
        ))
    }

    private func tabRow(_ tab: TerminalManager.Tab, indented: Bool) -> some View {
        let isActive = tab.id == terminals.activeID
        return HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.body)
                .foregroundStyle(isActive ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.textMuted))
            Text(tab.name)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(isActive ? AnyShapeStyle(.textMain) : AnyShapeStyle(.textMuted))
            Spacer(minLength: 0)
            Button {
                state.closeTerminalShell(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close this terminal (kills its shell)")
        }
        .padding(.leading, indented ? 22 : 10)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? AnyShapeStyle(.brandAccent.opacity(0.14)) : AnyShapeStyle(.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRename(tab) }
        .onTapGesture { terminals.activeID = tab.id }
        .contextMenu {
            Button("Rename…") { beginRename(tab) }
            Button("New Group…") {
                if let id = terminals.newGroup(containing: tab.id),
                   let group = terminals.layout.group(id) {
                    beginRenameGroup(group)
                }
            }
            Divider()
            Button("Close Terminal") { state.closeTerminalShell(tab.id) }
        }
        .opacity(draggedTabID == tab.id ? 0.4 : 1)
        .onDrag {
            draggedTabID = tab.id
            return NSItemProvider(object: "tab:\(tab.id.uuidString)" as NSString)
        }
        .onDrop(of: [.plainText], delegate: TabRowDropDelegate(
            row: tab.id, terminals: terminals,
            draggedTabID: $draggedTabID, draggedGroupID: $draggedGroupID
        ))
    }

    private func beginRename(_ tab: TerminalManager.Tab) {
        renameDraft = tab.name
        renaming = tab
    }

    private func beginRenameGroup(_ group: TerminalTabs.Group) {
        renameDraft = group.name
        renamingGroup = group
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        // Every open session stays mounted (hidden when inactive) so background
        // shells keep rendering into their scrollback instead of pausing.
        ZStack {
            ForEach(terminals.tabs) { tab in
                NativeTerminalView(
                    session: tab.session,
                    serial: state.targetSerials.first,
                    isActive: tab.id == terminals.activeID
                )
                .opacity(tab.id == terminals.activeID ? 1 : 0)
                .allowsHitTesting(tab.id == terminals.activeID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - Rail drag & drop

/// Rows reorder live as the drag passes over them (`dropEntered`), so these
/// delegates never decode the item provider — the dragged id travels in the
/// view's `draggedTabID`/`draggedGroupID` state instead.
private struct TabRowDropDelegate: DropDelegate {
    let row: UUID
    let terminals: TerminalManager
    @Binding var draggedTabID: UUID?
    @Binding var draggedGroupID: UUID?

    func dropEntered(info: DropInfo) {
        if let dragged = draggedTabID, dragged != row {
            // Before a loose row → stays loose; before a grouped row → joins
            // that group. The model reads the target's context.
            terminals.moveTab(dragged, before: row)
        } else if let dragged = draggedGroupID {
            // Dragging a group over a loose tab interleaves it there (a no-op
            // over a grouped row, whose id isn't a top-level entry).
            terminals.moveGroup(dragged, before: row)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        draggedGroupID = nil
        return true
    }
}

/// A tab dragged onto a group header appends to that group (works for
/// collapsed groups too); a group dragged onto another header reorders the
/// groups.
private struct GroupHeaderDropDelegate: DropDelegate {
    let group: UUID
    let terminals: TerminalManager
    @Binding var draggedTabID: UUID?
    @Binding var draggedGroupID: UUID?

    func dropEntered(info: DropInfo) {
        if let dragged = draggedTabID {
            terminals.moveTab(dragged, toEndOfGroup: group)
        } else if let dragged = draggedGroupID, dragged != group {
            terminals.moveGroup(dragged, before: group)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        draggedGroupID = nil
        return true
    }
}

/// The rail's empty tail: dropping a tab there sends it to the very end as a
/// loose tab (also how a tab leaves its group); a group goes last. Also the
/// safety net that clears the drag state when a drop lands on no row at all.
private struct RailTailDropDelegate: DropDelegate {
    let terminals: TerminalManager
    @Binding var draggedTabID: UUID?
    @Binding var draggedGroupID: UUID?

    func dropEntered(info: DropInfo) {
        if let dragged = draggedTabID {
            terminals.moveTabToLooseEnd(dragged)
        } else if let dragged = draggedGroupID {
            terminals.moveGroupToEnd(dragged)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        draggedGroupID = nil
        return true
    }
}
