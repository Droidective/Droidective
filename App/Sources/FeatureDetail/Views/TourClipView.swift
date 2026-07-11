import AVFoundation
import SwiftUI

/// Plays a bundled screen recording of the real app on the tour's demo stage,
/// looping and muted. Falls back to the drawn demo when the clip isn't
/// bundled, so a build without recordings still tours. With Reduce Motion on,
/// the clip holds its first frame instead of looping.
struct TourClipView<Fallback: View>: View {
    let clipName: String
    var height: CGFloat = 300
    @ViewBuilder var fallback: Fallback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clipURL: URL? {
        Bundle.main.url(forResource: clipName, withExtension: "mp4", subdirectory: "Tour")
            ?? Bundle.main.url(forResource: clipName, withExtension: "mp4")
    }

    var body: some View {
        if let clipURL {
            TourDemoCanvas(height: height) {
                LoopingVideoView(url: clipURL, paused: reduceMotion)
            }
        } else {
            fallback
        }
    }
}

/// An `AVPlayerLayer` looping one local file — muted, aspect-fit, no controls.
private struct LoopingVideoView: NSViewRepresentable {
    let url: URL
    let paused: Bool

    func makeNSView(context: Context) -> LoopingVideoNSView {
        LoopingVideoNSView(url: url, paused: paused)
    }

    func updateNSView(_ nsView: LoopingVideoNSView, context: Context) {}
}

private final class LoopingVideoNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL, paused: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
        if !paused { player.play() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
