import AVFoundation
import AVKit
import Combine
import SwiftUI

/// Hosts an `AVPlayerView` with its controls hidden — playback runs through
/// `VideoTransportBar` below the video instead, because AVKit's floating
/// overlay collapses into overlapping glyphs when a portrait video makes the
/// player narrow. The parent owns the `AVPlayer` so it can drive mute/speed/
/// seek; trim requests route through `VideoTrimmer`, which shows the native
/// controls only for the duration of the trim UI.
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let trimmer: VideoTrimmer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        trimmer.playerView = view
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
        trimmer.playerView = nsView
    }
}

/// A bare `AVPlayerLayer` host with no controls at all — used while cropping so
/// nothing overlays the crop selection.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.playerLayer.player = player
    }
}

final class PlayerContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer = playerLayer
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

/// Bridges SwiftUI controls to `AVPlayerView`'s built-in trimming UI. After the
/// user commits a trim, AVKit applies the in/out points to the player item as
/// `reversePlaybackEndTime` / `forwardPlaybackEndTime`; we read them back. The
/// trim result is bridged through a continuation so the `@Sendable` AVKit
/// completion captures only the (Sendable) continuation, never the player.
@MainActor
final class VideoTrimmer {
    weak var playerView: AVPlayerView?

    var canTrim: Bool { playerView?.canBeginTrimming ?? false }

    /// Present the trim UI; returns the chosen (start, end) in seconds, or nil if
    /// cancelled. An edge the user didn't move comes back as 0 / full duration.
    func beginTrim() async -> (start: Double, end: Double)? {
        guard let view = playerView else { return nil }
        // The trim UI rides AVKit's own controls, which stay hidden otherwise
        // (playback runs through VideoTransportBar) — show them just for the trim.
        view.controlsStyle = .floating
        defer { view.controlsStyle = .none }
        guard view.canBeginTrimming else { return nil }
        let committed = await withCheckedContinuation { continuation in
            view.beginTrimming { result in continuation.resume(returning: result == .okButton) }
        }
        guard committed, let item = view.player?.currentItem else { return nil }
        let duration = item.duration.seconds
        let startTime = item.reversePlaybackEndTime
        let endTime = item.forwardPlaybackEndTime
        let start = (startTime.isValid && !startTime.isIndefinite) ? max(0, startTime.seconds) : 0
        let end = (endTime.isValid && !endTime.isIndefinite && endTime.seconds > 0)
            ? endTime.seconds : duration
        return (start, end)
    }
}

/// Always-visible transport controls for the video editor: play/pause, a
/// scrubber, and timecodes. Sits below the player instead of overlaying it,
/// so the controls keep a full-width layout no matter how narrow the video is.
struct VideoTransportBar: View {
    let player: AVPlayer
    let duration: Double

    @State private var currentTime = 0.0
    @State private var isPlaying = false
    @State private var isScrubbing = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.app(.title3))
                    .frame(width: 30, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play")

            Text(timecode(currentTime))
                .font(.app(.callout)).monospacedDigit()
                .foregroundStyle(.textMuted)

            Slider(
                value: Binding(
                    get: { min(currentTime, duration) },
                    set: { currentTime = $0 }
                ),
                in: 0 ... max(duration, 0.01)
            ) { editing in
                isScrubbing = editing
                if !editing { seek(to: currentTime) }
            }

            Text(timecode(duration))
                .font(.app(.callout)).monospacedDigit()
                .foregroundStyle(.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            guard !isScrubbing else { return }
            let time = player.currentTime().seconds
            if time.isFinite { currentTime = time }
        }
        .onChange(of: currentTime) { _, time in
            if isScrubbing { seek(to: time) }
        }
        .onReceive(player.publisher(for: \.timeControlStatus)) { status in
            isPlaying = status != .paused
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            return
        }
        // Play from the paused position — or restart from the clip's start when
        // playback already ran to the (possibly trimmed) end.
        if let item = player.currentItem {
            let forward = item.forwardPlaybackEndTime
            let end = (forward.isValid && !forward.isIndefinite && forward.seconds > 0)
                ? forward.seconds : duration
            if end > 0, currentTime >= end - 0.05 {
                let reverse = item.reversePlaybackEndTime
                let start = (reverse.isValid && !reverse.isIndefinite) ? max(0, reverse.seconds) : 0
                seek(to: start)
            }
        }
        player.play()
    }

    private func seek(to seconds: Double) {
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func timecode(_ seconds: Double) -> String {
        let total = seconds.isFinite ? Int(seconds.rounded()) : 0
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
