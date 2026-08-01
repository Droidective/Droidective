import Foundation
import Testing
@testable import ADBKit

@Suite struct ResourceWatchdogTests {
    private let mb: Double = 1_048_576

    /// A sample with a calm memory footprint so only the CPU metric is in play.
    private func cpuSample(at uptime: Double, cpuTime: Double) -> ResourceSample {
        ResourceSample(uptime: uptime, cpuTimeSeconds: cpuTime, footprintBytes: 100 * 1_048_576)
    }

    /// A sample with no CPU progress so only the memory metric is in play.
    private func memorySample(at uptime: Double, footprintMB: Double) -> ResourceSample {
        ResourceSample(uptime: uptime, cpuTimeSeconds: 0, footprintBytes: UInt64(footprintMB * mb))
    }

    // MARK: - CPU% derivation

    @Test func cpuPercentComesFromCumulativeTimeDelta() {
        var dog = ResourceWatchdog(limits: .init(cpuPercent: 200, sustainedSamples: 1))
        #expect(dog.ingest(cpuSample(at: 0, cpuTime: 0)).isEmpty)  // first sample: no delta yet
        let events = dog.ingest(cpuSample(at: 5, cpuTime: 15))     // 15s CPU over 5s wall = 300%
        #expect(events == [.began(metric: .cpu, value: 300, limit: 200)])
    }

    @Test func nonAdvancingClockProducesNoCPUReading() {
        var dog = ResourceWatchdog(limits: .init(cpuPercent: 1, sustainedSamples: 1))
        _ = dog.ingest(cpuSample(at: 5, cpuTime: 0))
        #expect(dog.ingest(cpuSample(at: 5, cpuTime: 100)).isEmpty)
    }

    @Test func cpuBelowLimitStaysQuiet() {
        var dog = ResourceWatchdog(limits: .init(cpuPercent: 200, sustainedSamples: 1))
        _ = dog.ingest(cpuSample(at: 0, cpuTime: 0))
        #expect(dog.ingest(cpuSample(at: 5, cpuTime: 5)).isEmpty)  // 100% < 200%
    }

    // MARK: - Sustained-sample debounce

    @Test func memoryFiresOnlyAfterSustainedSamples() {
        var dog = ResourceWatchdog(limits: .init(memoryBytes: 1_000 * mb, sustainedSamples: 3))
        #expect(dog.ingest(memorySample(at: 0, footprintMB: 1_200)).isEmpty)
        #expect(dog.ingest(memorySample(at: 5, footprintMB: 1_200)).isEmpty)
        let events = dog.ingest(memorySample(at: 10, footprintMB: 1_300))
        #expect(events == [.began(metric: .memory, value: 1_300 * mb, limit: 1_000 * mb)])
    }

