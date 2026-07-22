import ADBKit
import SwiftUI
import UniformTypeIdentifiers

/// The Terminal feature's open shells. Owned by `AppState` (like
/// `reactotronSession`) so every session, its scrollback, the tab names, and
/// the group layout survive leaving the feature. Each tab holds one or more
/// split panes, each an independent PTY-backed zsh; where each tab sits
/// (groups, order) lives in the pure `TerminalTabs` model and each tab's pane
/// arrangement in `TerminalSplitTree`, so the moves are unit-tested in ADBKit.
@MainActor
@Observable
final class TerminalManager {
    struct Tab: Identifiable {
        let id = UUID()
        var name: String
        /// How this tab's panes divide its space (⌘D / ⇧⌘D).
        var splits: TerminalSplitTree
        /// The pane holding keyboard focus while this tab is frontmost.
        var activePaneID: UUID
        /// One PTY-backed shell per pane.
        fileprivate(set) var sessions: [UUID: TerminalSession] = [:]

        var activeSession: TerminalSession? { sessions[activePaneID] }
        func session(forPane id: UUID) -> TerminalSession? { sessions[id] }
    }

    private(set) var layout = TerminalTabs()
    private var tabsByID: [UUID: Tab] = [:]
    var activeID: UUID?
    private var groupCounter = 0

    /// The rail's drag-in-flight state — which row/group is dragged and where
    /// the insertion guideline sits. On the manager, not view `@State`, so the
    /// root drag janitor can clear it when a drag ends without a drop. The
    /// whole-view drop catch that used to do that job claimed the drag region
    /// for the entire feature area and killed the pane's tab drops (SwiftUI
    /// routes a drop to the deepest region under the cursor by *geometry*,
    /// regardless of whether its declared types match the drag).
    fileprivate var railDraggedTabID: UUID?
    fileprivate var railDraggedGroupID: UUID?
    fileprivate var railDropSlot: RailDropSlot?

    /// True while a rail row/group drag is in flight (the janitor's guard).
    var railDragActive: Bool {
        railDraggedTabID != nil || railDraggedGroupID != nil || railDropSlot != nil
    }

    /// Reset the rail drag state — a drop resolved, or the janitor caught a
    /// drag that ended with no drop (released over the shells or outside).
    func clearRailDrag() {
        railDraggedTabID = nil
        railDraggedGroupID = nil
        railDropSlot = nil
    }

    /// Set by `AppState`: a tab's *last* shell ended on its own (the user typed
    /// `exit`), so its tab should close through the same path as the × / ⌘W.
    /// A pane that exits while siblings remain just folds back into them.
    var onShellExited: ((UUID) -> Void)?

    /// Every open tab in display order (groups top to bottom).
    var tabs: [Tab] {
        layout.allTabIDs.compactMap { tabsByID[$0] }
    }

    var activeTab: Tab? {
        activeID.flatMap { tabsByID[$0] }
    }

    /// The shell holding keyboard focus — the active tab's active pane. Feeds
    /// the menu bar's find commands and new shells' directory inheritance.
    var activeSession: TerminalSession? { activeTab?.activeSession }

    func tab(_ id: UUID) -> Tab? { tabsByID[id] }

    /// The tabs of one group, in that group's order.
    func tabs(in group: TerminalTabs.Group) -> [Tab] {
        group.tabIDs.compactMap { tabsByID[$0] }
    }

    /// Open a fresh shell tab and focus it. The shell starts in
    /// `startDirectory` when given (the session-resume path), else the focused
    /// shell's working directory (home when there is none), and types
    /// `initialCommand` as soon as it spawns when one is given. It joins
    /// `group` when given, else the active tab's group, else lands loose — a
    /// fresh rail has no groups.
    func newTab(
        inGroup group: UUID? = nil, name: String? = nil, initialCommand: String? = nil,
        startDirectory: String? = nil
    ) {
        let paneID = UUID()
        let session = TerminalSession(
            startDirectory: startDirectory ?? activeSession?.currentDirectory,
            initialCommand: initialCommand
        )
        var tab = Tab(
            name: name ?? nextAutoName(),
            splits: TerminalSplitTree(pane: paneID),
            activePaneID: paneID
        )
        tab.sessions[paneID] = session
        tabsByID[tab.id] = tab
        wire(session, tabID: tab.id, paneID: paneID)
        let destination = group ?? activeID.flatMap { layout.groupID(ofTab: $0) }
        layout.add(tab: tab.id, toGroup: destination)
        // A new shell in a collapsed group would be invisible — reveal it.
        if let groupID = layout.groupID(ofTab: tab.id) {
            layout.setCollapsed(groupID, false)
        }
        activeID = tab.id
    }

