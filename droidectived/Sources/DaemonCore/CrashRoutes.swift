import ADBKit
import Foundation

/// Wire shapes for the device's crash buffer.
///
/// A pass-through over `CrashExtractor`, which does the reading and hands
/// `CrashParser` the splitting. The daemon decides nothing about what a crash
/// is: which buffer to read, when to fall back to `main`, and where one crash
/// ends are all questions ADBKit already answers, and answering them twice is
/// how the two clients would start disagreeing about how many crashes a device
/// has.
public enum CrashProtocol {
    public struct ListRequest: Codable, Equatable, Sendable {
        public let serial: String
        public init(serial: String) { self.serial = serial }
    }

    /// One crash.
    ///
    /// A DTO rather than `CrashReport`: that type is not `Codable`, and its
    /// `Kind` carries a `label` a client would otherwise have to reimplement —
    /// so the label travels, the way `AppSummary.displayName` does.
    public struct Report: Codable, Equatable, Sendable {
        /// Stable across refetches of the same buffer, so a watch poll does
        /// not move the selection.
        public let id: String
        /// A `CrashReport.Kind` raw value: java, native, reactNative, anr,
        /// unknown.
        public let kind: String
        public let kindLabel: String
        /// Logcat's own timestamp — "06-12 10:00:02.123". A string because
        /// logcat prints no year, so it is not a date anyone can parse.
        public let timestamp: String?
        public let process: String?
        public let pid: Int?
        /// One line: the exception, the signal, or the ANR.
        public let title: String
        /// The block as logcat printed it, bounded.
        public let raw: String
        /// The block with the threadtime prefixes stripped, bounded.
        public let body: String

        public init(_ report: CrashReport) {
            id = report.id
            kind = report.kind.rawValue
            kindLabel = report.kind.label
            timestamp = report.timestamp
            process = report.process
            pid = report.pid
            title = report.title
            raw = report.raw
            body = report.body
        }
    }

    public struct ListResponse: Codable, Equatable, Sendable {
        /// Newest first, as `CrashExtractor` orders them.
        public let crashes: [Report]
        public init(crashes: [Report]) { self.crashes = crashes }
    }
}

/// The two crash routes.
///
/// Separate from `DaemonServer` for the reason `FileRoutes` is: its `respond`
/// stays a table of routes, and these are testable without a socket.
enum CrashRoutes {
    static func list(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            CrashProtocol.ListRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            let crashes = try await backend.crashes(serial: request.serial)
            return (200, DaemonProtocol.encoded(CrashProtocol.ListResponse(
                crashes: crashes.map(CrashProtocol.Report.init))))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "Could not read the crash buffer.",
                detail: "\(error)")))
        }
    }

    static func clear(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            CrashProtocol.ListRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            try await backend.clearCrashBuffer(serial: request.serial)
            return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(
                FeatureResult(ok: true, message: "Crash buffer cleared"))))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "Could not clear the crash buffer.",
                detail: "\(error)")))
        }
    }
}
