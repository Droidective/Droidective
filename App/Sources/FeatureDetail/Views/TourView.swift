import AppKit
import KeyboardShortcuts
import SwiftUI

/// The onboarding tour, shown once on first launch and replayable from Home:
/// six pages, each led by a looping animated demo (see `TourDemos.swift`) —
/// the sidebar, tabs & split panes, roles, settings & hotkeys, then the two
/// Quick Actions steps: *pick the hotkey* (recorder inline; Next stays
/// disabled until one is set) and *try it*, whose stage is the user's own
/// hotkey drawn as keycaps pressing themselves. The try page is the only
/// exit and it can't be skipped: pressing the hotkey for real — building the
/// muscle memory, no button shortcut — opens Quick Actions, completes the
/// tour, marks it seen, and fires the confetti celebration
/// (`AppState.noteQuickActionsOpened`).
struct TourView: View {
    @Environment(AppState.self) private var state
    @State private var index = 0
    @State private var quickActionsShortcut: KeyboardShortcuts.Shortcut?

    private enum Demo {
        case sidebar, tabs, roles, settings, quickActions, pressHotkey
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
                 + "and boot emulators without opening the window. Pick that hotkey now."),
        Page(demo: .pressHotkey, title: "Try Quick Actions",
             body: "The home stretch: summon the panel once and the tour ends with a bang."),
    ]

    private var isLast: Bool { index == Self.pages.count - 1 }
    /// The pick-your-hotkey page, right before the try-it finale.
    private var isHotkeyPage: Bool { index == Self.pages.count - 2 }
    private var page: Page { Self.pages[index] }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            controls
        }
        .frame(width: 780, height: 700)
        // Non-skippable: no Esc / click-away dismissal — the tour ends by
        // trying Quick Actions on the last page.
        .interactiveDismissDisabled()
        .onAppear { quickActionsShortcut = KeyboardShortcuts.getShortcut(for: .quickActions) }
        .onChange(of: HotkeyRecording.shared.active) {
            quickActionsShortcut = KeyboardShortcuts.getShortcut(for: .quickActions)
        }
        // The panel-open hook completes the tour only while the final page is
        // waiting for it — earlier pages (and normal app use) stay inert.
        .onChange(of: index, initial: true) { _, new in
            state.awaitingQuickActionsTry = new == Self.pages.count - 1
        }
        .onDisappear { state.awaitingQuickActionsTry = false }
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
            if isHotkeyPage {
                hotkeyAsk
            }
            if isLast {
                tryGuide
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
        case .pressHotkey:
            HotkeyPressDemo(caps: keyCaps)
        }
    }

    /// The recorded hotkey split into keycap labels for the try-it stage —
    /// leading modifier symbols one cap each, then the key (␣ spelled out).
    private var keyCaps: [String] {
        let description = quickActionsShortcut.map(String.init(describing:)) ?? "⇧⌘␣"
        var caps: [String] = []
        var rest = Substring(description)
        while let first = rest.first, "⌃⌥⇧⌘".contains(first) {
            caps.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty {
            caps.append(rest == "␣" ? "space" : String(rest))
        }
        return caps
    }

    /// The pick-hotkey page's inline recorder — only while no hotkey is set;
    /// once one is recorded it shows the choice instead of nagging. Next
    /// stays disabled until this is answered.
    @ViewBuilder private var hotkeyAsk: some View {
        if quickActionsShortcut == nil {
            VStack(spacing: 8) {
                HotkeyRecorderField(name: .quickActions)
                    .frame(width: 220)
                Text("Recommended: ⇧⌘Space — free on a stock Mac; Spotlight keeps ⌘Space.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
                Button("Use ⇧⌘Space") {
                    // Launcher-style but free on a stock Mac: ⌘Space is
                    // Spotlight, ⌥Space is usually Raycast/Alfred, and
                    // ⌃Space/⌃⌥Space switch input sources.
                    KeyboardShortcuts.setShortcut(
                        KeyboardShortcuts.Shortcut(.space, modifiers: [.shift, .command]),
                        for: .quickActions
                    )
                    quickActionsShortcut = KeyboardShortcuts.getShortcut(for: .quickActions)
                }
            }
        } else {
            Label("Quick Actions is on \(quickActionsShortcut.map(String.init(describing:)) ?? "")",
                  systemImage: "checkmark.circle.fill")
                .font(.app(.callout))
                .foregroundStyle(.brandAccent)
        }
    }

    /// The hotkey the try-guide tells the user to press — live, so it never
    /// names a combo they didn't set.
    private var shortcutHint: String {
        quickActionsShortcut.map(String.init(describing:)) ?? "⇧⌘Space"
    }

    /// The last step's walkthrough: pressing the hotkey to open the panel is
    /// the tour's finish line (confetti included), so spell out exactly how.
    private var tryGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            guideRow(1, "Press \(shortcutHint) — it works anywhere, even with this window closed.")
            guideRow(2, "Type to find an action, then ⏎ runs it on your device.")
            guideRow(3, "Esc closes the panel when you're done.")
        }
        .padding(.top, 2)
    }

    private func guideRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.app(.caption).weight(.bold))
                .foregroundStyle(.brandAccent)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.brandAccent.opacity(0.15)))
            Text(text)
                .font(.app(.callout))
                .foregroundStyle(.textMain)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack {
            // Skip only fast-forwards to the last page — the try-it step
            // itself has no skip; opening the panel is the tour's one exit.
            Button("Skip") { skip() }
                .buttonStyle(.plain)
                .foregroundStyle(.textMuted)
                // A quiet, secondary action — suppress the accent-colored
                // keyboard focus ring so it doesn't read as a primary button.
                .focusEffectDisabled()
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)

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
                    // On the try page this returns to the pick-hotkey page.
                    Button("Back") { withAnimation { index -= 1 } }
                }
                if !isLast {
                    // The try page needs a hotkey to press, so the pick page
                    // holds the gate.
                    Button("Next") { withAnimation { index += 1 } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isHotkeyPage && quickActionsShortcut == nil)
                }
                // The try page adds no forward control on purpose: the finish
                // line is *pressing the hotkey* — the muscle memory the panel
                // lives on. The open completes the tour
                // (`noteQuickActionsOpened`) and pops confetti.
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Skipping mid-tour jumps to the tour's payoff: the try-it finale, via
    /// the pick-hotkey page when none is recorded yet (the finale needs a
    /// hotkey to press).
    private func skip() {
        withAnimation {
            index = quickActionsShortcut == nil ? Self.pages.count - 2 : Self.pages.count - 1
        }
    }
}

