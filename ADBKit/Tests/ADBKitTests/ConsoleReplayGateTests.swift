import Testing
@testable import ADBKit

/// The replay gate drops the console history a Hermes target re-sends on every
/// debugger (re)attach, so a reconnect doesn't duplicate the persistent feed.
@Suite struct ConsoleReplayGateTests {
    /// `admit` is mutating, which `#expect` can't call inline — collect the
    /// verdicts for a timestamp sequence instead.
    private func verdicts(_ gate: inout ConsoleReplayGate, _ timestamps: [Double?]) -> [Bool] {
        timestamps.map { gate.admit($0) }
    }

    @Test func firstConnectionShowsEverything() {
        var gate = ConsoleReplayGate()
        gate.connectionOpened(resumingSameApp: false)
        // Includes a same-millisecond live pair.
        #expect(verdicts(&gate, [100, 200, 200]) == [true, true, true])
    }

    @Test func reconnectToTheSameAppDropsTheReplayedHistory() {
        var gate = ConsoleReplayGate()
        gate.connectionOpened(resumingSameApp: false)
        #expect(verdicts(&gate, [100, 200]) == [true, true])

        gate.connectionOpened(resumingSameApp: true)
        // Replayed history (≤ 200) is dropped; a line logged while
        // disconnected is new; a same-ms live pair after the gate disarms
        // still shows.
        #expect(verdicts(&gate, [100, 200, 300, 300]) == [false, false, true, true])
    }

    @Test func firstNewerEventDisarmsTheGateForTheConnection() {
        // Replay arrives in order before live events; once one event passes,
        // an equal-or-older timestamp later must not be swallowed (a device
        // clock hiccup shouldn't eat live logs).
        var gate = ConsoleReplayGate()
        gate.connectionOpened(resumingSameApp: false)
        #expect(verdicts(&gate, [500]) == [true])
        gate.connectionOpened(resumingSameApp: true)
        #expect(verdicts(&gate, [600, 400]) == [true, true])
    }

    @Test func aDifferentAppStartsFresh() {
        var gate = ConsoleReplayGate()
        gate.connectionOpened(resumingSameApp: false)
        #expect(verdicts(&gate, [900]) == [true])

        gate.connectionOpened(resumingSameApp: false)
        // Another app's old history is all new to us.
        #expect(verdicts(&gate, [100]) == [true])
    }

    @Test func eventsWithoutTimestampsAlwaysPass() {
        var gate = ConsoleReplayGate()
        gate.connectionOpened(resumingSameApp: false)
        #expect(verdicts(&gate, [700]) == [true])
        gate.connectionOpened(resumingSameApp: true)
        #expect(verdicts(&gate, [nil]) == [true])
    }

    @Test func resumingWithNoHistoryYetGatesNothing() {
        var gate = ConsoleReplayGate()
        gate.connectionOpened(resumingSameApp: true)
        #expect(verdicts(&gate, [50]) == [true])
    }
}
