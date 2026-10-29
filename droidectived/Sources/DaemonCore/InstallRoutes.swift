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
        /// Launch the app on each device it reached — the install screens'
        /// "Open after installing". Absent means no.
        public let opensApp: Bool

        public init(serials: [String], path: String, opensApp: Bool = false) {
            self.serials = serials
            self.path = path
            self.opensApp = opensApp
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            serials = try container.decode([String].self, forKey: .serials)
            path = try container.decode(String.self, forKey: .path)
            opensApp = try container.decodeIfPresent(Bool.self, forKey: .opensApp) ?? false
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
        /// Whether the app was launched afterwards; only ever true when asked.
        public var opened = false
        /// Why it couldn't be launched, when that was asked and the install
        /// landed — no launcher activity, or a package name nobody could read.
        public var openFailure: String?
    }

    /// Which package to describe for the details card.
    public struct DetailsRequest: Codable, Equatable, Sendable {
        public let path: String

        public init(path: String) {
            self.path = path
        }
    }

    /// One package as the details card shows it. Every line arrives worded by
    /// ADBKit's `PackageDetails`, the same text the Mac's card reads, so the
    /// client lays it out rather than restating it.
    public struct Details: Codable, Equatable, Sendable {
        /// `apk`, `apks`, `xapk` or `apkm` — APK Studio takes only the first.
        public let format: String
        public let fileName: String
        public let fileSizeBytes: Int
        public let label: String?
        public let packageName: String?
        public let isDebuggable: Bool
        public let version: String?
        public let requires: String?
        public let targets: String?
        public let contents: String?
        public let nativeCode: String?
        public let launcher: String?
        /// The launcher line is a warning: aapt2 found nothing to open.
        public let hasNoLauncher: Bool
        public let signer: String?
        public let permissions: [String]
        /// Why lines are missing, when they are.
        public let note: String?

        public init(_ details: PackageDetails, hasAapt2: Bool) {
            format = details.format.rawValue
            fileName = details.fileName
            fileSizeBytes = details.fileSizeBytes
            label = details.label
            packageName = details.packageName
            isDebuggable = details.report?.isDebuggable ?? false
            version = details.versionSummary
            requires = details.requiresSummary
            targets = details.targetsSummary
            contents = details.contentsSummary
            nativeCode = details.nativeCodeSummary
            launcher = details.launcherSummary
            hasNoLauncher = details.hasNoLauncher
            signer = details.signerSummary
            permissions = details.permissionNames
            note = details.missingNote(hasAapt2: hasAapt2)
        }
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

    public static let notAPackage = DaemonProtocol.ErrorBody(
        code: "not_a_package",
        message: "That file isn't an APK, APKS, XAPK or APKM.")
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

        // Read alongside the first install, as the Mac does, so opening never
        // waits on aapt2 afterwards.
        let identity: Task<String?, Never>? = request.opensApp
            ? Task { await backend.packageDetails(path: request.path, readsSigning: false)?.packageName }
            : nil
        var outcomes: [InstallProtocol.Outcome] = []
        for serial in request.serials {
            // Sequential, not concurrent: two installs of the same package
            // share an unpack directory and bundletool, and the Mac installs
            // one device at a time for the same reason.
            var outcome = await installOne(request.path, on: serial, backend: backend)
            if outcome.ok, let identity {
                let opened = await open(await identity.value, on: serial, backend: backend)
                outcome.opened = opened.ok
                outcome.openFailure = opened.ok ? nil : opened.message
            }
            outcomes.append(outcome)
        }
        return (200, DaemonProtocol.encoded(InstallProtocol.Response(
            outcomes: outcomes,
            fileName: URL(fileURLWithPath: request.path).lastPathComponent)))
    }

    /// What the details card shows. A file that isn't an installable format
    /// is a 400; one that is but can't be read is still a 200 with thinner
    /// details and a note saying why — the Mac's card behaves the same.
    static func details(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(InstallProtocol.DetailsRequest.self, from: body),
              !request.path.isEmpty
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        guard let details = await backend.packageDetails(path: request.path, readsSigning: true) else {
            return (400, DaemonProtocol.encoded(InstallProtocol.notAPackage))
        }
        return (200, DaemonProtocol.encoded(InstallProtocol.Details(
            details, hasAapt2: await backend.hasAapt2())))
    }

    private static func installOne(
        _ path: String, on serial: String, backend: any DaemonBackend
    ) async -> InstallProtocol.Outcome {
        do {
            let result = try await backend.installPackage(path: path, serial: serial)
            return InstallProtocol.Outcome(serial: serial, ok: result.ok, message: result.message)
        } catch {
            // A bundle that cannot be processed at all — unknown format, a
            // corrupt archive, no matching ABI, bundletool missing. Those
            // carry their own explanations, so the text travels rather
            // than being flattened into "install failed".
            return InstallProtocol.Outcome(serial: serial, ok: false, message: describe(error))
        }
    }

    private static func open(
        _ packageID: String?, on serial: String, backend: any DaemonBackend
    ) async -> FeatureResult {
        guard let packageID else {
            return FeatureResult(ok: false, message: PackageDetails.unreadableNameForOpening)
        }
        do {
            return try await backend.controlApp(serial: serial, packageId: packageID, action: .open)
        } catch {
            return FeatureResult(ok: false, message: "Couldn't open it — \(describe(error))")
        }
    }

    /// `BundleError` writes a sentence worth showing; anything else does not.
    private static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
