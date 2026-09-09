import Foundation

/// What the app can account for of its own memory, and — the number that
/// matters — how much it cannot.
///
/// The app has now twice concluded it found the cause of a 1.5 GB footprint
/// and twice been wrong about the size of it, because nothing measured the
/// whole. `FeedMemoryBudget` capped the two streaming feeds after reasoning
/// that 128 MB of wire frames is roughly a gigabyte resident; the caps landed
/// and held (the field reports 21–33 MB of wire retained), and the footprint
/// still peaked at 1636 MB with four tabs open. Either the 8x decode estimate
/// badly understates the real cost, or most of that gigabyte was never the
/// feeds at all — and no event collected could tell those apart, because every
/// number in them described a feed.
///
/// So this is deliberately not another per-subsystem gauge. It is the
/// subtraction: every retainer that *can* size itself reports here, and what
/// telemetry ships is the total alongside `unattributedBytes` — the footprint
/// minus everything known. A report where the unattributed share is small
/// names the subsystem to fix. A report where it is 90% says the answer is in
/// something nobody is measuring, which is worth knowing on the first incident
/// rather than the third.
///
/// Every figure here is a *resident* estimate, so it is comparable to the
/// process footprint. A feed holding 24 MB of wire frames reports what those
/// cost decoded, not what they cost on the socket — mixing the two is the
/// mistake that started this.
public struct MemoryLedger: Sendable, Equatable {
    /// Who is holding memory. A fixed enum rather than free strings, for the
    /// reason the feed reporter it replaces gave: telemetry keys derived from
    /// this must be a closed set, so a renamed feature cannot silently start a
    /// new column, and a dashboard cannot quietly lose one.
    public enum Owner: String, Sendable, CaseIterable, Comparable {
        /// The Reactotron timeline's retained rows.
        case reactotron = "rt"
        /// The JS Console's retained rows.
        case jsConsole = "js"
        /// The logcat ring buffer.
        case logcat
        /// The iOS unified-log ring buffer.
        case iosLogs = "ioslog"
        /// Parsed crash reports held by the Crash Catcher.
        case crashes
        /// A capture open in the screenshot editor, plus its undo history.
        case screenshot = "shot"
        /// A decompiled APK's source tree.
        case decompile

        public static func < (lhs: Owner, rhs: Owner) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// One retainer's current holding. Rows and bytes are what it retains
    /// *now*, never a running total of what it has seen.
    public struct Entry: Sendable, Equatable {
        /// Estimated resident cost, comparable to the process footprint.
        public var residentBytes: Int
        /// Rows, frames, images — whatever this retainer counts in. Zero when
        /// the retainer has no meaningful unit.
        public var items: Int
        /// Whether any mounted view could see this when it last reported.
        /// Bytes held for something nobody is looking at is the shape of every
        /// incident so far.
        public var watched: Bool

        public init(residentBytes: Int, items: Int = 0, watched: Bool = false) {
            self.residentBytes = residentBytes
            self.items = items
            self.watched = watched
        }
    }

    private var entries: [Owner: Entry] = [:]

    public init() {}

    /// Record what a retainer holds right now, replacing its previous figure.
    public mutating func report(_ owner: Owner, _ entry: Entry) {
        entries[owner] = entry
    }

    /// A retainer that has gone away entirely — its tab closed, its session
    /// torn down. Without this its last reading is reported as live memory for
    /// the rest of the session, which turns the unattributed figure (the whole
    /// point of this type) negative and useless.
    public mutating func forget(_ owner: Owner) {
        entries.removeValue(forKey: owner)
    }

    public func entry(_ owner: Owner) -> Entry? { entries[owner] }

    /// Everything the app can account for.
    public var attributedBytes: Int {
        entries.values.reduce(0) { $0 + $1.residentBytes }
    }

    public var totalItems: Int { entries.values.reduce(0) { $0 + $1.items } }
    public var retainerCount: Int { entries.count }
    public var watchedCount: Int { entries.values.count { $0.watched } }

    /// The footprint this ledger cannot explain, floored at zero.
    ///
    /// Floored because these are estimates, and an estimate that overshoots
    /// the real footprint would otherwise report a negative — which reads as a
    /// data bug rather than as what it is, an over-generous multiplier. When
    /// this pins to zero repeatedly the estimates are too high, and that is
    /// itself the finding.
    public func unattributedBytes(footprintBytes: UInt64) -> Int {
        max(0, Int(footprintBytes) - attributedBytes)
    }

    /// Share of the footprint the app can account for, 0…100. The headline: a
    /// low number means the next incident must be diagnosed somewhere nobody
    /// is currently looking.
    public func attributedPercent(footprintBytes: UInt64) -> Int {
        guard footprintBytes > 0 else { return 0 }
        let share = Double(attributedBytes) / Double(footprintBytes) * 100
        return Int(min(100, max(0, share)).rounded())
    }

    /// Flattened for telemetry — numbers and fixed owner keys only, never
    /// contents. Prefixed `mem_` so these sit in their own namespace beside
    /// the feed-shaped keys that predate them and mean something different
    /// (those are wire bytes; these are resident estimates).
    public func properties(footprintBytes: UInt64) -> [String: Int] {
        var result: [String: Int] = [
            "mem_known_mb": Self.megabytes(attributedBytes),
            "mem_unknown_mb": Self.megabytes(unattributedBytes(footprintBytes: footprintBytes)),
            "mem_known_pct": attributedPercent(footprintBytes: footprintBytes),
            "mem_retainers": retainerCount,
            "mem_retainers_watched": watchedCount,
        ]
        for (owner, entry) in entries {
            result["mem_\(owner.rawValue)_mb"] = Self.megabytes(entry.residentBytes)
            if entry.items > 0 { result["mem_\(owner.rawValue)_items"] = entry.items }
        }
        return result
    }

    /// Whole megabytes, rounded to nearest — a retainer holding 700 KB reads
    /// as 1 MB rather than as nothing at all.
    static func megabytes(_ bytes: Int) -> Int {
        Int((Double(bytes) / 1_048_576).rounded())
    }
}
