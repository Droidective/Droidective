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

    @Test func aSignerIsNamedByItsCommonName() {
        #expect(ApkSigner(subjectDN: "CN=Android Debug, OU=Android, O=Android, C=US").commonName
            == "Android Debug")
        // CN need not come first, and an escaped comma belongs to the value.
        #expect(ApkSigner(subjectDN: #"O=Acme, CN=Acme\, Inc., C=US"#).commonName == "Acme, Inc.")
        // An organisation whose name merely ends in "CN" is not a CN.
        #expect(ApkSigner(subjectDN: "O=ACN=x, C=US").commonName == "O=ACN=x, C=US")
        #expect(ApkSigner(subjectDN: "O=Acme, C=US").commonName == "O=Acme, C=US")
        #expect(ApkSigner().commonName == nil)
    }

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

    @Test func readsTheV3SignerFormNewerApksignerPrints() {
        // Captured from build-tools 37.0.0's `apksigner verify -v --print-certs`
        // on a debug-signed APK: a v3 signature labels its lines "V3.0 Signer:"
        // and prints no numbered "Signer #1" block at all. The public-key
        // digest is zeroed (hex after "key" trips gitleaks); its line stays to
        // show it is not mistaken for the certificate's.
        let real = """
        Verifies
        Verified using v1 scheme (JAR signing): true
        Verified using v2 scheme (APK Signature Scheme v2): true
        Verified using v3 scheme (APK Signature Scheme v3): true
        Verified using v3.1 scheme (APK Signature Scheme v3.1): false
        Number of signers: 1
        V3.0 Signer: certificate DN: C=US, O=Android, CN=Android Debug
        V3.0 Signer: certificate SHA-256 digest: 2bd4b6fb61e5357c2a41e343dd36105256fc54094b7e2ee3a7b4fb741918afd8
        V3.0 Signer: certificate SHA-1 digest: 3a50a34eb38c24dd4d07963f4b3890d49403fc34
        V3.0 Signer: key algorithm: RSA
        V3.0 Signer: public key SHA-256 digest: 0000000000000000000000000000000000000000000000000000000000000000
        """
        let result = ApkSignature.parse(real)
        #expect(result.schemes == ["v1", "v2", "v3"])
        #expect(result.signers == [ApkSigner(
            subjectDN: "C=US, O=Android, CN=Android Debug",
            sha256: "2bd4b6fb61e5357c2a41e343dd36105256fc54094b7e2ee3a7b4fb741918afd8",
            sha1: "3a50a34eb38c24dd4d07963f4b3890d49403fc34")])
        #expect(result.signers.first?.commonName == "Android Debug")
    }

    @Test func aRotatedV3KeyIsTwoSignersAndARepeatedOneIsOne() {
        let output = """
        V3.0 Signer: certificate DN: CN=Old
        V3.0 Signer: certificate SHA-256 digest: aaaa
        V3.1 Signer (minSdkVersion=33, maxSdkVersion=2147483647): certificate DN: CN=New
        V3.1 Signer (minSdkVersion=33, maxSdkVersion=2147483647): certificate SHA-256 digest: bbbb
        V4 Signer: certificate DN: CN=Old
        V4 Signer: certificate SHA-256 digest: aaaa
        """
        let signers = ApkSignature.parse(output).signers
        #expect(signers.map(\.subjectDN) == ["CN=Old", "CN=New"])
    }

    @Test func emptyOutputYieldsNoSchemesOrSigners() {
        let result = ApkSignature.parse("")
        #expect(result.schemes.isEmpty)
        #expect(result.signers.isEmpty)
    }
}
