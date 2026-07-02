import Foundation

/// Pulls an app's launcher icon off the device *without* downloading the whole
/// APK. An APK is a zip, so `unzip -p <apk> <entry>` streams only the chosen
/// icon's bytes. We list entries with `unzip -l`, pick the sharpest raster
/// `ic_launcher`, and stream just that. Results are cached on disk so the list
/// only pays the cost once per app.
public struct AppIconService: Sendable {
    let client: AdbClient

    public init(client: AdbClient) {
        self.client = client
    }

    // Density buckets, richest first — we want the sharpest raster icon.
    static let densityOrder: [(token: String, rank: Int)] = [
        ("xxxhdpi", 6), ("xxhdpi", 5), ("xhdpi", 4),
        ("hdpi", 3), ("mdpi", 2), ("ldpi", 1), ("nodpi", 0), ("anydpi", 0),
    ]

    /// One row of `unzip -l` output: the entry path and its uncompressed size.
    public struct IconEntry: Sendable, Equatable {
        public let name: String
        public let size: Int
    }

    /// Parse `unzip -l` rows into (name, size), skipping the header, separator,
    /// and total lines. Each entry line is "  <length>  <date>  <time>   <name>"
    /// — header/total lines don't start with a numeric length and are dropped.
    public static func parseUnzipEntries(_ output: String) -> [IconEntry] {
        var entries: [IconEntry] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let fields = rawLine.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 4, let size = Int(fields[0]) else { continue }
            let name = fields[3...].joined(separator: " ")
            if !name.isEmpty {
                entries.append(IconEntry(name: name, size: size))
            }
        }
        return entries
    }

    /// Choose the best launcher-icon entry from an APK's file listing. Prefers a
    /// raster `ic_launcher` at the highest density, then round / foreground /
    /// other launcher rasters. When no name matches (resource shrinking flattens
    /// names to e.g. `res/xY.png`), falls back to the largest raster living in a
    /// density resource directory. Returns nil only when the APK ships no raster
    /// at all (vector-only adaptive icons) — the caller then shows a monogram.
    public static func pickIconEntry(_ entries: [IconEntry]) -> String? {
        var best: (entry: String, score: Int)?
        var largestRaster: (entry: String, size: Int)?
        for entry in entries {
            let lower = entry.name.lowercased()
            guard lower.hasSuffix(".png") || lower.hasSuffix(".webp") else { continue }
            let name = (lower as NSString).lastPathComponent
            // A raster in an icon density dir is a fallback candidate even when
            // its name matches nothing (obfuscated/flattened resource names).
            if lower.contains("/mipmap") || lower.contains("/drawable") {
                if entry.size > (largestRaster?.size ?? 0) {
                    largestRaster = (entry.name, entry.size)
                }
            }
            let baseScore: Int
            if name == "ic_launcher.png" || name == "ic_launcher.webp" {
                baseScore = 1000
            } else if name.contains("ic_launcher") && name.contains("round") {
                baseScore = 800
            } else if name.contains("ic_launcher") && name.contains("foreground") {
                baseScore = 700
            } else if name.contains("ic_launcher") {
                baseScore = 750
            } else if name.contains("launcher") || name.contains("app_icon")
                || name == "icon.png" || name == "icon.webp" {
                baseScore = 500
            } else if lower.contains("/mipmap") && name.contains("icon") {
                baseScore = 300
            } else if lower.contains("/mipmap") {
                baseScore = 200
            } else {
                continue
            }
            let score = baseScore + density(lower)
            if best == nil || score > best!.score {
                best = (entry.name, score)
            }
        }
        return best?.entry ?? largestRaster?.entry
    }

    static func density(_ path: String) -> Int {
        for (token, rank) in densityOrder where path.contains(token) {
            return rank
        }
        return 0
    }

    /// The launcher-icon bytes (PNG/WebP) for one package, or nil if the app
    /// ships no raster icon (or the device lacks `unzip`). Cached on disk.
    public func iconData(serial: String, packageId: String) async -> Data? {
        if let cached = Self.cachedData(packageId: packageId) {
            return cached.isEmpty ? nil : cached
        }
        guard let apk = await apkPath(serial: serial, packageId: packageId) else { return nil }

        guard let listing = try? await client.run(
            on: serial, ["exec-out", "unzip", "-l", apk], timeout: .seconds(20)
        ), listing.succeeded else {
            return nil
        }
        guard let entry = Self.pickIconEntry(Self.parseUnzipEntries(listing.stdout)) else {
            Self.cache(packageId: packageId, data: Data()) // sentinel: no raster icon
            return nil
        }

        guard let output = try? await client.runBinary(
            on: serial, ["exec-out", "unzip", "-p", apk, entry], timeout: .seconds(20)
        ), output.exitCode == 0, !output.stdout.isEmpty else {
            return nil
        }
        Self.cache(packageId: packageId, data: output.stdout)
        return output.stdout
    }

    private func apkPath(serial: String, packageId: String) async -> String? {
        guard let result = try? await client.run(on: serial, ["shell", "pm", "path", packageId]) else { return nil }
        let paths = result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "package:", with: "") }
            .filter { !$0.isEmpty }
        return paths.first { $0.hasSuffix("base.apk") } ?? paths.first
    }

    // MARK: - Disk cache (~/Library/Application Support/Droidective/IconCache)

    static func cacheDirectory() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("Droidective/IconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cacheURL(packageId: String) -> URL? {
        cacheDirectory()?.appendingPathComponent("\(packageId).img")
    }

    static func cachedData(packageId: String) -> Data? {
        guard let url = cacheURL(packageId: packageId) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func cache(packageId: String, data: Data) {
        guard let url = cacheURL(packageId: packageId) else { return }
        try? data.write(to: url)
    }
}
