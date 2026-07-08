import AppKit
import KeyboardShortcuts
import SwiftUI

/// A short paged walkthrough shown once on first launch (and replayable from
/// Home). Each step explains one part of the app; finishing or skipping marks
/// the tour seen so it won't reappear. Completing it (not skipping) ends on a
/// one-time ask to record a Quick Actions hotkey — shown only while none is
/// set, so a replay after recording one just closes.
struct TourView: View {
    @Environment(AppState.self) private var state
    @AppStorage("hasSeenTour") private var hasSeenTour = false
    @State private var index = 0
    @State private var pickingHotkey = false
    @State private var quickActionsShortcut: KeyboardShortcuts.Shortcut?

    private struct Step {
        let icon: String
        let title: String
        let body: String
        let shortcut: String?
    }

    private let steps: [Step] = [
        Step(icon: "iphone.gen3", title: "Welcome to Droidective",
             body: "Your command center for debugging Android and React Native apps over adb. Here's a 30-second tour.",
             shortcut: nil),
        Step(icon: "magnifyingglass", title: "Find anything fast",
             body: "Press the shortcut from anywhere to search every feature and jump straight to one.",
             shortcut: "⌘K"),
        Step(icon: "sidebar.left", title: "Your feature sidebar",
             body: "Features are grouped by category — toggle grouping off to drag them into your own order. Right-click any one to pin, enable, or disable it. With the search field focused, hold ⌘ to jump to a row with ⌘1–⌘9. The shortcut hides the sidebar.",
             shortcut: "⌘B"),
        Step(icon: "iphone.badge.play", title: "The device bar",
             body: "The bar up top shows the connected device and selected app bundle. It stays put as you move between features.",
             shortcut: nil),
        Step(icon: "chart.line.uptrend.xyaxis", title: "Monitor performance",
             body: "Performance Monitor charts per-core CPU, RAM, FPS, and per-process usage live; Network Speed tracks download/upload. Record a session and export it to JSON or CSV.",
             shortcut: nil),
        Step(icon: "checkmark.seal", title: "You're all set",
             body: "Open the Feature Catalog to switch on more tools, and Settings for theme and the setup Doctor. ⌘= / ⌘- zoom the whole UI. Revisit this tour anytime from Home.",
             shortcut: "⌘,"),
    ]

    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            if pickingHotkey {
                hotkeyContent
                Divider()
                hotkeyControls
            } else {
                content
                Divider()
                controls
            }
        }
        .frame(width: 540, height: 440)
    }

    private var content: some View {
        let step = steps[index]
        return VStack(spacing: 18) {
            Image(systemName: step.icon)
                .font(.app(size: 54))
                .foregroundStyle(.brandAccent)
                .symbolRenderingMode(.hierarchical)
            Text(step.title)
                .font(.app(.title).bold())
                .multilineTextAlignment(.center)
            if let shortcut = step.shortcut {
                Text(shortcut)
                    .font(.app(.title3).weight(.semibold))
                    .monospaced()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 8))
            }
            Text(step.body)
                .font(.app(.body))
                .multilineTextAlignment(.center)
                .foregroundStyle(.textMuted)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var controls: some View {
        HStack {
            Button("Skip") { finish() }
                .buttonStyle(.plain)
                .foregroundStyle(.textMuted)
                // A quiet, secondary action — suppress the accent-colored
                // keyboard focus ring so it doesn't read as a primary button.
                .focusEffectDisabled()
                .opacity(isLast ? 0 : 1)

            Spacer()

            HStack(spacing: 7) {
                ForEach(steps.indices, id: \.self) { i in
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
                Button(isLast ? "Get Started" : "Next") {
                    if isLast {
                        advancePastTour()
                    } else {
                        withAnimation { index += 1 }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var hotkeyContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "bolt.fill")
                .font(.app(size: 54))
                .foregroundStyle(.brandAccent)
                .symbolRenderingMode(.hierarchical)
            Text("One more thing: Quick Actions")
                .font(.app(.title).bold())
                .multilineTextAlignment(.center)
            Text("A global hotkey summons the Quick Actions panel from any app — run adb actions, manage apps, and boot emulators without opening the window. Pick one now, or change it anytime in Settings ▸ Hotkeys.")
                .font(.app(.body))
                .multilineTextAlignment(.center)
                .foregroundStyle(.textMuted)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                HotkeyRecorderField(name: .quickActions)
                    .frame(width: 220)
                Text("Recommended: ⇧⌘Space — it's free on a stock Mac, and Spotlight keeps ⌘Space.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onChange(of: HotkeyRecording.shared.active) {
            quickActionsShortcut = KeyboardShortcuts.getShortcut(for: .quickActions)
        }
    }

    private var hotkeyControls: some View {
        HStack {
            Button("Maybe Later") { finish() }
                .buttonStyle(.plain)
                .foregroundStyle(.textMuted)
                .focusEffectDisabled()
                .keyboardShortcut(.cancelAction)

            Spacer()

            if quickActionsShortcut == nil {
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
                Button("Done") { finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Completing the tour asks for a Quick Actions hotkey — but only while
    /// none is recorded, so it never nags after a choice (or a replay).
    private func advancePastTour() {
        hasSeenTour = true
        if KeyboardShortcuts.getShortcut(for: .quickActions) == nil {
            withAnimation { pickingHotkey = true }
        } else {
            state.presentTour = false
        }
    }

    private func finish() {
        hasSeenTour = true
        state.presentTour = false
    }
}