    @Test func dipBelowLimitResetsTheStrikeCount() {
        var dog = ResourceWatchdog(limits: .init(memoryBytes: 1_000 * mb, sustainedSamples: 3))
        _ = dog.ingest(memorySample(at: 0, footprintMB: 1_200))
        _ = dog.ingest(memorySample(at: 5, footprintMB: 1_200))
        _ = dog.ingest(memorySample(at: 10, footprintMB: 900))    // dip: strikes reset
        _ = dog.ingest(memorySample(at: 15, footprintMB: 1_200))
        #expect(dog.ingest(memorySample(at: 20, footprintMB: 1_200)).isEmpty)
        #expect(dog.ingest(memorySample(at: 25, footprintMB: 1_200))
            == [.began(metric: .memory, value: 1_200 * mb, limit: 1_000 * mb)])
    }

    @Test func firesOncePerEpisodeWhileUsageStaysHigh() {
        var dog = ResourceWatchdog(limits: .init(memoryBytes: 1_000 * mb, sustainedSamples: 1))
        #expect(dog.ingest(memorySample(at: 0, footprintMB: 1_500)).count == 1)
        #expect(dog.ingest(memorySample(at: 5, footprintMB: 1_600)).isEmpty)
        #expect(dog.ingest(memorySample(at: 10, footprintMB: 1_700)).isEmpty)
    }

    // MARK: - Recovery

    @Test func recoveryCarriesPeakAndDuration() {
        var dog = ResourceWatchdog(limits: .init(memoryBytes: 1_000 * mb, sustainedSamples: 1, resetFraction: 0.8))
        _ = dog.ingest(memorySample(at: 10, footprintMB: 1_200))  // began at t=10
        _ = dog.ingest(memorySample(at: 20, footprintMB: 2_000))  // peak
        let events = dog.ingest(memorySample(at: 30, footprintMB: 500))
        #expect(events == [.ended(metric: .memory, peak: 2_000 * mb, seconds: 20)])
    }

    @Test func episodePersistsBetweenResetLevelAndLimit() {
        var dog = ResourceWatchdog(limits: .init(memoryBytes: 1_000 * mb, sustainedSamples: 1, resetFraction: 0.8))
        _ = dog.ingest(memorySample(at: 0, footprintMB: 1_200))
        // 900 MB is under the 1 000 MB limit but over the 800 MB reset level.
        #expect(dog.ingest(memorySample(at: 5, footprintMB: 900)).isEmpty)
        #expect(dog.ingest(memorySample(at: 10, footprintMB: 700))
            == [.ended(metric: .memory, peak: 1_200 * mb, seconds: 10)])
    }

    // MARK: - Cooldown

    @Test func cooldownSuppressesARepeatIncident() {
        var dog = ResourceWatchdog(limits: .init(
            memoryBytes: 1_000 * mb, sustainedSamples: 1, cooldownSeconds: 100))
        _ = dog.ingest(memorySample(at: 0, footprintMB: 1_200))   // began
        _ = dog.ingest(memorySample(at: 10, footprintMB: 500))    // ended
        #expect(dog.ingest(memorySample(at: 20, footprintMB: 1_200)).isEmpty)  // within cooldown
        #expect(dog.ingest(memorySample(at: 110, footprintMB: 1_200))
            == [.began(metric: .memory, value: 1_200 * mb, limit: 1_000 * mb)])
    }

    // MARK: - Independence

    @Test func cpuAndMemoryEpisodesAreIndependent() {
        var dog = ResourceWatchdog(limits: .init(
            cpuPercent: 200, memoryBytes: 1_000 * mb, sustainedSamples: 1))
        _ = dog.ingest(ResourceSample(uptime: 0, cpuTimeSeconds: 0, footprintBytes: UInt64(1_500 * mb)))
        // Memory fired on the first sample; the second brings CPU over its limit too.
        let events = dog.ingest(ResourceSample(uptime: 5, cpuTimeSeconds: 15, footprintBytes: UInt64(1_500 * mb)))
        #expect(events == [.began(metric: .cpu, value: 300, limit: 200)])
    }

    // MARK: - CPU limit override (expected-heavy features)

    @Test func cpuOverrideSuppressesTheIncidentUnderExpectedLoad() {
        var dog = ResourceWatchdog(limits: .init(cpuPercent: 200, sustainedSamples: 1))
        _ = dog.ingest(cpuSample(at: 0, cpuTime: 0))
        // 300% CPU, but a mirroring feature is on screen this tick, so it's expected.
        #expect(dog.ingest(cpuSample(at: 5, cpuTime: 15), cpuLimitOverride: .infinity).isEmpty)
    }

    @Test func cpuOverrideRetiresAnInFlightEpisode() {
        var dog = ResourceWatchdog(limits: .init(cpuPercent: 200, sustainedSamples: 1, resetFraction: 0.8))
        _ = dog.ingest(cpuSample(at: 0, cpuTime: 0))
        #expect(dog.ingest(cpuSample(at: 5, cpuTime: 15)).count == 1)   // began at 300%
        // Mirroring starts mid-episode: the override ends it instead of stranding it.
        #expect(dog.ingest(cpuSample(at: 10, cpuTime: 25), cpuLimitOverride: .infinity)
            == [.ended(metric: .cpu, peak: 300, seconds: 5)])
    }

    @Test func cpuOverrideStillWatchesMemory() {
        var dog = ResourceWatchdog(limits: .init(
            cpuPercent: 200, memoryBytes: 1_000 * mb, sustainedSamples: 1))
        _ = dog.ingest(ResourceSample(uptime: 0, cpuTimeSeconds: 0, footprintBytes: UInt64(100 * mb)))
        // CPU is waived (mirroring), but a memory-overuse incident still fires.
        let events = dog.ingest(
            ResourceSample(uptime: 5, cpuTimeSeconds: 15, footprintBytes: UInt64(1_500 * mb)),
            cpuLimitOverride: .infinity)
        #expect(events == [.began(metric: .memory, value: 1_500 * mb, limit: 1_000 * mb)])
    }

    @Test func finiteCpuOverrideStillFiresPastTheRaisedLimit() {
        // The mirror override is a *raised* limit, not a pass: a leak burning
        // ~five cores with a mirror tab open must still report. An unbounded
        // override is what kept the v3.1.0 mirror-session leak (hours at
        // 250%+) invisible to telemetry.
        var dog = ResourceWatchdog(limits: .init(cpuPercent: 200, sustainedSamples: 1))
        _ = dog.ingest(cpuSample(at: 0, cpuTime: 0))
        #expect(dog.ingest(cpuSample(at: 5, cpuTime: 25), cpuLimitOverride: 450)
            == [.began(metric: .cpu, value: 500, limit: 450)])
    }

    @Test func finiteCpuOverrideStillCoversExpectedHeavyLoad() {
        // Healthy mirroring (~three busy cores) stays inside the raised
        // limit — expected load must not become incident noise.
        var dog = ResourceWatchdog(limits: .init(cpuPercent: 200, sustainedSamples: 1))
        _ = dog.ingest(cpuSample(at: 0, cpuTime: 0))
        #expect(dog.ingest(cpuSample(at: 5, cpuTime: 15), cpuLimitOverride: 450).isEmpty)
    }
}

@Suite struct ProcessStatsTests {
    // Self-usage sampling is a Darwin kernel call; off-Darwin `sample()` is
    // deliberately nil (see ProcessStats).
    #if canImport(Darwin)
    @Test func sampleReportsPlausibleValuesForThisProcess() throws {
        let first = try #require(ProcessStats.sample())
        let second = try #require(ProcessStats.sample())
        #expect(first.footprintBytes > 1_048_576)  // a running test process exceeds 1 MB
        #expect(first.cpuTimeSeconds > 0)
        #expect(second.cpuTimeSeconds >= first.cpuTimeSeconds)
        #expect(second.uptime >= first.uptime)
    }
    #else
    @Test func sampleIsNilOffDarwin() {
        #expect(ProcessStats.sample() == nil)
    }
    #endif
}
