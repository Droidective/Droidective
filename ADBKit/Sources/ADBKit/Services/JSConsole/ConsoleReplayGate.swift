import Foundation

/// Filters the console-history replay a Hermes target sends every time a
/// debugger (re)attaches. The console's feed outlives the connection, so
/// without a gate every reconnect (the proxy's heartbeat kill, the phone
/// sleeping, an app relaunch) appends the entire replayed history again,
/// duplicating the feed. CDP event timestamps come from the device's clock
/// and the replay arrives in order before any live event: on a reconnect to
/// the same app, events at or before the newest timestamp already delivered
/// are the replay and are dropped, and the first newer event permanently
/// disarms the gate for that connection — so a same-millisecond *live* pair
/// later on can never be swallowed.
public struct ConsoleReplayGate: Sendable, Equatable {
    private var newest: Double = 0
    private var gate: Double = 0
    private var gateArmed = false

    public init() {}

    /// Call when a connection opens. `resumingSameApp`: the feed already holds
    /// this app's history, so its replay would duplicate. A different app (or
    /// the first connection) shows everything — its history is all new.
    public mutating func connectionOpened(resumingSameApp: Bool) {
        if resumingSameApp {
            gate = newest
            gateArmed = newest > 0
        } else {
            newest = 0
            gate = 0
            gateArmed = false
        }
    }

    /// Whether an event with this CDP timestamp should be delivered; records
    /// it as seen. Events without a timestamp always pass (nothing to key on).
    public mutating func admit(_ timestamp: Double?) -> Bool {
        guard let timestamp else { return true }
        if gateArmed {
            if timestamp <= gate { return false }
            gateArmed = false
        }
        newest = max(newest, timestamp)
        return true
    }
}
