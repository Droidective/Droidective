import Foundation

/// A short-lived file holding a secret — a keystore password — so it never has
/// to ride on a command line, where every process on the machine can read it
/// out of the process table.
///
/// Shared by the two signing paths (`ApkSigningService`, `AabConvertService`)
/// because it's the security boundary for both, and one implementation is one
/// place to get the permissions right.
public enum SecretFile {
    public enum Failure: Error, LocalizedError, Sendable {
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .writeFailed(detail): detail
            }
        }
    }

    /// Write `secret` to a uniquely named file in the per-user temp directory
    /// and return its path. Callers delete it when the tool is done with it.
    ///
    /// The file is created and *then* tightened to 0600. That leaves a moment
    /// where it carries the default mode, which the per-user temp directory's
    /// own 0700 covers; creating it 0600 in one step would mean raw `open(2)`,
    /// which isn't portable.
    public static func write(_ secret: String, prefix: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)\(UUID().uuidString)")
        do {
            try Data(secret.utf8).write(to: url)
        } catch {
            // Say *why*. The previous implementation used
            // `FileManager.createFile`, whose Bool result threw away the reason
            // — which is how a one-off Windows CI failure ("Couldn't write the
            // keystore password file") arrived with nothing to diagnose.
            throw Failure.writeFailed(
                "Couldn't write the secret file at \(url.path): \(error.localizedDescription)")
        }
        try restrictToOwner(url)
        return url.path
    }

    /// Make the file readable only by its owner.
    ///
    /// On Windows this is best-effort *by design*: the POSIX mode isn't the
    /// mechanism there (the per-user temp directory's ACL is — `_wchmod` only
    /// toggles the read-only bit), and the call can fail transiently while
    /// something else still holds the freshly written file. Failing a signing
    /// run over an attribute the platform doesn't enforce would trade a real
    /// capability for no security.
    private static func restrictToOwner(_ url: URL) throws {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            #if os(Windows)
            return
            #else
            try? FileManager.default.removeItem(at: url)
            throw Failure.writeFailed(
                "Couldn't restrict the secret file's permissions: \(error.localizedDescription)")
            #endif
        }
    }
}
