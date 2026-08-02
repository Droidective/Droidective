import Foundation

/// The bounded queue behind one stream subscription.
///
/// A slow UI must never grow an unbounded queue in the daemon — the same trap
/// that forced the macOS log readers back onto Foundation's pull-driven reader.
/// So each subscription holds at most `capacity` items; past that the **oldest
/// go first** and the client is told how many, rather than the daemon eating
/// memory or the producer stalling.
///
/// This deliberately differs from the Mac app, which stalls: `bytes.lines` is
/// pull-driven, so a slow consumer backpressures the pipe. The divergence is
/// the decision — a responsive UI with an honest gap beats one that silently
/// falls behind real time. It also matches what the device already does, since
/// Android's logcat ring buffer drops under load regardless; "lossless" was
/// never actually on offer.
///
/// Dropping oldest rather than newest is the other half of that: a log tail is
/// read from the bottom, so the newest lines are the ones worth keeping.
struct StreamBuffer<Item: Sendable>: Sendable {
    /// Items waiting to go out, oldest first.
    private(set) var pending: [Item] = []
    /// Items discarded since the last `drain`, and never silently.
    private(set) var dropped = 0

    let capacity: Int

    /// - Parameter capacity: maximum items held before dropping starts. Must be
    ///   at least 1; a zero-capacity buffer would drop everything and report a
    ///   gap forever, which is a configuration bug rather than a runtime state.
    init(capacity: Int) {
        precondition(capacity >= 1, "a stream buffer must hold at least one item")
        self.capacity = capacity
    }

    /// Appends `items`, discarding the oldest to stay within capacity.
    ///
    /// Takes a batch rather than one item because that is how the producers
    /// deliver: `LogcatStreamer` already coalesces on its flush interval, and
    /// re-splitting a batch to push it one line at a time would be pure waste.
    mutating func append(contentsOf items: some Collection<Item>) {
        pending.append(contentsOf: items)
        let excess = pending.count - capacity
        guard excess > 0 else { return }
        pending.removeFirst(excess)
        dropped += excess
    }

    /// Everything waiting, plus how many were lost getting here — then resets.
    ///
    /// The count rides with the batch rather than being reported separately so
    /// the client can place the gap correctly: these N items arrived *after*
    /// that many were dropped.
    mutating func drain() -> (items: [Item], dropped: Int) {
        defer {
            pending.removeAll(keepingCapacity: true)
            dropped = 0
        }
        return (pending, dropped)
    }

    var isEmpty: Bool { pending.isEmpty && dropped == 0 }
}
