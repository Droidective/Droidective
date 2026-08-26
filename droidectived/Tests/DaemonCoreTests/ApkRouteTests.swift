import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The APK routes without a toolchain.
///
/// Three features ride these, and the thing they share is how they fail: a
/// missing SDK build-tool, which the client has to be able to tell apart from a
/// bad APK. So what is asserted here is mostly the shape of the refusals.
@Suite struct ApkRouteTests {
    /// The services name a missing tool themselves, so the tests use their own
    /// error rather than a stand-in that only looks like one.
    private static let missingTool = ApkSigningService.SigningError.toolMissing("apksigner")
    private static let brokenInput = AabConvertService.ConvertError.buildFailed(
        "The archive doesn't seem to be an App Bundle")

    private struct StubBackend: DaemonBackend {
        var report = ApkReport(info: ApkInfo(fileName: "app.apk", fileSizeBytes: 1_024))
        var refusal: (any Error)?
        var tools = ApkProtocol.Toolchain(
            aapt2: true, apksigner: true, zipalign: true, java: true, bundletool: true)

        func apkToolchain() async -> ApkProtocol.Toolchain { tools }

        func inspectApk(path: String) async -> ApkReport { report }

        func signApk(_ request: ApkProtocol.SignRequest) async throws -> ApkProtocol.SignResponse {
            if let refusal { throw refusal }
            return ApkProtocol.SignResponse(ok: true, message: "Signed", output: request.output)
        }

        func convertAab(
            _ request: ApkProtocol.ConvertRequest
        ) async throws -> ApkProtocol.ConvertResponse {
            if let refusal { throw refusal }
            return ApkProtocol.ConvertResponse(
                path: "\(request.outputDirectory)/universal.apk", sizeBytes: 4_096)
        }
    }

