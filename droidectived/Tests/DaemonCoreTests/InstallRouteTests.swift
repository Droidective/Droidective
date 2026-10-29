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
        private(set) var opens: [(serial: String, package: String)] = []
        private(set) var detailReads: [Bool] = []
        func record(_ path: String, _ serial: String) { installs.append((path, serial)) }
        func recordOpen(_ serial: String, _ package: String) { opens.append((serial, package)) }
        func recordDetails(readsSigning: Bool) { detailReads.append(readsSigning) }
    }

    private struct StubBackend: DaemonBackend {
        let log = CallLog()
        /// Serials that should fail, and what adb said.
        var rejects: [String: String] = [:]
        var refusal: Refusal?
        /// What the package reads as; nil models a file that isn't one.
        var details: PackageDetails? = Self.apiDemos
        /// What opening the app answers.
        var openResult = FeatureResult(ok: true, message: "Opened app")
        var aapt2 = true

        static let apiDemos: PackageDetails = {
            var details = PackageDetails(format: .apk, fileName: "app.apk", fileSizeBytes: 4096)
            details.report = ApkReport(
                info: ApkInfo(
                    fileName: "app.apk", fileSizeBytes: 4096, label: "API Demos",
                    packageName: "io.appium.android.apis", versionName: "3.1.0", versionCode: "18",
                    minSdk: "17", targetSdk: "28"),
                permissions: ["android.permission.CAMERA"],
                isDebuggable: true,
                signatureSchemes: ["v2"],
                signers: [ApkSigner(subjectDN: "CN=Android Debug, O=Android, C=US")],
                launchableActivity: "io.appium.android.apis.ApiDemos")
            return details
        }()

        func installPackage(path: String, serial: String) async throws -> FeatureResult {
            if let refusal { throw refusal }
            await log.record(path, serial)
            if let reason = rejects[serial] {
                return FeatureResult(ok: false, message: reason)
            }
            return FeatureResult(ok: true, message: "Installed")
        }

        func packageDetails(path: String, readsSigning: Bool) async -> PackageDetails? {
            await log.recordDetails(readsSigning: readsSigning)
            return details
        }

        func hasAapt2() async -> Bool { aapt2 }

        func controlApp(
            serial: String, packageId: String, action: AppControlService.AppAction
        ) async throws -> FeatureResult {
            #expect(action == .open)
            await log.recordOpen(serial, packageId)
            return openResult
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

    // MARK: Open after installing

    @Test func openingLaunchesTheAppOnEveryDeviceItReached() async throws {
        let backend = StubBackend(rejects: ["S2": "INSTALL_FAILED_INSUFFICIENT_STORAGE"])
        let answer = await InstallRoutes.install(
            body: body(InstallProtocol.Request(serials: ["S1", "S2", "S3"], path: "/tmp/app.apk", opensApp: true)),
            backend: backend)

        let response = try decode(InstallProtocol.Response.self, answer.body)
        #expect(response.outcomes.map(\.opened) == [true, false, true])
        #expect(response.outcomes.allSatisfy { $0.openFailure == nil })
        // Never on the device the install didn't reach.
        let opens = await backend.log.opens
        #expect(opens.map(\.serial) == ["S1", "S3"])
        #expect(opens.allSatisfy { $0.package == "io.appium.android.apis" })
        // The name is read once, and without the signer check.
        #expect(await backend.log.detailReads == [false])
    }

    @Test func notAskingToOpenReadsAndOpensNothing() async throws {
        let backend = StubBackend()
        let answer = await InstallRoutes.install(
            body: body(InstallProtocol.Request(serials: ["S1"], path: "/tmp/app.apk")),
            backend: backend)

        let response = try decode(InstallProtocol.Response.self, answer.body)
        #expect(response.outcomes[0].ok)
        #expect(!response.outcomes[0].opened)
        #expect(await backend.log.opens.isEmpty)
        #expect(await backend.log.detailReads.isEmpty)
    }

    @Test func aBodyFromBeforeTheFlagStillDecodesAsNotOpening() throws {
        let request = try decode(
            InstallProtocol.Request.self, Data(#"{"serials":["S1"],"path":"/tmp/a.apk"}"#.utf8))
        #expect(!request.opensApp)
    }

    @Test func anAppThatCannotBeOpenedSaysWhyWithoutFailingTheInstall() async throws {
        var noLauncher = StubBackend()
        noLauncher.openResult = FeatureResult(
            ok: false, message: "Couldn't launch io.appium.android.apis — it has no enabled launcher activity.")
        var unreadable = StubBackend()
        unreadable.details = nil

        for (backend, reason) in [
            (noLauncher, "no enabled launcher activity"),
            (unreadable, "needs the SDK build-tools"),
        ] {
            let answer = await InstallRoutes.install(
                body: body(InstallProtocol.Request(serials: ["S1"], path: "/tmp/app.apk", opensApp: true)),
                backend: backend)
            let outcome = try decode(InstallProtocol.Response.self, answer.body).outcomes[0]
            #expect(outcome.ok)
            #expect(!outcome.opened)
            #expect(outcome.openFailure?.contains(reason) == true)
        }
    }

    // MARK: Details

    @Test func detailsArriveWordedTheWayTheMacsCardWordsThem() async throws {
        let backend = StubBackend()
        let answer = await InstallRoutes.details(
            body: body(InstallProtocol.DetailsRequest(path: "/tmp/app.apk")), backend: backend)

        #expect(answer.status == 200)
        let details = try decode(InstallProtocol.Details.self, answer.body)
        #expect(details.format == "apk")
        #expect(details.label == "API Demos")
        #expect(details.packageName == "io.appium.android.apis")
        #expect(details.isDebuggable)
        #expect(details.version == "3.1.0  (18)")
        #expect(details.requires == "Android 4.2 (API 17) or later")
        #expect(details.targets == "Android 9 (API 28)")
        #expect(details.nativeCode == "None — runs on any CPU")
        #expect(details.launcher == "ApiDemos")
        #expect(!details.hasNoLauncher)
        #expect(details.signer == "Android Debug · v2 scheme")
        #expect(details.permissions == ["CAMERA"])
        #expect(details.note == nil)
        // The card shows the signer, so this read runs apksigner.
        #expect(await backend.log.detailReads == [true])
    }

    @Test func detailsWithoutTheBuildToolsSayWhy() async throws {
        var backend = StubBackend()
        backend.details = PackageDetails(format: .apk, fileName: "app.apk", fileSizeBytes: 1)
        backend.details?.report = ApkReport(info: ApkInfo(fileName: "app.apk", fileSizeBytes: 1))
        backend.aapt2 = false
        let answer = await InstallRoutes.details(
            body: body(InstallProtocol.DetailsRequest(path: "/tmp/app.apk")), backend: backend)

        let details = try decode(InstallProtocol.Details.self, answer.body)
        #expect(details.version == nil)
        #expect(details.launcher == nil)
        #expect(details.note?.contains("build-tools (aapt2)") == true)
    }

    @Test func detailsRefuseAFileThatIsNotAPackageAndABadBody() async {
        var backend = StubBackend()
        backend.details = nil
        let notAPackage = await InstallRoutes.details(
            body: body(InstallProtocol.DetailsRequest(path: "/tmp/notes.txt")), backend: backend)
        #expect(notAPackage.status == 400)
        let empty = await InstallRoutes.details(
            body: body(InstallProtocol.DetailsRequest(path: "")), backend: backend)
        #expect(empty.status == 400)
        let malformed = await InstallRoutes.details(body: Data("{".utf8), backend: backend)
        #expect(malformed.status == 400)
    }

    @Test func aMalformedBodyIsRefused() async {
        let answer = await InstallRoutes.install(
            body: Data("not json".utf8), backend: StubBackend())
        #expect(answer.status == 400)
    }
}
