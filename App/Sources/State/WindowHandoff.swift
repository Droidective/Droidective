import ADBKit
import AppKit
import Foundation
import SwiftUI

/// Moving a tab out of its window — into another open window, or into a new one
/// of its own.
///
/// Every route funnels through `AppState.beginHandoff`: the tab's context menu,
/// the Window menu, ⌃⌘N, a drag onto another window and a drag out of the app.
/// One entry point because the cases that need a confirmation (a live
/// recording, open shells) are easy to get right once and easy to forget four
/// times.

/// Where a tab being moved out of a window is going.
enum HandoffDestination: Equatable {
    /// A window that does not exist yet. `frame` is set when a drag decided
    /// where it should land; nil lets the usual cascade place it.
    case newWindow(frame: NSRect?)
    /// A window that is already open. `slot` is where in that window's strip
    /// the drop landed — it rides along rather than being applied at the drop,
    /// because a handoff can be held behind a confirmation and would otherwise
    /// lose the position by the time it runs.
    case window(WorkspaceID, slot: HandoffSlot?)
}

/// Where in a receiving window's tabs a moved tab should sit.
struct HandoffSlot: Equatable {
    /// Which pane. Out of range (dropped on a split the receiver doesn't have)
    /// is tolerated — the tab lands in the pane it opened in.
    var group: Int
    /// The tab it should sit before, or nil for the end of the pane.
    var before: String?
}

/// A tab drag in flight, anywhere in the app.
///
/// App-wide rather than per window because a tab can be dragged *into* a window
/// that did not start the drag, and out of the app entirely. Deliberately
/// written only twice per drag — at the start and at the end — because
/// `AppCore` is `@Observable` and `RootView.body` reads it, so a write per
/// mouse-move would re-render every open window on every mouse-move. Where the
/// insertion guideline goes stays in the strip's own local `@State`.
struct TabDrag: Equatable {
    let featureID: String
    /// The window the tab is being dragged out of.
    let source: WorkspaceID
}

/// What a window that has not been created yet should come up as.
///
/// The handoff half is deliberately a `WindowState` — the same record a window
/// persists — so the receiving window restores through the path a relaunch
/// already uses, and the two can never drift apart.
struct WindowSeed: Equatable {
    /// The device a plain new window was opened for (⇧⌘N, "New Window for
    /// Device"). Unused when `state` is set, which carries its own.
    var serial: String?
    /// Full opening state for a moved tab: the source window's device and app
    /// bundle, and exactly the one tab.
    var state: WindowState?
    /// Where a drag decided the window should appear, in screen coordinates.
    var frame: NSRect?
    /// Inherited from the source window, so a moved tab keeps running against
    /// the same set of devices it was.
    var runOnAll = false
    /// A torn-off window opens focused on its one feature. Reversible with ⌘B.
    var sidebarHidden = false
    /// The tab this window is being opened to receive, if any — the marker that
    /// lets `AppCore` tell a handoff's window from any other new one.
    var handoffFeatureID: String?
}

// MARK: - Starting a handoff

extension AppState {
    /// Start moving `featureID`'s tab out of this window.
    ///
    /// Moving a tab unmounts its view, exactly as closing it does, so the same
    /// two confirmations apply — and they are checked in the same order
    /// `closeTab` checks them.
    func beginHandoff(_ featureID: String, to destination: HandoffDestination) {
        guard canDetach(featureID, to: destination) else { return }
        if case .window(let target, _) = destination, target == id { return }
        if featureID == TabHandoff.terminalFeatureID, !terminals.tabs.isEmpty {
            terminalClosePrompt = .handoff(destination)
            return
        }
        if exitGuards[featureID] != nil {
            holdBehindGuard(.handoff(featureID, destination))
            return
        }
        core.completeHandoff(featureID, from: id, to: destination)
    }

    /// Whether this tab can go to that destination. A window of its own needs
    /// something to stay behind here; another *open* window does not, because
    /// consolidating two windows into one is a reasonable thing to want.
    func canDetach(_ featureID: String, to destination: HandoffDestination) -> Bool {
        switch destination {
        case .newWindow: canDetachTabToNewWindow(featureID)
        case .window: canDetachTab(featureID)
        }
    }

    /// Apply the parts of a seed that are window *preferences* rather than
    /// persisted state. Called by `AppCore.bind` before the restore, neither of
    /// which touches these.
    func adoptSeedPreferences(_ seed: WindowSeed) {
        runOnAll = seed.runOnAll
        // The pinned sidebar only; auto-hide mode already rests hidden, and
        // `SidebarVisibility.afterButtonPress` treats "fixed mode, hidden" as
        // the one state where the button just brings it back — so ⌘B is never
        // a dead click here.
        if seed.sidebarHidden { sidebarVisible = false }
    }

