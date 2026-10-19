#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Testing
@testable import ADBKit

/// The signing block of the real `droidective-android-0.1.0.apk`, exactly as
/// apksigner wrote it, followed by an end-of-central-directory record pointing
/// just past it. Sliced out by the scratch script described in the PR; the
/// central directory itself is left out because nothing here reads it.
enum ReleaseFixture {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/apk/droidective-android-0.1.0-signing-block.bin")

    static func bytes() throws -> Data { try Data(contentsOf: url) }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Builds zip-shaped bytes with a signing block, so each branch of the reader
/// can be reached with exactly the defect it handles.
enum SyntheticApk {
    static let v2: UInt32 = 0x7109_871A
    static let v3: UInt32 = 0xF053_68C0
    static let verityPadding: UInt32 = 0x4272_6577

    static func le(_ value: UInt64, _ width: Int) -> Data {
        Data((0..<width).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) })
    }

    static func prefixed(_ data: Data) -> Data { le(UInt64(data.count), 4) + data }

    static func sequence(_ items: [Data]) -> Data { items.map(prefixed).reduce(Data(), +) }

    /// A scheme's value: its signers, each with the given certificates.
    static func scheme(signers: [[Data]]) -> Data {
        let blobs = signers.map { certificates in
            let signedData = prefixed(Data()) + prefixed(sequence(certificates)) + prefixed(Data())
            return prefixed(signedData) + prefixed(Data()) + prefixed(Data())
        }
        return prefixed(sequence(blobs))
    }

    static func block(_ pairs: [(UInt32, Data)]) -> Data {
        let body = pairs.map { le(UInt64($0.1.count + 4), 8) + le(UInt64($0.0), 4) + $0.1 }
            .reduce(Data(), +)
        let size = UInt64(body.count + 8 + 16)
        return le(size, 8) + body + le(size, 8) + Data("APK Sig Block 42".utf8)
    }

    static func apk(block: Data?, comment: Data = Data()) -> Data {
        let entries = Data("PK\u{3}\u{4} local entries".utf8)
        let directory = Data("PK\u{1}\u{2} central directory".utf8)
        let offset = entries.count + (block?.count ?? 0)
        let end = le(0x0605_4B50, 4) + Data(count: 8) + le(UInt64(directory.count), 4)
            + le(UInt64(offset), 4) + le(UInt64(comment.count), 2) + comment
        return entries + (block ?? Data()) + directory + end
    }

    static func signed(by signers: [[Data]], scheme id: UInt32 = v2) -> Data {
        apk(block: block([(id, scheme(signers: signers))]))
    }
}

enum TestRelease {
    static func make(version: String, digest: String? = nil) -> PhoneAppRelease {
        PhoneAppRelease(
            version: version, apkName: "droidective-android-\(version).apk",
            apkURL: "https://github.com/Droidective/droidective-android/releases/download/v\(version)/droidective-android-\(version).apk",
            apkSize: 4_824_060, apkDigest: digest)
    }
}

/// Counts how often a closure was asked for the latest release.
actor Asked {
    private(set) var count = 0

    func note() -> PhoneAppRelease? {
        count += 1
        return nil
    }
}

