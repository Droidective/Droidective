import Foundation
import Testing

@testable import ADBKit

/// The retry that keeps a Windows sharing violation from failing a tool
/// install. Driven with an injected `pause`, so the loop is exercised without
/// any test sleeping.
@Suite struct FileRetryTests {
    private struct Boom: Error, Equatable {
        let attempt: Int
    }

    private struct Cancelled: Error, Equatable {}

    /// A recorder for the attempt numbers `pause` was called with — which is
    /// how many times the body failed, and in what order.
    private final class Pauses: @unchecked Sendable {
        private(set) var seen: [Int] = []
        func record(_ attempt: Int) { seen.append(attempt) }
    }

    @Test func succeedsOnTheFirstAttemptWithoutPausing() async throws {
        let pauses = Pauses()
        var calls = 0

        let value = try await FileRetry.run(pause: { pauses.record($0) }) {
            calls += 1
            return "moved"
        }

        #expect(value == "moved")
        #expect(calls == 1)
        #expect(pauses.seen.isEmpty)
    }

    /// The flake's actual shape: the move fails a couple of times while the
    /// scanner holds the file, then goes through.
    @Test func retriesUntilTheOperationGoesThrough() async throws {
        let pauses = Pauses()
        var calls = 0

        let value = try await FileRetry.run(pause: { pauses.record($0) }) {
            calls += 1
            if calls < 3 { throw Boom(attempt: calls) }
            return calls
        }

        #expect(value == 3)
        #expect(calls == 3)
        // Paused after the first and second failures, not after the success.
        #expect(pauses.seen == [1, 2])
    }

    @Test func rethrowsTheLastErrorWhenEveryAttemptFails() async throws {
        let pauses = Pauses()
        var calls = 0

        await #expect(throws: Boom(attempt: 4)) {
            try await FileRetry.run(attempts: 4, pause: { pauses.record($0) }) {
                calls += 1
                throw Boom(attempt: calls)
            }
        }

        #expect(calls == 4)
        #expect(pauses.seen == [1, 2, 3])
    }

    /// One attempt means no retry at all — the error comes straight back and
    /// nothing waits.
    @Test func asingleAttemptDoesNotPause() async throws {
        let pauses = Pauses()

        await #expect(throws: Boom(attempt: 1)) {
            try await FileRetry.run(attempts: 1, pause: { pauses.record($0) }) {
                throw Boom(attempt: 1)
            }
        }

        #expect(pauses.seen.isEmpty)
    }

    /// A nonsense count still runs the body once rather than trapping or
    /// silently succeeding with no work done.
    @Test func aNonPositiveAttemptCountStillRunsOnce() async throws {
        var calls = 0

        let value = try await FileRetry.run(attempts: 0, pause: { _ in }) {
            calls += 1
            return calls
        }

        #expect(value == 1)
        #expect(calls == 1)
    }

    /// The same nonsense count with a *failing* body has to give up, not spin.
    /// The loop counts down from the requested number, so a bare equality check
    /// against zero would sail past it and retry forever — this is the test
    /// that fails (by hanging) if that guard regresses.
    @Test func aNonPositiveAttemptCountGivesUpInsteadOfSpinning() async throws {
        let pauses = Pauses()
        var calls = 0

        await #expect(throws: Boom(attempt: 1)) {
            try await FileRetry.run(attempts: 0, pause: { pauses.record($0) }) {
                calls += 1
                throw Boom(attempt: calls)
            }
        }

        #expect(calls == 1)
        #expect(pauses.seen.isEmpty)
    }

    /// Cancellation wins over the filesystem error: the real `pause` throws
    /// when the install's task is cancelled, and the retry must stop there
    /// rather than keep hammering a move nobody is waiting for.
    @Test func aThrowingPauseAbortsTheRetryWithItsOwnError() async throws {
        var calls = 0

        await #expect(throws: Cancelled()) {
            try await FileRetry.run(pause: { _ in throw Cancelled() }) {
                calls += 1
                throw Boom(attempt: calls)
            }
        }

        // Failed once, then the pause stopped it — no second attempt.
        #expect(calls == 1)
    }

    /// The real default pause sleeps rather than spinning, and a cancelled task
    /// comes out of it as a cancellation rather than running the body again.
    @Test func theDefaultPauseFailsACancelledTask() async throws {
        let task = Task {
            var calls = 0
            return try await FileRetry.run {
                calls += 1
                throw Boom(attempt: calls)
            }
        }
        task.cancel()

        await #expect(throws: (any Error).self) { try await task.value }
    }
}
