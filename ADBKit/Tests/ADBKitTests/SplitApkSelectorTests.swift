import Foundation
import Testing

@testable import ADBKit

@Suite struct DeviceSpecTests {
    @Test func parseReadsAbiListDensityAndLanguage() {
        let spec = DeviceSpec.parse(props: [
            "ro.product.cpu.abilist": "arm64-v8a,armeabi-v7a,armeabi",
            "ro.sf.lcd_density": "420",
            "persist.sys.locale": "pt-BR",
        ])
        #expect(spec.abis == ["arm64-v8a", "armeabi-v7a", "armeabi"])
        #expect(spec.densityDpi == 420)
        #expect(spec.languages == ["pt"])
    }

    @Test func parseFallsBackToTheLegacySingleAbiProperties() {
        let spec = DeviceSpec.parse(props: [
            "ro.product.cpu.abi": "armeabi-v7a",
            "ro.product.cpu.abi2": "armeabi",
        ])
        #expect(spec.abis == ["armeabi-v7a", "armeabi"])
    }

    @Test func parseFallsBackAcrossDensityAndLocaleProperties() {
        let emulator = DeviceSpec.parse(props: ["qemu.sf.lcd_density": "560", "ro.product.locale": "en_US"])
        #expect(emulator.densityDpi == 560)
        #expect(emulator.languages == ["en"])
        // The vendor property is only consulted when the standard one is absent.
        let both = DeviceSpec.parse(props: ["ro.sf.lcd_density": "320", "qemu.sf.lcd_density": "560"])
        #expect(both.densityDpi == 320)
    }

    @Test func parseSurvivesAMissingOrMalformedDump() {
        let empty = DeviceSpec.parse(props: [:])
        #expect(empty.abis.isEmpty)
        #expect(empty.densityDpi == 0)
        #expect(empty.languages.isEmpty)
        // A non-numeric density is dropped rather than crashing or reading 0
        // out of a bad Int conversion chain.
        #expect(DeviceSpec.parse(props: ["ro.sf.lcd_density": "unknown"]).densityDpi == 0)
        // A one-letter locale isn't a language tag.
        #expect(DeviceSpec.parse(props: ["persist.sys.locale": "x"]).languages.isEmpty)
    }

    @Test func parseDeduplicatesLanguagesAcrossProperties() {
        let spec = DeviceSpec.parse(props: [
            "persist.sys.locale": "en-GB",
            "ro.product.locale": "en_US",
        ])
        #expect(spec.languages == ["en"])
    }
}

@Suite struct SplitApkSelectorTests {
    // MARK: file name classification

    @Test func classifiesThePlayAndApkPureNamingConvention() {
        #expect(SplitApkSelector.qualifier(ofFile: "com.example.apk") == .base)
        #expect(SplitApkSelector.qualifier(ofFile: "config.arm64_v8a.apk") == .abi("arm64_v8a"))
        #expect(SplitApkSelector.qualifier(ofFile: "split_config.armeabi_v7a.apk") == .abi("armeabi_v7a"))
        #expect(SplitApkSelector.qualifier(ofFile: "config.xxhdpi.apk") == .density("xxhdpi"))
        #expect(SplitApkSelector.qualifier(ofFile: "config.en.apk") == .language("en"))
        #expect(SplitApkSelector.qualifier(ofFile: "config.pt_br.apk") == .language("pt"))
        // A feature module's own config split carries the module prefix.
        #expect(SplitApkSelector.qualifier(ofFile: "myfeature.config.hdpi.apk") == .density("hdpi"))
        // Hyphenated ABI spellings normalise to the underscore form.
        #expect(SplitApkSelector.qualifier(ofFile: "config.arm64-v8a.apk") == .abi("arm64_v8a"))
    }

    @Test func classifiesBundletoolsNamingConvention() {
        #expect(SplitApkSelector.qualifier(ofFile: "base-master.apk") == .base)
        #expect(SplitApkSelector.qualifier(ofFile: "base-arm64_v8a.apk") == .abi("arm64_v8a"))
        #expect(SplitApkSelector.qualifier(ofFile: "base-xxhdpi.apk") == .density("xxhdpi"))
        #expect(SplitApkSelector.qualifier(ofFile: "base-en.apk") == .language("en"))
    }

    @Test func classifiesUnmodelledQualifiersAsOtherAndIgnoresDirectories() {
        // Texture-compression splits aren't modelled; they must not be mistaken
        // for a language tag and dropped.
        #expect(SplitApkSelector.qualifier(ofFile: "config.tcf_astc.apk") == .other("tcf_astc"))
        // Only the file name matters — a directory named `config.x86` upstream
        // of the file must not reclassify it.
        #expect(SplitApkSelector.qualifier(ofFile: "/tmp/config.x86/base.apk") == .base)
        #expect(SplitApkSelector.qualifier(ofFile: "/tmp/out/config.x86_64.apk") == .abi("x86_64"))
    }

