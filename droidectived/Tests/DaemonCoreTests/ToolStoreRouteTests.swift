import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// Settings ▸ Tools — the managed-tool store over the wire.
///
/// The rule worth guarding is which tools a host offers at all: the catalogue
/// is per-platform, so a client must not be able to ask this machine for a
/// download it has no asset for. The rest is that a failed download is the
/// download failing rather than the daemon breaking, and says which.
@Suite struct ToolStoreRouteTests {
    private struct Refusal: Error, CustomStringConvertible {
        let description = "GitHub said no"
    }

    private actor Installed {
        private(set) var installs: [ManagedTool] = []
        private(set) var removals: [ManagedTool] = []
        func install(_ tool: ManagedTool) { installs.append(tool) }
        func remove(_ tool: ManagedTool) { removals.append(tool) }
    }

    private struct StubBackend: DaemonBackend {
        var log = Installed()
        var failure: (any Error)?
        var entries: [ToolStoreProtocol.Entry] = []

        func managedToolEntries() async -> [ToolStoreProtocol.Entry] { entries }

        func installManagedTool(_ tool: ManagedTool) async throws -> String {
            if let failure { throw failure }
            await log.install(tool)
            return "/tmp/\(tool.rawValue)"
        }

        func removeManagedTool(_ tool: ManagedTool) async throws {
            if let failure { throw failure }
            await log.remove(tool)
        }
    }

    private func decode<T: Decodable>(_ answer: DaemonProtocol.Answer, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: answer.body)
    }

    private func encoded(_ value: some Encodable) throws -> Data {
        try DaemonProtocol.encode(value)
    }

    private func entry(
        _ id: String, installed: Bool = true, version: String? = "v1", pinned: String = "v1"
    ) -> ToolStoreProtocol.Entry {
        ToolStoreProtocol.Entry(
            id: id, installed: installed, version: version,
            pinnedVersion: pinned, sizeBytes: 1_024)
    }

    // MARK: - The entry itself

    /// "Upgradable" is the pin having moved past what is on disk — not simply
    /// "not installed", which is a different offer with a different button.
    @Test func anEntryIsUpgradableOnlyWhenThePinHasMovedPastIt() {
        #expect(!entry("jadx", version: "v1", pinned: "v1").upgradable)
        #expect(entry("jadx", version: "v1", pinned: "v2").upgradable)
        #expect(!entry("jadx", installed: false, version: nil, pinned: "v2").upgradable)
    }

    // MARK: - Routes

    @Test func listAnswersWhatTheHostCanFetch() async throws {
        let backend = StubBackend(entries: [entry("apktool"), entry("jadx")])
        let answer = await ToolStoreRoutes.list(backend: backend)
        #expect(answer.status == 200)

        let body = try decode(answer, as: ToolStoreProtocol.ListResponse.self)
        #expect(body.tools.map(\.id) == ["apktool", "jadx"])
        #expect(body.tools.first?.sizeBytes == 1_024)
    }

    @Test func installFetchesTheNamedToolAndAnswersTheNewList() async throws {
        let backend = StubBackend(entries: [entry("jadx")])
        let answer = await ToolStoreRoutes.install(
            body: try encoded(ToolStoreProtocol.ToolRequest(id: "jadx")), backend: backend)
        #expect(answer.status == 200)
        #expect(await backend.log.installs == [.jadx])
        // The answer is the whole list, so a screen never has to guess what
        // changed — it adopts what the daemon now says is on disk.
        _ = try decode(answer, as: ToolStoreProtocol.ListResponse.self)
    }

    @Test func removeDeletesTheNamedTool() async throws {
        let backend = StubBackend()
        let answer = await ToolStoreRoutes.remove(
            body: try encoded(ToolStoreProtocol.ToolRequest(id: "apktool")), backend: backend)
        #expect(answer.status == 200)
        #expect(await backend.log.removals == [.apktool])
    }

    @Test func anIdThatIsNotAToolAtAllIsRefused() async throws {
        for body in [
            try encoded(ToolStoreProtocol.ToolRequest(id: "definitely-not-a-tool")),
            Data("{}".utf8),
        ] {
            #expect(await ToolStoreRoutes.install(body: body, backend: StubBackend()).status == 400)
            #expect(await ToolStoreRoutes.remove(body: body, backend: StubBackend()).status == 400)
        }
    }

    /// The catalogue is per-platform, so a real tool this host has no asset for
    /// is a 404 — nothing was attempted, and telling someone the download
    /// failed would send them looking for a network problem.
    @Test func aToolThisHostCannotFetchIsNotFound() async throws {
        let absent = ManagedTool.allCases.first { ManagedToolSpec.hostCatalog[$0] == nil }
        guard let absent else {
            // Every tool is fetchable here (Linux and Windows), so there is no
            // case to exercise — and that is itself the correct state.
            return
        }
        let answer = await ToolStoreRoutes.install(
            body: try encoded(ToolStoreProtocol.ToolRequest(id: absent.rawValue)),
            backend: StubBackend())
        #expect(answer.status == 404)
        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.code == "unknown_tool")
    }

    /// A download that does not finish is GitHub, the network, or a digest
    /// that did not match — the daemon is fine, so it is a 502 carrying the
    /// reason rather than a 500.
    @Test func aFailedDownloadIsABadGatewayWithItsReason() async throws {
        let backend = StubBackend(failure: Refusal())
        let answer = await ToolStoreRoutes.install(
            body: try encoded(ToolStoreProtocol.ToolRequest(id: "jadx")), backend: backend)
        #expect(answer.status == 502)

        let body = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(body.error.code == "download_failed")
        #expect(body.error.detail?.contains("GitHub said no") == true)
    }

    // MARK: - The catalogue itself

    /// macOS bundles ffmpeg, so a downloadable second copy would be another
    /// answer to the same question; Windows and Linux have no bundle, so it has
    /// to be here or screen recording cannot work at all.
    @Test func ffmpegIsOfferedOnlyWhereTheAppDoesNotBundleIt() {
        let spec = ManagedToolSpec.hostCatalog[.ffmpeg]
        #if os(macOS)
        #expect(spec == nil)
        #else
        #expect(spec != nil)
        #expect(spec?.runnableName?.hasPrefix("ffmpeg") == true)
        #endif
    }

    /// Every entry the catalogue offers names a release this build pinned. An
    /// unpinned tool would follow whatever a repository moved to, which is the
    /// thing pinning exists to prevent.
    @Test func everyOfferedToolIsPinnedToATag() {
        for (tool, spec) in ManagedToolSpec.hostCatalog {
            #expect(!spec.pinnedTag.isEmpty, "\(tool.rawValue) has no pinned tag")
            #expect(spec.pinnedReleaseURL != nil, "\(tool.rawValue) has no release URL")
        }
    }

    /// Temurin ships a different archive per platform, and the pattern says so.
    /// Left as `mac` on Windows it would match nothing and the Java runtime the
    /// APK tools need could not be installed at all.
    @Test func theJavaRuntimeAsksForThisPlatformsArchive() throws {
        let spec = try #require(ManagedToolSpec.hostCatalog[.temurinJre])
        #if os(macOS)
        #expect(spec.assetPattern.contains("_mac_"))
        #elseif os(Windows)
        #expect(spec.assetPattern.contains("_windows_"))
        #else
        #expect(spec.assetPattern.contains("_linux_"))
        #endif
    }
}