/// GitHub, as far as a set-up run sees it: one JSON answer for the API and one
/// file for every download, with progress reported halfway and at the end.
final class ReleaseHost: HTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let json: Data
    private let apk: Data
    private let failure: (any Error)?
    private let delay: Duration
    private var fetched: [URL] = []
    private var downloaded: [URL] = []

    init(json: Data = Data(), apk: Data = Data(), failure: (any Error)? = nil, delay: Duration = .zero) {
        self.json = json
        self.apk = apk
        self.failure = failure
        self.delay = delay
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var fetches: [URL] { locked { fetched } }
    var downloads: [URL] { locked { downloaded } }

    func data(from url: URL) async throws -> Data {
        locked { fetched.append(url) }
        if delay > .zero { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        return json
    }

    func download(
        from url: URL, to destination: URL, onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        locked { downloaded.append(url) }
        if let failure { throw failure }
        onProgress?(0.5)
        try FixtureFile.write(apk, to: destination)
        onProgress?(1)
    }
}

@Suite struct ApkSigningBlockTests {
    private let mine = Data("my certificate".utf8)
    private let theirs = Data("their certificate".utf8)

    @Test func theRealReleaseIsSignedByThePinnedCertificate() throws {
        #expect(try ApkSigningBlock.certificateDigests(apk: ReleaseFixture.bytes())
            == [PhoneAppReleases.signingCertificateSHA256])
    }

    @Test func everySignerOfEverySchemeIsReported() throws {
        let apk = SyntheticApk.apk(block: SyntheticApk.block([
            (SyntheticApk.v2, SyntheticApk.scheme(signers: [[mine]])),
            (SyntheticApk.verityPadding, Data(count: 64)),
            (SyntheticApk.v3, SyntheticApk.scheme(signers: [[mine], [theirs, mine]])),
        ]))
        #expect(try ApkSigningBlock.certificates(apk: apk) == [mine, mine, theirs])
        #expect(try ApkSigningBlock.certificateDigests(apk: apk)
            == [mine, mine, theirs].map(ReleaseFixture.sha256))
    }

    @Test func aZipCommentIsSteppedOver() throws {
        // A comment holding the record's own signature must not be read as the
        // record: it is far enough from the end to be scanned, and its own
        // "comment length" doesn't reach the end of the file.
        let comment = SyntheticApk.le(0x0605_4B50, 4) + Data(count: 26) + Data("tail".utf8)
        let apk = SyntheticApk.apk(
            block: SyntheticApk.block([(SyntheticApk.v2, SyntheticApk.scheme(signers: [[mine]]))]),
            comment: comment)
        #expect(try ApkSigningBlock.certificates(apk: apk) == [mine])
    }

    @Test func whatIsntAZipIsntAnApk() {
        for bytes in [Data(), Data("hello".utf8), Data(count: 4096)] {
            #expect(throws: ApkSigningBlock.ReadError.notAnApk) {
                try ApkSigningBlock.certificates(apk: bytes)
            }
        }
    }

    @Test func aTruncatedDownloadIsntAnApk() throws {
        let apk = try ReleaseFixture.bytes()
        #expect(throws: ApkSigningBlock.ReadError.notAnApk) {
            try ApkSigningBlock.certificates(apk: apk.prefix(apk.count - 10))
        }
    }

    @Test func noV2SignatureIsUnsigned() {
        #expect(throws: ApkSigningBlock.ReadError.unsigned) {
            try ApkSigningBlock.certificates(apk: SyntheticApk.apk(block: nil))
        }
        #expect(throws: ApkSigningBlock.ReadError.unsigned) {
            try ApkSigningBlock.certificates(apk: SyntheticApk.apk(block: SyntheticApk.block([
                (SyntheticApk.verityPadding, Data(count: 32)),
            ])))
        }
    }

    @Test func damageIsNamedNotGuessedAround() {
        let good = SyntheticApk.block([(SyntheticApk.v2, SyntheticApk.scheme(signers: [[mine]]))])
        var disagreeing = good
        disagreeing[0] ^= 0x01
        let noSigners = SyntheticApk.block([(SyntheticApk.v2, SyntheticApk.prefixed(Data()))])
        let noCertificates = SyntheticApk.block([(SyntheticApk.v2, SyntheticApk.scheme(signers: [[]]))])
        var overlong = good
        overlong[8] = 0xFF
        let cases: [(Data, String)] = [
            (disagreeing, "its two size fields disagree"),
            (noSigners, "a signature has no signers"),
            (noCertificates, "a signer has no certificate"),
            (overlong, "a pair runs past the end of the block"),
        ]
        for (block, reason) in cases {
            #expect(throws: ApkSigningBlock.ReadError.malformed(reason)) {
                try ApkSigningBlock.certificates(apk: SyntheticApk.apk(block: block))
            }
        }
    }
}

@Suite struct PhoneAppReleasesTests {
    private func json(tag: String, assets: [String]) -> Data {
        let list = assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://github.com/x/\#($0)","size":4824060,"digest":"sha256:abc"}"#
        }.joined(separator: ",")
        return Data(#"{"tag_name":"\#(tag)","assets":[\#(list)]}"#.utf8)
    }

