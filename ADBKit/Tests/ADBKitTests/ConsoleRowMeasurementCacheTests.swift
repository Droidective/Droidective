import Testing

@testable import ADBKit

@Suite("Console row measurement cache")
struct ConsoleRowMeasurementCacheTests {
    private func measurement(height: Double) -> ConsoleRowMeasurement {
        ConsoleRowMeasurement(
            segments: [ConsoleRowSegment(width: 100, height: height, baseline: 10)],
            arrangement: ConsoleRowArrangement(
                slots: [ConsoleRowSlot(x: 0, y: 0)], width: 100, height: height
            )
        )
    }

    @Test func returnsWhatWasStoredAtTheSameWidth() {
        var cache = ConsoleRowMeasurementCache()
        cache.store(measurement(height: 17), atWidth: 320)

        #expect(cache.measurement(atWidth: 320) == measurement(height: 17))
    }

    @Test func missesAtAnotherWidth() {
        var cache = ConsoleRowMeasurementCache()
        cache.store(measurement(height: 17), atWidth: 320)

        #expect(cache.measurement(atWidth: 321) == nil)
    }

    /// A row with no width constraint is proposed `.infinity`, and that pass is
    /// worth memoising like any other.
    @Test func memoisesTheUnconstrainedWidth() {
        var cache = ConsoleRowMeasurementCache()
        cache.store(measurement(height: 17), atWidth: .infinity)

        #expect(cache.measurement(atWidth: .infinity) == measurement(height: 17))
    }

    @Test func startsEmpty() {
        #expect(ConsoleRowMeasurementCache().measurement(atWidth: 320) == nil)
    }

    /// Re-measuring a width already held replaces it rather than counting
    /// against the capacity a second time.
    @Test func restoringAWidthDoesNotGrowTheCache() {
        var cache = ConsoleRowMeasurementCache()
        cache.store(measurement(height: 17), atWidth: 320)
        cache.store(measurement(height: 24), atWidth: 320)

        #expect(cache.count == 1)
        #expect(cache.measurement(atWidth: 320) == measurement(height: 24))
    }

    /// The bound is what keeps a live resize — a new width every frame — from
    /// growing the memo for as long as the row stays mounted.
    @Test func evictsOnceFull() {
        var cache = ConsoleRowMeasurementCache()
        for step in 0..<ConsoleRowMeasurementCache.capacity {
            cache.store(measurement(height: 17), atWidth: Double(300 + step))
        }
        #expect(cache.count == ConsoleRowMeasurementCache.capacity)

        cache.store(measurement(height: 17), atWidth: 999)

        #expect(cache.count == 1)
        #expect(cache.measurement(atWidth: 999) != nil)
        #expect(cache.measurement(atWidth: 300) == nil)
    }

    /// A NaN width is never a usable key — it must neither be stored nor ever
    /// match, since every NaN compares unequal to itself.
    @Test func ignoresANonNumericWidth() {
        var cache = ConsoleRowMeasurementCache()
        cache.store(measurement(height: 17), atWidth: .nan)

        #expect(cache.count == 0)
        #expect(cache.measurement(atWidth: .nan) == nil)
    }
}