    /// The lowest "Terminal N" name not already in use, so a new tab reuses the
    /// numbers freed by closed tabs instead of climbing forever (only Terminal 1
    /// open ⇒ the next is Terminal 2, not Terminal 11). Names that aren't a plain
    /// "Terminal <number>" — user-renamed tabs — are ignored.
    private func nextAutoName() -> String {
        let prefix = "Terminal "
        let used = Set(tabsByID.values.compactMap { tab -> Int? in
            guard tab.name.hasPrefix(prefix) else { return nil }
            return Int(tab.name.dropFirst(prefix.count))
        })
        var n = 1
        while used.contains(n) { n += 1 }
        return "\(prefix)\(n)"
    }

    /// Kill every pane's shell and remove the tab. Focus falls to the neighbor
    /// that slid into its slot (mirroring the app's own tab-close behavior).
    func close(_ id: UUID) {
        guard let tab = tabsByID[id] else { return }
        let neighbor = layout.neighbor(of: id)
        for session in tab.sessions.values {
            session.kill()
        }
        layout.remove(tab: id)
        tabsByID[id] = nil
        if activeID == id {
            activeID = neighbor
            focusActiveSessionSoon()
        }
    }

    func rename(_ id: UUID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, tabsByID[id] != nil else { return }
        tabsByID[id]?.name = name
    }

    /// Each open tab's working directory — the focused pane's shell, read live
    /// from the kernel, falling back to where a never-shown shell was going to
    /// start — in display order. Read only at teardown time (no polling); this
    /// is the raw input to the session-resume snapshot (`TerminalResume`).
    var openTabDirectories: [String] {
        tabs.map { tab in
            tab.activeSession?.directoryToRemember
                ?? FileManager.default.homeDirectoryForCurrentUser.path
        }
    }

    /// Session resume: reopen one tab per remembered directory, display order,
    /// first tab focused. Cheap — tab structs only; each shell spawns lazily
    /// when its pane first renders. No-op unless the rail is empty (a live
    /// rail must never be doubled) or there's nothing to resume.
    func restore(directories: [String]) {
        guard tabsByID.isEmpty, !directories.isEmpty else { return }
        for directory in directories {
            newTab(startDirectory: directory)
        }
        activeID = layout.allTabIDs.first
    }

    /// Kill every shell and clear the tabs — the Terminal feature tab was
    /// closed, and background shells without a UI would be orphans. With the
    /// tabs cleared, the next new tab is "Terminal 1" again; only the group
    /// counter needs an explicit reset.
    func killAll() {
        for tab in tabsByID.values {
            for session in tab.sessions.values {
                session.kill()
            }
        }
        tabsByID.removeAll()
        layout = TerminalTabs()
        activeID = nil
        groupCounter = 0
    }

    /// Focus the next (+1) / previous (-1) tab, wrapping across groups.
    func cycle(by offset: Int) {
        guard let current = activeID ?? layout.allTabIDs.first else { return }
        activeID = layout.tab(offset: offset, from: current)
    }

    // MARK: - Split panes

    /// Split the focused pane (⌘D / ⇧⌘D): the new shell takes half its space,
    /// starts in its working directory, and gets focus.
    func splitActivePane(_ direction: TerminalSplitTree.Direction) {
        guard let tabID = activeID, var tab = tabsByID[tabID] else { return }
        let paneID = UUID()
        guard tab.splits.split(pane: tab.activePaneID, direction: direction, adding: paneID) else {
            return
        }
        let session = TerminalSession(
            startDirectory: tab.activeSession?.currentDirectory
        )
        tab.sessions[paneID] = session
        tab.activePaneID = paneID
        tabsByID[tabID] = tab
        wire(session, tabID: tabID, paneID: paneID)
    }

