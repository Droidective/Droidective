import Foundation
import os

/// Process-wide tally of the bytes Droidective *itself* moves over the network:
/// the JS-console CDP WebSocket, the scrcpy mirror sockets, the Reactotron
/// server, and managed-tool downloads. adb's own transfers run in the separate
/// `adb` process, so they're correctly excluded — this is "this app's" traffic.
///
/// A single `OSAllocatedUnfairLock` add per chunk keeps it off the hot path; the
/// debug metrics overlay reads `totals()` on a timer and turns the deltas into a
/// throughput. Counters are cumulative and monotonic (`&+` wraps rather than
/// traps, which the overlay's delta clamps to zero).
public final class NetworkTrafficMeter: Sendable {
    public static let shared = NetworkTrafficMeter()

    /// Cumulative bytes received and sent since launch.
    public struct Totals: Sendable, Equatable {
        public var received: UInt64
        public var sent: UInt64

        public init(received: UInt64 = 0, sent: UInt64 = 0) {
            self.received = received
            self.sent = sent
        }
    }

    private let state = OSAllocatedUnfairLock(initialState: Totals())

    /// Internal so production uses the shared meter while tests can measure a
    /// fresh instance without cross-test interference.
    init() {}

    public func recordReceived(_ bytes: Int) {
        guard bytes > 0 else { return }
        state.withLock { $0.received &+= UInt64(bytes) }
    }

    public func recordSent(_ bytes: Int) {
        guard bytes > 0 else { return }
        state.withLock { $0.sent &+= UInt64(bytes) }
    }

    public func totals() -> Totals { state.withLock { $0 } }
}
