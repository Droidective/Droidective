import Testing
@testable import ADBKit

@Suite struct NetworkTrafficMeterTests {
    @Test func accumulatesReceivedAndSentSeparately() {
        let meter = NetworkTrafficMeter()
        meter.recordReceived(100)
        meter.recordReceived(50)
        meter.recordSent(30)

        let totals = meter.totals()
        #expect(totals.received == 150)
        #expect(totals.sent == 30)
    }

    @Test func ignoresZeroAndNegativeAmounts() {
        // Empty reads/writes are common (a keep-alive frame, a closed socket) and
        // must not perturb the tally.
        let meter = NetworkTrafficMeter()
        meter.recordReceived(0)
        meter.recordReceived(-10)
        meter.recordSent(0)

        let totals = meter.totals()
        #expect(totals.received == 0)
        #expect(totals.sent == 0)
    }

    @Test func totalsAreCumulativeAcrossReads() {
        let meter = NetworkTrafficMeter()
        meter.recordReceived(200)
        _ = meter.totals()
        meter.recordReceived(300)
        #expect(meter.totals().received == 500)
    }
}
