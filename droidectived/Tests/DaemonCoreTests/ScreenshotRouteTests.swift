import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The Screenshot editor's capture route.
@Suite struct ScreenshotRouteTests {
    private struct StubBackend: DaemonBackend {
        let png: Data
        let failure: (any Error)?

        func listDevices() async -> [Device] { [] }

        func captureScreenshot(serial: String) async throws -> Data {
            if let failure { throw failure }
            return png
        }
    }

    private struct Refused: Error, CustomStringConvertible {
        var description: String { "device offline" }
    }

    /// Four bytes standing in for a PNG: this route does not parse the image,
    /// it carries it, so the shape that matters is the encoding.
    private static let bytes = Data([0x89, 0x50, 0x4E, 0x47])

    @Test func carriesThePngAsBase64() async throws {
        let (status, body) = await ScreenshotRoutes.capture(
            body: Data(#"{"serial":"emulator-5554"}"#.utf8),
            backend: StubBackend(png: Self.bytes, failure: nil))
        #expect(status == 200)
        let decoded = try JSONDecoder().decode(
            ScreenshotProtocol.CaptureResponse.self, from: body)
        #expect(Data(base64Encoded: decoded.png) == Self.bytes)
    }

    @Test func aDeviceThatRefusesIsAdbsAnswerNotADaemonFault() async throws {
        let (status, body) = await ScreenshotRoutes.capture(
            body: Data(#"{"serial":"emulator-5554"}"#.utf8),
            backend: StubBackend(png: Data(), failure: Refused()))
        // 502, not 500: the daemon worked and the device did not.
        #expect(status == 502)
        let error = try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: body)
        #expect(error.error.code == "adb_failed")
        #expect(error.error.detail?.contains("device offline") == true)
    }

    @Test func aBodyItCannotReadIsA400() async {
        let (status, _) = await ScreenshotRoutes.capture(
            body: Data("not json".utf8),
            backend: StubBackend(png: Self.bytes, failure: nil))
        #expect(status == 400)
    }

    @Test(arguments: [
        (nil as Int?, 0),
        (0, 0),
        (3, 3),
        (10, 10),
        // The delay is a sleep inside a route handler, so an absurd one would
        // hold the handler rather than the client's own timer.
        (3600, 30),
        (-5, 0),
    ])
    func clampsTheDelay(requested: Int?, expected: Int) {
        let request = ScreenshotProtocol.CaptureRequest(
            serial: "emulator-5554", delaySeconds: requested)
        #expect(request.clampedDelay == expected)
    }
}
