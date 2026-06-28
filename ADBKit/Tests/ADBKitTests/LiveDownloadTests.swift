import Foundation
import Testing
@testable import ADBKit

/// Throwaway diagnostic: exercises the REAL download path against GitHub.
/// Gated on LIVE_DL=1 so it never runs in CI.
@Suite struct LiveDownloadTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_DL"] == "1"))
    func downloadsApktoolForReal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString)")
        let store = ManagedToolStore(rootDirectory: root)
        print("LIVE: installing apktool…")
        let path = try await store.install(.apktool) { fraction in
            print("LIVE apktool progress: \(Int(fraction * 100))%")
        }
        print("LIVE apktool installed at: \(path)")
        #expect(path.hasSuffix(".jar"))
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_DL"] == "1"))
    func downloadsJadxForReal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString)")
        let store = ManagedToolStore(rootDirectory: root)
        print("LIVE: installing jadx…")
        let path = try await store.install(.jadx)
        print("LIVE jadx installed at: \(path)")
        #expect(path.hasSuffix("/jadx"))
        #expect(FileManager.default.fileExists(atPath: path))
    }
}
