import Testing
@testable import ADBKit

@Suite struct MirrorAudioFallbackTests {
    @Test func retriesWhenAudioOnAndNeverStreamed() {
        #expect(MirrorAudioFallback.shouldRetryWithoutAudio(
            audioRequested: true, everStreamed: false, stopped: false))
    }

    @Test func noRetryOnceVideoStreamed() {
        #expect(!MirrorAudioFallback.shouldRetryWithoutAudio(
            audioRequested: true, everStreamed: true, stopped: false))
    }

    @Test func noRetryWhenAudioWasNotRequested() {
        // Already video-only: nothing to fall back to (and avoids a retry loop).
        #expect(!MirrorAudioFallback.shouldRetryWithoutAudio(
            audioRequested: false, everStreamed: false, stopped: false))
        #expect(!MirrorAudioFallback.shouldRetryWithoutAudio(
            audioRequested: false, everStreamed: true, stopped: false))
    }

    @Test func neverRetriesAfterOwnerStopped() {
        // A stop during bring-up also ends the session before its first frame —
        // retrying then resurrects a session nothing owns (the leaked headless
        // mirrors behind the 500%+ CPU reports). Stopped is terminal.
        #expect(!MirrorAudioFallback.shouldRetryWithoutAudio(
            audioRequested: true, everStreamed: false, stopped: true))
        #expect(!MirrorAudioFallback.shouldRetryWithoutAudio(
            audioRequested: true, everStreamed: true, stopped: true))
        #expect(!MirrorAudioFallback.shouldRetryWithoutAudio(
            audioRequested: false, everStreamed: false, stopped: true))
    }
}
