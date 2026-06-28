import Foundation

/// Keystore details for signing a release APK. The passwords are handed to
/// apksigner through a 0600 temp file (`--ks-pass file:`), never on the command
/// line, so they don't leak into the process list or the command log.
public struct KeystoreCredentials: Sendable, Equatable {
    public var keystorePath: String
    public var storePassword: String
    public var keyAlias: String?
    public var keyPassword: String?

    public init(keystorePath: String, storePassword: String, keyAlias: String? = nil, keyPassword: String? = nil) {
        self.keystorePath = keystorePath
        self.storePassword = storePassword
        self.keyAlias = keyAlias
        self.keyPassword = keyPassword
    }

    /// The standard Android debug keystore (`~/.android/debug.keystore`), whose
    /// password and alias are public constants — fine to pass as-is.
    public static func debug(keystorePath: String) -> KeystoreCredentials {
        KeystoreCredentials(
            keystorePath: keystorePath, storePassword: "android",
            keyAlias: "androiddebugkey", keyPassword: "android")
    }
}

/// A keystore to create with `keytool -genkeypair`. The passwords go to keytool
/// through 0600 temp files (`-storepass:file` / `-keypass:file`), never argv.
public struct NewKeystore: Sendable, Equatable {
    public var path: String
    public var alias: String
    public var storePassword: String
    public var keyPassword: String?
    public var commonName: String
    public var organization: String?
    public var validityDays: Int

    public init(
        path: String, alias: String, storePassword: String, keyPassword: String? = nil,
        commonName: String, organization: String? = nil, validityDays: Int = 10_000
    ) {
        self.path = path
        self.alias = alias
        self.storePassword = storePassword
        self.keyPassword = keyPassword
        self.commonName = commonName
        self.organization = organization
        self.validityDays = validityDays
    }

    /// The `-dname` value, e.g. `CN=My App, O=Acme`. A single argv element (no
    /// shell), so spaces and commas are safe.
    var distinguishedName: String {
        var parts = ["CN=\(commonName)"]
        if let organization, !organization.isEmpty { parts.append("O=\(organization)") }
        return parts.joined(separator: ", ")
    }
}

public struct SignResult: Sendable, Equatable {
    public var ok: Bool
    public var message: String
    public var signature: ApkSignature.Result?

    public init(ok: Bool, message: String, signature: ApkSignature.Result? = nil) {
        self.ok = ok
        self.message = message
        self.signature = signature
    }
}

/// Aligns and signs an APK: `zipalign` (page-align) → `apksigner sign` → verify.
/// zipalign comes from the SDK build-tools; apksigner runs as `java -jar` so it
/// doesn't depend on the wrapper finding a JDK. All paths are argument-vector
/// elements (no shell); passwords go through a temp file.
public struct ApkSigningService: Sendable {
    public enum SigningError: Error, LocalizedError, Equatable {
        case toolMissing(String)
        case stepFailed(String)

        public var errorDescription: String? {
            switch self {
            case .toolMissing(let what): "\(what) isn't available."
            case .stepFailed(let reason): reason
            }
        }
    }

    let toolchain: ApkToolchain
    let runner: any ProcessRunning

    public init(toolchain: ApkToolchain, runner: any ProcessRunning = SystemProcessRunner()) {
        self.toolchain = toolchain
        self.runner = runner
    }

    /// Align `input` into `output`, then sign `output` in place and verify it.
    /// `output` must differ from `input` (zipalign can't align in place).
    public func sign(input: String, output: String, credentials: KeystoreCredentials) async throws -> SignResult {
        guard let zipalign = await toolchain.zipalign() else { throw SigningError.toolMissing("zipalign (Android SDK build-tools)") }
        guard let java = await toolchain.java(), let jar = await toolchain.apksignerJar() else {
            throw SigningError.toolMissing("apksigner (Android SDK build-tools + Java)")
        }

        let aligned = await runner.run(
            executable: zipalign, arguments: Self.zipalignArguments(input: input, output: output),
            timeout: .seconds(120), maxOutputBytes: 1 << 20)
        guard aligned.exitCode == 0 else { throw SigningError.stepFailed("zipalign failed: \(aligned.stderrText)") }

        let storePassFile = try writeSecret(credentials.storePassword)
        let keyPassFile = try writeSecret(credentials.keyPassword ?? credentials.storePassword)
        defer {
            try? FileManager.default.removeItem(atPath: storePassFile)
            try? FileManager.default.removeItem(atPath: keyPassFile)
        }

        let signArgs = Self.signArguments(
            jar: jar, keystore: credentials.keystorePath, storePassFile: storePassFile,
            keyAlias: credentials.keyAlias, keyPassFile: keyPassFile, target: output)
        let signed = await runner.run(executable: java, arguments: signArgs, timeout: .seconds(120), maxOutputBytes: 1 << 20)
        guard signed.exitCode == 0 else { throw SigningError.stepFailed("apksigner failed: \(signed.stderrText)") }

        let verify = await runner.run(
            executable: java, arguments: Self.verifyArguments(jar: jar, target: output),
            timeout: .seconds(60), maxOutputBytes: 4 << 20)
        return SignResult(
            ok: true,
            message: "Signed \(URL(fileURLWithPath: output).lastPathComponent)",
            signature: ApkSignature.parse(verify.stdoutText))
    }