    /// Close one split pane (killing its shell); a sibling absorbs its space
    /// and takes focus. Returns false when the pane is its tab's only one —
    /// the caller closes the whole tab instead.
    @discardableResult
    func closePane(_ paneID: UUID, inTab tabID: UUID) -> Bool {
        guard var tab = tabsByID[tabID], tab.splits.contains(paneID),
              tab.splits.paneCount > 1
        else { return false }
        let neighbor = tab.splits.neighbor(of: paneID)
        tab.sessions[paneID]?.kill()
        tab.sessions[paneID] = nil
        tab.splits.remove(pane: paneID)
        if tab.activePaneID == paneID, let neighbor { tab.activePaneID = neighbor }
        tabsByID[tabID] = tab
        focusActiveSessionSoon()
        return true
    }

    /// ⌘W: close the focused split pane. Returns false when the focused tab
    /// has a single pane — the caller peels the whole tab instead.
    func closeActivePane() -> Bool {
        guard let tab = activeTab else { return false }
        return closePane(tab.activePaneID, inTab: tab.id)
    }

    /// Close one pane, or hand the whole tab to the shell-exit path when it's
    /// the last — the funnel for the pane × button and the right-click Close.
    func closePaneOrTab(_ paneID: UUID, inTab tabID: UUID) {
        if !closePane(paneID, inTab: tabID) {
            onShellExited?(tabID)
        }
    }

