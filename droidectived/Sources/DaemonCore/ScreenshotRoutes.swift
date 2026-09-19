import ADBKit
import Foundation

/// Wire shapes for the Screenshot editor's capture.
///
/// Separate from the `screenshot` *action*, which grabs and writes a file. This
/// one answers with the **bytes**, because the editor writes nothing to disk
/// until the user saves or copies — the Mac splits the same two paths, with
/// `captureForEditor` returning `ScreenCaptureService.captureScreenshotData`
/// and `runScreenshot` saving straight to the capture folder.
public enum ScreenshotProtocol {
    public struct CaptureRequest: Codable, Equatable, Sendable {
        public let serial: String
        /// Seconds to wait before grabbing, for the delay picker. Clamped
        /// daemon-side: this becomes a sleep in the daemon's own process, so a
        /// client asking for an hour would hold a route handler for an hour.
        public let delaySeconds: Int?

        public init(serial: String, delaySeconds: Int? = nil) {
            self.serial = serial
            self.delaySeconds = delaySeconds
        }

        /// The Mac's picker offers 0/3/5/10; anything beyond that is refused
        /// rather than honoured.
        public var clampedDelay: Int { min(30, max(0, delaySeconds ?? 0)) }
    }

    public struct CaptureResponse: Codable, Equatable, Sendable {
        /// The PNG, base64. Bytes rather than a path: nothing is written yet.
        public let png: String
        public init(png: String) { self.png = png }
    }
}

enum ScreenshotRoutes {
    static func capture(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(
            ScreenshotProtocol.CaptureRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        if request.clampedDelay > 0 {
            try? await Task.sleep(for: .seconds(request.clampedDelay))
        }
        do {
            let png = try await backend.captureScreenshot(serial: request.serial)
            return (200, DaemonProtocol.encoded(ScreenshotProtocol.CaptureResponse(
                png: png.base64EncodedString())))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "adb_failed", message: "Could not capture the screen.",
                detail: "\(error)")))
        }
    }
}
