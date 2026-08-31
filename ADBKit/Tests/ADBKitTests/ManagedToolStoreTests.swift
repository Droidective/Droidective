#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Testing
@testable import ADBKit

/// Host-extraction tooling differs enough on Windows that two fixtures below
/// cannot be built or decoded there; `.enabled(if:)` reports them as skipped
/// rather than silently compiling them out.
private let isWindows: Bool = {
    #if os(Windows)
    return true
    #else
    return false
    #endif
}()

@Suite struct ManagedToolStoreTests {
    /// Canned network: every `data(from:)` returns the same release JSON, every
    /// download writes the same asset bytes. Extraction uses the real runner.
    final class MockHTTP: HTTPFetching, @unchecked Sendable {
        let releaseJSON: Data
        let assetBytes: Data
        private(set) var requested: [URL] = []
        init(releaseJSON: Data, assetBytes: Data) {
            self.releaseJSON = releaseJSON
            self.assetBytes = assetBytes
        }
        func data(from url: URL) async throws -> Data {
            requested.append(url)
            return releaseJSON
        }
        func download(from url: URL, to destination: URL, onProgress: (@Sendable (Double) -> Void)?) async throws {
            onProgress?(1)
            try FixtureFile.write(assetBytes, to: destination)
        }
    }

    private func releaseJSON(tag: String, assetName: String, digest: String? = nil) -> Data {
        let digestField = digest.map { #","digest":"\#($0)""# } ?? ""
        let json = #"{"tag_name":"\#(tag)","assets":[{"name":"\#(assetName)","browser_download_url":"https://example/\#(assetName)","size":7\#(digestField)}]}"#
        return Data(json.utf8)
    }

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("toolstore-\(UUID().uuidString)")
    }

    @Test func seedInstallsABundledCopyAndResolvesIt() async throws {
        let jar = FileManager.default.temporaryDirectory.appendingPathComponent("bundletool-all.jar")
        try FixtureFile.write(Data("BUNDLED-JAR".utf8), to: jar)
        defer { try? FileManager.default.removeItem(at: jar) }
        let store = ManagedToolStore(rootDirectory: tempRoot())

        try await store.seed(.bundletool, version: "1.18.3", from: jar)

        #expect(await store.installedVersion(.bundletool) == "1.18.3")
        #expect(await store.resolve(.bundletool)?.hasSuffix("bundletool-all.jar") == true)
        // Idempotent: seeding the same version again is a no-op, not a crash.
        try await store.seed(.bundletool, version: "1.18.3", from: jar)
        // A newer bundled copy (an app update) upgrades in place …
        try await store.seed(.bundletool, version: "1.19.0", from: jar)
        #expect(await store.installedVersion(.bundletool) == "1.19.0")
        // … but an older one never downgrades a newer install.
        try await store.seed(.bundletool, version: "1.18.3", from: jar)
        #expect(await store.installedVersion(.bundletool) == "1.19.0")
    }

    @Test func installsApktoolJarAndResolvesIt() async throws {
        let bytes = Data("FAKE-JAR".utf8)
        let http = MockHTTP(releaseJSON: releaseJSON(tag: "v2.11.0", assetName: "apktool_2.11.0.jar"), assetBytes: bytes)
        let store = ManagedToolStore(rootDirectory: tempRoot(), http: http)

        let path = try await store.install(.apktool)

        #expect(path.hasSuffix("apktool_2.11.0.jar"))
        #expect(await store.installedVersion(.apktool) == "v2.11.0")
        #expect(await store.resolve(.apktool) == path)
        #expect(FileManager.default.contents(atPath: path) == bytes)
        // The release is fetched at the pinned tag, never `releases/latest`.
        #expect(http.requested == [ManagedToolSpec.catalog[.apktool]?.pinnedReleaseURL].compactMap(\.self))
    }

    @Test func locationSizeAndRemoveManageTheInstall() async throws {
        let bytes = Data("FAKE-JAR-CONTENTS".utf8)
        let http = MockHTTP(releaseJSON: releaseJSON(tag: "v2.11.0", assetName: "apktool_2.11.0.jar"), assetBytes: bytes)
        let store = ManagedToolStore(rootDirectory: tempRoot(), http: http)
        _ = try await store.install(.apktool)

        let dir = try #require(await store.location(.apktool))
        #expect(ManagedToolStore.size(at: dir) >= Int64(bytes.count))

        try await store.remove(.apktool)
        #expect(await store.location(.apktool) == nil)
        #expect(await store.installedVersion(.apktool) == nil)
    }

    @Test func verifiesAssetDigestWhenPresent() async throws {
        let bytes = Data("signed-payload".utf8)
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let http = MockHTTP(
            releaseJSON: releaseJSON(tag: "v1.3.0", assetName: "uber-apk-signer-1.3.0.jar", digest: "sha256:\(sha)"),
            assetBytes: bytes)
        let store = ManagedToolStore(rootDirectory: tempRoot(), http: http)

        let path = try await store.install(.uberApkSigner)
        #expect(path.hasSuffix(".jar"))
    }

