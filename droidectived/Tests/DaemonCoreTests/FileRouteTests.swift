import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The filesystem routes without a socket.
///
/// `DaemonServerTests` proves they are wired into NIO; this suite is about what
/// they decide — which verbs reach the device, which are refused before they
/// get there, and whether `asRoot` survives the wire. Those are the answers
/// that matter on the one surface of this protocol that *writes* to a device.
@Suite struct FileRouteTests {

    /// What the backend was actually asked to do.
    private actor CallLog {
        private(set) var operations: [FileProtocol.Operation] = []
        private(set) var rootFlags: [Bool] = []
        private(set) var listedPaths: [String] = []

        func record(_ operation: FileProtocol.Operation, asRoot: Bool) {
            operations.append(operation)
            rootFlags.append(asRoot)
        }

        func recordList(_ path: String, asRoot: Bool) {
            listedPaths.append(path)
            rootFlags.append(asRoot)
        }
    }

    private struct Refusal: Error, CustomStringConvertible {
        let description: String
    }

    private struct RecordingBackend: DaemonBackend {
        let log: CallLog
        /// When set, every filesystem call throws it — the "adb said no" path.
        var refusal: Refusal?
        var info: FileExplorerService.FileInfo?

        func listDevices() async -> [Device] { [] }

        func runAction(
            featureID: String, serial: String, platform: DevicePlatform,
            params: [String: FeatureValue]
        ) async -> FeatureResult {
            FeatureResult(ok: true, message: "stub")
        }

        func listApps(serial: String) async throws -> [AppListing] { [] }

        func controlApp(
            serial: String, packageId: String, action: AppControlService.AppAction
        ) async throws -> FeatureResult {
            FeatureResult(ok: true, message: "stub")
        }

        func deviceProperties(serial: String) async throws -> [String: String] { [:] }

        func rootStatus(serial: String) async -> RootStatus {
            RootStatus(hasRootShell: false, likelyRooted: false, summary: "stub", signals: [])
        }

        func listFiles(serial: String, path: String, asRoot: Bool) async throws -> [FsEntry] {
            if let refusal { throw refusal }
            await log.recordList(path, asRoot: asRoot)
            return [FsEntry(name: "note.txt", isDir: false, size: 12, perms: "-rw-rw----")]
        }

        func fileOperation(
            serial: String, _ operation: FileProtocol.Operation, asRoot: Bool
        ) async throws -> FeatureResult {
            if let refusal { throw refusal }
            await log.record(operation, asRoot: asRoot)
            return FeatureResult(ok: true, message: "done")
        }

        func fileInfo(
            serial: String, path: String, asRoot: Bool
        ) async throws -> FileExplorerService.FileInfo? {
            if let refusal { throw refusal }
            return info
        }

        func pullFile(
            serial: String, path: String, to destination: String, asRoot: Bool
        ) async throws -> String {
            if let refusal { throw refusal }
            return destination
        }
    }

    private func backend(
        refusal: Refusal? = nil, info: FileExplorerService.FileInfo? = nil
    ) -> (RecordingBackend, CallLog) {
        let log = CallLog()
        return (RecordingBackend(log: log, refusal: refusal, info: info), log)
    }

    private func json(_ body: String) -> Data { Data(body.utf8) }