    // MARK: selection

    private static let phone = DeviceSpec(abis: ["arm64-v8a", "armeabi-v7a"], densityDpi: 420, languages: ["en"])

    @Test func keepsTheBaseTheBestAbiAndTheNearestDensity() {
        let files = [
            "base.apk", "config.arm64_v8a.apk", "config.armeabi_v7a.apk", "config.x86.apk",
            "config.hdpi.apk", "config.xhdpi.apk", "config.xxhdpi.apk", "config.xxxhdpi.apk",
        ]
        let selection = SplitApkSelector.select(files: files, spec: Self.phone)
        #expect(selection.chosenABI == "arm64_v8a")
        #expect(!selection.abiUnmatched)
        // 420 dpi → the smallest bucket at or above it (xxhdpi, 480).
        #expect(selection.files == ["base.apk", "config.arm64_v8a.apk", "config.xxhdpi.apk"])
    }

    @Test func fallsBackToTheDevicesSecondAbiWhenTheFirstIsntShipped() {
        let files = ["base.apk", "config.armeabi_v7a.apk", "config.x86.apk"]
        let selection = SplitApkSelector.select(files: files, spec: Self.phone)
        #expect(selection.chosenABI == "armeabi_v7a")
        #expect(selection.files == ["base.apk", "config.armeabi_v7a.apk"])
    }

    @Test func reportsAnUnmatchedAbiRatherThanInstallingABrokenSet() {
        let selection = SplitApkSelector.select(
            files: ["base.apk", "config.x86.apk", "config.x86_64.apk"], spec: Self.phone)
        #expect(selection.abiUnmatched)
        #expect(selection.chosenABI == nil)
    }

    @Test func aBundleWithNoAbiSplitsIsNeverUnmatched() {
        let selection = SplitApkSelector.select(files: ["base.apk", "config.en.apk"], spec: Self.phone)
        #expect(!selection.abiUnmatched)
        #expect(selection.chosenABI == nil)
    }

    @Test func picksTheLargestDensityBelowWhenNoneReachTheDevice() {
        let selection = SplitApkSelector.select(
            files: ["base.apk", "config.mdpi.apk", "config.hdpi.apk"], spec: Self.phone)
        #expect(selection.files == ["base.apk", "config.hdpi.apk"])
    }

    @Test func picksTheLargestDensityWhenTheDeviceDensityIsUnknown() {
        let spec = DeviceSpec(abis: ["arm64-v8a"], densityDpi: 0, languages: [])
        let selection = SplitApkSelector.select(
            files: ["base.apk", "config.hdpi.apk", "config.xxhdpi.apk"], spec: spec)
        #expect(selection.files == ["base.apk", "config.xxhdpi.apk"])
    }

    @Test func alwaysKeepsDensityAgnosticSplits() {
        let selection = SplitApkSelector.select(
            files: ["base.apk", "config.nodpi.apk", "config.anydpi.apk", "config.mdpi.apk"], spec: Self.phone)
        #expect(selection.files == ["base.apk", "config.nodpi.apk", "config.anydpi.apk", "config.mdpi.apk"])
    }

    @Test func keepsTheDevicesLanguagesAndEnglishAsTheFallback() {
        let spec = DeviceSpec(abis: ["arm64-v8a"], densityDpi: 420, languages: ["de"])
        let selection = SplitApkSelector.select(
            files: ["base.apk", "config.de.apk", "config.en.apk", "config.fr.apk", "config.ja.apk"], spec: spec)
        #expect(selection.files == ["base.apk", "config.de.apk", "config.en.apk"])
    }

    @Test func keepsFeatureModulesAndUnmodelledSplits() {
        let files = ["base.apk", "split_dynamicfeature.apk", "config.tcf_astc.apk", "config.x86.apk"]
        let spec = DeviceSpec(abis: ["x86_64", "x86"], densityDpi: 320, languages: ["en"])
        let selection = SplitApkSelector.select(files: files, spec: spec)
        #expect(selection.files == ["base.apk", "split_dynamicfeature.apk", "config.tcf_astc.apk", "config.x86.apk"])
    }

    @Test func returnsPathsUntouchedAndPreservesInputOrder() {
        let files = ["/w/x/config.xxhdpi.apk", "/w/x/base.apk", "/w/x/config.arm64_v8a.apk"]
        let selection = SplitApkSelector.select(files: files, spec: Self.phone)
        #expect(selection.files == files)
    }

    @Test func aSingleUnsplitApkPassesThroughUnchanged() {
        let selection = SplitApkSelector.select(files: ["app-release.apk"], spec: Self.phone)
        // `release` matches no qualifier dimension, so the APK is kept as-is.
        #expect(selection.files == ["app-release.apk"])
        #expect(!selection.abiUnmatched)
    }
}
