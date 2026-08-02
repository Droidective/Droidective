import AppKit
import SwiftUI

/// Copies and reports whether there was anything to copy — an empty body
/// shouldn't claim success. (`copyToPasteboard` is the app-wide unconditional
/// twin; the acknowledgement here needs to know when nothing happened.)
@discardableResult
@MainActor
func copyApiText(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    copyToPasteboard(text)
    return true
}

/// A copy button that says so: the icon becomes a checkmark for a moment after
/// a successful copy, because a button that looks identical before and after
/// leaves you wondering whether the click registered — and re-copying "just in
/// case" is the tell that it didn't.
///
/// Reactotron has its own filled-pill variant suited to that console; this is
/// the borderless icon a dense toolbar wants.
///
/// Nothing moves: the checkmark is drawn in the same slot as the icon, so a row
/// of controls doesn't reflow on every copy.
struct ApiCopyButton: View {
    let help: String
    /// Optional visible label, for the places that show "Copy" rather than an
    /// icon alone.
    var title: String?
    let text: () -> String

    @State private var copied = false
    @State private var revert: Task<Void, Never>?

    /// Long enough to notice, short enough not to linger past the next action.
    private static let holdSeconds: Double = 1.2

    var body: some View {
        Button {
            guard copyApiText(text()) else { return }
            acknowledge()
        } label: {
            if let title {
                Label(copied ? "Copied" : title, systemImage: symbol)
                    .foregroundStyle(copied ? Color.brandAccent : Color.textMain)
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(copied ? Color.brandAccent : Color.textMain)
                    // Both glyphs share one frame so the checkmark can't nudge
                    // its neighbours.
                    .frame(width: 16, alignment: .center)
            }
        }
        .help(copied ? "Copied" : help)
        .animation(.easeInOut(duration: 0.15), value: copied)
        .onDisappear { revert?.cancel() }
    }

    private var symbol: String { copied ? "checkmark" : "doc.on.doc" }

    private func acknowledge() {
        copied = true
        // A second copy restarts the hold rather than reverting mid-way.
        revert?.cancel()
        revert = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.holdSeconds))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

/// The acknowledgement for copies started from a menu, where the control that
/// would show a checkmark has already closed. A small capsule naming what was
/// copied, which fades itself out.
struct ApiCopyToast: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.textMain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.bgSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.borderSubtle))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: message)
    }
}

extension View {
    /// Shows `message` as a transient "copied" capsule over this view.
    func apiCopyToast(_ message: Binding<String?>) -> some View {
        modifier(ApiCopyToast(message: message))
    }
}
