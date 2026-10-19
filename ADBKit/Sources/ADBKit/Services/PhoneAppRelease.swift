import Foundation

/// A published release of Droidective for Android, and the APK it ships.
public struct PhoneAppRelease: Sendable, Equatable, Codable {
    /// "0.1.1": the tag without its `v`, which is also the app's `versionName`.
    public let version: String
    public let apkName: String
    public let apkURL: String
    public let apkSize: Int
    /// GitHub's `sha256:…` for the APK, when the release carries one.
    public let apkDigest: String?

    public init(version: String, apkName: String, apkURL: String, apkSize: Int, apkDigest: String?) {
        self.version = version
        self.apkName = apkName
        self.apkURL = apkURL
        self.apkSize = apkSize
        self.apkDigest = apkDigest
    }
}

/// Where Droidective for Android's releases come from, and how the Mac knows
/// one is genuine.
///
/// Unlike the managed tools, which pin an exact tag so a hijacked "latest"
/// release is never pulled, this has to follow the latest release: that is
/// what installing and updating the app means. What makes that safe is the
/// signing certificate. Every release is signed with one key, its certificate
/// is pinned here, and an APK that names any other is never installed. Android
/// enforces the same signer on an update by itself, but not on a first
/// install, which is the case the pin is for.
public enum PhoneAppReleases {
    public static let latestURL =
        URL(string: "https://api.github.com/repos/Droidective/droidective-android/releases/latest")!

    /// SHA-256 of the release signing certificate, lowercase hex. The Android
    /// repo commits the same value as `release-cert.sha256`, and its release
    /// script refuses an APK signed by anything else.
    public static let signingCertificateSHA256 =
        "2b059f5e11610a1dd948e777121edf1a953cf5dcdf0e86ade08d6a2787d6d8b0"

    /// Android 11, the app's `minSdk`.
    public static let minimumSdk = 30

    /// The release in a `releases/latest` response: a `vX.Y.Z` tag with the APK
    /// named for it, `droidective-android-X.Y.Z.apk`, which is what the
    /// release workflow publishes. nil for a release that has neither, so one
    /// made some other way is never installed.
    public static func release(from data: Data) throws -> PhoneAppRelease? {
        let release = try ManagedToolReleases.parse(data)
        guard release.tagName.hasPrefix("v") else { return nil }
        let version = String(release.tagName.dropFirst())
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let digits = Set("0123456789")
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(digits.contains) })
        else { return nil }
        let name = "droidective-android-\(version).apk"
        guard let apk = release.assets.first(where: { $0.name == name }) else { return nil }
        return PhoneAppRelease(
            version: version, apkName: apk.name, apkURL: apk.downloadURL, apkSize: apk.size,
            apkDigest: apk.digest)
    }

    /// Why a downloaded APK can't be installed, or nil when it can: it must
    /// match the release's digest when there is one, and every signer must
    /// name the pinned certificate.
    public static func problem(apkAt url: URL, release: PhoneAppRelease) -> String? {
        if let expected = release.apkDigest, expected.hasPrefix("sha256:") {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                return "Couldn't read the downloaded APK."
            }
            let want = String(expected.dropFirst("sha256:".count)).lowercased()
            guard ApkSigningBlock.sha256Hex(data) == want else {
                return "The download doesn't match the release's checksum, so it wasn't installed."
            }
        }
        let signers: [String]
        do {
            signers = try ApkSigningBlock.certificateDigests(apkAt: url)
        } catch {
            return "Couldn't read the downloaded APK's signature: \(error.localizedDescription)"
        }
        guard signers.allSatisfy({ $0 == signingCertificateSHA256 }) else {
            return "The download isn't signed with Droidective's release key, so it wasn't installed."
        }
        return nil
    }
}

