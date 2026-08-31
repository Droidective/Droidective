import ADBKit
import Foundation

/// The wire shapes for the managed-tool store — Settings ▸ Tools.
///
/// Deliberately not folded into `/v1/apk/tools`, whose own comment says why:
/// that route exists for the decompiler's two, and a screen that listed the
/// whole catalogue would be a tool manager. This is the tool manager.
///
/// What it lists is `ManagedToolSpec.hostCatalog`, so a host offers exactly
/// what it can actually fetch — ffmpeg appears on Windows and Linux and not on
/// macOS, where the app bundles one.
public enum ToolStoreProtocol {

    public struct Entry: Codable, Equatable, Sendable {
        /// `ManagedTool`'s raw value — the id a client sends back to install.
        public let id: String
        public let installed: Bool
        /// The release tag on disk, when there is one.
        public let version: String?
        /// The pinned tag this build would install. Different from `version`
        /// means an upgrade is available; equal means it is current.
        public let pinnedVersion: String
        public let sizeBytes: Int64

        public init(
            id: String, installed: Bool, version: String?,
            pinnedVersion: String, sizeBytes: Int64
        ) {
            self.id = id
            self.installed = installed
            self.version = version
            self.pinnedVersion = pinnedVersion
            self.sizeBytes = sizeBytes
        }

        /// True when the pin has moved past what is on disk.
        public var upgradable: Bool {
            installed && version != nil && version != pinnedVersion
        }
    }

    public struct ListResponse: Codable, Equatable, Sendable {
        public let tools: [Entry]
        public init(tools: [Entry]) { self.tools = tools }
    }

    public struct ToolRequest: Codable, Equatable, Sendable {
        public let id: String
        public init(id: String) { self.id = id }
    }

    static let badRequest = DaemonProtocol.ErrorBody(
        code: "bad_request", message: "That is not a tool request.", detail: nil)

    /// A tool this *host* cannot fetch is a 404 rather than a failed download:
    /// nothing was attempted, and the catalogue is per-platform.
    static let unknownTool = DaemonProtocol.ErrorBody(
        code: "unknown_tool", message: "This platform has no download for that tool.", detail: nil)
}

/// The three tool-store routes: what is here, fetch one, remove one.
enum ToolStoreRoutes {
    static func list(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        (200, DaemonProtocol.encoded(
            ToolStoreProtocol.ListResponse(tools: await backend.managedToolEntries())))
    }

    static func install(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ToolStoreProtocol.ToolRequest.self, from: body),
            let tool = ManagedTool(rawValue: request.id)
        else { return (400, DaemonProtocol.encoded(ToolStoreProtocol.badRequest)) }
        guard ManagedToolSpec.hostCatalog[tool] != nil else {
            return (404, DaemonProtocol.encoded(ToolStoreProtocol.unknownTool))
        }
        do {
            _ = try await backend.installManagedTool(tool)
            return await list(backend: backend)
        } catch {
            // The network, GitHub, or a digest that did not match. All three are
            // the download failing rather than the daemon breaking, and the
            // message is the one thing that says which.
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "download_failed",
                message: (error as? any LocalizedError)?.errorDescription
                    ?? "The download did not finish.",
                detail: "\(error)")))
        }
    }

    static func remove(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ToolStoreProtocol.ToolRequest.self, from: body),
            let tool = ManagedTool(rawValue: request.id)
        else { return (400, DaemonProtocol.encoded(ToolStoreProtocol.badRequest)) }
        do {
            try await backend.removeManagedTool(tool)
            return await list(backend: backend)
        } catch {
            return (500, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "remove_failed", message: "Couldn't remove that tool.",
                detail: "\(error)")))
        }
    }
}
