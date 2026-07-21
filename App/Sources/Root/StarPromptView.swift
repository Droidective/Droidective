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
        VStack(spacing: 16) {
            Image(systemName: "star.fill")
                .font(.app(size: 20, weight: .semibold))
                .foregroundStyle(.brandAccent)
                .frame(width: 40, height: 40)
                .background(Color.brandAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 6) {
                Text("Enjoying the app?")
                    .font(.app(.title3).bold())
                Text("If the project's useful to you, a star on GitHub helps others find it.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Maybe Later") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .frame(maxWidth: .infinity)

                Button {
                    onStar()
                    dismiss()
                } label: {
                    Label("Star on GitHub", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .tint(.brandAccent)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 380)
        .background(.bgRoot)
    }
}