/// The latest Droidective for Android release, asked of GitHub at most once
/// per `maxAge`.
///
/// The device menu asks every time it opens, and anonymous GitHub API calls
/// are capped at 60 an hour per address, so answers are kept. A failure is
/// kept for at most `failureRetry`, so a network blip doesn't hide updates for
/// hours; callers asking at once share one request.
public actor PhoneAppReleaseCheck {
    public enum Lookup: Sendable, Equatable {
        case found(PhoneAppRelease)
        case failed(String)

        public var release: PhoneAppRelease? {
            if case .found(let release) = self { return release }
            return nil
        }
    }

    public static let failureRetry: TimeInterval = 15 * 60
    /// How long the device menu trusts an answer.
    public static let menuMaxAge: TimeInterval = 6 * 60 * 60
    /// Fresher for the set-up sheet: opening it is asking.
    public static let sheetMaxAge: TimeInterval = 10 * 60

    private let http: any HTTPFetching
    private let now: @Sendable () -> Date
    private var last: (lookup: Lookup, at: Date)?
    private var inFlight: Task<Lookup, Never>?

    public init(
        http: any HTTPFetching = URLSessionHTTP(), now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.http = http
        self.now = now
    }

    public func latest(maxAge: TimeInterval) async -> Lookup {
        if let last {
            let age = now().timeIntervalSince(last.at)
            let keep = last.lookup.release == nil ? min(maxAge, Self.failureRetry) : maxAge
            if age >= 0, age < keep { return last.lookup }
        }
        if let inFlight { return await inFlight.value }
        let task = Task { await fetch() }
        inFlight = task
        let lookup = await task.value
        inFlight = nil
        last = (lookup, now())
        return lookup
    }

    private func fetch() async -> Lookup {
        do {
            let data = try await http.data(from: PhoneAppReleases.latestURL)
            guard let release = try PhoneAppReleases.release(from: data) else {
                return .failed("The latest release on GitHub has no APK to install.")
            }
            return .found(release)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// What the device menu offers for Droidective for Android on one phone.
public enum PhoneAppOffer: Sendable, Equatable {
    /// The app isn't on the phone, and the phone can run it.
    case install
    /// The phone has an older version than the latest release.
    case update(from: String, to: String)
    /// The app is current, and something one click fixes is still undone.
    case setUp

    public var menuTitle: String {
        switch self {
        case .install: "Install Droidective on This Phone…"
        case .update: "Update Droidective on This Phone…"
        case .setUp: "Set Up Droidective on This Phone…"
        }
    }

    /// nil when there's nothing to offer. Install is offered without knowing
    /// the latest release, so a phone without the app costs no network request;
    /// the sheet says so if GitHub can't be reached. An installed version newer
    /// than the latest release is a development build, and is left alone.
    public static func decide(
        status: PhoneAppSetupStatus, latest: PhoneAppRelease?
    ) -> PhoneAppOffer? {
        guard status.appInstalled else {
            if let sdk = status.sdk, sdk < PhoneAppReleases.minimumSdk { return nil }
            return .install
        }
        if let latest, let installed = status.appVersion,
           ManagedToolReleases.isNewer(latest.version, than: installed) {
            return .update(from: installed, to: latest.version)
        }
        return status.needsSetup ? .setUp : nil
    }
}

/// What a set-up run does about the app itself before granting anything.
public enum PhoneAppStep: Sendable, Equatable {
    case none
    case install(PhoneAppRelease)
    case update(PhoneAppRelease)

    public static func decide(status: PhoneAppSetupStatus, latest: PhoneAppRelease?) -> PhoneAppStep {
        guard let latest else { return .none }
        switch PhoneAppOffer.decide(status: status, latest: latest) {
        case .install: return .install(latest)
        case .update: return .update(latest)
        case .setUp, nil: return .none
        }
    }
}

/// Where a set-up run is, for the sheet's progress line.
public enum PhoneAppSetupStage: Sendable, Equatable {
    case downloading(version: String, fraction: Double?)
    case verifying
    case installing(version: String)
    case granting
    case startingShizuku

    public var label: String {
        switch self {
        case .downloading(let version, let fraction):
            guard let fraction else { return "Downloading \(version)…" }
            return "Downloading \(version)… \(Int((fraction * 100).rounded()))%"
        case .verifying: return "Checking the signature…"
        case .installing(let version): return "Installing \(version)…"
        case .granting: return "Granting permissions…"
        case .startingShizuku: return "Starting Shizuku…"
        }
    }
}
