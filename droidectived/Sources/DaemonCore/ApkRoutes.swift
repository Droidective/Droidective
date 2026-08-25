import ADBKit
import Foundation

/// The wire shapes for the APK tools: inspect, sign, and convert a bundle.
///
/// Three features over one toolchain, so they share a protocol enum — what they
/// have in common is the part that fails, which is a missing tool rather than
/// anything about the file.
public enum ApkProtocol {
    /// Which of the tools these features need are actually on this machine.
    ///
    /// Asked for up front rather than discovered by a failed run: the SDK's
    /// build-tools are detected, not downloadable, so "install the build-tools"
    /// is advice the screen can give before someone picks a file — and after a
    /// failed run it reads as though their APK was the problem.
    public struct Toolchain: Codable, Equatable, Sendable {
        public let aapt2: Bool
        public let apksigner: Bool
        public let zipalign: Bool
        public let java: Bool
        public let bundletool: Bool

        public init(aapt2: Bool, apksigner: Bool, zipalign: Bool, java: Bool, bundletool: Bool) {
            self.aapt2 = aapt2
            self.apksigner = apksigner
            self.zipalign = zipalign
            self.java = java
            self.bundletool = bundletool
        }
    }

    public struct PathRequest: Codable, Equatable, Sendable {
        public let path: String
        public init(path: String) { self.path = path }
    }

    public struct Signer: Codable, Equatable, Sendable {
        public let subjectDN: String?
        public let sha256: String?
        public let sha1: String?

        public init(_ signer: ApkSigner) {
            subjectDN = signer.subjectDN
            sha256 = signer.sha256
            sha1 = signer.sha1
        }
    }

    public struct Report: Codable, Equatable, Sendable {
        public let fileName: String
        public let fileSizeBytes: Int
        public let label: String?
        public let packageName: String?
        public let versionName: String?
        public let versionCode: String?
        public let minSdk: String?
        public let targetSdk: String?
        /// False when aapt2 was missing, so the screen can say *why* it is
        /// showing a name and a size and nothing else.
        public let hasDetails: Bool
        public let permissions: [String]
        public let features: [String]
        public let isDebuggable: Bool
        public let signatureSchemes: [String]
        public let signers: [Signer]

        public init(_ report: ApkReport) {
            fileName = report.info.fileName
            fileSizeBytes = report.info.fileSizeBytes
            label = report.info.label
            packageName = report.info.packageName
            versionName = report.info.versionName
            versionCode = report.info.versionCode
            minSdk = report.info.minSdk
            targetSdk = report.info.targetSdk
            hasDetails = report.info.hasDetails
            permissions = report.permissions
            features = report.features
            isDebuggable = report.isDebuggable
            signatureSchemes = report.signatureSchemes
            signers = report.signers.map(Signer.init)
        }
    }

    /// A keystore, as a client hands one over.
    ///
    /// The password rides the loopback socket in the request body, which is the
    /// same trust boundary the token already establishes. What it must *not* do
    /// is reach a command line: `ApkSigningService` writes it to a 0600 temp
    /// file precisely so it never appears in argv, and that stays true here
    /// because this only hands the value on.
    public struct Keystore: Codable, Equatable, Sendable {
        public let path: String
        public let storePassword: String
        public let keyAlias: String?
        public let keyPassword: String?

        public init(
            path: String, storePassword: String, keyAlias: String? = nil,
            keyPassword: String? = nil
        ) {
            self.path = path
            self.storePassword = storePassword
            self.keyAlias = keyAlias
            self.keyPassword = keyPassword
        }

        public var credentials: KeystoreCredentials {
            KeystoreCredentials(
                keystorePath: path, storePassword: storePassword,
                keyAlias: keyAlias, keyPassword: keyPassword)
        }
    }

    public struct SignRequest: Codable, Equatable, Sendable {
        public let input: String
        public let output: String
        public let keystore: Keystore

        public init(input: String, output: String, keystore: Keystore) {
            self.input = input
            self.output = output
            self.keystore = keystore
        }
    }

    public struct SignResponse: Codable, Equatable, Sendable {
        public let ok: Bool
        public let message: String
        public let output: String?

        public init(ok: Bool, message: String, output: String?) {
            self.ok = ok
            self.message = message
            self.output = output
        }
    }

    public struct ConvertRequest: Codable, Equatable, Sendable {
        public let input: String
        /// Where the universal APK should land.
        public let outputDirectory: String
        /// Absent leaves bundletool's own debug key, which is what the Mac's
        /// screen does until someone chooses a keystore.
        public let keystore: Keystore?

        public init(input: String, outputDirectory: String, keystore: Keystore? = nil) {
            self.input = input
            self.outputDirectory = outputDirectory
            self.keystore = keystore
        }
    }

    public struct ConvertResponse: Codable, Equatable, Sendable {
        public let path: String
        public let sizeBytes: Int64

        public init(path: String, sizeBytes: Int64) {
            self.path = path
            self.sizeBytes = sizeBytes
        }
    }

    static let badRequest = DaemonProtocol.ErrorBody(
        code: "bad_request", message: "That is not an APK request.", detail: nil)

    static func toolMissing(_ detail: String) -> DaemonProtocol.ErrorBody {
        DaemonProtocol.ErrorBody(
            code: "tool_missing",
            message: "A tool this needs is not installed.", detail: detail)
    }
}

/// The four APK routes, behind three features.
enum ApkRoutes {
    static func toolchain(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        (200, DaemonProtocol.encoded(await backend.apkToolchain()))
    }

    static func inspect(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard
            let request = try? JSONDecoder().decode(ApkProtocol.PathRequest.self, from: body),
            !request.path.isEmpty
        else { return (400, DaemonProtocol.encoded(ApkProtocol.badRequest)) }
        let report = await backend.inspectApk(path: request.path)
        return (200, DaemonProtocol.encoded(ApkProtocol.Report(report)))
    }

    static func sign(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard
            let request = try? JSONDecoder().decode(ApkProtocol.SignRequest.self, from: body),
            !request.input.isEmpty, !request.output.isEmpty, !request.keystore.path.isEmpty
        else { return (400, DaemonProtocol.encoded(ApkProtocol.badRequest)) }
        do {
            let result = try await backend.signApk(request)
            return (200, DaemonProtocol.encoded(result))
        } catch {
            // The toolchain's own words. "apksigner was not found" and "the
            // keystore password is wrong" want different things done about
            // them, and only the first is worth a link to the build-tools.
            return (422, DaemonProtocol.encoded(ApkProtocol.toolMissing("\(error)")))
        }
    }

    static func convert(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard
            let request = try? JSONDecoder().decode(ApkProtocol.ConvertRequest.self, from: body),
            !request.input.isEmpty, !request.outputDirectory.isEmpty
        else { return (400, DaemonProtocol.encoded(ApkProtocol.badRequest)) }
        do {
            let converted = try await backend.convertAab(request)
            return (200, DaemonProtocol.encoded(converted))
        } catch {
            return (422, DaemonProtocol.encoded(ApkProtocol.toolMissing("\(error)")))
        }
    }
}
