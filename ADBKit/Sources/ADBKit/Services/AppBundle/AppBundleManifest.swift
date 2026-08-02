import Foundation

/// The metadata a split-bundle container carries about the app inside it,
/// normalised across APKPure's `manifest.json` (`.xapk`) and APKMirror's
/// `info.json` (`.apkm`). Both are optional conveniences: when a container has
/// no manifest, or it fails to parse, the installer falls back to scanning the
/// extracted files, so nothing here is load-bearing for the install itself.
public struct AppBundleManifest: Sendable, Equatable {
    /// An OBB expansion file to push alongside the APKs.
    public struct Expansion: Sendable, Equatable {
        /// Path of the file inside the archive.
        public var file: String
        /// Destination relative to the device's external storage root.
        public var installPath: String

        public init(file: String, installPath: String) {
            self.file = file
            self.installPath = installPath
        }
    }

    public var packageName: String?
    public var appName: String?
    public var versionName: String?
    public var versionCode: String?
    /// Split APKs the manifest lists, as archive-relative paths. Empty means
    /// "scan the extracted tree instead".
    public var splitFiles: [String] = []
    public var expansions: [Expansion] = []

    public init(
        packageName: String? = nil, appName: String? = nil, versionName: String? = nil,
        versionCode: String? = nil, splitFiles: [String] = [], expansions: [Expansion] = []
    ) {
        self.packageName = packageName
        self.appName = appName
        self.versionName = versionName
        self.versionCode = versionCode
        self.splitFiles = splitFiles
        self.expansions = expansions
    }

    /// The manifest file name a format keeps at its archive root, if any.
    public static func manifestFileName(for format: AppPackageFormat) -> String? {
        switch format {
        case .xapk: "manifest.json"
        case .apkm: "info.json"
        case .apk, .apks: nil
        }
    }

    /// Parse the manifest for `format`. Both producers have shipped several
    /// schema versions and type the same field as a string in one and a number
    /// in the next, so every value is read leniently and a missing field is just
    /// nil rather than a failure.
    public static func parse(_ data: Data, format: AppPackageFormat) -> AppBundleManifest? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return switch format {
        case .xapk: parseXapk(root)
        case .apkm: parseApkm(root)
        case .apk, .apks: nil
        }
    }

    private static func parseXapk(_ root: [String: Any]) -> AppBundleManifest {
        var manifest = AppBundleManifest(
            packageName: string(root["package_name"]),
            appName: string(root["name"]),
            versionName: string(root["version_name"]),
            versionCode: string(root["version_code"]))
        manifest.splitFiles = (root["split_apks"] as? [[String: Any]] ?? [])
            .compactMap { safeRelativePath(string($0["file"])) }
        manifest.expansions = (root["expansions"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let file = safeRelativePath(string(entry["file"])) else { return nil }
            let install = safeRelativePath(string(entry["install_path"])) ?? file
            return Expansion(file: file, installPath: install)
        }
        return manifest
    }

    /// APKMirror's `info.json` describes the release but never lists the splits
    /// — the installer scans the extracted files for those.
    private static func parseApkm(_ root: [String: Any]) -> AppBundleManifest {
        AppBundleManifest(
            packageName: string(root["pname"]),
            appName: string(root["app_name"]) ?? string(root["apk_title"]),
            versionName: string(root["release_version"]),
            versionCode: string(root["versioncode"]))
    }

    /// Read a JSON value that may be typed as a string or a number.
    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: text.isEmpty ? nil : text
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    /// Reject archive paths that escape the extraction directory or the device's
    /// external storage. A container is untrusted input, and its `install_path`
    /// is concatenated onto a device path — `../` there would write outside the
    /// app's OBB directory.
    static func safeRelativePath(_ path: String?) -> String? {
        guard let path, !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return nil }
        let components = path.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/")
        guard !components.contains(".."), !components.contains("") else { return nil }
        return components.joined(separator: "/")
    }
}
