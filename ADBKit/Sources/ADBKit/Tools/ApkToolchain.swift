import Foundation

/// Resolves the tools the APK features need, applying the right source per tool:
/// SDK build-tools are detected (`ToolLocator`), the managed tools are pulled
/// from GitHub releases (`ManagedToolStore`), and `java` prefers a detected JDK
/// but falls back to the managed Temurin JRE when one has been downloaded.
///
/// Returning nil means "not available" — callers surface a point-of-use prompt
/// (e.g. offer to download the runtime) rather than failing silently.
public struct ApkToolchain: Sendable {
    public let locator: ToolLocator
    public let store: ManagedToolStore

    public init(locator: ToolLocator, store: ManagedToolStore) {
        self.locator = locator
        self.store = store
    }

    // SDK build-tools — detected, never downloaded (they ship with the SDK).
    public func aapt2() async -> String? { await locator.aapt2Path() }
    public func apksignerJar() async -> String? { await locator.apksignerJarPath() }
    public func zipalign() async -> String? { await locator.zipalignPath() }

    /// A `java` launcher: a detected system JDK first, otherwise the managed
    /// Temurin JRE — but only if it's already been downloaded. nil → the UI
    /// should prompt the user to download a runtime.
    public func java() async -> String? {
        if let system = await locator.javaPath() { return system }
        return await store.resolve(.temurinJre)
    }

    /// `keytool` for creating signing keystores — it lives beside `java` in the
    /// same `bin/` (both the JDK and the Temurin JRE ship it). nil when no Java
    /// runtime is resolved or keytool is missing.
    public func keytool() async -> String? {
        guard let java = await java() else { return nil }
        let path = URL(fileURLWithPath: java).deletingLastPathComponent()
            .appendingPathComponent("keytool").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    // Managed tools — downloaded from GitHub releases on demand.
    public func jadx() async -> String? { await store.resolve(.jadx) }
    public func apktool() async -> String? { await store.resolve(.apktool) }
    public func uberApkSigner() async -> String? { await store.resolve(.uberApkSigner) }
}
