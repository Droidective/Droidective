import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The install route without a device.
///
/// The thing worth defending is that a multi-device install reports **per
/// device**: installing onto three where one is out of space is a partial
/// success, and one collapsed verdict would hide which one needs attention.
@Suite struct InstallRouteTests {
    private struct Refusal: Error, LocalizedError {
        let errorDescription: String?
    }

    private actor CallLog {
        private(set) var installs: [(String, String)] = []
        func record(_ path: String, _ serial: String) { installs.append((path, serial)) }
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        /// Serials that should fail, and what adb said.
        var rejects: [String: String] = [:]
        var refusal: Refusal?

        func installPackage(path: String, serial: String) async throws -> FeatureResult {
            if let refusal { throw refusal }
            await log.record(path, serial)
            if let reason = rejects[serial] {
                return FeatureResult(ok: false, message: reason)
            }
            return FeatureResult(ok: true, message: "Installed")
        }
    }

    private func body(_ value: some Encodable) -> Data { DaemonProtocol.encoded(value) }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    @Test func theFormatListComesFromTheServiceNotFromAHardcodedCopy() throws {
        // The client's file picker filters on this, so a format added to
        // `AppPackageFormat` is offered by both apps without a second edit.
        let response = try decode(
            InstallProtocol.FormatsResponse.self, InstallRoutes.formats().body)
        #expect(response.extensions == AppPackageFormat.fileExtensions)
        #expect(response.extensions.contains("xapk"))
    }

    @Test func installsOntoEveryTargetedDevice() async throws {
        let backend = StubBackend()
        let answer = await InstallRoutes.install(
            body: body(InstallProtocol.Request(
                serials: ["S1", "S2"], path: "/tmp/app.apk")),
            backend: backend)

        #expect(answer.status == 200)
        #expect(await backend.log.installs.map(\.1) == ["S1", "S2"])
    }

    @Test func eachDeviceGetsItsOwnVerdict() async throws {
        // One device out of space is a partial success, not a failure of the
        // whole install.
        let backend = StubBackend(rejects: ["S2": "INSTALL_FAILED_INSUFFICIENT_STORAGE"])
        let answer = await InstallRoutes.install(
            body: body(InstallProtocol.Request(serials: ["S1", "S2"], path: "/tmp/app.apk")),
            backend: backend)

        let response = try decode(InstallProtocol.Response.self, answer.body)
        #expect(response.outcomes.count == 2)
        #expect(response.outcomes[0].ok)
        #expect(!response.outcomes[1].ok)
        #expect(response.outcomes[1].message.contains("INSUFFICIENT_STORAGE"))
    }

    @Test func theAnswerNamesThePackageForTheStatusLine() async throws {
        let answer = await InstallRoutes.install(
            body: body(InstallProtocol.Request(
                serials: ["S1"], path: "/Users/someone/Downloads/MyApp-release.apk")),
            backend: StubBackend())
        let response = try decode(InstallProtocol.Response.self, answer.body)
        #expect(response.fileName == "MyApp-release.apk")
    }

    @Test func aBundleThatCannotBeProcessedKeepsItsOwnExplanation() async throws {
        // `BundleError` writes sentences worth showing — "no native code for
        // this device's CPU" is actionable in a way "install failed" is not.
        let backend = StubBackend(
            refusal: Refusal(errorDescription: "The bundle has no native code for this device's CPU (arm64-v8a)."))
        let answer = await InstallRoutes.install(
            body: body(InstallProtocol.Request(serials: ["S1"], path: "/tmp/app.xapk")),
            backend: backend)

        // Still a 200: the request was fine, the package was not.
        #expect(answer.status == 200)
        let response = try decode(InstallProtocol.Response.self, answer.body)
        #expect(!response.outcomes[0].ok)
        #expect(response.outcomes[0].message.contains("no native code"))
    }

    @Test func aRequestWithNoDeviceOrNoPathIsRefused() async throws {
        for request in [
            InstallProtocol.Request(serials: [], path: "/tmp/app.apk"),
            InstallProtocol.Request(serials: ["S1"], path: ""),
        ] {
            let backend = StubBackend()
            let answer = await InstallRoutes.install(body: body(request), backend: backend)
            #expect(answer.status == 400)
            #expect(await backend.log.installs.isEmpty)
        }
    }

    @Test func aMalformedBodyIsRefused() async {
        let answer = await InstallRoutes.install(
            body: Data("not json".utf8), backend: StubBackend())
        #expect(answer.status == 400)
    }
}
