import Foundation

/// One width's worth of a console row's measurement: every segment's own size
/// and the arrangement `ConsoleRowLayout` derived from them.
public struct ConsoleRowMeasurement: Sendable, Equatable {
    public let segments: [ConsoleRowSegment]
    public let arrangement: ConsoleRowArrangement

    public init(segments: [ConsoleRowSegment], arrangement: ConsoleRowArrangement) {
        self.segments = segments
        self.arrangement = arrangement
    }
}

/// A console row's measurements, memoised by the width they were taken at.
///
/// Measuring is the expensive half of laying a row out: every segment is an
/// attributed `Text` up to the console's display cap, and sizing one lays the
/// text out for real. SwiftUI asks a `Layout` for its size several times per
/// pass — the enclosing stack probing its children, then the frame around the
/// row, then the placement call — and an unmemoised row re-measured all of its
/// text on each of them. Across a feed of a thousand rows that is the
/// difference between a scroll and a multi-second main-thread stall.
///
/// Bounded on purpose: a layout pass probes a handful of distinct widths, but a
/// live window resize walks through a new one every frame, so an unbounded memo
/// would grow for as long as the row is mounted.
public struct ConsoleRowMeasurementCache: Sendable {
    /// How many distinct widths are kept at once.
    public static let capacity = 4

    private var entries: [Double: ConsoleRowMeasurement] = [:]

    public init() {}

    /// How many widths are currently memoised.
    public var count: Int { entries.count }

    /// The measurement taken at `width`, if it is still held.
    ///
    /// A non-finite width other than infinity (SwiftUI proposes `.infinity` for
    /// an unconstrained row) is never a usable key, so it always misses.
    public func measurement(atWidth width: Double) -> ConsoleRowMeasurement? {
        guard !width.isNaN else { return nil }
        return entries[width]
    }

    /// Memoise `measurement` under `width`, evicting everything held once the
    /// cache is full. Wholesale eviction rather than a least-recently-used pick
    /// because the case that overflows is a resize, where every held width is
    /// equally stale a frame later.
    public mutating func store(_ measurement: ConsoleRowMeasurement, atWidth width: Double) {
        guard !width.isNaN else { return }
        if entries[width] == nil, entries.count >= Self.capacity {
            entries.removeAll(keepingCapacity: true)
        }
        entries[width] = measurement
    }
}
