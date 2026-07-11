import AppKit
import KeyboardShortcuts
import SwiftUI

/// The onboarding tour, shown once on first launch and replayable from Home:
/// five pages, each led by a looping animated demo (see `TourDemos.swift`) —
/// the sidebar, tabs & split panes, roles, settings & hotkeys, and finally the
/// Quick Actions panel with an inline ask to record its global hotkey (the
/// recorder shows only while no hotkey is set). Finishing or skipping marks
/// the tour seen so it won't reappear.
struct TourView: View {
    @Environment(AppState.self) private var state
    @AppStorage("hasSeenTour") private var hasSeenTour = false
    @State private var index = 0
    @State private var quickActionsShortcut: KeyboardShortcuts.Shortcut?

    private enum Demo {
        case sidebar, tabs, roles, settings, quickActions
    }

    private struct Page {
        let demo: Demo
        let title: String
        let body: String
    }

    private static let pages: [Page] = [
        Page(demo: .sidebar, title: "Your feature sidebar",
             body: "Every tool lives in the sidebar, grouped by category. Right-click to pin favorites, "
                 + "drag to reorder, or press ⌘T and search — ⏎ opens the top match."),
        Page(demo: .tabs, title: "Tabs & split panes",
             body: "Open features in tabs with the + button (or ⌘T). Drag a tab onto the content "
                 + "to split the pane and watch two features side by side — logs next to performance."),
        Page(demo: .roles, title: "Pick your role",
             body: "Your role curates which tools lead — React Native, QA, Android, security, and more. "
                 + "It's a starting point, not a limit: change it anytime from Home, and add any tool back."),
        Page(demo: .settings, title: "Settings & hotkeys",
             body: "⌘, opens Settings: theme, the setup Doctor that checks your toolchain, and Hotkeys — "
                 + "give any feature a global shortcut that works even while Droidective is in the background."),
        Page(demo: .quickActions, title: "Quick Actions, from anywhere",
             body: "One hotkey summons a Raycast-style panel over any app — run adb actions, manage apps, "
                 + "and boot emulators without opening the window."),
    ]

    private var isLast: Bool { index == Self.pages.count - 1 }
    private var page: Page { Self.pages[index] }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            controls
        }
        .frame(width: 780, height: 700)
        .onAppear { quickActionsShortcut = KeyboardShortcuts.getShortcut(for: .quickActions) }
        .onChange(of: HotkeyRecording.shared.active) {
            quickActionsShortcut = KeyboardShortcuts.getShortcut(for: .quickActions)
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            // The stage flexes to absorb whatever height the text below
            // doesn't need — no dead space between the clip and the controls.
            demo
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(index)   // restart the loop when the page changes
            Text(page.title)
                .font(.app(.title2).bold())
                .multilineTextAlignment(.center)
            Text(page.body)
                .font(.app(.body))
                .multilineTextAlignment(.center)
                .foregroundStyle(.textMuted)
                .frame(maxWidth: 560)
                .fixedSize(horizontal: false, vertical: true)
            if isLast {
                hotkeyAsk
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Each page leads with a looping recording of the real app
    /// (`App/Resources/Tour/tour-*.mp4`); the drawn demo is the fallback for
    /// a build without recordings.
    @ViewBuilder private var demo: some View {
        switch page.demo {
        case .sidebar:
            TourClipView(clipName: "tour-sidebar") { SidebarTourDemo() }
        case .tabs:
            TourClipView(clipName: "tour-tabs") { TabsSplitTourDemo() }
        case .roles:
            TourClipView(clipName: "tour-roles") { RolesTourDemo() }
        case .settings:
            TourClipView(clipName: "tour-settings") { SettingsHotkeysTourDemo() }
        case .quickActions:
            TourClipView(clipName: "tour-quick-actions") { QuickActionsTourDemo() }
        }
    }

    /// The final page's inline recorder — only while no hotkey is set; once
    /// one is recorded it shows the choice instead of nagging.
    @ViewBuilder private var hotkeyAsk: some View {
        if quickActionsShortcut == nil {
            VStack(spacing: 6) {
                HotkeyRecorderField(name: .quickActions)
                    .frame(width: 220)
                Text("Recommended: ⇧⌘Space — free on a stock Mac; Spotlight keeps ⌘Space.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }
        } else {
            Label("Quick Actions is on \(quickActionsShortcut.map(String.init(describing:)) ?? "")",
                  systemImage: "checkmark.circle.fill")
                .font(.app(.callout))
                .foregroundStyle(.brandAccent)
        }
    }

    private var controls: some View {
        HStack {
            Button(isLast && quickActionsShortcut == nil ? "Maybe Later" : "Skip") { skip() }
                .buttonStyle(.plain)
                .foregroundStyle(.textMuted)
                // A quiet, secondary action — suppress the accent-colored
                // keyboard focus ring so it doesn't read as a primary button.
                .focusEffectDisabled()
                .opacity(isLast && quickActionsShortcut != nil ? 0 : 1)

            Spacer()

            HStack(spacing: 7) {
                ForEach(Self.pages.indices, id: \.self) { i in
                    Circle()
                        .fill(i == index ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.quaternary))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if index > 0 {
                    Button("Back") { withAnimation { index -= 1 } }
                }
                if !isLast {
                    Button("Next") { withAnimation { index += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else if quickActionsShortcut == nil {
                    Button("Use ⇧⌘Space") {
                        // Launcher-style but free on a stock Mac: ⌘Space is
                        // Spotlight, ⌥Space is usually Raycast/Alfred, and
                        // ⌃Space/⌃⌥Space switch input sources.
                        KeyboardShortcuts.setShortcut(
                            KeyboardShortcuts.Shortcut(.space, modifiers: [.shift, .command]),
                            for: .quickActions
                        )
                        finish()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") { finish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Skipping mid-tour still lands on the Quick Actions page while no
    /// hotkey is recorded — the panel is only reachable through its shortcut,
    /// so closing without one would quietly leave the feature unusable. With
    /// a hotkey already set (or from that page's "Maybe Later"), skip closes.
    private func skip() {
        if !isLast, quickActionsShortcut == nil {
            withAnimation { index = Self.pages.count - 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        hasSeenTour = true
        state.presentTour = false
    }
}
