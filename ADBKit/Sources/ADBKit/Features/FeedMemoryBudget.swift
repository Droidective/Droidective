import Foundation

/// How much memory one streaming feed's retained buffer may hold.
///
/// The number that matters is *resident* bytes; what the feeds actually cap is
/// *wire* bytes — the size of the frames as they arrived off the socket. Those
/// are not the same figure. Each frame is decoded into a Swift object graph
/// several times its wire size (the parsed payload, the strings each row
/// caches for search and display, one `RtItem`/`JSEntry` per row), so a wire
/// cap is a resident cap divided by that multiple. Both feeds shipped a flat
/// 128 MB wire cap, which is roughly a **gigabyte** resident;
/// `ReactotronTimeline`'s own comment conceded the multiple without following
/// it through to the number.
///
/// What that cost, measured on one install (a 16 GB M5, `Mac17,2`) with three
/// tabs open — home, js-console, reactotron — from its `feature_perf` windows:
///
///     08:00   363 MB      the session's baseline
///     10:00  1096 MB
///     11:00  1578 MB      peak, 102% CPU
///     …      0.8–1.5 GB   for the next *day*, sawtoothing
///
/// The sawtooth is the tell. It is not a leak — the rings do evict, and the
/// footprint comes back down — it is the buffers' own working range, and with
/// two feeds at 128 MB of wire each that range is predicted at roughly
/// 0.3–2 GB. Observed: 0.8–1.5 GB. The cap *was* the bug, which is why looking
/// for a leak would never have found anything.
///
/// Alongside it, sixty-odd 2-second main-thread hangs over two days, nearly all
/// with the app not even frontmost (Sentry DROIDECTIVE-MAC-B), and CPU peaks of
/// 56–102% attributed to a feed nobody was looking at.
///
/// So the budget is a fraction of the machine rather than a constant. A
/// debugging tool has no business retaining the same fixed 128 MB of frames on
/// a machine with 8 GB as on one with 64 — and no business holding a gigabyte
/// of decoded log rows on any of them.
public enum FeedMemoryBudget {
    /// Resident bytes one decoded frame costs per wire byte.
    ///
    /// Between 5x and 9x across the two incidents above — 55 MB of wire frames
    /// sat inside a 566 MB process, and a buffer at the old cap inside 1.47 GB.
    /// 8 is the conservative end of that range: the budget should err toward
    /// retaining less, because the failure it prevents is machine-wide.
    public static let decodedGraphMultiplier = 8

    /// Share of the machine's RAM one feed's decoded buffer may occupy — 1/32,
    /// about 3%. Two feeds streaming at once (the shape of the incident: a
    /// Reactotron tab and a JS Console tab) therefore reach ~6%, which leaves
    /// an 8 GB machine its headroom.
    static let hostFraction = 32
    /// Ceiling however much RAM the machine has. A feed holding more decoded
    /// history than this is holding more than anyone scrolls back through, and
    /// the count cap (`ReactotronTimeline.maxItems`) bites long before it on
    /// ordinary traffic.
    static let maximumDecodedBytes = 192 << 20
    /// Floor, so a small machine still keeps a useful amount of history rather
    /// than a feed that evicts what it just received.
    static let minimumDecodedBytes = 48 << 20

    /// Resident ceiling for one feed's retained buffer.
    public static func decodedBudget(physicalMemory: UInt64) -> Int {
        let share = physicalMemory / UInt64(hostFraction)
        let clamped = min(UInt64(maximumDecodedBytes), max(UInt64(minimumDecodedBytes), share))
        return Int(clamped)
    }

    /// The wire-byte cap a feed applies to keep `decodedBudget` within reach.
    public static func wireBudget(physicalMemory: UInt64) -> Int {
        decodedBudget(physicalMemory: physicalMemory) / decodedGraphMultiplier
    }

    /// The wire-byte cap for the machine this is running on — what the feeds
    /// use.
    ///
    /// Resolved once. A feed consults this on the *per-event* ingest path (the
    /// early-flush bound), and `physicalMemory` is a `sysctl` read: cheap, but
    /// not free per event on the one path this whole type exists to make
    /// cheaper. There is nothing to invalidate — a process does not change
    /// machines.
    public static let wireBudget = wireBudget(
        physicalMemory: ProcessInfo.processInfo.physicalMemory)
}
