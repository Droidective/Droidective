import Testing
@testable import ADBKit

@Suite struct FeaturePerfAggregatorTests {
    private func sample(_ uptime: Double, cpu: Double, mem: UInt64) -> ResourceSample {
        ResourceSample(uptime: uptime, cpuTimeSeconds: cpu, footprintBytes: mem)
    }

    @Test func firstSampleOpensAWindowWithoutFlushing() {
        var agg = FeaturePerfAggregator()
        #expect(agg.ingest(sample(0, cpu: 0, mem: 100), feature: "logcat") == nil)
    }

    @Test func featureChangeFlushesAveragesAndPeaksForThePriorFeature() {
        var agg = FeaturePerfAggregator()
        #expect(agg.ingest(sample(0, cpu: 0, mem: 100), feature: "logcat") == nil)
        #expect(agg.ingest(sample(1, cpu: 0.5, mem: 200), feature: "logcat") == nil)  // 50% CPU
        #expect(agg.ingest(sample(2, cpu: 1.0, mem: 150), feature: "logcat") == nil)  // 50% CPU

        // Switching to another feature closes logcat's window.
        let logcat = agg.ingest(sample(3, cpu: 1.0, mem: 300), feature: "mirror")
        #expect(logcat?.feature == "logcat")
        #expect(logcat?.seconds == 2)                     // 2 - 0
        #expect(logcat?.samples == 3)
        #expect(logcat?.averageCPUPercent == 50)          // (50 + 50) / 2 cpu samples
        #expect(logcat?.peakCPUPercent == 50)
        #expect(logcat?.averageMemoryBytes == 150)        // (100 + 200 + 150) / 3
        #expect(logcat?.peakMemoryBytes == 200)
    }

    @Test func rollingWindowFlushesEvenWhenTheFeatureNeverChanges() {
        var agg = FeaturePerfAggregator(maxWindowSeconds: 2)
        #expect(agg.ingest(sample(0, cpu: 0, mem: 100), feature: "mirror") == nil)
        #expect(agg.ingest(sample(1, cpu: 0.2, mem: 100), feature: "mirror") == nil)
        // At uptime 2 the window has spanned maxWindowSeconds, so it rolls over.
        let record = agg.ingest(sample(2, cpu: 0.4, mem: 100), feature: "mirror")
        #expect(record?.feature == "mirror")
        #expect(record?.seconds == 2)
        #expect(record?.samples == 3)
    }

    @Test func flushClosesTheFinalWindowOnce() {
        var agg = FeaturePerfAggregator()
        _ = agg.ingest(sample(0, cpu: 0, mem: 100), feature: "apps")
        _ = agg.ingest(sample(1, cpu: 0.1, mem: 120), feature: "apps")

        let record = agg.flush()
        #expect(record?.feature == "apps")
        #expect(record?.samples == 2)
        #expect(agg.flush() == nil)   // nothing left to flush
    }

    @Test func flushOnAnUnusedAggregatorReturnsNil() {
        var agg = FeaturePerfAggregator()
        #expect(agg.flush() == nil)
    }
}
