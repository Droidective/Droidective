import Foundation

/// The installable Android package formats Droidective accepts.
///
/// Only `.apk` is a single package adb can install directly. The other three are
/// zip containers around a *split* app (a base APK plus per-ABI/density/language
/// config splits), each from a different producer:
///
/// - `.apks` — bundletool's own output (`build-apks`), carrying a `toc.pb`
///   device-targeting table. Installed by handing the archive back to bundletool.
/// - `.xapk` — APKPure's container: a `manifest.json`, the splits, and any OBB
///   expansion files under `Android/obb/<package>/`.
/// - `.apkm` — APKMirror's container: an `info.json` plus the splits.
public enum AppPackageFormat: String, Sendable, CaseIterable {
    case apk
    case apks
    case xapk
    case apkm

    /// Every extension the app opens, lowercased — the single source of truth
    /// for drop filters, open panels, and the Finder document types.
    public static var fileExtensions: [String] { allCases.map(\.rawValue) }

    /// Classify by file extension. Returns nil for anything else, so callers can
    /// reject a stray file instead of guessing.
    public static func detect(fileName: String) -> AppPackageFormat? {
        AppPackageFormat(rawValue: URL(fileURLWithPath: fileName).pathExtension.lowercased())
    }

    /// True when the file is a zip container that has to be unpacked (or handed
    /// to bundletool) rather than passed straight to `adb install`.
    public var isBundle: Bool { self != .apk }

    /// How the format is named in UI copy.
    public var displayName: String {
        switch self {
        case .apk: "APK"
        case .apks: "APKS"
        case .xapk: "XAPK"
        case .apkm: "APKM"
        }
    }
}
