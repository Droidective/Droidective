import Foundation

/// A tool the app fetches from its GitHub releases and keeps up to date itself,
/// rather than asking the user to install it. Cached under Application Support,
/// version-tracked, and upgradable in place (see `ManagedToolStore`).
public enum ManagedTool: String, Sendable, CaseIterable, Codable {
    case jadx
    case apktool
    case uberApkSigner = "uber-apk-signer"
    case fridaServer = "frida-server"
    case fridaGadget = "frida-gadget"
    case temurinJre = "temurin-jre"
    case bundletool
    /// Windows and Linux only. macOS bundles a static ffmpeg in the app, so a
    /// downloadable second copy would be another answer to the same question —
    /// `hostCatalog` leaves it out there.
    case ffmpeg
}

/// How a downloaded release asset turns into a runnable artifact.
public enum ArtifactKind: Sendable, Equatable {
    /// The asset itself is the runnable jar (run via `java -jar`).
    case jar
    /// A `.zip` whose extracted tree contains the runnable.
    case zipArchive
    /// A `.tar.gz` whose extracted tree contains the runnable.
    case tarGz
    /// A bare `.xz`-compressed single binary (frida; pushed to the device).
    case xzBinary
    /// A `.tar.xz` whose extracted tree contains the runnable. `tar -xf` picks
    /// the compression itself on bsdtar and on GNU tar since 1.15, so this
    /// needs no separate `xz` on the host.
    case tarXz
}

/// Static metadata for a managed tool: which GitHub repo and release tag to
/// fetch it from, how to recognise the right release asset, and where the
/// runnable sits once placed. Pure data — no I/O — so the catalog and its
/// matchers are unit-tested.
public struct ManagedToolSpec: Sendable, Equatable {
    public let tool: ManagedTool
    public let owner: String
    public let repo: String
    /// The exact release tag the app installs — a known-good version pinned at
    /// build time, so a compromised or broken "latest" release can't be pulled
    /// automatically. App updates ship new pins.
    public let pinnedTag: String
    public let kind: ArtifactKind
    /// Regex matched against a release asset's file name. `{arch}` is replaced
    /// with the target architecture for per-arch tools (Temurin uses the Mac's
    /// arch; frida uses the device ABI); other patterns ignore it.
    public let assetPattern: String
    /// File name of the runnable to locate within the extracted tree, or nil
    /// when the downloaded asset is itself the runnable (`.jar` / `.xzBinary`).
    public let runnableName: String?

    public init(
        tool: ManagedTool, owner: String, repo: String, pinnedTag: String, kind: ArtifactKind,
        assetPattern: String, runnableName: String? = nil
    ) {
        self.tool = tool
        self.owner = owner
        self.repo = repo
        self.pinnedTag = pinnedTag
        self.kind = kind
        self.assetPattern = assetPattern
        self.runnableName = runnableName
    }

    /// `GET /repos/{owner}/{repo}/releases/tags/{pinnedTag}`.
    public var pinnedReleaseURL: URL? {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(pinnedTag)")
    }

