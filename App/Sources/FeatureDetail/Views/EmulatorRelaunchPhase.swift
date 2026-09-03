/// The stages a relaunch passes through and what the AVD's row says during
/// each. Pure, so the wording is testable without an emulator — and worth
/// separating because a relaunch spends nearly all of its time in
/// `waitingForShutdown`, which is exactly the stretch that used to render as
/// nothing at all while the console port was polled for up to 20 seconds.
enum EmulatorRelaunchPhase: Equatable, Sendable {
    case stopping
    case waitingForShutdown(secondsElapsed: Int)
    case booting

    /// What the row shows beside its spinner.
    var label: String {
        switch self {
        case .stopping:
            "Stopping…"
        case let .waitingForShutdown(seconds):
            // The count only appears once there is something to count: a
            // bare "0s" on the first tick reads like a stuck timer.
            seconds < 1
                ? "Waiting for it to shut down…"
                : "Waiting for it to shut down… \(seconds)s"
        case .booting:
            "Booting…"
        }
    }

    /// `adb emu kill` failed, so there is nothing to wait for — and booting
    /// now would race the still-running emulator into a second serial, which
    /// is the whole reason the wait exists.
    static func stopFailed(name: String, reason: String) -> String {
        "Couldn't stop \(name): \(reason)"
    }

    /// The console port never freed. Booting anyway produces the second
    /// serial the wait is there to prevent, so the relaunch stops instead and
    /// says the emulator is still up.
    static func shutdownTimedOut(name: String, seconds: Int) -> String {
        "\(name) didn't shut down within \(seconds)s — it's still running, so it wasn't relaunched"
    }
}