    @Test func theLatestReleaseIsTheApkNamedForItsTag() throws {
        let release = try PhoneAppReleases.release(from: json(
            tag: "v0.1.1",
            assets: ["droidective-android-0.1.1.apk.sha256", "droidective-android-0.1.1.apk"]))
        #expect(release == PhoneAppRelease(
            version: "0.1.1", apkName: "droidective-android-0.1.1.apk",
            apkURL: "https://github.com/x/droidective-android-0.1.1.apk", apkSize: 4_824_060,
            apkDigest: "sha256:abc"))
    }

    @Test func aReleaseMadeAnyOtherWayIsIgnored() throws {
        let cases: [(String, [String])] = [
            ("v0.1.1", ["droidective-android-0.1.1.apk.sha256"]),
            ("v0.1.1", ["droidective-android-0.1.0.apk"]),
            ("0.1.1", ["droidective-android-0.1.1.apk"]),
            ("v0.1", ["droidective-android-0.1.apk"]),
            ("v0.1.1-beta.1", ["droidective-android-0.1.1-beta.1.apk"]),
            ("v0.1./", ["droidective-android-0.1./.apk"]),
            ("v1..2", ["droidective-android-1..2.apk"]),
        ]
        for (tag, assets) in cases {
            #expect(try PhoneAppReleases.release(from: json(tag: tag, assets: assets)) == nil)
        }
    }

    @Test func aGenuineDownloadPasses() throws {
        let file = try write(ReleaseFixture.bytes())
        let digest = "sha256:" + ReleaseFixture.sha256(try ReleaseFixture.bytes())
        #expect(PhoneAppReleases.problem(apkAt: file, release: TestRelease.make(version: "0.1.0", digest: digest)) == nil)
        #expect(PhoneAppReleases.problem(apkAt: file, release: TestRelease.make(version: "0.1.0")) == nil)
    }

    @Test func aDownloadThatDoesntMatchItsDigestIsRefused() throws {
        let file = try write(ReleaseFixture.bytes())
        let release = TestRelease.make(version: "0.1.0", digest: "sha256:" + String(repeating: "0", count: 64))
        #expect(PhoneAppReleases.problem(apkAt: file, release: release)
            == "The download doesn't match the release's checksum, so it wasn't installed.")
    }

    @Test func anyOtherSignerIsRefused() throws {
        let pinned = try ApkSigningBlock.certificates(apk: ReleaseFixture.bytes())[0]
        let other = Data("someone else's certificate".utf8)
        let refused = "The download isn't signed with Droidective's release key, so it wasn't installed."
        // Another key alone, and the pinned key with another beside it in a newer scheme.
        let alone = try write(SyntheticApk.signed(by: [[other]]))
        let beside = try write(SyntheticApk.apk(block: SyntheticApk.block([
            (SyntheticApk.v2, SyntheticApk.scheme(signers: [[pinned]])),
            (SyntheticApk.v3, SyntheticApk.scheme(signers: [[other]])),
        ])))
        let release = TestRelease.make(version: "0.1.0")
        #expect(PhoneAppReleases.problem(apkAt: alone, release: release) == refused)
        #expect(PhoneAppReleases.problem(apkAt: beside, release: release) == refused)
        let genuine = try write(SyntheticApk.signed(by: [[pinned]], scheme: SyntheticApk.v3))
        #expect(PhoneAppReleases.problem(apkAt: genuine, release: release) == nil)
    }

    @Test func anUnsignedDownloadIsRefusedWithTheReason() throws {
        let file = try write(SyntheticApk.apk(block: nil))
        #expect(PhoneAppReleases.problem(apkAt: file, release: TestRelease.make(version: "0.1.0"))
            == "Couldn't read the downloaded APK's signature: The APK has no v2 or later signature.")
    }

    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phone-app-\(UUID().uuidString).apk")
        try FixtureFile.write(data, to: url)
        return url
    }
}

@Suite struct PhoneAppReleaseCheckTests {
    private let json = Data(#"{"tag_name":"v0.1.1","assets":[{"name":"droidective-android-0.1.1.apk","browser_download_url":"https://github.com/x/a.apk","size":1}]}"#.utf8)

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = Date(timeIntervalSince1970: 1_800_000_000)
        private func locked<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }

        var now: Date { locked { current } }
        func advance(_ seconds: TimeInterval) { locked { current += seconds } }
    }

    @Test func anAnswerIsKeptForItsMaxAge() async {
        let host = ReleaseHost(json: json)
        let clock = Clock()
        let check = PhoneAppReleaseCheck(http: host, now: { clock.now })

        #expect(await check.latest(maxAge: 3600).release?.version == "0.1.1")
        clock.advance(3599)
        _ = await check.latest(maxAge: 3600)
        #expect(host.fetches == [PhoneAppReleases.latestURL])
        clock.advance(2)
        _ = await check.latest(maxAge: 3600)
        #expect(host.fetches.count == 2)
    }

    @Test func aFailureIsRetriedSoonerThanAnAnswer() async {
        let host = ReleaseHost(failure: ManagedToolStore.StoreError.http(403))
        let clock = Clock()
        let check = PhoneAppReleaseCheck(http: host, now: { clock.now })

        #expect(await check.latest(maxAge: 6 * 3600)
            == .failed("GitHub's anonymous request limit was reached — try again in a few minutes."))
        clock.advance(PhoneAppReleaseCheck.failureRetry - 1)
        _ = await check.latest(maxAge: 6 * 3600)
        #expect(host.fetches.count == 1)
        clock.advance(2)
        _ = await check.latest(maxAge: 6 * 3600)
        #expect(host.fetches.count == 2)
    }

    @Test func askersAtOnceShareOneRequest() async {
        let host = ReleaseHost(json: json, delay: .milliseconds(100))
        let check = PhoneAppReleaseCheck(http: host)

        async let first = check.latest(maxAge: 60)
        async let second = check.latest(maxAge: 60)
        let answers = await [first, second]

        #expect(answers.allSatisfy { $0.release?.version == "0.1.1" })
        #expect(host.fetches.count == 1)
    }

    @Test func aReleaseWithoutTheApkIsAFailure() async {
        let host = ReleaseHost(json: Data(#"{"tag_name":"v0.1.1","assets":[]}"#.utf8))
        #expect(await PhoneAppReleaseCheck(http: host).latest(maxAge: 60)
            == .failed("The latest release on GitHub has no APK to install."))
    }
}

