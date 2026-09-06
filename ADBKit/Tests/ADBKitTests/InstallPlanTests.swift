import Testing
@testable import ADBKit

@Suite struct InstallPlanTests {
    private func apk(version: String? = "1.0", code: String?) -> ApkInfo {
        var info = ApkInfo(fileName: "app.apk", fileSizeBytes: 1024)
        info.packageName = "com.example.app"
        info.versionName = version
        info.versionCode = code
        return info
    }

    // MARK: - Version codes

    @Test func theCodeIsTheComparisonNotTheName() {
        #expect(InstallPlan.compareVersionCodes("30500", "30201") == .orderedDescending)
        #expect(InstallPlan.compareVersionCodes("30201", "30500") == .orderedAscending)
        #expect(InstallPlan.compareVersionCodes("30500", "30500") == .orderedSame)
    }

    @Test func aMissingOrNonNumericCodeIsNotAnOrdering() {
        #expect(InstallPlan.compareVersionCodes(nil, "1") == nil)
        #expect(InstallPlan.compareVersionCodes("1", nil) == nil)
        #expect(InstallPlan.compareVersionCodes("1.0", "2") == nil)
        #expect(InstallPlan.compareVersionCodes("", "2") == nil)
        #expect(InstallPlan.compareVersionCodes("  ", "2") == nil)
        #expect(InstallPlan.compareVersionCodes("12a", "2") == nil)
    }

    @Test func aCodeTooBigForInt32StillCompares() {
        // Play allows version codes up to 2_100_000_000, and a wrapping parse
        // would order two real builds backwards.
        #expect(InstallPlan.compareVersionCodes("2100000000", "2099999999") == .orderedDescending)
    }

    @Test func surroundingWhitespaceFromDumpsysIsIgnored() {
        #expect(InstallPlan.compareVersionCodes(" 30500 ", "30201") == .orderedDescending)
    }

    // MARK: - Sentinels the device reports for "nothing here"

    @Test func theNotInstalledSentinelsAreNotVersions() {
        // AppInfo.notInstalled fills its fields with em-dashes; dumpsys can
        // also say "null". Neither may read as a version, or a first install
        // would present itself as a reinstall.
        for sentinel in ["\u{2014}", "-", "null", "", "   "] {
            let version = InstalledAppVersion(versionName: sentinel, versionCode: sentinel)
            #expect(version.versionName == nil, "name \(sentinel)")
            #expect(version.versionCode == nil, "code \(sentinel)")
        }
    }

    // MARK: - The decision

    @Test func nothingInstalledIsAPlainInstallWithNoChoiceToMake() {
        let decision = InstallPlan.decide(local: apk(code: "30500"), installed: nil)
        #expect(decision.relation == .notInstalled)
        #expect(decision.primaryTitle == "Install")
        #expect(decision.offersChoice == false)
        #expect(decision.canKeepData)
    }

    @Test func aSentinelOnlyRecordCountsAsNothingInstalled() {
        let decision = InstallPlan.decide(
            local: apk(code: "30500"),
            installed: InstalledAppVersion(versionName: "\u{2014}", versionCode: "\u{2014}"))
        #expect(decision.relation == .notInstalled)
    }

    @Test func aNewerPackageIsAnUpdateThatKeepsData() {
        let decision = InstallPlan.decide(
            local: apk(code: "30500"), installed: InstalledAppVersion(versionCode: "30201"))
        #expect(decision.relation == .update)
        #expect(decision.primaryTitle == "Update")
        #expect(decision.canKeepData)
        #expect(decision.replaceByDefault == false)
        #expect(decision.offersChoice)
    }

    @Test func theSameVersionIsAReinstall() {
        let decision = InstallPlan.decide(
            local: apk(code: "30500"), installed: InstalledAppVersion(versionCode: "30500"))
        #expect(decision.relation == .reinstall)
        #expect(decision.primaryTitle == "Reinstall")
    }

