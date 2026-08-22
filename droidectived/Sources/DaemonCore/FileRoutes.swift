import ADBKit
import Foundation

/// Wire shapes for the device's filesystem.
///
/// Like the app routes, a thin pass-through: `FileExplorerService` owns the
/// commands and — the part that matters — the `shellQuote`ing of every path, so
/// the daemon never assembles a device shell line of its own. That is load
/// bearing here in a way it is not elsewhere in the protocol: this is the first
/// surface that *writes* to a device, and every path on it arrives from a
/// client.
public enum FileProtocol {

    // MARK: - Browsing

    public struct ListRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let path: String
        /// Browse the whole filesystem through `su -c`. Absent means no.
        public let asRoot: Bool?

        public init(serial: String, path: String, asRoot: Bool? = nil) {
            self.serial = serial
            self.path = path
            self.asRoot = asRoot
        }

        public var wantsRoot: Bool { asRoot ?? false }
    }

    /// One directory entry.
    ///
    /// A DTO rather than `FsEntry` itself: that type is not `Codable`, and its
    /// `id` is a computed property that would not survive encoding.
    public struct Entry: Codable, Equatable, Sendable {
        public let name: String
        public let isDir: Bool
        public let size: Int
        /// The `ls -la` mode column — "drwxrwx---".
        public let perms: String

        public init(_ entry: FsEntry) {
            name = entry.name
            isDir = entry.isDir
            size = entry.size
            perms = entry.perms
        }
    }

    public struct ListResponse: Codable, Equatable, Sendable {
        /// Echoed back, so a client that has already navigated on can tell a
        /// late reply from the current one.
        public let path: String
        public let entries: [Entry]

        public init(path: String, entries: [Entry]) {
            self.path = path
            self.entries = entries
        }
    }

    // MARK: - Mutations

    /// What may be done to a path. The client sends the raw value and an
    /// unrecognised one is refused before it reaches the device, exactly as
    /// `/v1/apps/control` refuses an unknown verb.
    public enum OperationKind: String, CaseIterable, Codable, Sendable {
        case makeDirectory
        case delete
        case copy
        case move
    }

    /// A resolved operation. Modelled with associated values so there is no
    /// impossible state to handle downstream: a `copy` with nowhere to copy to
    /// cannot be constructed.
    public enum Operation: Equatable, Sendable {
        case makeDirectory(path: String)
        case delete(path: String)
        case copy(source: String, destination: String)
        case move(source: String, destination: String)
    }

    public struct OperationRequest: Codable, Equatable, Sendable {
        public let serial: String
        /// An `OperationKind` raw value.
        public let op: String
        /// The target — or the source, for copy and move.
        public let path: String
        /// The destination *directory*. Copy and move only.
        public let destination: String?
        public let asRoot: Bool?

        public init(
            serial: String, op: String, path: String, destination: String? = nil,
            asRoot: Bool? = nil
        ) {
            self.serial = serial
            self.op = op
            self.path = path
            self.destination = destination
            self.asRoot = asRoot
        }

        public var wantsRoot: Bool { asRoot ?? false }
        public var kind: OperationKind? { OperationKind(rawValue: op) }

        /// `nil` when copy or move arrived with nowhere to land. Refused rather
        /// than guessed at: guessing would mean picking a directory on someone
        /// else's device.
        public var resolvedOperation: Operation? {
            switch kind {
            case .makeDirectory: return .makeDirectory(path: path)
            case .delete: return .delete(path: path)
            case .copy:
                guard let destination else { return nil }
                return .copy(source: path, destination: destination)
            case .move:
                guard let destination else { return nil }
                return .move(source: path, destination: destination)
            case nil: return nil
            }
        }
    }

    // MARK: - Get Info

    public struct InfoRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let path: String
        public let asRoot: Bool?

        public init(serial: String, path: String, asRoot: Bool? = nil) {
            self.serial = serial
            self.path = path
            self.asRoot = asRoot
        }

        public var wantsRoot: Bool { asRoot ?? false }
    }

    public struct InfoResponse: Codable, Equatable, Sendable {
        public struct Details: Codable, Equatable, Sendable {
            public let type: String
            public let sizeBytes: Int?
            public let owner: String
            public let permissions: String
            public let modified: String
            /// Last metadata change. Android's filesystems do not record a
            /// creation time, so this is the closest thing there is.
            public let changed: String

            public init(_ info: FileExplorerService.FileInfo) {
                type = info.type
                sizeBytes = info.sizeBytes
                owner = info.owner
                permissions = info.permissions
                modified = info.modified
                changed = info.changed
            }
        }

        /// Null when the device could not stat the path. A file that is gone is
        /// an answer, not a fault, so it is a 200 with nothing in it.
        public let info: Details?

        public init(info: Details?) { self.info = info }
    }

    // MARK: - Pull

    /// `destination` is a **host** path, and the client picks it.
    ///
    /// Only the client knows where its own Downloads folder is — it is the
    /// process with the platform's path APIs — so a daemon that guessed would
    /// give a second answer to a question that already has one. Loopback plus
    /// the bearer token is what makes accepting a host path reasonable; the
    /// daemon writes exactly where it is told and nowhere else.
    public struct PullRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let path: String
        public let destination: String
        public let asRoot: Bool?

        public init(serial: String, path: String, destination: String, asRoot: Bool? = nil) {
            self.serial = serial
            self.path = path
            self.destination = destination
            self.asRoot = asRoot
        }

        public var wantsRoot: Bool { asRoot ?? false }
    }

    public struct PullResponse: Codable, Equatable, Sendable {
        /// Where it actually landed, so the client can offer to reveal it.
        public let path: String

        public init(path: String) { self.path = path }
    }

    // MARK: - Refusals

    public static let unknownOperation = DaemonProtocol.ErrorBody(
        code: "unknown_operation",
        message: "No such file operation.",
        detail: "known operations: "
            + OperationKind.allCases.map(\.rawValue).joined(separator: ", "))

    public static let missingDestination = DaemonProtocol.ErrorBody(
        code: "missing_destination",
        message: "copy and move need a destination directory.")
}

