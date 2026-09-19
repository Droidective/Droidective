import Foundation

/// Which files on disk make up one APK pull.
///
/// A split app is pulled as several files beside the one the user chose —
/// `com.x.apk` plus `com.x.split_config.en.apk` and friends, named by
/// `AppInspectionService.splitDestination`. The progress strip polled only the
/// chosen file's size against `apkSizeBytes`, which is the sum of *all* of
/// them, so the bar climbed to base/total, stalled there for the rest of the
/// pull, and then jumped to done. On a bundle whose splits outweigh the base
/// that is most of the wait spent looking stuck.
///
/// Pure and name-based: the caller does the directory read, this decides what
/// counts.
public enum PullProgress {
    /// Whether `fileName`, sitting in the destination's directory, is part of
    /// the pull that chose `destinationName`.
    ///
    /// The chosen file itself, or a split named after its stem. A neighbour
    /// that merely starts with the same letters (`com.example2.apk` beside
    /// `com.example.apk`) is excluded by requiring the separating dot.
    public static func belongsToPull(fileName: String, destinationName: String) -> Bool {
        if fileName == destinationName { return true }
        let stem = (destinationName as NSString).deletingPathExtension
        guard !stem.isEmpty else { return false }
        let suffix = (destinationName as NSString).pathExtension
        guard !suffix.isEmpty else { return false }
        return fileName.hasPrefix("\(stem).") && fileName.hasSuffix(".\(suffix)")
    }

    /// `419.4 MB of 1.2 GB` — what the progress strip says under the bar, or
    /// nil when there is nothing true to say.
    ///
    /// Sized with `ByteCountFormatter`'s `.file` style, which is what the File
    /// Explorer row and every other size in the app uses: the strip sits above
    /// the row being pulled, and the two disagreeing about one file reads as a
    /// broken transfer rather than as two conventions.
    ///
    /// A directory pull has no single total (`nil`), and neither has a file
    /// whose size adb did not report, so those say nothing rather than
    /// counting up towards a number that does not exist — the same reason the
    /// bar goes indeterminate. `copied` is clamped, because adb writes in
    /// blocks and a file system may report the allocated size, so passing the
    /// total briefly is ordinary.
    public static func caption(copied: Int, total: Int?) -> String? {
        guard let total, total > 0 else { return nil }
        let size = { (bytes: Int) in
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        return "\(size(min(copied, total))) of \(size(total))"
    }
}
