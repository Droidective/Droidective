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
}