    public static let catalog: [ManagedTool: ManagedToolSpec] = [
        .jadx: ManagedToolSpec(
            tool: .jadx, owner: "skylot", repo: "jadx", pinnedTag: "v1.5.6", kind: .zipArchive,
            assetPattern: #"^jadx-\d.*\.zip$"#, runnableName: "jadx"),
        .apktool: ManagedToolSpec(
            tool: .apktool, owner: "iBotPeaches", repo: "Apktool", pinnedTag: "v3.0.2", kind: .jar,
            assetPattern: #"^apktool_.*\.jar$"#),
        .uberApkSigner: ManagedToolSpec(
            tool: .uberApkSigner, owner: "patrickfav", repo: "uber-apk-signer", pinnedTag: "v1.3.0",
            kind: .jar, assetPattern: #"^uber-apk-signer-.*\.jar$"#),
        .fridaServer: ManagedToolSpec(
            tool: .fridaServer, owner: "frida", repo: "frida", pinnedTag: "17.15.4", kind: .xzBinary,
            assetPattern: #"^frida-server-.*-android-{arch}\.xz$"#, runnableName: "frida-server"),
        .fridaGadget: ManagedToolSpec(
            tool: .fridaGadget, owner: "frida", repo: "frida", pinnedTag: "17.15.4", kind: .xzBinary,
            assetPattern: #"^frida-gadget-.*-android-{arch}\.so\.xz$"#, runnableName: "frida-gadget.so"),
        .temurinJre: ManagedToolSpec(
            tool: .temurinJre, owner: "adoptium", repo: "temurin21-binaries",
            pinnedTag: "jdk-21.0.11+10", kind: .tarGz,
            assetPattern: #"^OpenJDK21U-jre_{arch}_mac_hotspot_.*\.tar\.gz$"#, runnableName: "java"),
        .bundletool: ManagedToolSpec(
            tool: .bundletool, owner: "google", repo: "bundletool", pinnedTag: "1.18.3",
            kind: .jar, assetPattern: #"^bundletool-all-.*\.jar$"#),
    ]

    /// What this host may download, and how.
    ///
    /// The base `catalog` is macOS-shaped — Temurin's asset pattern says `mac`
    /// in it — because that is the app it was written for. Rather than making
    /// every entry conditional, a host adds or replaces the few that differ,
    /// and macOS gets exactly what it always got.
    ///
    /// ffmpeg is the clearest case: the Mac app bundles one, so it is not in
    /// this list there; Windows and Linux have no bundle, so it is a managed
    /// download beside jadx and apktool rather than something a person has to
    /// install first.
    public static var hostCatalog: [ManagedTool: ManagedToolSpec] {
        #if os(macOS)
        return catalog
        #elseif os(Windows)
        return catalog.merging([
            .ffmpeg: ManagedToolSpec(
                tool: .ffmpeg, owner: "BtbN", repo: "FFmpeg-Builds",
                pinnedTag: ffmpegPinnedTag, kind: .zipArchive,
                assetPattern: #"^ffmpeg-n.*-win64-gpl-.*\.zip$"#, runnableName: "ffmpeg.exe"),
            .temurinJre: ManagedToolSpec(
                tool: .temurinJre, owner: "adoptium", repo: "temurin21-binaries",
                pinnedTag: "jdk-21.0.11+10", kind: .zipArchive,
                assetPattern: #"^OpenJDK21U-jre_{arch}_windows_hotspot_.*\.zip$"#,
                runnableName: "java.exe"),
        ]) { _, new in new }
        #else
        return catalog.merging([
            .ffmpeg: ManagedToolSpec(
                tool: .ffmpeg, owner: "BtbN", repo: "FFmpeg-Builds",
                pinnedTag: ffmpegPinnedTag, kind: .tarXz,
                assetPattern: #"^ffmpeg-n.*-linux64-gpl-.*\.tar\.xz$"#, runnableName: "ffmpeg"),
            .temurinJre: ManagedToolSpec(
                tool: .temurinJre, owner: "adoptium", repo: "temurin21-binaries",
                pinnedTag: "jdk-21.0.11+10", kind: .tarGz,
                assetPattern: #"^OpenJDK21U-jre_{arch}_linux_hotspot_.*\.tar\.gz$"#,
                runnableName: "java"),
        ]) { _, new in new }
        #endif
    }

    /// A dated build rather than BtbN's rolling `latest`, for the reason every
    /// other tool here is pinned: an app update is what should change which
    /// binary people run, not a repository moving under them.
    static let ffmpegPinnedTag = "autobuild-2025-06-20-14-16"
}

/// One GitHub release and its downloadable assets, decoded from the
/// `releases/tags/{tag}` API response.
public struct GitHubRelease: Sendable, Equatable, Decodable {
    public let tagName: String
    public let assets: [Asset]

    public struct Asset: Sendable, Equatable, Decodable {
        public let name: String
        public let downloadURL: String
        public let size: Int
        /// e.g. "sha256:abc…" — present on newer releases, used to verify the
        /// download. nil on older releases.
        public let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case size
            case digest
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

/// Pure helpers over GitHub release data — parsing, asset selection, and version
/// comparison. No I/O, so they're unit-tested without the network.
public enum ManagedToolReleases {
    public static func parse(_ data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// The first asset whose name matches `spec.assetPattern` (with `{arch}`
    /// substituted), or nil when the release carries no matching asset.
    public static func selectAsset(
        _ release: GitHubRelease, spec: ManagedToolSpec, arch: String
    ) -> GitHubRelease.Asset? {
        let pattern = spec.assetPattern.replacingOccurrences(
            of: "{arch}", with: NSRegularExpression.escapedPattern(for: arch))
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return release.assets.first { asset in
            let range = NSRange(asset.name.startIndex..., in: asset.name)
            return regex.firstMatch(in: asset.name, range: range) != nil
        }
    }

    /// True when `candidate` is a newer version than `current`, comparing the
    /// numeric components of each tag (so "v2.11.0" > "v2.9.0" and
    /// "jdk-21.0.4+7" > "jdk-21.0.3+9"). Equal numerics → not newer.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = numericComponents(candidate)
        let rhs = numericComponents(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// Numeric runs of a version tag, ignoring any non-digit separators
    /// ("v", "jdk-", ".", "+"): "jdk-21.0.4+7" → [21, 0, 4, 7].
    static func numericComponents(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }
}
