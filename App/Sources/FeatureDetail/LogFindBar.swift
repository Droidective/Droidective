import SwiftUI

/// The Find strip shared by the log panes (logcat, iOS logs). Find highlights
/// matches and steps between them without hiding anything — the toolbar's
/// Filter field is the control that hides non-matching lines. Focuses itself
/// on appear; ⏎/⌘G step forward, ⇧⌘G steps back, Esc closes.
struct LogFindBar: View {
    @Binding var text: String
    /// "3 of 41" / "No matches" — nil hides the label (empty query).
    let countLabel: String?
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    /// Bump to re-focus the field — ⌘F pressed while the bar is already open.
    var focusToken = 0
    /// Attach the ⌘G/⇧⌘G shortcuts only while the owning tab is the active
    /// one — keep-alive hidden tabs stay mounted, and a hidden bar's
    /// shortcuts steal the keys from the visible one.
    var shortcutsActive = true
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in logs", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(onNext)
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
                .frame(maxWidth: 240)
            if let countLabel {
                Text(countLabel)
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                    .monospacedDigit()
            }
            Spacer()
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(IconButtonStyle())
            .help("Previous match (⇧⌘G)")
            .keyboardShortcut(shortcutsActive ? KeyboardShortcut("g", modifiers: [.command, .shift]) : nil)
            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(IconButtonStyle())
            .help("Next match (⌘G)")
            .keyboardShortcut(shortcutsActive ? KeyboardShortcut("g", modifiers: .command) : nil)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconButtonStyle())
            .help("Close find (Esc)")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.yellow.opacity(0.08))
        .onAppear { focused = true }
        // Deferred: a synchronous @FocusState write doesn't take while
        // another field (e.g. the sidebar search) still holds focus.
        .onChange(of: focusToken) { _, _ in
            Task { @MainActor in focused = true }
        }
    }
}