    /// Put the keyboard in the surviving shell after a close. Deferred a beat
    /// so SwiftUI finishes unmounting the closed pane first — AppKit moves
    /// first responder to the window during that teardown, which would
    /// otherwise swallow the focus we just set.
    private func focusActiveSessionSoon() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            self?.activeSession?.takeFocus()
        }
    }

    /// Route a session's callbacks back to its pane: an exit closes the pane
    /// (or hands the tab close to `onShellExited` when it's the last one),
    /// taking keyboard focus marks the pane active, and the right-click menu
    /// acts on the pane it was opened over.
    private func wire(_ session: TerminalSession, tabID: UUID, paneID: UUID) {
        session.onProcessExit = { [weak self] in
            self?.closePaneOrTab(paneID, inTab: tabID)
        }
        session.onFocus = { [weak self] in
            guard let self, self.tabsByID[tabID] != nil else { return }
            self.activeID = tabID
            self.tabsByID[tabID]?.activePaneID = paneID
        }
        session.isInSplit = { [weak self] in
            (self?.tabsByID[tabID]?.splits.paneCount ?? 1) > 1
        }
        session.onMenuAction = { [weak self] action in
            guard let self, self.tabsByID[tabID] != nil else { return }
            self.activeID = tabID
            self.tabsByID[tabID]?.activePaneID = paneID
            switch action {
            case .splitVertically: self.splitActivePane(.vertical)
            case .splitHorizontally: self.splitActivePane(.horizontal)
            case .newTab: self.newTab()
            case .rename: self.renameRequestID = tabID
            case .close: self.closePaneOrTab(paneID, inTab: tabID)
            }
        }
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

/// A real multi-tab terminal: each tab is one or more split panes, each its
/// own PTY-backed login shell (SwiftTerm), with the selected device exported
/// as ANDROID_SERIAL. Sessions are listed in a collapsible left rail — or a
/// Chrome-style strip along the top, toggleable — loose (ungrouped) by
/// default; a right-click wraps a tab in a new group, tabs and groups
/// drag-reorder and interleave, and a group deletes itself once its last tab
/// leaves. ⌘D/⇧⌘D split the focused pane, and new shells start in the focused
/// shell's directory. Every session keeps running (scrollback intact) while
/// you work in other features.
extension AppState {
    /// Open the Terminal feature on a fresh shell that immediately runs
    /// `line` — the "continue in a real terminal" path for a command whose
    /// output is interactive or long-running (watch modes, prompts, builds).
    func runInTerminal(_ line: String, named name: String? = nil) {
        terminals.newTab(name: name, initialCommand: line)
        requestFeature("terminal")
    }

    /// Remember every open terminal tab's working directory (display order,
    /// capped — see `TerminalResume`) so the next Terminal open resumes there.
    /// Called only on *implicit* teardown: the feature tab closing, quit, a
    /// background-mode window close, a role reset. Tabs closed explicitly
    /// (⌘W / × / `exit`) already left the rail, so they're forgotten by
    /// construction — closing a tab means done with it.
    func rememberTerminalDirectories() {
        layout.terminalResumeDirs = TerminalResume.snapshot(terminals.openTabDirectories)
        persistLayout()
    }

    /// First shell(s) for a Terminal showing an empty rail: resume the
    /// directories remembered at the last implicit teardown, or a single
    /// fresh shell when there's nothing to resume.
    func openTerminalResumingWork() {
        let remembered = TerminalResume.snapshot(layout.terminalResumeDirs ?? [])
        if remembered.isEmpty {
            terminals.newTab()
        } else {
            terminals.restore(directories: remembered)
        }
    }
}

struct TerminalView: View {
    @Environment(AppState.self) private var state
    @State private var renaming: TerminalManager.Tab?
    @State private var renamingGroup: TerminalTabs.Group?
    @State private var renameDraft = ""
    @AppStorage("terminalRailCollapsed") private var railCollapsed = false
    /// Where the tab list lives: a Chrome-style strip along the top (default)
    /// or a left rail.
    @AppStorage("terminalTabsOnTop") private var tabsOnTop = true
    /// Live width of the top strip's scroll viewport, so its tab row can fill
    /// the available space (the drop-at-end tail stretches to it) yet still
    /// scroll once the tabs overflow instead of being clipped.
    @State private var topStripWidth: CGFloat = 0
    @Environment(\.windowOpacity) private var windowOpacity
    private var terminals: TerminalManager { state.terminals }

    var body: some View {
        Group {
            if tabsOnTop {
                VStack(spacing: 0) {
                    topStrip
                    Divider()
                    content
                }
            } else {
                HStack(spacing: 0) {
                    rail
                    Divider()
                    content
                }
            }
        }
        // No whole-view drop catch here: SwiftUI routes a drop to the deepest
        // drop region under the cursor by geometry, regardless of type match,
        // so a feature-wide target — even one listening for a type a tab drag
        // doesn't carry — killed the pane's drop-to-split while a terminal tab
        // was mounted. Rail drags that end without a drop are cleared by the
        // root drag janitor (`RootView.installDragJanitor`) instead.
        // A first visit opens a shell right away — an empty terminal screen
        // with a lone + button would just be a speed bump. Directories
        // remembered at the last implicit teardown resume here; a window
        // reopened from background mode restores in `activateMainWindow`
        // instead (the view stays mounted, so this task won't re-fire).
        .task {
            if terminals.tabs.isEmpty { state.openTerminalResumingWork() }
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

    // MARK: - Shared menus

    /// One context menu for a tab wherever it renders (rail row / strip chip).
    @ViewBuilder
    private func tabMenu(_ tab: TerminalManager.Tab) -> some View {
        Button("Rename…") { beginRename(tab) }
        Button("New Group…") {
            if let id = terminals.newGroup(containing: tab.id),
               let group = terminals.layout.group(id) {
                beginRenameGroup(group)
            }
        }
        Divider()
        Button("Split Vertically") {
            terminals.activeID = tab.id
            terminals.splitActivePane(.vertical)
        }
        Button("Split Horizontally") {
            terminals.activeID = tab.id
            terminals.splitActivePane(.horizontal)
        }
        Divider()
        Button("Close Terminal") { state.closeTerminalShell(tab.id) }
    }

    @ViewBuilder
    private func groupMenu(_ group: TerminalTabs.Group) -> some View {
        Button("New Terminal Here") { terminals.newTab(inGroup: group.id) }
        Button("Rename…") { beginRenameGroup(group) }
        Divider()
        Button("Close Group") { state.closeTerminalGroup(group.id) }
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
            // The controls live on top so New Terminal is always in reach —
            // it used to hide at the rail's bottom, below the fold on tall
            // tab lists.
            HStack(spacing: 4) {
                railButton("plus", help: "New terminal") {
                    terminals.newTab()
                }
                Spacer()
                railButton("rectangle.topthird.inset.filled", help: "Move tabs to the top (Chrome-style)") {
                    tabsOnTop = true
                }
                railButton("sidebar.left", help: "Hide the terminal list") {
                    railCollapsed = true
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

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
                        .overlay(alignment: .top) {
                            guideline(terminals.railDropSlot == .railEnd).padding(.horizontal, 8)
                        }
                        .onDrop(of: [.terminalRailItem], delegate: RailTailDropDelegate(
                            terminals: terminals
                        ))
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: 210)
        .background(.bgSurface)
    }

    private func railButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(.callout).weight(.medium))
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
                .font(.app(size: 9, weight: .bold))
                .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                .foregroundStyle(.textMuted)
            Text(group.name)
                .font(.app(.callout).weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.textMuted)
            Text("\(group.tabIDs.count)")
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRenameGroup(group) }
        .onTapGesture { terminals.toggleCollapsed(group.id) }
        .contextMenu { groupMenu(group) }
        .opacity(terminals.railDraggedGroupID == group.id ? 0.4 : 1)
        // Above the header → a group reorders here; below it → a tab joins the
        // group.
        .overlay(alignment: .top) {
            guideline(terminals.railDropSlot == .beforeGroup(group.id)).offset(y: -1)
        }
        .overlay(alignment: .bottom) {
            guideline(terminals.railDropSlot == .intoGroup(group.id)).offset(y: 1)
        }
        .onDrag {
            terminals.railDraggedGroupID = group.id
            return privateDragItem(.terminalRailItem, "group:\(group.id.uuidString)")
        }
        .onDrop(of: [.terminalRailItem], delegate: GroupHeaderDropDelegate(
            group: group.id, terminals: terminals
        ))
    }

    private func tabRow(_ tab: TerminalManager.Tab, indented: Bool) -> some View {
        let isActive = tab.id == terminals.activeID
        return HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.app(.body))
                .foregroundStyle(isActive ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.textMuted))
            Text(tab.name)
                .font(.app(.callout))
                .lineLimit(1)
                .foregroundStyle(isActive ? AnyShapeStyle(.textMain) : AnyShapeStyle(.textMuted))
            Spacer(minLength: 0)
            Button {
                state.closeTerminalShell(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.app(size: 10, weight: .bold))
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
        .contextMenu { tabMenu(tab) }
        .opacity(terminals.railDraggedTabID == tab.id ? 0.4 : 1)
        // A tab drops before this row; a group dragged over a loose row
        // interleaves before it. Both draw the guideline above the row.
        .overlay(alignment: .top) {
            guideline(
                terminals.railDropSlot == .beforeTab(tab.id)
                    || (!indented && terminals.railDropSlot == .beforeGroup(tab.id))
            )
            .offset(y: -1)
        }
        .onDrag {
            terminals.railDraggedTabID = tab.id
            return privateDragItem(.terminalRailItem, "tab:\(tab.id.uuidString)")
        }
        .onDrop(of: [.terminalRailItem], delegate: TabRowDropDelegate(
            row: tab.id, isLoose: !indented, terminals: terminals
        ))
    }

    // MARK: - Top strip (Chrome-style tabs)

    /// The horizontal alternative to the rail: tab chips along the top, the
    /// same groups/context menus/drag-reorder, with + right after the last
    /// tab, Chrome-style.
    private var topStrip: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(terminals.layout.entries) { entry in
                        switch entry {
                        case .tab(let id):
                            if let tab = terminals.tab(id) { tabChip(tab, grouped: false) }
                        case .group(let group):
                            groupChip(group)
                            if !group.isCollapsed {
                                ForEach(terminals.tabs(in: group)) { tab in
                                    tabChip(tab, grouped: true)
                                }
                            }
                        }
                    }
                    railButton("plus", help: "New terminal") {
                        terminals.newTab()
                    }

                    // The strip's empty tail: dropping a drag here lands it at
                    // the very end (loose), like the rail's bottom zone. It
                    // lives inside the scroll content so the row can fill the
                    // viewport (the `minWidth` below stretches it), and it
                    // collapses to `minWidth` once the tabs overflow.
                    Color.clear
                        .frame(minWidth: 24, maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .overlay(alignment: .leading) {
                            verticalGuideline(terminals.railDropSlot == .railEnd)
                        }
                        .onDrop(of: [.terminalRailItem], delegate: RailTailDropDelegate(
                            terminals: terminals
                        ))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                // Fill the viewport when the tabs are short so the tail's drop
                // zone spans the empty space; grow past it (scrolling) when
                // they overflow, instead of clipping the rightmost tabs.
                .frame(minWidth: topStripWidth, alignment: .leading)
            }
            // The scroll view is now the only greedy sibling, so it takes all
            // width up to the trailing button; measure that width to feed the
            // row's `minWidth` above.
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                topStripWidth = width
            }

            railButton("sidebar.left", help: "Move tabs to a sidebar") {
                tabsOnTop = false
            }
            .padding(.trailing, 8)
        }
        .frame(height: 38)
        .background(.bgSurface)
    }

    private func tabChip(_ tab: TerminalManager.Tab, grouped: Bool) -> some View {
        let isActive = tab.id == terminals.activeID
        return HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.app(.caption))
                .foregroundStyle(isActive ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.textMuted))
            Text(tab.name)
                .font(.app(.callout))
                .lineLimit(1)
                .foregroundStyle(isActive ? AnyShapeStyle(.textMain) : AnyShapeStyle(.textMuted))
            Button {
                state.closeTerminalShell(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.app(size: 9, weight: .bold))
                    .foregroundStyle(.textMuted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close this terminal (kills its shell)")
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isActive
                        ? AnyShapeStyle(.brandAccent.opacity(0.14))
                        : grouped
                            ? AnyShapeStyle(.textMuted.opacity(0.08))
                            : AnyShapeStyle(.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRename(tab) }
        .onTapGesture { terminals.activeID = tab.id }
        .contextMenu { tabMenu(tab) }
        .opacity(terminals.railDraggedTabID == tab.id ? 0.4 : 1)
        // Left of the chip: a tab drops before it; a group dragged over a
        // loose chip interleaves before it — the rail's slots, rotated 90°.
        .overlay(alignment: .leading) {
            verticalGuideline(
                terminals.railDropSlot == .beforeTab(tab.id)
                    || (!grouped && terminals.railDropSlot == .beforeGroup(tab.id))
            )
            .offset(x: -3)
        }
        .onDrag {
            terminals.railDraggedTabID = tab.id
            return privateDragItem(.terminalRailItem, "tab:\(tab.id.uuidString)")
        }
        .onDrop(of: [.terminalRailItem], delegate: TabRowDropDelegate(
            row: tab.id, isLoose: !grouped, terminals: terminals
        ))
    }

    private func groupChip(_ group: TerminalTabs.Group) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.right")
                .font(.app(size: 8, weight: .bold))
                .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                .foregroundStyle(.textMuted)
            Text(group.name)
                .font(.app(.callout).weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.textMuted)
            Text("\(group.tabIDs.count)")
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(.textMuted.opacity(0.12)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRenameGroup(group) }
        .onTapGesture { terminals.toggleCollapsed(group.id) }
        .contextMenu { groupMenu(group) }
        .opacity(terminals.railDraggedGroupID == group.id ? 0.4 : 1)
        // Left of the chip → a group reorders here; right of it → a tab joins
        // the group (the rail header's above/below slots, rotated).
        .overlay(alignment: .leading) {
            verticalGuideline(terminals.railDropSlot == .beforeGroup(group.id)).offset(x: -3)
        }
        .overlay(alignment: .trailing) {
            verticalGuideline(terminals.railDropSlot == .intoGroup(group.id)).offset(x: 3)
        }
        .onDrag {
            terminals.railDraggedGroupID = group.id
            return privateDragItem(.terminalRailItem, "group:\(group.id.uuidString)")
        }
        .onDrop(of: [.terminalRailItem], delegate: GroupHeaderDropDelegate(
            group: group.id, terminals: terminals
        ))
    }

    /// The accent insertion indicator shown at a drop slot — a thin capped line,
    /// matching the sidebar's guideline.
    @ViewBuilder
    private func guideline(_ show: Bool) -> some View {
        if show {
            HStack(spacing: 0) {
                guidelineCap
                Rectangle().fill(Color.brandAccent).frame(height: 2)
                guidelineCap
            }
            .frame(height: 6)
        }
    }

    private var guidelineCap: some View {
        RoundedRectangle(cornerRadius: 1).fill(Color.brandAccent).frame(width: 3, height: 6)
    }

    /// The guideline turned upright for the top strip's chips.
    @ViewBuilder
    private func verticalGuideline(_ show: Bool) -> some View {
        if show {
            VStack(spacing: 0) {
                verticalGuidelineCap
                Rectangle().fill(Color.brandAccent).frame(width: 2)
                verticalGuidelineCap
            }
            .frame(width: 6)
        }
    }

    private var verticalGuidelineCap: some View {
        RoundedRectangle(cornerRadius: 1).fill(Color.brandAccent).frame(width: 6, height: 3)
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
                TerminalSplitNodeView(
                    node: tab.splits.root,
                    tab: tab,
                    serial: state.targetSerials.first,
                    isActiveTab: tab.id == terminals.activeID,
                    onClosePane: { paneID in
                        terminals.closePaneOrTab(paneID, inTab: tab.id)
                    }
                )
                .opacity(tab.id == terminals.activeID ? 1 : 0)
                .allowsHitTesting(tab.id == terminals.activeID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Translucent window: the shells stop painting their default
        // background entirely (see `applyBackgroundAlpha` — SwiftTerm
        // double-fills, compounding any partial alpha), so this underlay
        // carries the terminal's single tint at the window opacity.
        .background(Color.black.opacity(WindowEffects.clamped(windowOpacity)))
    }
}

