import Testing

/// Relaunching an emulator reported nothing at all: the stop result was
/// discarded, the console-port poll ran for up to 20 seconds with the row
/// unchanged, and the only toast was "Launching…" long after the click. These
/// lock the wording each stage now shows, including the two ways it can end
/// without booting.
@Suite struct EmulatorRelaunchPhaseTests {
    @Test func eachStageSaysWhatItIsDoing() {
        #expect(EmulatorRelaunchPhase.stopping.label == "Stopping…")
        #expect(EmulatorRelaunchPhase.booting.label == "Booting…")
    }

    /// The wait is the long one, so it counts up — but not from "0s", which
    /// reads like a timer that never started.
    @Test func theShutdownWaitCountsUpOnceThereIsSomethingToCount() {
        #expect(
            EmulatorRelaunchPhase.waitingForShutdown(secondsElapsed: 0).label
                == "Waiting for it to shut down…"
        )
        #expect(
            EmulatorRelaunchPhase.waitingForShutdown(secondsElapsed: 1).label
                == "Waiting for it to shut down… 1s"
        )
        #expect(
            EmulatorRelaunchPhase.waitingForShutdown(secondsElapsed: 17).label
                == "Waiting for it to shut down… 17s"
        )
    }

    /// A failed `adb emu kill` used to be swallowed by `_ = try?`, and the
    /// relaunch waited 20s and booted anyway. The reason has to reach the user.
    @Test func aFailedStopCarriesAdbsReason() {
        #expect(
            EmulatorRelaunchPhase.stopFailed(name: "Pixel_7", reason: "device offline")
                == "Couldn't stop Pixel_7: device offline"
        )
    }

    /// Booting while the old process still holds the console port is what
    /// produces a second serial, so the timeout says it did not relaunch.
    @Test func aShutdownThatNeverFinishesSaysTheEmulatorIsStillUp() {
        let message = EmulatorRelaunchPhase.shutdownTimedOut(name: "Pixel_7", seconds: 20)
        #expect(message.contains("didn't shut down within 20s"))
        #expect(message.contains("wasn't relaunched"))
    }

    @Test func phasesAreDistinguishable() {
        #expect(EmulatorRelaunchPhase.stopping != .booting)
        #expect(
            EmulatorRelaunchPhase.waitingForShutdown(secondsElapsed: 1)
                != .waitingForShutdown(secondsElapsed: 2)
        )
    }
}
