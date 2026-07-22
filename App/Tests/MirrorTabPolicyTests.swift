import Testing

/// The mirror tab's hide/return decisions — the recording exemption and the
/// wrong-device retarget rule are the bug-prone branches the grace window
/// introduced (a resumed session is bound to its original device forever).
@Suite struct MirrorTabPolicyTests {
    @Test func hidingSchedulesTeardownUnlessRecording() {
        #expect(MirrorTabPolicy.schedulesTeardownOnHide(isRecording: false))
        #expect(!MirrorTabPolicy.schedulesTeardownOnHide(isRecording: true))
    }

    @Test func returningWithNoSessionReconnects() {
        #expect(
            MirrorTabPolicy.onReturn(
                hasSession: false, isRecording: false, sessionEnded: false, deviceChanged: false)
                == .reconnect)
    }

    /// The grace window's whole point: a live session on the still-selected
    /// device resumes in place with no reconnect flash.
    @Test func returningToALiveSessionResumes() {
        #expect(
            MirrorTabPolicy.onReturn(
                hasSession: true, isRecording: false, sessionEnded: false, deviceChanged: false)
                == .resume)
    }

    /// Switching the device bar while hidden must re-target on return —
    /// resuming would silently mirror (and control) the wrong device.
    @Test func returningAfterADeviceSwitchReconnects() {
        #expect(
            MirrorTabPolicy.onReturn(
                hasSession: true, isRecording: false, sessionEnded: false, deviceChanged: true)
                == .reconnect)
    }

    /// A session that died while hidden reconnects on return instead of
    /// resuming into the stopped/failed card.
    @Test func returningToAnEndedSessionReconnects() {
        #expect(
            MirrorTabPolicy.onReturn(
                hasSession: true, isRecording: false, sessionEnded: true, deviceChanged: false)
                == .reconnect)
    }

    /// A recording is never torn down or re-targeted out from under the user —
    /// it stays on its device even if the bar selection moved on.
    @Test func recordingAlwaysResumesInPlace() {
        #expect(
            MirrorTabPolicy.onReturn(
                hasSession: true, isRecording: true, sessionEnded: false, deviceChanged: true)
                == .resume)
    }
}
