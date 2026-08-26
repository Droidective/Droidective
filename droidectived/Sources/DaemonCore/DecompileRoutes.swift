import ADBKit
import Foundation

/// The wire shapes for APK Decompile — jadx or apktool over one APK, then
/// reading and searching what they wrote.
///
/// Three of these routes take a path *from the client*, and that is the whole
/// security question here. The daemon runs as the developer, so a path it
/// accepts unchecked is an arbitrary read of their disk over a loopback socket.
/// The decompile output root is the only place these three may look, and
/// `confined(to:)` is what says so — a check on the resolved path, not the one
/// that arrived, because `..` is what a caller would reach for.
public enum DecompileProtocol {
    /// Which decompiler to run. Mirrors `DecompileService.Mode` rather than
    /// re-spelling it, so a mode added there fails to decode here instead of
    /// silently meaning something else.
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case jadx
        case apktool

        var service: DecompileService.Mode {
            switch self {
            case .jadx: .jadx
            case .apktool: .apktool
            }
        }
    }

    public struct Request: Codable, Equatable, Sendable {
        public let path: String
        public let mode: Mode
        /// A previous run of the same APK and mode is reused by default — the
        /// output is deterministic and jadx is slow. The screen's Re-run passes
        /// false.
        public let refresh: Bool?

        public init(path: String, mode: Mode, refresh: Bool? = nil) {
            self.path = path
            self.mode = mode
            self.refresh = refresh
        }
    }

    /// One entry in the decompiled tree.
    ///
    /// `children` is absent for a file and present (possibly empty) for a
    /// directory, which is how `FileNode` distinguishes them — an empty
    /// directory is a directory, and flattening that to a file would put a
    /// disclosure triangle on the wrong rows.
    public struct Node: Codable, Equatable, Sendable {
        public let name: String
        public let path: String
        public let children: [Node]?

        public init(_ node: FileNode) {
            name = node.name
            path = node.path
            children = node.children?.map(Node.init)
        }
    }

    public struct Tree: Codable, Equatable, Sendable {
        /// The output directory, which every later read and search is confined
        /// to. The client passes it back rather than the daemon remembering it:
        /// two panes can hold two different decompiles at once.
        public let root: String
        public let tree: Node

        public init(root: String, tree: Node) {
            self.root = root
            self.tree = tree
        }
    }

    public struct FileRequest: Codable, Equatable, Sendable {
        public let root: String
        public let path: String

        public init(root: String, path: String) {
            self.root = root
            self.path = path
        }
    }

    /// One decompiled file's text.
    ///
    /// Capped: jadx writes the odd multi-megabyte class, and a viewer that has
    /// to hold one is a viewer that stops responding. `truncated` is what lets
    /// the screen say so rather than showing a file that quietly stops.
    public struct FileText: Codable, Equatable, Sendable {
        public let text: String
        public let truncated: Bool
        public let byteCount: Int

        public init(text: String, truncated: Bool, byteCount: Int) {
            self.text = text
            self.truncated = truncated
            self.byteCount = byteCount
        }
    }

    public struct SearchRequest: Codable, Equatable, Sendable {
        public let root: String
        public let query: String

        public init(root: String, query: String) {
            self.root = root
            self.query = query
        }
    }

    public struct Hit: Codable, Equatable, Sendable {
        public let path: String
        public let line: Int
        public let text: String

        public init(_ hit: DecompileService.SearchHit) {
            path = hit.path
            line = hit.line
            text = hit.text
        }
    }

    public struct Hits: Codable, Equatable, Sendable {
        public let hits: [Hit]
        /// True when the cap was reached, so the screen can say the list is
        /// partial rather than implying the search found exactly this many.
        public let capped: Bool

        public init(hits: [Hit], capped: Bool) {
            self.hits = hits
            self.capped = capped
        }
    }

    public struct RebuildRequest: Codable, Equatable, Sendable {
        public let root: String
        public let sourceDir: String
        public let output: String

        public init(root: String, sourceDir: String, output: String) {
            self.root = root
            self.sourceDir = sourceDir
            self.output = output
        }
    }

    public struct RebuildResponse: Codable, Equatable, Sendable {
        public let output: String

        public init(output: String) { self.output = output }
    }

    /// The most a single file may return, and the most hits a search may.
    static let maxFileBytes = 4 << 20
    static let maxHits = 500

    static let badRequest = DaemonProtocol.ErrorBody(
        code: "bad_request", message: "That is not a decompile request.", detail: nil)

    static let outsideRoot = DaemonProtocol.ErrorBody(
        code: "outside_root",
        message: "That path is not inside the decompiled output.",
        detail: "Reads and searches are confined to the directory the decompile produced.")

    /// Whether `path` really sits inside `root`.
    ///
    /// Both sides are resolved first, because the question is about the file
    /// this would open and not about the string that arrived: `root/../../etc`
    /// is inside `root` by prefix and nowhere near it on disk. Compared as path
    /// components rather than characters, so a sibling named `output-evil` is
    /// not read as being inside `output`.
    static func confined(_ path: String, to root: String) -> Bool {
        let rootParts = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath()
            .pathComponents
        let pathParts = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            .pathComponents
        guard pathParts.count >= rootParts.count else { return false }
        return Array(pathParts.prefix(rootParts.count)) == rootParts
    }

    /// Whether `root` is one of the daemon's own decompile output directories.
    ///
    /// The client hands the root back on every call, so trusting it would make
    /// the confinement check circular — a caller naming `/` as the root would
    /// pass. It has to be under the cache directory the decompiler writes to.
    static func isOutputRoot(_ root: String, cache: URL) -> Bool {
        confined(root, to: cache.path)
    }

    static func failure(_ error: any Error) -> DaemonProtocol.ErrorBody {
        let detail = "\(error)"
        if case DecompileService.DecompileError.toolMissing = error {
            return DaemonProtocol.ErrorBody(
                code: "tool_missing",
                message: "A tool this needs is not installed.", detail: detail)
        }
        return DaemonProtocol.ErrorBody(
            code: "tool_failed", message: "The decompiler could not finish.", detail: detail)
    }
}

