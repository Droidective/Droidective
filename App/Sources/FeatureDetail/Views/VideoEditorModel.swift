import ADBKit
import AVFoundation
import Foundation

/// A video open in the editor, kept per window by `FeatureStateStore` rather
/// than as view `@State`.
///
/// Two things here are expensive enough that losing them to a tab moving reads
/// as a restart. The **edits** — trim, rotate, crop, speed, the undo stack
/// behind them — are unsaved work: nothing is written until Export. The
/// **proxy** is an MP4 ffmpeg builds when AVFoundation can't play the source
/// (an AV1 `.mp4`, most `.mkv`), which for a long recording is a transcode of
/// the whole file; rebuilding it because a window changed would make the editor
/// unusable for a minute for no reason.
///
/// The player travels too. A fresh `AVPlayer` on the far side would reload,
/// re-buffer and lose the playhead — and for a proxied source it would have to
/// be pointed back at the proxy anyway, which is exactly what `builtFor`
/// records.
@MainActor
@Observable
final class VideoEditorModel {
    /// What the editor has open, nil when this tab shows no editor. The hosts
    /// render `VideoEditorPane` exactly while this holds a source.
    var source: VideoSource?
    /// The source `player`, `asset` and `proxyURL` were built for. A `.task`
    /// that finds this unchanged is a remount — the tab moved — not a new
    /// video, so it keeps what it has instead of starting over.
    private(set) var builtFor: VideoSource?

    private(set) var player = AVPlayer()
    private(set) var asset: AVURLAsset?
    /// Bridges the AVKit trim UI, which lives on the player view.
    let trimmer = VideoTrimmer()

    var edit = EditState()
    var undoStack: [EditState] = []
    var redoStack: [EditState] = []
    /// The edit state at the last successful export; edits matching it count as
    /// saved, so the leave prompt doesn't fire after exporting.
    var lastExportedEdit: EditState?
    /// An export runs in a task the view doesn't own, so a move must not make
    /// the button look ready while it is still going.
    var isExporting = false

    var videoSize: CGSize?
    var assetDuration: Double = 0

    /// An MP4 stand-in for a source AVFoundation refuses, built by ffmpeg and
    /// used for playback only — the export always reads `source.url`, so a
    /// proxy costs the saved file nothing. Deleted when the editor closes.
    var proxyURL: URL?
    /// Neither a remux nor a transcode produced something playable: the file
    /// can't be edited here, and saying so beats a black pane.
    var proxyFailed = false

    var cropMode = false
    var cropBeforeEditing: CropRect?

    /// Identifies the leave guard, so a stale clear can't wipe another's — and
    /// so the window this tab moves to re-registers the same one.
    let exitGuardID = UUID()

    /// Open `source`, unless it is already open. Hosts call this to put the
    /// editor up — building the player here rather than in the pane's `.task`
    /// keeps the first frame from being a black pane — and the pane calls it
    /// again from that task, where a remount caused by a move must change
    /// nothing at all.
    func open(_ source: VideoSource) {
        guard builtFor != source else { return }
        discardProxy()
        let asset = AVURLAsset(url: source.url)
        self.asset = asset
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        builtFor = source
        self.source = source
        edit = EditState()
        undoStack = []
        redoStack = []
        lastExportedEdit = nil
        videoSize = nil
        assetDuration = 0
        proxyFailed = false
        cropMode = false
        cropBeforeEditing = nil
    }

    /// Play a proxy instead of the source. A *fresh* `AVPlayer`, not
    /// `replaceCurrentItem`: a player that already failed on the original is
    /// permanently `.failed` and can't be recovered by handing it a new item.
    func playProxy(at url: URL) {
        proxyURL = url
        let swapped = AVURLAsset(url: url)
        asset = swapped
        player = AVPlayer(playerItem: AVPlayerItem(asset: swapped))
    }

    /// Close the editor. The source file is the caller's to deal with — a
    /// recording is a temp file it deletes, an opened file is never touched —
    /// but the proxy is ours.
    func close() {
        player.pause()
        discardProxy()
        source = nil
        builtFor = nil
        asset = nil
        player = AVPlayer()
        edit = EditState()
        undoStack = []
        redoStack = []
        lastExportedEdit = nil
        videoSize = nil
        assetDuration = 0
        proxyFailed = false
        cropMode = false
        cropBeforeEditing = nil
        isExporting = false
    }

    /// Give up the editor *and* the recording it was opened on — the tab is
    /// closing, so the temp file nobody chose to keep goes with it. An opened
    /// file is never deleted, which is the whole difference `VideoSource` draws.
    func closeAndDiscardRecording() {
        if case .recording(let url) = source {
            try? FileManager.default.removeItem(at: url)
        }
        close()
    }

    /// Unsaved edits exist — the ones a leave would discard.
    var hasUnsavedEdits: Bool { edit != EditState() && edit != lastExportedEdit }

    /// The proxy is scratch: nothing refers to it once the editor is done with
    /// it, and a transcoded recording is the size of the original.
    private func discardProxy() {
        guard let proxyURL else { return }
        try? FileManager.default.removeItem(at: proxyURL)
        self.proxyURL = nil
    }
}
