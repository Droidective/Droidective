import ADBKit
import SwiftUI

/// After a recording stops, ask what to do with it: open it in the video editor,
/// save it as-is to the capture folder, or discard it. Shared by Screen Record
/// and Mirror Screen. The recording lives in a temp file until the choice is
/// made; cancelling the dialog discards it (so nothing is orphaned).
private struct RecordingDecisionModifier: ViewModifier {
    @Environment(AppState.self) private var state
    @Binding var url: URL?
    let onEdit: (URL) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Recording finished", isPresented: presented, titleVisibility: .visible
        ) {
            Button("Edit") { act(onEdit) }
            Button("Save") { act(save) }
            Button("Discard", role: .destructive) { act(discard) }
        } message: {
            Text("Edit it in the video editor, save it to your capture folder, or discard it.")
        }
    }

    /// Shown while a recording awaits a decision. Dismissing without a choice
    /// (Cancel/Escape) discards the temp file.
    private var presented: Binding<Bool> {
        Binding(
            get: { url != nil },
            set: { shown in if !shown, let pending = url { url = nil; discard(pending) } })
    }

    /// Clear `url` first so the dialog's dismissal doesn't also fire the
    /// cancel/discard path, then run the chosen action.
    private func act(_ body: (URL) -> Void) {
        guard let pending = url else { return }
        url = nil
        body(pending)
    }

    private func discard(_ pending: URL) {
        try? FileManager.default.removeItem(at: pending)
    }

    private func save(_ pending: URL) {
        do {
            let dir = try ScreenCaptureService.ensureCaptureDir()
            let dest = dir.appendingPathComponent("recording_\(ScreenCaptureService.stamp()).mp4")
            try FileManager.default.moveItem(at: pending, to: dest)
            state.showToast(Toast(message: "Recording saved", ok: true, revealPath: dest.path))
        } catch {
            state.showToast(Toast(message: "Couldn’t save recording: \(error.localizedDescription)", ok: false))
        }
    }
}

extension View {
    /// Present the Discard/Save/Edit prompt when `url` is set to a finished
    /// recording. `onEdit` receives the file to open in the editor.
    func recordingDecision(url: Binding<URL?>, onEdit: @escaping (URL) -> Void) -> some View {
        modifier(RecordingDecisionModifier(url: url, onEdit: onEdit))
    }
}
