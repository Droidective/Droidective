import Foundation

public enum AppPaths {
    /// ~/Library/Application Support/Droidective
    public static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Droidective", isDirectory: true)
    }

    /// ~/Library/Caches/Droidective/decompiled — jadx/apktool output. Throwaway:
    /// regenerable from the APK, reused within a run, and cleared on quit (kept
    /// out of Application Support so it never competes with the durable tools).
    public static var decompiledCacheDir: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Droidective/decompiled", isDirectory: true)
    }
}

/// One JSON file holding one Codable value, cached in memory and written
/// atomically. The durable-data analog of the reference's `DataStore<T>`.
public actor JSONStore<T: Codable & Sendable> {
    private let fileURL: URL
    private let defaultValue: T
    private var cached: T?

    public init(filename: String, default defaultValue: T, directory: URL = AppPaths.supportDir) {
        self.fileURL = directory.appendingPathComponent(filename)
        self.defaultValue = defaultValue
    }

    public func load() -> T {
        if let cached { return cached }
        let loaded: T
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(T.self, from: data) {
                loaded = decoded
            } else {
                // The file exists but doesn't decode — set it aside instead
                // of letting the next save() overwrite the user's data.
                let backup = fileURL.appendingPathExtension("corrupt")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: fileURL, to: backup)
                loaded = defaultValue
            }
        } else {
            loaded = defaultValue
        }
        cached = loaded
        return loaded
    }

    public func save(_ value: T) async throws {
        // Cache only after the write succeeds — a throwing write must not leave
        // the in-memory cache holding a value that never reached disk, or a
        // later load() would return unpersisted data.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // Both branches finish by renaming a temp file over `fileURL`, and on
        // Windows a scanner holding either end fails that rename with a sharing
        // violation — the same one `FileRetry` was added for. What is lost here
        // is a user's layout or prefs, so it retries rather than surfacing.
        try await FileRetry.run {
            #if canImport(Darwin)
            let tempURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent(".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)")
            try data.write(to: tempURL)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            #else
            // corelibs Foundation doesn't implement replaceItemAt; its `.atomic`
            // write is the same temp-file-then-rename(2) dance.
            try data.write(to: fileURL, options: .atomic)
            #endif
        }
        cached = value
    }

    @discardableResult
    public func update(_ mutate: @Sendable (inout T) -> Void) async throws -> T {
        var value = load()
        mutate(&value)
        try await save(value)
        return value
    }
}
