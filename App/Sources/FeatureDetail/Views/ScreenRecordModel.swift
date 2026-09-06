import ADBKit
import Foundation

/// A screen recording in progress, kept per window by `FeatureStateStore`
/// rather than as view `@State`.
///
/// The recorder writes to its file through a headless scrcpy session that owes
/// nothing to the view — the view only polls it for a preview frame. So a tab
/// moving to another window need not interrupt a take: the recorder crosses
/// with the tab and the receiving window re-arms the preview, the device lock
/// and the leave guard. Aborting one because a window changed would be
/// destroying the user's recording to satisfy a view lifecycle.
///
/// A *finished* take waiting on Save/Discard/Edit (`decisionURL`) matters just
/// as much: it is a file the user has not decided about yet.
@MainActor
@Observable
final class ScreenRecordModel {
    /// The live recorder, nil when nothing is being captured.
    var recorder: ScreenRecorder?
    var isRecording = false
    var isPaused = false
    /// Reference date for the elapsed timer, shifted forward on each resume so
    /// the displayed time counts only *active* recording (paused excluded).
    var startedAt: Date?
    /// When the current pause began; nil while actively recording.
    var pausedAt: Date?
    /// The file being written, before the user has decided what to do with it.
    var recordedURL: URL?
    /// A finished recording awaiting the Discard/Save/Edit choice.
    var decisionURL: URL?
    /// The serial the active recording targets, watched for disconnects.
    var recordingSerial: String?
    /// The recording device vanished mid-capture: the captured segments are
    /// kept and only Stop (save/edit/discard) remains.
    var deviceLost = false
    /// Stops the recording at the chosen duration. A plain `Task`, so it keeps
    /// counting across a move — the limit is about the recording, not the view.
    var limitTask: Task<Void, Never>?
    /// Identifies the leave guard, so a stale clear can't wipe another's — and
    /// so the window this tab moves to re-registers the same one.
    let exitGuardID = UUID()

    /// Whether there is anything a close would destroy.
    var hasUndecidedWork: Bool { isRecording || recordedURL != nil || decisionURL != nil }

    /// Give up the recording and its file — the tab is closing for good.
    func abortAndDiscard() {
        limitTask?.cancel()
        limitTask = nil
        if isRecording, let recorder {
            Task { await recorder.abort() }
        }
        for url in [recordedURL, decisionURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        isRecording = false
        recordedURL = nil
        decisionURL = nil
    }
}