    @Test func rejectsAssetWithMismatchedDigestAndInstallsNothing() async throws {
        let http = MockHTTP(
            releaseJSON: releaseJSON(tag: "v1", assetName: "apktool_x.jar", digest: "sha256:deadbeef"),
            assetBytes: Data("not-the-signed-bytes".utf8))
        let store = ManagedToolStore(rootDirectory: tempRoot(), http: http)

        await #expect(throws: ManagedToolStore.StoreError.digestMismatch) {
            try await store.install(.apktool)
        }
        #expect(await store.installedVersion(.apktool) == nil)
        #expect(await store.resolve(.apktool) == nil)
    }

    // Not on Windows: the fixture builder shells out to POSIX `tar` to create the archive.
    @Test(.enabled(if: !isWindows)) func installsTarGzAndFindsTheNestedRunnable() async throws {
        // Real .tar.gz fixture, extracted by the real runner — exercises the
        // tar path and the recursive runnable search (Temurin's java is nested).
        let tgz = try Self.makeTarGz(runnableRelPath: "Contents/Home/bin/java")
        // Named for the platform running the test, because the Temurin spec is
        // per-host — the Mac's pattern wants `_mac_` and Linux's wants
        // `_linux_`, and an asset that matched neither would fail here for a
        // reason that has nothing to do with tar.
        #if os(macOS)
        let asset = "OpenJDK21U-jre_aarch64_mac_hotspot_21.0.4_7.tar.gz"
        #else
        let asset = "OpenJDK21U-jre_aarch64_linux_hotspot_21.0.4_7.tar.gz"
        #endif
        let http = MockHTTP(releaseJSON: releaseJSON(tag: "jdk-21.0.4+7", assetName: asset), assetBytes: tgz)
        let store = ManagedToolStore(rootDirectory: tempRoot(), http: http)

        let path = try await store.install(.temurinJre, arch: "aarch64")

        #expect(path.hasSuffix("/bin/java"))
        #expect(FileManager.default.isExecutableFile(atPath: path))
        #expect(await store.resolve(.temurinJre) == path)
    }

    @Test func upgradeAvailableComparesTheInstalledVersionAgainstThePin() async throws {
        let root = tempRoot()
        let pin = try #require(ManagedToolSpec.catalog[.apktool]?.pinnedTag)
        // Not installed → the pin itself is "available", with no network fetch.
        let old = MockHTTP(releaseJSON: releaseJSON(tag: "v2.10.0", assetName: "apktool_2.10.0.jar"), assetBytes: Data("a".utf8))
        let store = ManagedToolStore(rootDirectory: root, http: old)
        #expect(try await store.upgradeAvailable(.apktool) == pin)
        #expect(old.requested.isEmpty)

        // An install older than the pin (from a previous app version) → pin offered.
        _ = try await store.install(.apktool)
        #expect(try await store.upgradeAvailable(.apktool) == pin)

        // At the pin → current.
        let pinned = MockHTTP(releaseJSON: releaseJSON(tag: pin, assetName: "apktool_3.0.2.jar"), assetBytes: Data("b".utf8))
        let upgraded = ManagedToolStore(rootDirectory: root, http: pinned)
        _ = try await upgraded.install(.apktool)
        #expect(await upgraded.installedVersion(.apktool) == pin)
        #expect(try await upgraded.upgradeAvailable(.apktool) == nil)
    }

    // Not on Windows: `.xz` decoding is deliberately unimplemented on Windows (see the follow-up
    // in docs/cross-platform.md), so the store throws rather than extracting.
    @Test(.enabled(if: !isWindows)) func decompressesXzAssetIntoTheRunnableBinary() async throws {
        // frida ships bare .xz; round-trip a payload through the same coder the
        // store decodes with on this platform, then confirm it lands as an
        // executable frida-server.
        let payload = Data("ELF-ish-frida-server-bytes".utf8)
        let xz = try Self.makeXz(payload)
        let http = MockHTTP(
            releaseJSON: releaseJSON(tag: "16.4.0", assetName: "frida-server-16.4.0-android-arm64.xz"),
            assetBytes: xz)
        let store = ManagedToolStore(rootDirectory: tempRoot(), http: http)

        let path = try await store.install(.fridaServer, arch: "arm64")

        #expect(path.hasSuffix("/frida-server"))
        #expect(FileManager.default.contents(atPath: path) == payload)
        #expect(FileManager.default.isExecutableFile(atPath: path))
    }

    /// A bare `.xz` of `payload`, made with the same coder the store decodes
    /// with on this platform (Compression's lzma on Darwin, the xz CLI else).
    private static func makeXz(_ payload: Data) throws -> Data {
        #if canImport(Darwin)
        return try (payload as NSData).compressed(using: .lzma) as Data
        #else
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("xz-src-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let raw = work.appendingPathComponent("payload")
        try FixtureFile.write(payload, to: raw)
        let xz = Process()
        xz.executableURL = URL(fileURLWithPath: "/usr/bin/xz")
        xz.arguments = ["--compress", raw.path]
        try xz.run()
        xz.waitUntilExit()
        return try Data(contentsOf: work.appendingPathComponent("payload.xz"))
        #endif
    }

    /// A real `.tar.gz` containing a single executable at `runnableRelPath`
    /// under a top-level `jdk-21/` dir, mirroring Temurin's layout.
    private static func makeTarGz(runnableRelPath: String) throws -> Data {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("tgz-src-\(UUID().uuidString)")
        let runnable = work.appendingPathComponent("jdk-21").appendingPathComponent(runnableRelPath)
        try fm.createDirectory(at: runnable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FixtureFile.write("#!/bin/sh\necho java\n", to: runnable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnable.path)
        let out = work.appendingPathComponent("out.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", out.path, "-C", work.path, "jdk-21"]
        try tar.run()
        tar.waitUntilExit()
        return try Data(contentsOf: out)
    }
}