/// The try-it page's stage: the user's own hotkey drawn as oversized keycaps
/// that press themselves in a loop — the visual instruction to press it for
/// real. Driven by a TimelineView clock (a `repeatForever` animation can
/// stall when the sheet re-renders — see the sidebar jiggle).
private struct HotkeyPressDemo: View {
    let caps: [String]

    var body: some View {
        TimelineView(.animation) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2)
            let pressed = cycle > 1.3 && cycle < 1.8
            HStack(spacing: 16) {
                ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                    KeyCapView(label: cap, pressed: pressed)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: pressed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One oversized keyboard key, drawn resting or pressed (sunken, accented).
private struct KeyCapView: View {
    let label: String
    let pressed: Bool

    /// Named keys ("space") get a wide cap; symbols stay square.
    private var isWide: Bool { label.count > 1 }

    var body: some View {
        Text(label)
            .font(.app(size: isWide ? 26 : 38, weight: .medium))
            .foregroundStyle(pressed ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.textMain))
            .frame(width: isWide ? 210 : 84, height: 84)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(pressed ? AnyShapeStyle(.brandAccent.opacity(0.18)) : AnyShapeStyle(.bgSurface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        pressed ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.separator),
                        lineWidth: pressed ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(pressed ? 0.12 : 0.3), radius: pressed ? 2 : 7, y: pressed ? 1 : 6)
            .offset(y: pressed ? 4 : 0)
    }
}