    /// Create a self-signed keystore with `keytool -genkeypair` (RSA 2048), so a
    /// release key can be made and used to sign without leaving the app. Returns
    /// the credentials ready to pass straight to `sign`.
    public func createKeystore(_ spec: NewKeystore) async throws -> KeystoreCredentials {
        guard let keytool = await toolchain.keytool() else {
            throw SigningError.toolMissing("keytool (Java runtime)")
        }
        let storePassFile = try writeSecret(spec.storePassword)
        let keyPassFile = try writeSecret(spec.keyPassword ?? spec.storePassword)
        defer {
            try? FileManager.default.removeItem(atPath: storePassFile)
            try? FileManager.default.removeItem(atPath: keyPassFile)
        }
        let result = await runner.run(
            executable: keytool,
            arguments: Self.createKeystoreArguments(spec: spec, storePassFile: storePassFile, keyPassFile: keyPassFile),
            timeout: .seconds(120), maxOutputBytes: 1 << 20)
        guard result.exitCode == 0 else {
            throw SigningError.stepFailed("keytool failed: \(result.stderrText.isEmpty ? result.stdoutText : result.stderrText)")
        }
        return KeystoreCredentials(
            keystorePath: spec.path, storePassword: spec.storePassword,
            keyAlias: spec.alias, keyPassword: spec.keyPassword)
    }

    /// Verify an already-signed APK.
    public func verify(apkPath: String) async throws -> ApkSignature.Result {
        guard let java = await toolchain.java(), let jar = await toolchain.apksignerJar() else {
            throw SigningError.toolMissing("apksigner (Android SDK build-tools + Java)")
        }
        let output = await runner.run(
            executable: java, arguments: Self.verifyArguments(jar: jar, target: apkPath),
            timeout: .seconds(60), maxOutputBytes: 4 << 20)
        return ApkSignature.parse(output.stdoutText)
    }

    // MARK: - Pure argument builders (unit-tested)

    /// `zipalign -f -p 4 <in> <out>` — overwrite, page-align uncompressed .so.
    static func zipalignArguments(input: String, output: String) -> [String] {
        ["-f", "-p", "4", input, output]
    }

    /// `java -jar apksigner.jar sign --ks … --ks-pass file:… [--ks-key-alias …]
    /// --key-pass file:… <apk>`. Passwords are referenced by file, not value.
    static func signArguments(
        jar: String, keystore: String, storePassFile: String,
        keyAlias: String?, keyPassFile: String, target: String
    ) -> [String] {
        var args = ["-jar", jar, "sign", "--ks", keystore, "--ks-pass", "file:\(storePassFile)"]
        if let keyAlias { args += ["--ks-key-alias", keyAlias] }
        args += ["--key-pass", "file:\(keyPassFile)", target]
        return args
    }

    static func verifyArguments(jar: String, target: String) -> [String] {
        ["-jar", jar, "verify", "-v", "--print-certs", target]
    }

    /// `keytool -genkeypair -noprompt -keystore … -alias … -keyalg RSA -keysize
    /// 2048 -validity … -storepass:file … -keypass:file … -dname …`. Passwords are
    /// referenced by file; `-noprompt` + a supplied `-dname` keep it non-interactive.
    static func createKeystoreArguments(spec: NewKeystore, storePassFile: String, keyPassFile: String) -> [String] {
        [
            "-genkeypair", "-noprompt",
            "-keystore", spec.path, "-alias", spec.alias,
            "-keyalg", "RSA", "-keysize", "2048",
            "-validity", String(spec.validityDays),
            "-storepass:file", storePassFile,
            "-keypass:file", keyPassFile,
            "-dname", spec.distinguishedName,
        ]
    }

    /// Write a secret to a 0600 temp file and return its path. Callers delete it.
    private func writeSecret(_ secret: String) throws -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("apksign-\(UUID().uuidString)")
        try secret.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        return path.path
    }
}
