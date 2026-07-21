import SwiftUI

/// Recurring nudge to star the project on GitHub, shown every few launches
/// until the user stars or the ask cap is hit (cadence + outcome handled in
/// RootView). The view is presentation-only: it opens the repo via `onStar`
/// and dismisses; RootView's `onDismiss` records the outcome.
struct StarPromptView: View {
    @Environment(\.dismiss) private var dismiss

    /// Opens the GitHub repository (routed through AppState so views stay thin).
    let onStar: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "star.fill")
                .font(.app(size: 34, weight: .semibold))
                .foregroundStyle(.brandAccent)
                .frame(width: 64, height: 64)
                .background(Color.brandAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 7) {
                Text("Enjoying the app?")
                    .font(.app(.title2).bold())
                Text("If the project's useful to you, consider giving it a star on GitHub. It takes a moment and genuinely helps others find it.")
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button {
                    onStar()
                    dismiss()
                } label: {
                    Label("Star on GitHub", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .tint(.brandAccent)

                Button("Maybe Later") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
            }
        }
        .padding(28)
        .frame(width: 380)
        .background(.bgRoot)
    }
}