/// The four decompile routes, behind one feature.
enum DecompileRoutes {
    static func run(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard
            let request = try? JSONDecoder().decode(DecompileProtocol.Request.self, from: body),
            !request.path.isEmpty
        else { return (400, DaemonProtocol.encoded(DecompileProtocol.badRequest)) }
        do {
            return (200, DaemonProtocol.encoded(try await backend.decompileApk(request)))
        } catch {
            return (422, DaemonProtocol.encoded(DecompileProtocol.failure(error)))
        }
    }

    static func file(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard
            let request = try? JSONDecoder().decode(DecompileProtocol.FileRequest.self, from: body),
            !request.path.isEmpty, !request.root.isEmpty
        else { return (400, DaemonProtocol.encoded(DecompileProtocol.badRequest)) }
        guard let text = await backend.decompiledFile(request) else {
            return (403, DaemonProtocol.encoded(DecompileProtocol.outsideRoot))
        }
        return (200, DaemonProtocol.encoded(text))
    }

    static func search(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard
            let request = try? JSONDecoder().decode(
                DecompileProtocol.SearchRequest.self, from: body),
            !request.root.isEmpty
        else { return (400, DaemonProtocol.encoded(DecompileProtocol.badRequest)) }
        guard let hits = await backend.searchDecompiled(request) else {
            return (403, DaemonProtocol.encoded(DecompileProtocol.outsideRoot))
        }
        return (200, DaemonProtocol.encoded(hits))
    }

    static func rebuild(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard
            let request = try? JSONDecoder().decode(
                DecompileProtocol.RebuildRequest.self, from: body),
            !request.sourceDir.isEmpty, !request.output.isEmpty, !request.root.isEmpty
        else { return (400, DaemonProtocol.encoded(DecompileProtocol.badRequest)) }
        do {
            guard let rebuilt = try await backend.rebuildDecompiled(request) else {
                return (403, DaemonProtocol.encoded(DecompileProtocol.outsideRoot))
            }
            return (200, DaemonProtocol.encoded(rebuilt))
        } catch {
            return (422, DaemonProtocol.encoded(DecompileProtocol.failure(error)))
        }
    }
}
