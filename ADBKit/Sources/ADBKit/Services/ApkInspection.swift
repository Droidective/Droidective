import Foundation

/// Identifying details parsed from a local APK, shown in the install prompt.
/// `label`/`packageName`/… are nil when aapt2 isn't available — the file name
/// and size are always present.
public struct ApkInfo: Sendable, Equatable {
    public var fileName: String
    public var fileSizeBytes: Int
    public var label: String?
    public var packageName: String?
    public var versionName: String?
    public var versionCode: String?
    public var minSdk: String?
    public var targetSdk: String?

    public init(
        fileName: String,
        fileSizeBytes: Int,
        label: String? = nil,
        packageName: String? = nil,
        versionName: String? = nil,
        versionCode: String? = nil,
        minSdk: String? = nil,
        targetSdk: String? = nil
    ) {
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.label = label
        self.packageName = packageName
        self.versionName = versionName
        self.versionCode = versionCode
        self.minSdk = minSdk
        self.targetSdk = targetSdk
    }

    /// True when aapt2 resolved at least the app label, package, or version —
    /// i.e. there's more to show than the file name and size.
    public var hasDetails: Bool {
        label != nil || packageName != nil || versionName != nil
    }
}

/// Parses `aapt2 dump badging` output. Pure and isolated so it's unit-tested
/// without aapt2 installed.
public enum ApkBadging {
    public struct Fields: Sendable, Equatable {
        public var label: String?
        public var packageName: String?
        public var versionName: String?
        public var versionCode: String?
        public var minSdk: String?
        public var targetSdk: String?
        public var permissions: [String] = []
        public var features: [String] = []
        public var isDebuggable = false
    }

    /// Pull the fields out of badging text. Identity fields each live on their
    /// own line, e.g. `package: name='com.x' versionCode='1' versionName='1.0'`
    /// and `application-label:'My App'`; permissions/features repeat as
    /// `uses-permission: name='…'`; `application-debuggable` appears only when
    /// the app is debuggable.
    public static func parse(_ output: String) -> Fields {
        Fields(
            label: regexFirstGroup(output, #"application-label:'([^']*)'"#)
                ?? regexFirstGroup(output, #"application: label='([^']*)'"#),
            packageName: regexFirstGroup(output, #"package: name='([^']*)'"#),
            versionName: regexFirstGroup(output, #"versionName='([^']*)'"#),
            versionCode: regexFirstGroup(output, #"versionCode='([^']*)'"#),
            minSdk: regexFirstGroup(output, #"sdkVersion:'([^']*)'"#),
            targetSdk: regexFirstGroup(output, #"targetSdkVersion:'([^']*)'"#),
            permissions: regexAllGroups(output, #"uses-permission(?:-sdk-\d+)?: name='([^']*)'"#),
            features: regexAllGroups(output, #"uses-feature(?:-not-required)?: name='([^']*)'"#),
            isDebuggable: output.contains("application-debuggable")
        )
    }
}

/// One signer certificate from `apksigner verify --print-certs`.
public struct ApkSigner: Sendable, Equatable {
    public var subjectDN: String?
    public var sha256: String?
    public var sha1: String?

    public init(subjectDN: String? = nil, sha256: String? = nil, sha1: String? = nil) {
        self.subjectDN = subjectDN
        self.sha256 = sha256
        self.sha1 = sha1
    }
}

/// Deep inspection of an APK — identity + permissions + signing — assembled by
/// `ApkInspectionService` for the inspector view. Degrades gracefully: with no
/// build-tools it's just `info`; with no JDK the `signers` stay empty.
public struct ApkReport: Sendable, Equatable {
    public var info: ApkInfo
    public var permissions: [String]
    public var features: [String]
    public var isDebuggable: Bool
    public var signatureSchemes: [String]
    public var signers: [ApkSigner]

    public init(
        info: ApkInfo,
        permissions: [String] = [],
        features: [String] = [],
        isDebuggable: Bool = false,
        signatureSchemes: [String] = [],
        signers: [ApkSigner] = []
    ) {
        self.info = info
        self.permissions = permissions
        self.features = features
        self.isDebuggable = isDebuggable
        self.signatureSchemes = signatureSchemes
        self.signers = signers
    }
}

/// Parses `apksigner verify -v --print-certs` output. Pure and isolated so it's
/// unit-tested without apksigner installed.
public enum ApkSignature {
    public struct Result: Sendable, Equatable {
        public var schemes: [String]
        public var signers: [ApkSigner]

        public init(schemes: [String] = [], signers: [ApkSigner] = []) {
            self.schemes = schemes
            self.signers = signers
        }
    }

    public static func parse(_ output: String) -> Result {
        Result(schemes: parseSchemes(output), signers: parseSigners(output))
    }

    /// "Verified using v2 scheme (APK Signature Scheme v2): true" → "v2".
    private static func parseSchemes(_ output: String) -> [String] {
        output.components(separatedBy: .newlines).compactMap {
            regexFirstGroup($0, #"Verified using (v\d(?:\.\d)?) scheme[^:]*:\s*true"#)
        }
    }

    /// Lines tagged with a signer index — "Signer #1 certificate DN: …",
    /// "…SHA-256 digest: …" — grouped into one `ApkSigner` per index.
    private static func parseSigners(_ output: String) -> [ApkSigner] {
        var byIndex: [Int: ApkSigner] = [:]
        for line in output.components(separatedBy: .newlines) {
            guard let indexText = regexFirstGroup(line, #"Signer #(\d+) certificate"#),
                  let index = Int(indexText) else { continue }
            var signer = byIndex[index] ?? ApkSigner()
            if let dn = regexFirstGroup(line, #"certificate DN:\s*(.+)$"#) {
                signer.subjectDN = dn.trimmingCharacters(in: .whitespaces)
            }
            if let sha = regexFirstGroup(line, #"SHA-256 digest:\s*([0-9a-fA-F]+)"#) { signer.sha256 = sha }
            if let sha = regexFirstGroup(line, #"SHA-1 digest:\s*([0-9a-fA-F]+)"#) { signer.sha1 = sha }
            byIndex[index] = signer
        }
        return byIndex.sorted { $0.key < $1.key }.map(\.value)
    }
}

/// First capture group of `pattern` in `text`, or nil (also nil for an empty
/// capture, e.g. `versionName=''`).
private func regexFirstGroup(_ text: String, _ pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let full = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: full), match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text) else { return nil }
    let value = String(text[range])
    return value.isEmpty ? nil : value
}

/// Every first-capture-group match of `pattern`, de-duplicated, order preserved.
private func regexAllGroups(_ text: String, _ pattern: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let full = NSRange(text.startIndex..., in: text)
    var seen = Set<String>()
    var result: [String] = []
    for match in regex.matches(in: text, range: full) where match.numberOfRanges > 1 {
        guard let range = Range(match.range(at: 1), in: text) else { continue }
        let value = String(text[range])
        if !value.isEmpty, seen.insert(value).inserted { result.append(value) }
    }
    return result
}