@Suite struct PhoneAppOfferTests {
    private let all = PhoneAppSetupService.requiredPermissions(sdk: 36)
    private let latest = TestRelease.make(version: "0.1.1")

    private func status(
        installed: Bool = true, version: String? = "0.1.0", sdk: Int? = 36, granted: Bool = true,
        shizukuRunning: Bool = true
    ) -> PhoneAppSetupStatus {
        PhoneAppSetupStatus(
            appInstalled: installed, appVersion: installed ? version : nil, sdk: sdk,
            requiredPermissions: installed ? all : [], grantedPermissions: granted && installed ? all : [],
            shizukuInstalled: true, shizukuRunning: shizukuRunning)
    }

    @Test func aPhoneWithoutTheAppIsOfferedItFromAndroid11() {
        #expect(PhoneAppOffer.decide(status: status(installed: false), latest: nil) == .install)
        #expect(PhoneAppOffer.decide(status: status(installed: false, sdk: 30), latest: latest) == .install)
        #expect(PhoneAppOffer.decide(status: status(installed: false, sdk: 29), latest: latest) == nil)
        // An unread SDK doesn't hide the offer; adb's own refusal would say why.
        #expect(PhoneAppOffer.decide(status: status(installed: false, sdk: nil), latest: nil) == .install)
    }

    @Test func anOlderAppIsOfferedTheUpdateBeforeAnySetUp() {
        #expect(PhoneAppOffer.decide(status: status(granted: false), latest: latest)
            == .update(from: "0.1.0", to: "0.1.1"))
        #expect(PhoneAppOffer.decide(status: status(version: "0.1.1", granted: false), latest: latest)
            == .setUp)
        #expect(PhoneAppOffer.decide(status: status(version: "0.1.1"), latest: latest) == nil)
    }

    @Test func aNewerOrUnknownVersionIsNeverOfferedAnUpdate() {
        #expect(PhoneAppOffer.decide(status: status(version: "0.2.0"), latest: latest) == nil)
        #expect(PhoneAppOffer.decide(status: status(version: nil), latest: latest) == nil)
        #expect(PhoneAppOffer.decide(status: status(), latest: nil) == nil)
    }

    @Test func eachOfferHasItsMenuWords() {
        #expect(PhoneAppOffer.install.menuTitle == "Install Droidective on This Phone…")
        #expect(PhoneAppOffer.update(from: "0.1.0", to: "0.1.1").menuTitle
            == "Update Droidective on This Phone…")
        #expect(PhoneAppOffer.setUp.menuTitle == "Set Up Droidective on This Phone…")
    }

    @Test func aRunInstallsOnlyWhatTheOfferWouldHave() {
        #expect(PhoneAppStep.decide(status: status(installed: false), latest: latest) == .install(latest))
        #expect(PhoneAppStep.decide(status: status(installed: false), latest: nil) == .none)
        #expect(PhoneAppStep.decide(status: status(installed: false, sdk: 29), latest: latest) == .none)
        #expect(PhoneAppStep.decide(status: status(), latest: latest) == .update(latest))
        #expect(PhoneAppStep.decide(status: status(version: "0.1.1", granted: false), latest: latest) == .none)
    }

    @Test func stagesReadAsProgress() {
        #expect(PhoneAppSetupStage.downloading(version: "0.1.1", fraction: nil).label == "Downloading 0.1.1…")
        #expect(PhoneAppSetupStage.downloading(version: "0.1.1", fraction: 0.42).label
            == "Downloading 0.1.1… 42%")
        #expect(PhoneAppSetupStage.verifying.label == "Checking the signature…")
        #expect(PhoneAppSetupStage.installing(version: "0.1.1").label == "Installing 0.1.1…")
    }
}