/// Renders one tab's split tree: a pane is its shell, a split lays its
/// children out along its direction with hairline separators, recursing.
private struct TerminalSplitNodeView: View {
    let node: TerminalSplitTree.Node?
    let tab: TerminalManager.Tab
    let serial: String?
    let isActiveTab: Bool
    let onClosePane: (UUID) -> Void
    @Environment(\.windowOpacity) private var windowOpacity

    var body: some View {
        switch node {
        case nil:
            Color.black.opacity(WindowEffects.clamped(windowOpacity))
        case .pane(let paneID)?:
            if let session = tab.session(forPane: paneID) {
                let isSplit = tab.splits.paneCount > 1
                NativeTerminalView(
                    session: session,
                    serial: serial,
                    isActive: isActiveTab && paneID == tab.activePaneID
                )
                // In a split, the shell sits inside a small gutter so the
                // focus ring never draws over the first/last row of text.
                .padding(isSplit ? 3 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    // With multiple panes, mark where the keyboard goes.
                    if isSplit, paneID == tab.activePaneID {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Color.brandAccent.opacity(0.5), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSplit {
                        Button {
                            onClosePane(paneID)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.app(size: 13))
                                .foregroundStyle(.white.opacity(0.35))
                                .background(Circle().fill(Color.black.opacity(0.6)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .help("Close this pane (kills its shell)")
                    }
                }
            }
        case .split(let direction, let children)?:
            let layout = direction == .vertical
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            layout {
                // Children keyed by their subtree's first pane, not position:
                // closing a middle sibling shifts the ones after it, and
                // positional identity would hand a surviving slot a different
                // session (its container's old shell view and click routing
                // going stale with it).
                ForEach(Array(children.enumerated()), id: \.element.firstPaneID) { index, child in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.16))
                            .frame(
                                width: direction == .vertical ? 1 : nil,
                                height: direction == .horizontal ? 1 : nil
                            )
                    }
                    TerminalSplitNodeView(
                        node: child, tab: tab, serial: serial, isActiveTab: isActiveTab,
                        onClosePane: onClosePane
                    )
                }
            }
        }
    }
}

