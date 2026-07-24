import Testing

/// The ingest-rate decade bucket: 0 below one per minute, then 1, 10, 100…
/// The [1, 10) → 1 rung is the easy one to get wrong (it isn't in the
/// "10, 100, 1000" mental model), and the exact rung edges are what keep
/// the diagnostic context from re-publishing on rate noise.
@Suite struct ConsoleRateBucketTests {
    @Test func quietStreamsBucketToZero() {
        #expect(ConsoleRateBucket.decade(0) == 0)
        #expect(ConsoleRateBucket.decade(0.9) == 0)
    }

    @Test func singleDigitRatesBucketToOne() {
        #expect(ConsoleRateBucket.decade(1) == 1)
        #expect(ConsoleRateBucket.decade(9.99) == 1)
    }

    @Test func edgesLandOnTheirOwnDecade() {
        #expect(ConsoleRateBucket.decade(10) == 10)
        #expect(ConsoleRateBucket.decade(99) == 10)
        #expect(ConsoleRateBucket.decade(100) == 100)
        #expect(ConsoleRateBucket.decade(1234) == 1000)
        #expect(ConsoleRateBucket.decade(60000) == 10000)
    }

    // A burst breadcrumb fires only on a rise that reaches the floor — the
    // first publish, a steady rate, and a falling rate must all stay quiet.

    @Test func risesToTheFloorAndAboveAreBursts() {
        #expect(ConsoleRateBucket.isBurst(from: 100, to: 1000))
        #expect(ConsoleRateBucket.isBurst(from: 1000, to: 10000))
        #expect(ConsoleRateBucket.isBurst(from: 0, to: 1000))
    }

    @Test func firstPublishIsBaselineNotABurst() {
        #expect(!ConsoleRateBucket.isBurst(from: nil, to: 10000))
    }

    @Test func steadyFallingAndSmallRatesAreNotBursts() {
        #expect(!ConsoleRateBucket.isBurst(from: 1000, to: 1000))
        #expect(!ConsoleRateBucket.isBurst(from: 10000, to: 1000))
        #expect(!ConsoleRateBucket.isBurst(from: 10, to: 100))
    }
}