    private func decode<T: Decodable>(_ answer: DaemonProtocol.Answer, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: answer.body)
    }

    private func signRequest() throws -> Data {
        try JSONEncoder().encode(
            ApkProtocol.SignRequest(
                input: "/tmp/in.apk", output: "/tmp/out.apk",
                keystore: ApkProtocol.Keystore(path: "/tmp/ks.jks", storePassword: "hunter2")))
    }

    // MARK: - toolchain

    @Test func theToolchainRouteSaysWhatIsInstalled() async throws {
        // Asked before a file is picked, so a screen can say "install the
        // build-tools" instead of letting a run fail and reading as a bad APK.
        let backend = StubBackend(
            tools: ApkProtocol.Toolchain(
                aapt2: false, apksigner: true, zipalign: true, java: true, bundletool: false))
        let answer = await ApkRoutes.toolchain(backend: backend)

        #expect(answer.status == 200)
        let tools = try decode(answer, as: ApkProtocol.Toolchain.self)
        #expect(!tools.aapt2)
        #expect(tools.apksigner)
        #expect(!tools.bundletool)
    }

    // MARK: - inspect

    @Test func inspectCarriesTheWholeReport() async throws {
        let report = ApkReport(
            info: ApkInfo(
                fileName: "app.apk", fileSizeBytes: 2_048, label: "Example",
                packageName: "com.example", versionName: "1.2", versionCode: "12",
                minSdk: "24", targetSdk: "34"),
            permissions: ["android.permission.INTERNET"],
            features: ["android.hardware.camera"],
            isDebuggable: true,
            signatureSchemes: ["v2"],
            signers: [ApkSigner(subjectDN: "CN=Example", sha256: "abc", sha1: "def")])
        let answer = await ApkRoutes.inspect(
            body: try JSONEncoder().encode(ApkProtocol.PathRequest(path: "/tmp/app.apk")),
            backend: StubBackend(report: report))

        #expect(answer.status == 200)
        let body = try decode(answer, as: ApkProtocol.Report.self)
        #expect(body.packageName == "com.example")
        #expect(body.minSdk == "24")
        #expect(body.permissions == ["android.permission.INTERNET"])
        #expect(body.isDebuggable)
        #expect(body.signers.first?.sha256 == "abc")
    }

    @Test func anApkWithNoAapt2StillAnswersWithWhatIsKnown() async throws {
        // Best-effort by construction: without aapt2 the name and size are
        // still real, and `hasDetails` is how the screen says why that is all.
        let answer = await ApkRoutes.inspect(
            body: try JSONEncoder().encode(ApkProtocol.PathRequest(path: "/tmp/app.apk")),
            backend: StubBackend())

        let body = try decode(answer, as: ApkProtocol.Report.self)
        #expect(body.fileName == "app.apk")
        #expect(body.fileSizeBytes == 1_024)
        #expect(!body.hasDetails)
    }

    @Test func inspectNeedsAPath() async throws {
        let answer = await ApkRoutes.inspect(
            body: try JSONEncoder().encode(ApkProtocol.PathRequest(path: "")),
            backend: StubBackend())
        #expect(answer.status == 400)
    }

    // MARK: - sign

    @Test func signAnswersWhereTheSignedApkLanded() async throws {
        let answer = await ApkRoutes.sign(body: try signRequest(), backend: StubBackend())

        #expect(answer.status == 200)
        let body = try decode(answer, as: ApkProtocol.SignResponse.self)
        #expect(body.ok)
        #expect(body.output == "/tmp/out.apk")
    }

    @Test func aMissingToolIsItsOwnAnswerRatherThanAFailedSigning() async throws {
        // 422, not 500: nothing is wrong with the request or the daemon — a
        // tool is absent, and that is the one thing the user can fix.
        let answer = await ApkRoutes.sign(
            body: try signRequest(), backend: StubBackend(refusal: Self.missingTool))

        #expect(answer.status == 422)
        let error = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(error.error.code == "tool_missing")
        #expect(error.error.detail?.contains("apksigner") == true)
    }

    @Test func aToolThatRanAndRefusedIsNotReportedAsAMissingOne() async throws {
        // Found by running it: bundletool rejecting a plain APK as "not an App
        // Bundle" came back as `tool_missing`, which sends someone to install
        // something they already have.
        let request = ApkProtocol.ConvertRequest(
            input: "/tmp/not-a-bundle.apk", outputDirectory: "/tmp/out")
        let answer = await ApkRoutes.convert(
            body: try JSONEncoder().encode(request),
            backend: StubBackend(refusal: Self.brokenInput))

        #expect(answer.status == 422)
        let error = try decode(answer, as: DaemonProtocol.ErrorBody.self)
        #expect(error.error.code == "tool_failed")
        #expect(error.error.detail?.contains("App Bundle") == true)
    }

    @Test func signNeedsAnInputAnOutputAndAKeystore() async throws {
        let backend = StubBackend()
        let bad = [
            ApkProtocol.SignRequest(
                input: "", output: "/tmp/out.apk",
                keystore: ApkProtocol.Keystore(path: "/k", storePassword: "p")),
            ApkProtocol.SignRequest(
                input: "/tmp/in.apk", output: "",
                keystore: ApkProtocol.Keystore(path: "/k", storePassword: "p")),
            ApkProtocol.SignRequest(
                input: "/tmp/in.apk", output: "/tmp/out.apk",
                keystore: ApkProtocol.Keystore(path: "", storePassword: "p")),
        ]
        for request in bad {
            let answer = await ApkRoutes.sign(
                body: try JSONEncoder().encode(request), backend: backend)
            #expect(answer.status == 400)
        }
    }

    @Test func aKeystorePasswordIsCarriedButNeverPutInAnArgument() throws {
        // The password rides the request body, which is the trust boundary the
        // token already establishes. What must stay true is that it reaches
        // `ApkSigningService` as a value — that service writes it to a 0600
        // temp file precisely so it never appears in argv.
        let keystore = ApkProtocol.Keystore(
            path: "/tmp/ks.jks", storePassword: "hunter2", keyAlias: "key0")
        let credentials = keystore.credentials

        #expect(credentials.storePassword == "hunter2")
        #expect(credentials.keystorePath == "/tmp/ks.jks")
        #expect(credentials.keyAlias == "key0")
    }

    // MARK: - convert

    @Test func convertAnswersWhereTheUniversalApkLanded() async throws {
        let request = ApkProtocol.ConvertRequest(
            input: "/tmp/app.aab", outputDirectory: "/tmp/out")
        let answer = await ApkRoutes.convert(
            body: try JSONEncoder().encode(request), backend: StubBackend())

        #expect(answer.status == 200)
        let body = try decode(answer, as: ApkProtocol.ConvertResponse.self)
        #expect(body.path == "/tmp/out/universal.apk")
        #expect(body.sizeBytes == 4_096)
    }

    @Test func convertWithoutAKeystoreIsAllowed() async throws {
        // bundletool's own debug key is what the Mac's screen uses until
        // someone chooses a keystore, so no keystore is a valid request.
        let json = Data(#"{"input":"/tmp/a.aab","outputDirectory":"/tmp/out"}"#.utf8)
        let answer = await ApkRoutes.convert(body: json, backend: StubBackend())
        #expect(answer.status == 200)
    }

    @Test func convertWithoutBundletoolSaysWhichToolIsMissing() async throws {
        let request = ApkProtocol.ConvertRequest(
            input: "/tmp/app.aab", outputDirectory: "/tmp/out")
        let answer = await ApkRoutes.convert(
            body: try JSONEncoder().encode(request), backend: StubBackend(refusal: Self.missingTool))

        #expect(answer.status == 422)
        #expect(try decode(answer, as: DaemonProtocol.ErrorBody.self).error.code == "tool_missing")
    }

    @Test func convertNeedsAnInputAndSomewhereToPutIt() async throws {
        let backend = StubBackend()
        for request in [
            ApkProtocol.ConvertRequest(input: "", outputDirectory: "/tmp/out"),
            ApkProtocol.ConvertRequest(input: "/tmp/a.aab", outputDirectory: ""),
        ] {
            let answer = await ApkRoutes.convert(
                body: try JSONEncoder().encode(request), backend: backend)
            #expect(answer.status == 400)
        }
    }
}
