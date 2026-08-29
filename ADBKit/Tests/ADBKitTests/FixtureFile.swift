import Foundation

/// Writing a file from a test fixture, on a filesystem that sometimes says no.
///
/// Windows CI refuses writes into a just-created temp directory with
/// `NSCocoaErrorDomain 513` / `Win32Error(code: 32)` — ERROR_SHARING_VIOLATION —
/// because something outside the process is still holding the path. It is the
/// same transient the shipping code carries `FileRetry` for, and it has now
/// failed `AabConvertServiceTests`, `DecompileServiceTests` and
/// `ManagedToolStoreTests` in turn, each time as a confusing error about
/// whatever the fixture was setting up for rather than about the write.
///
/// Two rules, both learned from those failures:
///
/// 1. **Never atomic.** An atomic write is write-a-temp-then-rename, and the
///    rename is the operation Windows refuses. A fixture writing a brand-new
///    file into a brand-new unique directory has no previous version to
///    protect, so atomicity buys it nothing and costs it this.
/// 2. **Retry, then say so.** A transient clears in milliseconds. One that does
///    not is a real problem, and it should be reported as a failure to *write*,
///    naming the path — not as whatever the code under test said two steps
///    later.
///
/// `FileRetry` itself is not used here: it is `async`, and these fixtures are
/// synchronous set-up.
enum FixtureFile {
    /// How many times to try before giving up. The shipping `FileRetry` uses
    /// the same count and the same rising back-off.
    static let attempts = 5

    static func write(_ contents: Data, to url: URL) throws {
        var lastError: (any Error)?
        for attempt in 1...attempts {
            do {
                try contents.write(to: url)
                return
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.05 * Double(attempt))
            }
        }
        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    static func write(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }
}