/// The four filesystem routes.
///
/// Separate from `DaemonServer` so its `respond` does not grow a fifth of the
/// protocol, and so each of these can be unit-tested without a socket. They
/// deal in `Data` and an HTTP status code rather than NIO types for the same
/// reason.
enum FileRoutes {
    static func list(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = decode(FileProtocol.ListRequest.self, from: body) else {
            return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest))
        }
        do {
            let entries = try await backend.listFiles(
                serial: request.serial, path: request.path, asRoot: request.wantsRoot)
            return (200, DaemonProtocol.encoded(FileProtocol.ListResponse(
                path: request.path, entries: entries.map(FileProtocol.Entry.init))))
        } catch {
            return adbRefused("Could not read that folder.", error)
        }
    }

    static func operation(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = decode(FileProtocol.OperationRequest.self, from: body) else {
            return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest))
        }
        guard request.kind != nil else {
            return (400, DaemonProtocol.encoded(FileProtocol.unknownOperation))
        }
        guard let operation = request.resolvedOperation else {
            return (400, DaemonProtocol.encoded(FileProtocol.missingDestination))
        }
        do {
            let result = try await backend.fileOperation(
                serial: request.serial, operation, asRoot: request.wantsRoot)
            // A refusal from the device is a *successful* request: 200 with
            // ok=false, the same split `/v1/actions/run` keeps.
            return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(result)))
        } catch {
            return adbRefused("The file operation failed.", error)
        }
    }

    static func info(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = decode(FileProtocol.InfoRequest.self, from: body) else {
            return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest))
        }
        do {
            let details = try await backend.fileInfo(
                serial: request.serial, path: request.path, asRoot: request.wantsRoot)
            return (200, DaemonProtocol.encoded(FileProtocol.InfoResponse(
                info: details.map(FileProtocol.InfoResponse.Details.init))))
        } catch {
            return adbRefused("Could not read that file's details.", error)
        }
    }

    static func pull(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = decode(FileProtocol.PullRequest.self, from: body) else {
            return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest))
        }
        do {
            let landed = try await backend.pullFile(
                serial: request.serial, path: request.path,
                to: request.destination, asRoot: request.wantsRoot)
            return (200, DaemonProtocol.encoded(FileProtocol.PullResponse(path: landed)))
        } catch {
            return adbRefused("Could not pull that file.", error)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from body: Data) -> T? {
        try? JSONDecoder().decode(type, from: body)
    }

    /// adb's answer, not a daemon fault — the 502 every other route uses,
    /// carrying adb's own words.
    private static func adbRefused(_ message: String, _ error: some Error) -> DaemonProtocol.Answer {
        (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
            code: "adb_failed", message: message, detail: "\(error)")))
    }
}
