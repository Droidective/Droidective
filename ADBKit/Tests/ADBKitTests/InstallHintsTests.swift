import Foundation
import Testing

@testable import ADBKit

/// The hint *is* the whole answer — the app never installs a tool itself — so a
/// wrong one is worse than none. These pin the wording and the distribution
/// detection, neither of which anyone can eyeball on a machine that already has
/// adb.
@Suite struct InstallHintsTests {
    // MARK: - Reading /etc/os-release

    @Test func readsQuotedAndBareValues() {
        let fields = InstallHints.parseOSRelease(
            """
            NAME="Ubuntu"
            VERSION_ID="24.04"
            ID=ubuntu
            ID_LIKE=debian
            """)
        #expect(fields["NAME"] == "Ubuntu")
        #expect(fields["ID"] == "ubuntu")
        #expect(fields["ID_LIKE"] == "debian")
    }

    /// Written by a package manager, and seen with CRLF in container images.
    @Test func survivesCRLFAndCommentsAndBlanks() {
        let fields = InstallHints.parseOSRelease("# a comment\r\n\r\nID=fedora\r\nVERSION_ID=40\r\n")
        #expect(fields["ID"] == "fedora")
        #expect(fields["VERSION_ID"] == "40")
    }

    @Test func aFileItCannotReadNamesNoFamily() {
        #expect(InstallHints.linuxFamily(osRelease: "") == .unknown)
        #expect(InstallHints.linuxFamily(osRelease: "not=a=distro") == .unknown)
    }

    // MARK: - Which family

    @Test func recognisesTheFourFamiliesByID() {
        #expect(InstallHints.linuxFamily(osRelease: "ID=debian") == .debian)
        #expect(InstallHints.linuxFamily(osRelease: "ID=fedora") == .fedora)
        #expect(InstallHints.linuxFamily(osRelease: "ID=arch") == .arch)
        #expect(InstallHints.linuxFamily(osRelease: "ID=opensuse-tumbleweed") == .suse)
    }

    /// The case that matters more than it looks: Mint, Pop!_OS, Zorin and
    /// elementary all report their own `ID` and lean on `ID_LIKE`, and every one
    /// of them installs adb with apt.
    @Test func fallsBackToIDLikeForTheDerivatives() {
        #expect(InstallHints.linuxFamily(osRelease: "ID=linuxmint\nID_LIKE=ubuntu") == .debian)
        #expect(InstallHints.linuxFamily(osRelease: "ID=pop\nID_LIKE=\"ubuntu debian\"") == .debian)
        #expect(InstallHints.linuxFamily(osRelease: "ID=manjaro\nID_LIKE=arch") == .arch)
        #expect(InstallHints.linuxFamily(osRelease: "ID=rocky\nID_LIKE=\"rhel centos fedora\"") == .fedora)
    }

    /// `ID` wins over `ID_LIKE` — a distribution that names itself is not
    /// guessing.
    @Test func theDistributionsOwnIDBeatsWhatItSaysItIsLike() {
        #expect(InstallHints.linuxFamily(osRelease: "ID=fedora\nID_LIKE=debian") == .fedora)
    }

    // MARK: - The command

    @Test func everyKnownFamilyHasACommandAndTheUnknownOneDoesNot() {
        for family in InstallHints.LinuxFamily.allCases where family != .unknown {
            let command = InstallHints.adbCommand(for: family)
            #expect(command != nil, "\(family.rawValue) has no install command")
            #expect(command?.contains("sudo") == true, "\(family.rawValue) should be a root install")
        }
        // Guessing a package manager is worse than naming the package.
        #expect(InstallHints.adbCommand(for: .unknown) == nil)
    }

    @Test func theDebianCommandIsTheOneThatWorksOnUbuntu() {
        #expect(InstallHints.adbCommand(for: .debian) == "sudo apt install android-tools-adb")
    }

    // MARK: - The sentence

    /// Whatever the platform, the hint has to say what is wrong and what to do
    /// — a hint that only says "adb is missing" leaves the reader where it
    /// found them.
    @Test func theHintIsActionableOnEveryPlatform() {
        let hint = InstallHints.adb(osRelease: "ID=ubuntu")
        #expect(!hint.isEmpty)
        #expect(hint.lowercased().contains("adb") || hint.lowercased().contains("platform-tools"))

        #if os(Linux)
        #expect(hint.contains("sudo apt install android-tools-adb"))
        #expect(InstallHints.adb(osRelease: "ID=fedora").contains("dnf"))
        // An unrecognised distribution names the package rather than inventing
        // a command that would fail.
        let unknown = InstallHints.adb(osRelease: "ID=something-new")
        #expect(!unknown.contains("sudo"))
        #expect(unknown.contains("android-tools"))
        #elseif os(Windows)
        #expect(hint.contains("winget") || hint.contains("PATH"))
        #else
        #expect(hint.contains("developer.android.com"))
        #endif
    }
}
