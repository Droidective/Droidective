import ADBKit
import SwiftUI

/// Expandable list of recent user-initiated adb commands.
struct CommandLogView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [CommandLogEntry] = []
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Command Log")
                    .font(.app(.headline))
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Refresh")
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Clear command log")
                Button("Close") { dismiss() }
            }
            .padding(12)
            .confirmationDialog(
                "Clear the command log?",
                isPresented: $confirmClear,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) {
                    Task {
                        await state.env.commandLog.clear()
                        await refresh()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all recorded commands.")
            }

            Divider()

            if entries.isEmpty {
                ContentUnavailableView(
                    "No commands yet",
                    systemImage: "terminal",
                    description: Text("Commands you run appear here with their output.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    CommandLogRow(entry: entry)
                }
            }
        }
        .frame(width: 560, height: 420)
        .task { await refresh() }
    }

    private func refresh() async {
        entries = await state.env.commandLog.snapshot()
    }
}
