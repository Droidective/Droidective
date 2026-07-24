/// Order-of-magnitude bucketing for the console's ingest-rate diagnostic:
/// 0 for under one message per minute, then 1, 10, 100, 1000… The decade —
/// not the exact rate — is the signal, and the coarse bucket is what keeps
/// the published diagnostic context from re-publishing on every noisy 2 s
/// discovery pass.
enum ConsoleRateBucket {
    static func decade(_ perMinute: Double) -> Int {
        guard perMinute >= 1 else { return 0 }
        var bucket = 1
        while Double(bucket * 10) <= perMinute { bucket *= 10 }
        return bucket
    }

    /// The bucket at which a rate rise counts as a burst worth a breadcrumb.
    static let burstFloor = 1000

    /// Whether a bucket transition is a burst: only a *rise* landing at or
    /// above `burstFloor`, and only when a previous publication exists — the
    /// first publish after a connect is baseline, not news, and a steady or
    /// falling rate must never crumb (it would spam the timeline on every
    /// re-publish of an already-busy stream).
    static func isBurst(from previous: Int?, to next: Int) -> Bool {
        guard let previous else { return false }
        return next > previous && next >= burstFloor
    }
}
