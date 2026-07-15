import Foundation

/// Decides whether a mirror session that just ended should be reconnected
/// without audio.
///
/// scrcpy starts its audio encoder while bringing the session up. On devices
/// that can't capture audio — most emulators, where `AudioRecord` can't be
/// created — that encoder fails *before* the first video frame and scrcpy aborts
/// the whole session, video included. So when audio was requested and the
/// session died before ever streaming a frame, audio is the likely culprit and a
/// video-only reconnect keeps mirroring working. If video had already streamed,
/// the session ended for some other reason and must not be silently restarted.
///
/// `stopped` is the owner's terminal teardown. A stop during bring-up also ends
/// the session before its first frame (the transport surfaces it as a push or
/// connect failure, not a cancellation), which is indistinguishable from an
/// audio abort by timing alone — retrying then resurrects a session nothing
/// owns, leaking a headless mirror that streams and decodes until the app
/// quits (Sentry DROIDECTIVE-MAC-2K: several leaks stacked to 578% CPU).
public enum MirrorAudioFallback {
    public static func shouldRetryWithoutAudio(
        audioRequested: Bool, everStreamed: Bool, stopped: Bool
    ) -> Bool {
        audioRequested && !everStreamed && !stopped
    }
}