    /// A tab drag in flight anywhere in the app, or nil. Every drop target
    /// validates on this rather than on `draggingTabID`, so a window that did
    /// not start the drag still accepts the tab.
    var anyTabDrag: TabDrag? { core.tabDrag }

    /// Windows this one's tabs can be moved into, in window order — the tab
    /// menu's "Move to Window" list.
    var handoffTargets: [(id: WorkspaceID, label: String)] {
        core.registry.entries.filter { $0.id != id }.map { entry in
            let device = entry.serial
                .flatMap { serial in core.devices.first { $0.serial == serial } }
                .map(core.deviceDisplayName)
            let label = core.registry.label(of: entry.id)
            return (id: entry.id, label: device.map { "\(label) — \($0)" } ?? label)
        }
    }
}

// MARK: - Performing it

extension AppCore {
    /// Move `featureID`'s tab out of `from`.
    ///
    /// The ordering is the whole correctness story: the source releases the tab
    /// **before** the destination asks for it. Both writes land on the same
    /// main-actor turn through `persistTabs` → `noteOpenFeatures`, so an
    /// exclusive feature is never registered in two windows at once and the
    /// destination never comes up on the collision banner for a session that is
    /// already gone.
    func completeHandoff(_ featureID: String, from: WorkspaceID, to destination: HandoffDestination) {
        guard let source = workspace(id: from),
              source.canDetach(featureID, to: destination) else { return }
        if case .window(let target, _) = destination, target == from { return }
        // Asking for a window we cannot open would detach the tab into nowhere.
        // Checked before anything is given up, never after.
        if case .newWindow = destination, !canOpenWindow { return }

        let record = source.windowRecord
        let carry = source.detachTab(featureID)

        switch destination {
        case .window(let target, let slot):
            guard let receiver = workspace(id: target) else {
                // The window went away between the drop and here (⌘Q, a script).
                // Put the tab back rather than dropping it on the floor.
                source.adoptHandoff(featureID, carrying: carry, at: nil)
                return
            }
            receiver.adoptHandoff(featureID, carrying: carry, at: slot)
            reconcileSharedSessions()
            focusWindow(target)

        case .newWindow(let frame):
            let seeded = openSeededWindow(WindowSeed(
                state: TabHandoff.seed(
                    featureID: featureID,
                    from: record,
                    newID: .generate(),
                    carrying: carry),
                frame: frame,
                runOnAll: source.runOnAll,
                sidebarHidden: true,
                handoffFeatureID: featureID))
            if !seeded { source.adoptHandoff(featureID, carrying: carry, at: nil) }
        }
    }

    /// Stop an app-wide session that a handoff left with no window showing it.
    ///
    /// `stopBackgroundWork` deliberately skips the Reactotron relay for a
    /// *moving* tab, because the tab is about to reopen and stopping the relay
    /// would drop every connected client for nothing. This is the other half of
    /// that bargain: once the move has landed, if no window has the tab after
    /// all, the relay stops here instead of running on with no way to reach it.
    func reconcileSharedSessions() {
        guard reactotronSession.isRunning, !mcp.keepsRelayAlive else { return }
        let openAnywhere = registry.entries.contains { $0.openFeatureIDs.contains("reactotron") }
        guard !openAnywhere else { return }
        Task { await reactotronSession.stop() }
    }
}

// MARK: - Menu

/// Tab ▸ Move Tab to New Window / Move Tab to Window.
///
/// Its own `View` rather than inline in the scene for the reason
/// `MirrorWindowCommands` is: the app's `body` is one large `some Scene`
/// expression, and CI's type-checker is already close to its limit on it.
struct TabHandoffCommands: View {
    let core: AppCore

    private var state: AppState? { core.frontmost }
    private var activeTab: String? { state?.activeTabID }
    private var canMoveOut: Bool {
        guard let state, let activeTab else { return false }
        return state.canDetachTabToNewWindow(activeTab)
    }

    private var canMoveToWindow: Bool {
        guard let state, let activeTab else { return false }
        return state.canDetachTab(activeTab)
    }

    var body: some View {
        Button("Move Tab to New Window") {
            guard let state, let activeTab else { return }
            state.beginHandoff(activeTab, to: .newWindow(frame: nil))
        }
        .keyboardShortcut("n", modifiers: [.command, .control])
        .disabled(!canMoveOut)

        let targets = state?.handoffTargets ?? []
        if !targets.isEmpty {
            Menu("Move Tab to Window") {
                ForEach(targets, id: \.id) { target in
                    Button(target.label) {
                        guard let state, let activeTab else { return }
                        state.beginHandoff(activeTab, to: .window(target.id, slot: nil))
                    }
                }
            }
            .disabled(!canMoveToWindow)
        }
    }
}
