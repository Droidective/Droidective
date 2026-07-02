import Foundation

/// Constant-time disposal for throwaway cache directories.
///
/// Deleting the decompiled-APK cache tree (tens of thousands of jadx/apktool
/// files) with `FileManager.removeItem` walks it file by file — seconds of
/// wall time, which hung quit when it ran in `applicationWillTerminate`
/// (Sentry DROIDECTIVE-MAC-R). Instead, `setAside` renames the directory to a
/// uniquely named `<name>.trash-<uuid>` sibling — a single `rename()`, constant
/// time regardless of contents — and `sweep` deletes any such leftovers later,
/// off the critical path (next launch, in a detached task).
public enum CacheTrash {
    /// Atomically renames `directory` to `<name>.trash-<uuid>` next to it.
    ///
    /// Constant time regardless of the tree's size. A missing directory is a
    /// no-op; a failed rename leaves the directory in place for a later
    /// attempt. Returns the trash URL, or nil if nothing was moved.
    @discardableResult
    public static func setAside(_ directory: URL) -> URL? {
        let trashURL = directory.deletingLastPathComponent().appendingPathComponent(
            "\(directory.lastPathComponent)\(trashInfix)\(UUID().uuidString)", isDirectory: true
        )
        do {
            try FileManager.default.moveItem(at: directory, to: trashURL)
        } catch {
            return nil
        }
        return trashURL
    }

    /// Deletes every `<name>.trash-*` sibling of `directory`, leaving the live
    /// directory (and everything else in the parent) alone. A missing parent is
    /// a no-op. Tree deletion is slow — call this off the main actor.
    public static func sweep(around directory: URL) {
        let parent = directory.deletingLastPathComponent()
        let prefix = directory.lastPathComponent + trashInfix
        guard let siblings = try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: nil
        ) else { return }
        for sibling in siblings where sibling.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: sibling)
        }
    }

    private static let trashInfix = ".trash-"
}