    @Test func aDowngradeCannotKeepDataAndSaysSo() {
        // Android refuses an in-place downgrade, so the only route wipes the
        // app. The sheet has to say that before the click, not after adb does.
        let decision = InstallPlan.decide(
            local: apk(code: "30201"), installed: InstalledAppVersion(versionCode: "30500"))
        #expect(decision.relation == .downgrade)
        #expect(decision.primaryTitle == "Downgrade & Replace")
        #expect(decision.canKeepData == false)
        #expect(decision.keepDataNote == "Not possible for a downgrade")
        #expect(decision.replaceByDefault)
    }

    @Test func anUnreadableApkStillOffersAnInstallAndExplainsTheGap() {
        // No aapt2 on the machine: the package has no version code, so the
        // sheet must degrade rather than disappear.
        let decision = InstallPlan.decide(
            local: apk(version: nil, code: nil), installed: InstalledAppVersion(versionCode: "30500"))
        #expect(decision.relation == .unknown)
        #expect(decision.primaryTitle == "Install")
        #expect(decision.canKeepData)
        #expect(decision.keepDataNote == "Version details need the Android SDK build-tools")
    }

    @Test func aDeviceThatDidNotReportACodeIsUnknownWithoutBlamingTheToolchain() {
        let decision = InstallPlan.decide(
            local: apk(code: "30500"), installed: InstalledAppVersion(versionName: "3.0"))
        #expect(decision.relation == .unknown)
        #expect(decision.keepDataNote == nil)
    }

    // MARK: - Labels

    @Test func theVersionLabelPairsNameAndCodeAndSurvivesEitherMissing() {
        #expect(InstallPlan.versionLabel(name: "3.0.2", code: "30201") == "3.0.2  (30201)")
        #expect(InstallPlan.versionLabel(name: "3.0.2", code: nil) == "3.0.2")
        #expect(InstallPlan.versionLabel(name: nil, code: "30201") == "(30201)")
        #expect(InstallPlan.versionLabel(name: nil, code: nil) == "Unknown")
    }

    // MARK: - Recovery

    @Test func onlyFailuresAnUninstallActuallyFixesOfferTheRetry() {
        #expect(InstallPlan.isResolvedByReplacing("Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]"))
        #expect(InstallPlan.isResolvedByReplacing("Failure [INSTALL_FAILED_VERSION_DOWNGRADE]"))
        #expect(InstallPlan.isResolvedByReplacing("signatures do not match previously installed version"))
    }

    @Test func theFriendlyWordingOfARecoverableCodeIsAlsoRecognised() {
        // The App layer shows `friendlyReason`'s prose, not adb's code, and a
        // caller that reads a job's message rather than its raw output would
        // silently never offer the recovery. That is exactly what happened:
        // the codes matched, the sentence the user was looking at did not.
        for code in ["INSTALL_FAILED_UPDATE_INCOMPATIBLE", "INSTALL_FAILED_VERSION_DOWNGRADE"] {
            let friendly = AppInstallService.friendlyReason(code)
            #expect(
                InstallPlan.isResolvedByReplacing(friendly),
                "friendly wording of \(code) is not recognised: \(friendly)")
        }
    }

    @Test func theFriendlyWordingOfAnUnrecoverableCodeStaysUnrecoverable() {
        for code in ["INSTALL_FAILED_INSUFFICIENT_STORAGE", "INSTALL_FAILED_NO_MATCHING_ABIS"] {
            #expect(!InstallPlan.isResolvedByReplacing(AppInstallService.friendlyReason(code)))
        }
    }

    @Test func aFailureAnUninstallCannotFixDoesNotOfferIt() {
        // Wiping the app buys nothing here, and offering it would destroy data
        // for no reason.
        #expect(!InstallPlan.isResolvedByReplacing("Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]"))
        #expect(!InstallPlan.isResolvedByReplacing("Failure [INSTALL_FAILED_NO_MATCHING_ABIS]"))
        #expect(!InstallPlan.isResolvedByReplacing("Failure [INSTALL_PARSE_FAILED_NO_CERTIFICATES]"))
        #expect(!InstallPlan.isResolvedByReplacing(""))
    }
}
