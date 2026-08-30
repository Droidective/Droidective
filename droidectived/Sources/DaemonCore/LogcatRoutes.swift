import ADBKit
import Foundation

/// The one thing a log client cannot work out for itself: which process id an
/// app is running under.
///
/// The Mac's log view narrows to an app with `adb logcat --pid`, and this is
/// what makes that reachable over the wire. Deliberately *not* a package filter
/// on the subscription: the pid has to be re-resolved while the log is open —
/// an app that has not launched yet, and an app that relaunches under a new
/// pid, are both ordinary — and the client is the half that knows whether it is
/// waiting for one or following the other. A subscription that quietly
/// re-resolved would have no way to say which of the two it was doing, and a
/// log that has gone silent because the app died looks exactly like a log that
/// has gone silent because the app is idle.
///
/// Filtering on the device rather than in the client is the point. A client-side
/// filter over a mixed buffer keeps every other app's lines in the ring, so a
/// chatty neighbour evicts the lines being looked for — with `--pid` the buffer
/// holds nothing else.
public enum LogcatProtocol {
    public struct PidRequest: Codable, Equatable, Sendable {
        public let serial: String
        public let packageId: String

        public init(serial: String, packageId: String) {
            self.serial = serial
            self.packageId = packageId
        }
    }

    /// The app's pid, or nil when it is not running.
    ///
    /// An omitted key rather than an error, the same call `/v1/apps/foreground`
    /// makes: "not running" is the ordinary state of an app whose log you
    /// opened first, and a 502 would make the client treat it as a fault.
    public struct PidResponse: Codable, Equatable, Sendable {
        public let pid: Int?

        public init(pid: Int?) {
            self.pid = pid
        }
    }
}
