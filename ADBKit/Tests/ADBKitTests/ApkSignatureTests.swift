import Foundation
import Testing
@testable import ADBKit

@Suite struct ApkSignatureTests {
    /// A representative slice of `apksigner verify -v --print-certs` output.
    private let sample = """
    Verifies
    Verified using v1 scheme (JAR signing): true
    Verified using v2 scheme (APK Signature Scheme v2): true
    Verified using v3 scheme (APK Signature Scheme v3): false
    Verified using v4 scheme (APK Signature Scheme v4): false
    Number of signers: 1
    Signer #1 certificate DN: CN=Android Debug, OU=Android, O=Android, C=US
    Signer #1 certificate SHA-256 digest: 3a2b1c0d4e5f6a7b8c9d0e1f
    Signer #1 certificate SHA-1 digest: 0011223344556677
    Signer #1 certificate MD5 digest: ffeeddccbbaa9988
    """

    @Test func parsesOnlyEnabledSchemes() {
        // v3/v4 are `false` here and must be excluded.
        #expect(ApkSignature.parse(sample).schemes == ["v1", "v2"])
    }

    @Test func parsesSignerDnAndDigests() {
        let signers = ApkSignature.parse(sample).signers
        #expect(signers.count == 1)
        #expect(signers.first?.subjectDN == "CN=Android Debug, OU=Android, O=Android, C=US")
        #expect(signers.first?.sha256 == "3a2b1c0d4e5f6a7b8c9d0e1f")
        #expect(signers.first?.sha1 == "0011223344556677")
    }

    @Test func groupsMultipleSignersByIndex() {
        let output = """
        Signer #1 certificate DN: CN=One
        Signer #1 certificate SHA-256 digest: aaaa
        Signer #2 certificate DN: CN=Two
        Signer #2 certificate SHA-256 digest: bbbb
        """
        let signers = ApkSignature.parse(output).signers
        #expect(signers.count == 2)
        #expect(signers[0].subjectDN == "CN=One")
        #expect(signers[0].sha256 == "aaaa")
        #expect(signers[1].subjectDN == "CN=Two")
        #expect(signers[1].sha256 == "bbbb")
    }

    @Test func emptyOutputYieldsNoSchemesOrSigners() {
        let result = ApkSignature.parse("")
        #expect(result.schemes.isEmpty)
        #expect(result.signers.isEmpty)
    }
}
