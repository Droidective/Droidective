/// Pure decisions for how the mirror reacts to its tab hiding or returning,
/// extracted from `ScreenMirrorView` so the recording exemption and the
/// return-retarget rules are pinned by AppTests rather than only by eye.
/// (The grace-window *timing* stays view glue; only the branching lives here.)
enum MirrorTabPolicy {
    /// What returning to the tab does with a session the grace window kept.
    enum ReturnAction: Equatable {
        /// Keep the live session in place — no reconnect flash.
        case resume
        /// Connect fresh to the selected device (also the no-session path).
        case reconnect
    }

    /// `sessionEnded`: the session failed or stopped while hidden.
    /// `deviceChanged`: the device-bar selection no longer matches the
    /// session's device. A recording always resumes in place — it stays on
    /// its device until the user deals with it.
    static func onReturn(
        hasSession: Bool, isRecording: Bool, sessionEnded: Bool, deviceChanged: Bool
    ) -> ReturnAction {
        guard hasSession else { return .reconnect }
        if isRecording { return .resume }
        return (sessionEnded || deviceChanged) ? .reconnect : .resume
    }

    /// Whether hiding the tab schedules the grace-window teardown — never for
    /// a recording, which must keep capturing.
    static func schedulesTeardownOnHide(isRecording: Bool) -> Bool {
        !isRecording
    }
}