// MARK: - Rail drag & drop

/// Where the insertion guideline is drawn during a rail drag. The delegates
/// set it as the drag moves and the matching row draws the accent line; the
/// move is applied only on drop.
private enum RailDropSlot: Equatable {
    case beforeTab(UUID)     // guideline above a tab row
    case intoGroup(UUID)     // guideline below a group header — a tab joins the group
    case beforeGroup(UUID)   // guideline above a group header (or a loose tab) — a group reorders here
    case railEnd             // guideline at the rail's bottom — loose end / group to end
}

/// One tab row's drop target. A dragged tab drops before this row (loose or
/// grouped, matching the row's context); a dragged group interleaves before a
/// *loose* row. Rows hold still — only the manager's `railDropSlot` changes —
/// until the drop.
private struct TabRowDropDelegate: DropDelegate {
    let row: UUID
    let isLoose: Bool
    let terminals: TerminalManager

    private var slot: RailDropSlot? {
        if let dragged = terminals.railDraggedTabID, dragged != row { return .beforeTab(row) }
        // A group targets a loose row (its id is a top-level entry); a grouped
        // row isn't, so a group drag there would be a no-op — offer no slot.
        if terminals.railDraggedGroupID != nil, isLoose { return .beforeGroup(row) }
        return nil
    }

