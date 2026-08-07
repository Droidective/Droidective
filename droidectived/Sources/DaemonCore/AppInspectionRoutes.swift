import ADBKit
import Foundation

/// Wire shapes for the per-app screens: App Info, Permissions, Memory Usage
/// and the sandbox browser.
///
/// All four hang off a package id the client already chose in Apps, so every
/// request carries `serial` + `packageId` and nothing else. `manage-app` is not
/// here: its verbs are `AppControlService.AppAction`, which `/v1/apps/control`
/// already serves, and a second route for the same six verbs would be a second
/// list to keep in agreement.
public enum AppInspectionProtocol {
    public struct AppRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let packageId: String

        public init(serial: String, packageId: String) {
            self.serial = serial
            self.packageId = packageId
        }
    }

    // MARK: - App info

    public struct InfoResponse: Codable, Equatable, Sendable {
        public let installed: Bool
        public let versionName: String
        public let versionCode: String
        public let targetSdk: String
        public let minSdk: String
        public let firstInstall: String
        public let lastUpdate: String
        public let apkPath: String?
        public let apkSizeBytes: Int?

        public init(_ info: AppInfo) {
            installed = info.installed
            versionName = info.versionName
            versionCode = info.versionCode
            targetSdk = info.targetSdk
            minSdk = info.minSdk
            firstInstall = info.firstInstall
            lastUpdate = info.lastUpdate
            apkPath = info.apkPath
            apkSizeBytes = info.apkSizeBytes
        }
    }

    // MARK: - Permissions

    public struct Permission: Codable, Equatable, Sendable {
        public let name: String
        /// The trailing component — "CAMERA". Sent rather than derived so both
        /// UIs split a permission name the same way.
        public let shortName: String
        public let granted: Bool

        public init(_ entry: PermissionEntry) {
            name = entry.name
            shortName = entry.shortName
            granted = entry.granted
        }
    }

    public struct PermissionsResponse: Codable, Equatable, Sendable {
        public let permissions: [Permission]
    }

    public struct PermissionWriteRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let packageId: String
        public let permission: String
        public let grant: Bool

        public init(serial: String, packageId: String, permission: String, grant: Bool) {
            self.serial = serial
            self.packageId = packageId
            self.permission = permission
            self.grant = grant
        }
    }

    // MARK: - Memory

    public struct MemInfoResponse: Codable, Equatable, Sendable {
        /// False when the app has no process — a stopped app is an answer, not
        /// an error, and the Mac says so rather than showing zeroes.
        public let running: Bool
        public let totalPssKb: Int?
        /// `dumpsys meminfo`'s summary block, in the order it printed. An array
        /// of pairs rather than a dictionary: the order is the information.
        public let summary: [Row]

        public struct Row: Codable, Equatable, Sendable {
            public let key: String
            public let value: String
        }

        public init(_ info: MemInfo) {
            running = info.running
            totalPssKb = info.totalPssKb
            summary = info.summary.map { Row(key: $0.key, value: $0.value) }
        }
    }

    // MARK: - Sandbox

    public struct SandboxRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let packageId: String
        public let path: String

        public init(serial: String, packageId: String, path: String) {
            self.serial = serial
            self.packageId = packageId
            self.path = path
        }
    }

    public struct SandboxResponse: Codable, Equatable, Sendable {
        /// Echoed back, so a late reply can be told from the current one.
        public let path: String
        public let entries: [FileProtocol.Entry]
        /// False when `run-as` refused — the app is not debuggable. Not an
        /// error: it is the normal answer for a release build, and the Mac
        /// explains it rather than showing a failure.
        public let debuggable: Bool
    }

    /// A pull out of an app's sandbox, or of its APK.
    ///
    /// The destination is decided by the client process, as `/v1/files/pull`'s
    /// is: the daemon does not know where this platform's Downloads folder is,
    /// and it is not the daemon's business to choose one.
    public struct PullRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let packageId: String
        /// The device path, for a sandbox pull. Ignored by the APK pull, which
        /// asks the package manager where the APK is.
        public let path: String?
        public let destination: String

        public init(serial: String, packageId: String, path: String? = nil, destination: String) {
            self.serial = serial
            self.packageId = packageId
            self.path = path
            self.destination = destination
        }
    }

    public struct PullResponse: Codable, Equatable, Sendable {
        /// Where each file landed on this computer. An APK pull can answer
        /// several — an App Bundle install has splits beside the base.
        public let paths: [String]
    }
}

/// The per-app inspection routes.
enum AppInspectionRoutes {
    static func info(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        await app(body: body, failure: "Could not read the app info") { request in
            let info = try await backend.appInfo(
                serial: request.serial, packageId: request.packageId)
            return AppInspectionProtocol.InfoResponse(info)
        }
    }

    static func permissions(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        await app(body: body, failure: "Could not read the permissions") { request in
            let entries = try await backend.permissions(
                serial: request.serial, packageId: request.packageId)
            return AppInspectionProtocol.PermissionsResponse(
                permissions: entries.map(AppInspectionProtocol.Permission.init))
        }
    }

    static func setPermission(body: Data, backend: any DaemonBackend) async
        -> DaemonProtocol.Answer
    {
        guard let request = try? JSONDecoder().decode(
            AppInspectionProtocol.PermissionWriteRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            let result = try await backend.setPermission(
                serial: request.serial, packageId: request.packageId,
                permission: request.permission, grant: request.grant)
            return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(result)))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "Could not change the permission.",
                detail: "\(error)")))
        }
    }

    static func meminfo(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        await app(body: body, failure: "Could not read the memory usage") { request in
            let info = try await backend.meminfo(
                serial: request.serial, packageId: request.packageId)
            return AppInspectionProtocol.MemInfoResponse(info)
        }
    }

    static func sandboxList(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            AppInspectionProtocol.SandboxRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            let listing = try await backend.sandboxList(
                serial: request.serial, packageId: request.packageId, path: request.path)
            return (200, DaemonProtocol.encoded(AppInspectionProtocol.SandboxResponse(
                path: request.path,
                entries: listing.entries.map(FileProtocol.Entry.init),
                debuggable: listing.debuggable)))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "Could not list the sandbox.",
                detail: "\(error)")))
        }
    }

    static func sandboxPull(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            AppInspectionProtocol.PullRequest.self, from: body),
            let path = request.path
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            let landed = try await backend.sandboxPull(
                serial: request.serial, packageId: request.packageId,
                path: path, to: request.destination)
            return (200, DaemonProtocol.encoded(
                AppInspectionProtocol.PullResponse(paths: [landed])))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "pull_failed", message: "Could not pull the file.",
                detail: "\(error)")))
        }
    }

    static func pullApk(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            AppInspectionProtocol.PullRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            let landed = try await backend.pullApk(
                serial: request.serial, packageId: request.packageId, to: request.destination)
            return (200, DaemonProtocol.encoded(AppInspectionProtocol.PullResponse(paths: landed)))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "pull_failed", message: "Could not pull the APK.",
                detail: "\(error)")))
        }
    }

    /// The three reads that take a plain `serial` + `packageId` and differ only
    /// in what they ask the backend for.
    private static func app<Response: Encodable>(
        body: Data, failure: String,
        read: (AppInspectionProtocol.AppRequest) async throws -> Response
    ) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            AppInspectionProtocol.AppRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            return (200, DaemonProtocol.encoded(try await read(request)))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "\(failure).", detail: "\(error)")))
        }
    }
}
