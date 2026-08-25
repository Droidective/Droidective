import Foundation

/// Retry a filesystem mutation that can fail transiently because something
/// outside this process still holds the file open.
///
/// Windows is why this exists. A file that was just written can still be locked
/// by whatever read it on the way in — a virus scanner is the usual one, and
/// Defender on a CI runner is the reliable reproducer — and renaming it then
/// fails with ERROR_SHARING_VIOLATION (Win32 32), surfaced as
/// `NSFileWriteNoPermissionError` against the *source* path. It clears in
/// milliseconds. `SecretFile.restrictToOwner` already names the same behaviour
/// for the same reason.
///
/// Deliberately not gated to Windows. POSIX `rename(2)` does not care who has
/// the file open, so off Windows this all but always succeeds on the first
/// attempt — but a scanned or network volume can stall anywhere, and one code
/// path is one path the tests cover on every platform.
enum FileRetry {
    /// Run `body`, retrying up to `attempts` times before rethrowing.
    ///
    /// `pause` is called between attempts with the 1-based number of the
    /// attempt that just failed, so a test can drive the loop without sleeping.
    /// A `pause` that throws — the default does, on cancellation — aborts the
    /// retry with *its* error rather than the filesystem one: a cancelled
    /// install should stop, not keep retrying.
    ///
    /// `isolation` inherits the caller's actor so `body` can touch that actor's
    /// state — `ManagedToolStore`'s `fileManager` — without being sent across
    /// an isolation boundary and tripping strict concurrency.
    static func run<T>(
        attempts: Int = 5,
        isolation: isolated (any Actor)? = #isolation,
        pause: (Int) async throws -> Void = { try await Task.sleep(for: .milliseconds(50 * $0)) },
        _ body: () throws -> T
    ) async throws -> T {
        var remaining = max(1, attempts)
        var attempt = 0
        while true {
            attempt += 1
            remaining -= 1
            do {
                return try body()
            } catch {
                // `<=`, not `==`: a caller passing a non-positive count drives
                // `remaining` straight past zero, and an equality check would
                // then never stop — a retry loop that spins forever instead of
                // reporting the failure.
                if remaining <= 0 { throw error }
                try await pause(attempt)
            }
        }
    }
}