    private func errorCode(_ body: Data) throws -> String {
        try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: body).error.code
    }

    // MARK: - Resolving an operation

    @Test func everyKnownVerbResolvesToAnOperation() throws {
        // The registry-invariant shape: a verb added to the enum but never
        // resolved would be accepted by the route and then do nothing.
        for kind in FileProtocol.OperationKind.allCases {
            let request = FileProtocol.OperationRequest(
                serial: "S1", op: kind.rawValue, path: "/sdcard/a", destination: "/sdcard/b")
            #expect(
                request.resolvedOperation != nil,
                "\(kind.rawValue) is in the enum but resolves to nothing")
        }
    }

    @Test func copyAndMoveCarrySourceAndDestinationSeparately() throws {
        let copy = FileProtocol.OperationRequest(
            serial: "S1", op: "copy", path: "/sdcard/a", destination: "/sdcard/b")
        #expect(copy.resolvedOperation == .copy(source: "/sdcard/a", destination: "/sdcard/b"))

        let move = FileProtocol.OperationRequest(
            serial: "S1", op: "move", path: "/sdcard/a", destination: "/sdcard/b")
        #expect(move.resolvedOperation == .move(source: "/sdcard/a", destination: "/sdcard/b"))

        let remove = FileProtocol.OperationRequest(serial: "S1", op: "delete", path: "/sdcard/a")
        #expect(remove.resolvedOperation == .delete(path: "/sdcard/a"))
    }

    // MARK: - What never reaches the device

    @Test func anUnknownVerbIsRefusedBeforeItReachesTheDevice() async throws {
        let (stub, log) = backend()
        let answer = await FileRoutes.operation(
            body: json(#"{"serial":"S1","op":"chmod","path":"/sdcard/a"}"#), backend: stub)
        #expect(answer.status == 400)
        #expect(try errorCode(answer.body) == "unknown_operation")
        #expect(await log.operations.isEmpty)
    }

    @Test func copyWithNowhereToLandIsRefusedRatherThanGuessedAt() async throws {
        let (stub, log) = backend()
        let answer = await FileRoutes.operation(
            body: json(#"{"serial":"S1","op":"copy","path":"/sdcard/a"}"#), backend: stub)
        #expect(answer.status == 400)
        #expect(try errorCode(answer.body) == "missing_destination")
        #expect(await log.operations.isEmpty)
    }

    @Test func aBodyTheRouteCannotReadIsABadRequest() async throws {
        let (stub, _) = backend()
        for answer in await [
            FileRoutes.list(body: json("not json"), backend: stub),
            FileRoutes.operation(body: json("not json"), backend: stub),
            FileRoutes.info(body: json("not json"), backend: stub),
            FileRoutes.pull(body: json("not json"), backend: stub),
        ] {
            #expect(answer.status == 400)
            #expect(try errorCode(answer.body) == "bad_request")
        }
    }

    @Test func aPullWithNoDestinationIsRefused() async throws {
        // `destination` is not optional: a daemon that filled one in would be
        // deciding where someone else's files go.
        let (stub, _) = backend()
        let answer = await FileRoutes.pull(
            body: json(#"{"serial":"S1","path":"/sdcard/a"}"#), backend: stub)
        #expect(answer.status == 400)
    }

    // MARK: - What does reach it

    @Test func aMakeDirectoryReachesTheBackendVerbatim() async throws {
        let (stub, log) = backend()
        let answer = await FileRoutes.operation(
            body: json(#"{"serial":"S1","op":"makeDirectory","path":"/sdcard/a b;c"}"#),
            backend: stub)
        #expect(answer.status == 200)
        // Verbatim on purpose: quoting is `FileExplorerService`'s job and the
        // daemon must not pre-mangle a path that is about to be quoted.
        #expect(await log.operations == [.makeDirectory(path: "/sdcard/a b;c")])
    }

    @Test func asRootSurvivesTheWire() async throws {
        // Absent means no, and a client that means it has to say so — a root
        // flag lost in transit browses the wrong filesystem silently.
        let (stub, log) = backend()
        _ = await FileRoutes.operation(
            body: json(#"{"serial":"S1","op":"delete","path":"/data/x","asRoot":true}"#),
            backend: stub)
        _ = await FileRoutes.list(
            body: json(#"{"serial":"S1","path":"/data"}"#), backend: stub)
        #expect(await log.rootFlags == [true, false])
    }

    @Test func aDeviceRefusalIsA502CarryingAdbsOwnWords() async throws {
        let (stub, _) = backend(refusal: Refusal(description: "adb: device offline"))
        let answer = await FileRoutes.list(
            body: json(#"{"serial":"S1","path":"/sdcard"}"#), backend: stub)
        #expect(answer.status == 502)
        let decoded = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: answer.body)
        #expect(decoded.error.code == "adb_failed")
        #expect(decoded.error.detail?.contains("device offline") == true)
    }

    @Test func aFailedOperationIsA200WithOkFalse() async throws {
        // The protocol's sharpest edge, kept here too: the device saying no is
        // an answer, not a transport fault.
        let log = CallLog()
        let stub = FailingOperationBackend(log: log)
        let answer = await FileRoutes.operation(
            body: json(#"{"serial":"S1","op":"delete","path":"/sdcard/a"}"#), backend: stub)
        #expect(answer.status == 200)
        let decoded = try JSONDecoder().decode(ActionProtocol.RunResponse.self, from: answer.body)
        #expect(!decoded.ok)
        #expect(decoded.message == "Permission denied")
    }

    @Test func aPathTheDeviceCannotStatIsNullNotAnError() async throws {
        let (stub, _) = backend()
        let answer = await FileRoutes.info(
            body: json(#"{"serial":"S1","path":"/sdcard/gone"}"#), backend: stub)
        #expect(answer.status == 200)
        let decoded = try JSONDecoder().decode(FileProtocol.InfoResponse.self, from: answer.body)
        #expect(decoded.info == nil)
    }

    @Test func statDetailsSurviveTheWire() async throws {
        let (stub, _) = backend(info: FileExplorerService.FileInfo(
            type: "Regular file", sizeBytes: 12, owner: "u0_a123", permissions: "-rw-rw----",
            modified: "2026-06-12 18:03:11 +0530", changed: "2026-06-12 18:03:11 +0530"))
        let answer = await FileRoutes.info(
            body: json(#"{"serial":"S1","path":"/sdcard/note.txt"}"#), backend: stub)
        let decoded = try JSONDecoder().decode(FileProtocol.InfoResponse.self, from: answer.body)
        #expect(decoded.info?.owner == "u0_a123")
        #expect(decoded.info?.sizeBytes == 12)
        #expect(decoded.info?.permissions == "-rw-rw----")
    }

    /// Answers a refusal the way the device does — a zero-exit `FeatureResult`
    /// with `ok: false` — rather than throwing.
    private struct FailingOperationBackend: DaemonBackend {
        let log: CallLog

        func listDevices() async -> [Device] { [] }
        func runAction(
            featureID: String, serial: String, platform: DevicePlatform,
            params: [String: FeatureValue]
        ) async -> FeatureResult { FeatureResult(ok: true, message: "stub") }
        func listApps(serial: String) async throws -> [AppListing] { [] }
        func controlApp(
            serial: String, packageId: String, action: AppControlService.AppAction
        ) async throws -> FeatureResult { FeatureResult(ok: true, message: "stub") }
        func deviceProperties(serial: String) async throws -> [String: String] { [:] }
        func rootStatus(serial: String) async -> RootStatus {
            RootStatus(hasRootShell: false, likelyRooted: false, summary: "stub", signals: [])
        }
        func listFiles(serial: String, path: String, asRoot: Bool) async throws -> [FsEntry] { [] }
        func fileOperation(
            serial: String, _ operation: FileProtocol.Operation, asRoot: Bool
        ) async throws -> FeatureResult {
            FeatureResult(ok: false, message: "Permission denied")
        }
        func fileInfo(
            serial: String, path: String, asRoot: Bool
        ) async throws -> FileExplorerService.FileInfo? { nil }
        func pullFile(
            serial: String, path: String, to destination: String, asRoot: Bool
        ) async throws -> String { destination }
    }
}