    func validateDrop(info: DropInfo) -> Bool { slot != nil }
    func dropEntered(info: DropInfo) { terminals.railDropSlot = slot }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        terminals.railDropSlot = slot
        return slot == nil ? nil : DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) {
        if terminals.railDropSlot == slot { terminals.railDropSlot = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { terminals.clearRailDrag() }
        if let dragged = terminals.railDraggedTabID, dragged != row {
            terminals.moveTab(dragged, before: row)
            return true
        }
        if let dragged = terminals.railDraggedGroupID, isLoose {
            terminals.moveGroup(dragged, before: row)
            return true
        }
        return false
    }
}

/// A group header's drop target: a dragged tab joins the group (guideline
/// below the header); a dragged group reorders before it (guideline above).
private struct GroupHeaderDropDelegate: DropDelegate {
    let group: UUID
    let terminals: TerminalManager

    private var slot: RailDropSlot? {
        if terminals.railDraggedTabID != nil { return .intoGroup(group) }
        if let dragged = terminals.railDraggedGroupID, dragged != group {
            return .beforeGroup(group)
        }
        return nil
    }

    func validateDrop(info: DropInfo) -> Bool { slot != nil }
    func dropEntered(info: DropInfo) { terminals.railDropSlot = slot }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        terminals.railDropSlot = slot
        return slot == nil ? nil : DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) {
        if terminals.railDropSlot == slot { terminals.railDropSlot = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { terminals.clearRailDrag() }
        if let dragged = terminals.railDraggedTabID {
            terminals.moveTab(dragged, toEndOfGroup: group)
            return true
        }
        if let dragged = terminals.railDraggedGroupID, dragged != group {
            terminals.moveGroup(dragged, before: group)
            return true
        }
        return false
    }
}

/// The rail's empty tail: a tab drops to the very end as loose (also how a tab
/// leaves its group); a group goes last. Also the safety net that clears the
/// drag state when a drop lands on no row at all.
private struct RailTailDropDelegate: DropDelegate {
    let terminals: TerminalManager

    private var isDragging: Bool {
        terminals.railDraggedTabID != nil || terminals.railDraggedGroupID != nil
    }

    func validateDrop(info: DropInfo) -> Bool { isDragging }
    func dropEntered(info: DropInfo) { if isDragging { terminals.railDropSlot = .railEnd } }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isDragging { terminals.railDropSlot = .railEnd }
        return isDragging ? DropProposal(operation: .move) : nil
    }
    func dropExited(info: DropInfo) {
        if terminals.railDropSlot == .railEnd { terminals.railDropSlot = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { terminals.clearRailDrag() }
        if let dragged = terminals.railDraggedTabID {
            terminals.moveTabToLooseEnd(dragged)
            return true
        }
        if let dragged = terminals.railDraggedGroupID {
            terminals.moveGroupToEnd(dragged)
            return true
        }
        return false
    }
}
