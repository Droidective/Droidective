import Foundation
import Testing
@testable import ADBKit

@Suite struct ManagedToolTests {
    /// Build a `releases/latest` payload from asset file names and parse it —
    /// exercises decoding and asset selection together.
    private func release(tag: String, assetNames: [String]) throws -> GitHubRelease {
        let assets = assetNames
            .map { #"{"name":"\#($0)","browser_download_url":"https://example/\#($0)","size":7}"# }
            .joined(separator: ",")
        let json = #"{"tag_name":"\#(tag)","assets":[\#(assets)]}"#
        return try ManagedToolReleases.parse(Data(json.utf8))
    }

    // MARK: parsing

    @Test func parsesTagAssetsUrlSizeAndDigest() throws {
        let json = """
        {
          "tag_name": "v2.11.0",
          "assets": [
            {"name": "apktool_2.11.0.jar",
             "browser_download_url": "https://github.com/iBotPeaches/Apktool/releases/download/v2.11.0/apktool_2.11.0.jar",
             "size": 24117248,
             "digest": "sha256:deadbeef"}
          ]
        }
        """
        let parsed = try ManagedToolReleases.parse(Data(json.utf8))
        #expect(parsed.tagName == "v2.11.0")
        #expect(parsed.assets.count == 1)
        #expect(parsed.assets[0].name == "apktool_2.11.0.jar")
        #expect(parsed.assets[0].downloadURL.hasSuffix("apktool_2.11.0.jar"))
        #expect(parsed.assets[0].size == 24117248)
        #expect(parsed.assets[0].digest == "sha256:deadbeef")
    }

    @Test func toleratesMissingDigestAndUnknownFields() throws {
        let json = #"{"tag_name":"v1","html_url":"https://x","assets":[{"name":"a.jar","browser_download_url":"https://x/a.jar","size":1}]}"#
        let parsed = try ManagedToolReleases.parse(Data(json.utf8))
        #expect(parsed.assets[0].digest == nil)
    }

    // MARK: asset selection

    @Test func selectsApktoolJar() throws {
        let spec = ManagedToolSpec.catalog[.apktool]!
        let rel = try release(tag: "v2.11.0", assetNames: ["apktool_2.11.0.jar", "checksums.txt"])
        #expect(ManagedToolReleases.selectAsset(rel, spec: spec, arch: "")?.name == "apktool_2.11.0.jar")
    }

    @Test func jadxPicksTheCliDistNotTheGuiBuild() throws {
        // `^jadx-\d…` requires a digit right after "jadx-", so the gui builds
        // ("jadx-gui-…") are excluded and the plain dist zip wins.
        let spec = ManagedToolSpec.catalog[.jadx]!
        let rel = try release(tag: "v1.5.0", assetNames: [
            "jadx-gui-1.5.0-with-jre-macos.zip", "jadx-1.5.0.zip",
        ])
        #expect(ManagedToolReleases.selectAsset(rel, spec: spec, arch: "")?.name == "jadx-1.5.0.zip")
    }

    @Test func temurinPicksTheRequestedMacArch() throws {
        let spec = ManagedToolSpec.catalog[.temurinJre]!
        let rel = try release(tag: "jdk-21.0.4+7", assetNames: [
            "OpenJDK21U-jre_aarch64_mac_hotspot_21.0.4_7.tar.gz",
            "OpenJDK21U-jre_x64_mac_hotspot_21.0.4_7.tar.gz",
        ])
        #expect(ManagedToolReleases.selectAsset(rel, spec: spec, arch: "aarch64")?.name
            == "OpenJDK21U-jre_aarch64_mac_hotspot_21.0.4_7.tar.gz")
        #expect(ManagedToolReleases.selectAsset(rel, spec: spec, arch: "x64")?.name
            == "OpenJDK21U-jre_x64_mac_hotspot_21.0.4_7.tar.gz")
    }

    @Test func fridaServerAndGadgetMatchPerArchFromTheSameRelease() throws {
        let rel = try release(tag: "16.4.0", assetNames: [
            "frida-server-16.4.0-android-arm64.xz",
            "frida-server-16.4.0-android-x86_64.xz",
            "frida-gadget-16.4.0-android-arm64.so.xz",
        ])
        let server = ManagedToolSpec.catalog[.fridaServer]!
        let gadget = ManagedToolSpec.catalog[.fridaGadget]!
        // arm64 must not be satisfied by the x86_64 asset.
        #expect(ManagedToolReleases.selectAsset(rel, spec: server, arch: "arm64")?.name
            == "frida-server-16.4.0-android-arm64.xz")
        #expect(ManagedToolReleases.selectAsset(rel, spec: gadget, arch: "arm64")?.name
            == "frida-gadget-16.4.0-android-arm64.so.xz")
        // No asset for an unavailable ABI.
        #expect(ManagedToolReleases.selectAsset(rel, spec: server, arch: "mips") == nil)
    }

    @Test func bundletoolPicksTheAllJarNotSources() throws {
        let spec = ManagedToolSpec.catalog[.bundletool]!
        let rel = try release(tag: "1.18.3", assetNames: [
            "bundletool-1.18.3-sources.jar", "bundletool-all-1.18.3.jar",
        ])
        #expect(ManagedToolReleases.selectAsset(rel, spec: spec, arch: "")?.name == "bundletool-all-1.18.3.jar")
    }

    // MARK: version comparison

    @Test func isNewerComparesNumericComponents() {
        #expect(ManagedToolReleases.isNewer("v2.11.0", than: "v2.9.0"))   // 11 > 9, not string order
        #expect(!ManagedToolReleases.isNewer("v2.9.0", than: "v2.11.0"))
        #expect(!ManagedToolReleases.isNewer("v1.5.0", than: "v1.5.0"))   // equal → not newer
        #expect(ManagedToolReleases.isNewer("jdk-21.0.4+7", than: "jdk-21.0.3+9"))
        #expect(!ManagedToolReleases.isNewer("jdk-21.0.3+9", than: "jdk-21.0.4+7"))
    }

    // MARK: error messages

    @Test func rateLimited403ExplainsItselfInsteadOfABareCode() {
        let message = ManagedToolStore.StoreError.http(403).errorDescription ?? ""
        #expect(message.contains("limit"))
        #expect(ManagedToolStore.StoreError.http(500).errorDescription == "Download failed (HTTP 500).")
    }

    // MARK: catalog invariants

    /// Every spec this host offers is complete and pinned.
    ///
    /// `hostCatalog` rather than `ManagedTool.allCases`: not every tool is
    /// managed on every platform. ffmpeg is *bundled* on the Mac and downloaded
    /// off it, so the enum has a case the Mac's catalog deliberately does not
    /// carry — asking every case for a spec would fail on the one platform that
    /// does not need one.
    @Test func everyOfferedToolHasASpecWithAPinnedReleaseURL() throws {
        for (tool, spec) in ManagedToolSpec.hostCatalog {
            #expect(spec.tool == tool)
            #expect(!spec.pinnedTag.isEmpty, "\(tool.rawValue) needs a pinned tag")
            #expect(spec.pinnedReleaseURL?.absoluteString
                == "https://api.github.com/repos/\(spec.owner)/\(spec.repo)/releases/tags/\(spec.pinnedTag)")
        }
    }

    /// And what each platform offers is the platform's own answer, not a
    /// leftover: the Mac bundles ffmpeg, so it must not appear there, and every
    /// other platform must download it — a missing entry would be a Tools
    /// screen that silently cannot record.
    @Test func ffmpegIsManagedEverywhereItIsNotBundled() throws {
        #if os(macOS)
        #expect(ManagedToolSpec.hostCatalog[.ffmpeg] == nil, "ffmpeg is bundled on macOS")
        #else
        let spec = try #require(ManagedToolSpec.hostCatalog[.ffmpeg])
        #expect(!spec.runnableName.isEmpty)
        #expect(!spec.assetPattern.isEmpty)
        #endif
    }
}
