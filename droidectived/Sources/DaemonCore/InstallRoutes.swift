import ADBKit
import Foundation

/// Wire shapes for installing an app package.
///
/// The path is a **host** path, chosen by the client process through its own
/// file picker — the daemon never browses the filesystem on a caller's behalf.
/// That keeps the boundary where it already is: the daemon drives adb, and
/// deciding which file a person meant is the UI's job.
public enum InstallProtocol {
    public struct Request: Codable, Equatable, Sendable {
        /// One or more devices. The Mac installs on every targeted device when
        /// run-on-all is on, and reports each separately.
        public let serials: [String]
        public let path: String

        public init(serials: [String], path: String) {
            self.serials = serials
            self.path = path
        }
    }

    /// One device's outcome.
    ///
    /// Per device rather than one verdict: installing onto three devices where
    /// one is out of space is a partial success, and collapsing that into a
    /// single ok/failed would hide which one needs attention.
    public struct Outcome: Codable, Equatable, Sendable {
        public let serial: String
        public let ok: Bool
        public let message: String
    }

    public struct Response: Codable, Equatable, Sendable {
        public let outcomes: [Outcome]
        /// The package's own name, for the status line.
        public let fileName: String
    }

    /// Every extension the daemon will install, from `AppPackageFormat` rather
    /// than restated — the same list the Mac's drop filters and open panel
    /// derive from, so the two apps accept exactly the same files.
    public static var fileExtensions: [String] { AppPackageFormat.fileExtensions }

    public struct FormatsResponse: Codable, Equatable, Sendable {
        public let extensions: [String]
    }

    public static let badInstallRequest = DaemonProtocol.ErrorBody(
        code: "bad_install_request",
        message: "Name a package path and at least one device.")
}

/// The install routes.
enum InstallRoutes {
    /// What the client's file picker should filter on.
    ///
    /// Served rather than hardcoded in the UI so a format added to
    /// `AppPackageFormat` is offered by both apps without a second edit — the
    /// same reason the feature registry travels.
    static func formats() -> DaemonProtocol.Answer {
        (200, DaemonProtocol.encoded(InstallProtocol.FormatsResponse(
            extensions: InstallProtocol.fileExtensions)))
    }

    static func install(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(InstallProtocol.Request.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        guard !request.serials.isEmpty, !request.path.isEmpty else {
            return (400, DaemonProtocol.encoded(InstallProtocol.badInstallRequest))
        }

        var outcomes: [InstallProtocol.Outcome] = []
        for serial in request.serials {
            // Sequential, not concurrent: two installs of the same package
            // share an unpack directory and bundletool, and the Mac installs
            // one device at a time for the same reason.
            do {
                let result = try await backend.installPackage(path: request.path, serial: serial)
                outcomes.append(InstallProtocol.Outcome(
                    serial: serial, ok: result.ok, message: result.message))
            } catch {
                // A bundle that cannot be processed at all — unknown format, a
                // corrupt archive, no matching ABI, bundletool missing. Those
                // carry their own explanations, so the text travels rather
                // than being flattened into "install failed".
                outcomes.append(InstallProtocol.Outcome(
                    serial: serial, ok: false, message: describe(error)))
            }
        }
        return (200, DaemonProtocol.encoded(InstallProtocol.Response(
            outcomes: outcomes,
            fileName: URL(fileURLWithPath: request.path).lastPathComponent)))
    }

    /// `BundleError` writes a sentence worth showing; anything else does not.
    private static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
