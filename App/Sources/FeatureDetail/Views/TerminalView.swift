import ADBKit
import SwiftUI

/// The Terminal feature's open shells. Owned by `AppState` (like
/// `reactotronSession`) so every session, its scrollback, and the tab names
/// survive leaving the feature. Each tab is an independent PTY-backed zsh.
@MainActor
@Observable
final class TerminalManager {
    struct Tab: Identifiable {
        let id = UUID()
        var name: String
        let session: TerminalSession
    }

    private(set) var tabs: [Tab] = []
    var activeID: UUID?
    private var counter = 0

    /// Set by `AppState`: a shell ended on its own (the user typed `exit`),
    /// so its tab should close through the same path as the × / ⌘W.
    var onShellExited: ((UUID) -> Void)?

    var activeTab: Tab? {
        tabs.first { $0.id == activeID }
    }

    /// Open a fresh shell tab and focus it.
    func newTab() {
        counter += 1
        let tab = Tab(name: "Terminal \(counter)", session: TerminalSession())
        tab.session.onProcessExit = { [weak self] in self?.onShellExited?(tab.id) }
        tabs.append(tab)
        activeID = tab.id
    }

    /// Kill the tab's shell and remove it. Focus falls to the neighbor that
    /// slid into its slot (mirroring the app's own tab-close behavior).
    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].session.kill()
        let wasActive = activeID == id
        tabs.remove(at: index)
        if wasActive {
            activeID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    func rename(_ id: UUID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].name = name
    }

    /// Kill every shell and clear the tabs — the Terminal feature tab was
    /// closed, and background shells without a UI would be orphans. The name
    /// counter resets so a reopened feature starts at "Terminal 1" again.
    func killAll() {
        for tab in tabs {
            tab.session.kill()
        }
        tabs.removeAll()
        activeID = nil
        counter = 0
    }

    /// Focus the next (+1) / previous (-1) tab, wrapping.
    func cycle(by offset: Int) {
        guard !tabs.isEmpty else { return }
        let current = tabs.firstIndex { $0.id == activeID } ?? 0
        activeID = tabs[(current + offset + tabs.count) % tabs.count].id
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
/// (SwiftTerm), with the selected device exported as ANDROID_SERIAL. Tabs are
/// renameable (double-click or right-click) and every session keeps running —
/// scrollback intact — while you work in other features.
struct TerminalView: View {
    @Environment(AppState.self) private var state
    @State private var renaming: TerminalManager.Tab?
    @State private var renameDraft = ""

    private var terminals: TerminalManager { state.terminals }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider()
            content
        }
        // A first visit opens a shell right away — an empty terminal screen
        // with a lone + button would just be a speed bump.
        .task {
            if terminals.tabs.isEmpty { terminals.newTab() }
        }
        // The menu bar's Rename Terminal… (⇧⌘R) can't reach this view's dialog
        // state directly — it posts a request on the manager instead.
        .onChange(of: terminals.renameRequestID) { _, id in
            guard let id, let tab = terminals.tabs.first(where: { $0.id == id }) else { return }
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
    }

    /// Binding the alert can dismiss without losing which tab it targets.
    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    /// The chips' natural width and the strip's full width, so the + button
    /// can trail the last tab while everything fits and pin to the right edge
    /// once the tabs overflow. The chips are measured without the button, so
    /// the threshold can't feed back into itself.
    @State private var chipsWidth: CGFloat = 0
    @State private var stripWidth: CGFloat = .infinity

    private var plusIsPinned: Bool {
        // chips + inline button (28) + row spacing (4) + content padding (16)
        chipsWidth + 48 > stripWidth
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(terminals.tabs) { tab in
                            chip(tab)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { chipsWidth = $0 }

                    if !plusIsPinned {
                        newTabButton
                    }
                }
                .padding(.horizontal, 8)
            }

            if plusIsPinned {
                Spacer(minLength: 4)
                newTabButton
                    .padding(.trailing, 6)
            }
        }
        .frame(height: 36)
        .background(.bgSurface)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { stripWidth = $0 }
    }

    private var newTabButton: some View {
        Button {
            terminals.newTab()
        } label: {
            Image(systemName: "plus")
                .font(.callout.weight(.medium))
                .foregroundStyle(.textMuted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New terminal")
    }

    private func chip(_ tab: TerminalManager.Tab) -> some View {
        let isActive = tab.id == terminals.activeID
        return HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundStyle(isActive ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.textMuted))
            Text(tab.name)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(isActive ? AnyShapeStyle(.textMain) : AnyShapeStyle(.textMuted))
            Button {
                state.closeTerminalShell(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.textMuted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close this terminal (kills its shell)")
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
        .onTapGesture(count: 2) { beginRename(tab) }
        .onTapGesture { terminals.activeID = tab.id }
        .contextMenu {
            Button("Rename…") { beginRename(tab) }
            Divider()
            Button("Close Terminal") { state.closeTerminalShell(tab.id) }
        }
    }

    private func beginRename(_ tab: TerminalManager.Tab) {
        renameDraft = tab.name
        renaming = tab
    }

    @ViewBuilder
    private var content: some View {
        // Every open session stays mounted (hidden when inactive) so background
        // shells keep rendering into their scrollback instead of pausing.
        ZStack {
            ForEach(terminals.tabs) { tab in
                NativeTerminalView(session: tab.session, serial: state.targetSerials.first)
                    .opacity(tab.id == terminals.activeID ? 1 : 0)
                    .allowsHitTesting(tab.id == terminals.activeID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
