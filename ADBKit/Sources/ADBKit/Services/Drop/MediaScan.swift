import Foundation

/// Getting a pushed file into MediaStore, so a screenshot dropped on the
/// mirror actually turns up in the Gallery instead of only in Files.
///
/// `adb push` writes the bytes and nothing else — the media database is not
/// watching the filesystem. Which command performs the scan changed with
/// Android 10: `MEDIA_SCANNER_SCAN_FILE` is ignored for `file://` URIs from
/// API 29 on (the same change that took away raw file paths), and the
/// replacement is a direct provider call. Older devices only know the
/// broadcast. Pure and static so both arg vectors are asserted in tests
/// rather than tried on one phone and assumed.
public enum MediaScan {
    /// The first API level where the provider call is the working route.
    public static let providerCallMinimumSDK = 29

    /// The adb argument vector (everything after the serial) that indexes
    /// `path`. The path crosses `adb shell`, so it is quoted — a dropped file
    /// name is whatever Finder had, backticks and all.
    public static func command(sdk: Int?, path: String) -> [String] {
        // An unknown SDK takes the modern route: it is what every device the
        // app can still reach a Play-services era build on understands, and a
        // failed scan is a cosmetic loss, not a lost file.
        guard let sdk, sdk < providerCallMinimumSDK else {
            return [
                "shell", "content", "call",
                "--uri", "content://media/external/file",
                "--method", "scan_file",
                "--arg", shellQuote(path),
            ]
        }
        return [
            "shell", "am", "broadcast",
            "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE",
            "-d", shellQuote("file://" + path),
        ]
    }
}
