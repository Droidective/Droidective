import ADBKit
import Foundation
import os

/// Single source of truth for the third-party binaries shipped inside the app
/// bundle, so Droidective is self-contained (no separate scrcpy/ffmpeg
/// install needed).
///
/// **Updating a bundled tool** (scalable on purpose): run
/// `scripts/update-bundled-tools.sh`, which downloads the pinned versions into
/// `App/Resources/`, then bump the version constants here if they changed. The
/// resources are forced into the app's resources build phase in `project.yml`,
/// signed by `scripts/package-dmg.sh`, and attributed in `THIRD_PARTY_NOTICES.md`.
/// Lives in the App layer because ADBKit is bundle-free; resolved paths are
/// passed into ADBKit services.
enum BundledTools {
    /// scrcpy-server payload version. MUST match the bundled `scrcpy-server`
    /// binary — `app_process` is launched with it and the server aborts on a
    /// version mismatch. Keep in lockstep with the binary in `App/Resources`.
    static let scrcpyVersion = "4.1"

    private static let scrcpyServerResource = "scrcpy-server"
    private static let ffmpegResource = "ffmpeg"

    /// The bundled scrcpy server (jar path + version), or nil if the resource is
    /// missing from the build.
    static func scrcpyServer() -> ScrcpyServerInfo? {
        guard let url = Bundle.main.url(forResource: scrcpyServerResource, withExtension: nil) else {
            return nil
        }
        return ScrcpyServerInfo(jarPath: url.path, version: scrcpyVersion)
    }

    /// Absolute path to the bundled ffmpeg executable, or nil if it's missing.
    static func ffmpegPath() -> String? {
        Bundle.main.url(forResource: ffmpegResource, withExtension: nil)?.path
    }

    /// Jar releases bundled under versionless names (so upgrades don't touch
    /// project.yml). Keep each in lockstep with the jar in `App/Resources` and
    /// its pin in `ManagedToolSpec.catalog`.
    static let bundletoolVersion = "1.18.3"
    static let uberApkSignerVersion = "v1.3.0"

    /// Copy the bundled tools into the managed-tool store ("factory seed") so
    /// the AAB converter and APK signing work offline out of the box;
    /// Settings ▸ Tools keeps version-tracking and upgrading over the seeded
    /// copies. Idempotent and never downgrades — safe to call at every launch
    /// and before every gate check.
    static func seed(into store: ManagedToolStore) async {
        await seed(.bundletool, resource: "bundletool-all", version: bundletoolVersion, into: store)
        await seed(.uberApkSigner, resource: "uber-apk-signer", version: uberApkSignerVersion, into: store)
    }

    private static func seed(
        _ tool: ManagedTool, resource: String, version: String, into store: ManagedToolStore
    ) async {
        guard let jar = Bundle.main.url(forResource: resource, withExtension: "jar") else {
            log.error("\(resource).jar missing from the app bundle — \(tool.rawValue) falls back to its download gate")
            return
        }
        do {
            try await store.seed(tool, version: version, from: jar)
        } catch {
            // Not fatal: the download gates and Settings ▸ Tools still work.
            log.error("seeding \(tool.rawValue) failed: \(error.localizedDescription)")
        }
    }

    private static let log = Logger(subsystem: "com.rohindh.droidective", category: "bundled-tools")
}
