import Foundation
import Testing
@testable import ADBKit

@Suite struct ApkBadgingTests {
    /// A representative slice of `aapt2 dump badging` output.
    private let sample = """
    package: name='com.example.myapp' versionCode='42' versionName='2.1.0' compileSdkVersion='34' compileSdkVersionCodename='14'
    sdkVersion:'24'
    targetSdkVersion:'34'
    uses-permission: name='android.permission.INTERNET'
    application-label:'My Example App'
    application-label-en-US:'My Example App'
    application-label-fr:'Mon App'
    application: label='My Example App' icon='res/mipmap-anydpi-v26/ic_launcher.xml'
    launchable-activity: name='com.example.myapp.MainActivity'  label='My Example App'
    """

    @Test func parsesAllIdentifyingFields() {
        let fields = ApkBadging.parse(sample)
        #expect(fields.packageName == "com.example.myapp")
        #expect(fields.versionName == "2.1.0")
        #expect(fields.versionCode == "42")
        #expect(fields.label == "My Example App")
        #expect(fields.minSdk == "24")
        #expect(fields.targetSdk == "34")
    }

    @Test func packageNameIsNotConfusedWithPermissionOrActivityNames() {
        // `name='…'` also appears on uses-permission / launchable-activity lines;
        // only the `package:` line's name is the package id.
        #expect(ApkBadging.parse(sample).packageName == "com.example.myapp")
    }

    @Test func minSdkIsNotShadowedByTargetSdk() {
        // `targetSdkVersion` must not be misread as `sdkVersion` (case matters).
        let fields = ApkBadging.parse(sample)
        #expect(fields.minSdk == "24")
        #expect(fields.targetSdk == "34")
    }

    @Test func readsTheMinSdkModernBuildToolsActuallyPrint() {
        // Captured from `aapt2 dump badging` (build-tools 36.1.0) against a real
        // APK pulled off an emulator. The sample above is aapt*1*'s spelling,
        // `sdkVersion:'24'`, and matching only that read nil against every
        // modern build-tools — the capital S in `minSdkVersion` is not in the
        // lowercase pattern, so it never matched at all.
        let real = """
        package: name='com.android.settings' versionCode='35' versionName='15' \
        platformBuildVersionName='15' platformBuildVersionCode='35' \
        compileSdkVersion='35' compileSdkVersionCodename='15'
        minSdkVersion:'35'
        targetSdkVersion:'35'
        uses-permission: name='android.permission.WAKE_LOCK'
        """
        let fields = ApkBadging.parse(real)
        #expect(fields.minSdk == "35")
        #expect(fields.targetSdk == "35")
        #expect(fields.packageName == "com.android.settings")
    }

    @Test func stillReadsTheOlderSpelling() {
        // aapt1's `sdkVersion:'21'` stays supported, and cannot be confused
        // with `targetSdkVersion`, which capitalises the S too.
        let old = """
        package: name='com.x' versionCode='1' versionName='1.0'
        sdkVersion:'21'
        targetSdkVersion:'30'
        """
        let fields = ApkBadging.parse(old)
        #expect(fields.minSdk == "21")
        #expect(fields.targetSdk == "30")
    }

    @Test func fallsBackToApplicationLineLabel() {
        let output = """
        package: name='com.x' versionCode='1' versionName='1.0'
        application: label='Fallback Label' icon='res/ic.png'
        """
        #expect(ApkBadging.parse(output).label == "Fallback Label")
    }

    @Test func emptyValuesAndGarbageYieldNil() {
        let fields = ApkBadging.parse("package: name='' versionName='' \nnonsense line")
        #expect(fields.packageName == nil)
        #expect(fields.versionName == nil)
        #expect(fields.label == nil)
        #expect(fields.minSdk == nil)
    }

    @Test func apkInfoHasDetailsReflectsBadging() {
        let bare = ApkInfo(fileName: "app.apk", fileSizeBytes: 1024)
        #expect(!bare.hasDetails)
        let rich = ApkInfo(fileName: "app.apk", fileSizeBytes: 1024, packageName: "com.x")
        #expect(rich.hasDetails)
    }

    @Test func parsesPermissionsFeaturesAndDebuggable() {
        let output = """
        package: name='com.x' versionCode='1' versionName='1.0'
        sdkVersion:'24'
        targetSdkVersion:'34'
        application-debuggable
        uses-permission: name='android.permission.INTERNET'
        uses-permission: name='android.permission.CAMERA'
        uses-permission-sdk-23: name='android.permission.READ_CONTACTS'
        uses-feature: name='android.hardware.camera'
        uses-feature-not-required: name='android.hardware.location'
        """
        let fields = ApkBadging.parse(output)
        #expect(fields.permissions == [
            "android.permission.INTERNET",
            "android.permission.CAMERA",
            "android.permission.READ_CONTACTS",
        ])
        #expect(fields.features == ["android.hardware.camera", "android.hardware.location"])
        #expect(fields.isDebuggable)
    }

    @Test func releaseApkExposesItsPermissionAndIsNotDebuggable() {
        let fields = ApkBadging.parse(sample)
        #expect(fields.permissions == ["android.permission.INTERNET"])
        #expect(!fields.isDebuggable)
    }

    @Test func duplicatePermissionsAreCollapsedPreservingOrder() {
        let output = """
        uses-permission: name='android.permission.CAMERA'
        uses-permission: name='android.permission.INTERNET'
        uses-permission: name='android.permission.CAMERA'
        """
        #expect(ApkBadging.parse(output).permissions == [
            "android.permission.CAMERA", "android.permission.INTERNET",
        ])
    }
}
