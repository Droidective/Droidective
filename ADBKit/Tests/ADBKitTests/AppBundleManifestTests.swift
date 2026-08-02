import Foundation
import Testing

@testable import ADBKit

@Suite struct AppPackageFormatTests {
    @Test func detectsEveryInstallableExtensionCaseInsensitively() {
        #expect(AppPackageFormat.detect(fileName: "/d/app.apk") == .apk)
        #expect(AppPackageFormat.detect(fileName: "/d/app.APKS") == .apks)
        #expect(AppPackageFormat.detect(fileName: "app.XAPK") == .xapk)
        #expect(AppPackageFormat.detect(fileName: "My App v1.2.apkm") == .apkm)
    }

    @Test func rejectsAnythingElse() {
        #expect(AppPackageFormat.detect(fileName: "/d/bundle.aab") == nil)
        #expect(AppPackageFormat.detect(fileName: "/d/archive.zip") == nil)
        #expect(AppPackageFormat.detect(fileName: "/d/noextension") == nil)
        // A directory that merely ends in `.apk` still classifies by extension;
        // the installer's file check is what rejects it.
        #expect(AppPackageFormat.detect(fileName: "/d/apk") == nil)
    }

    @Test func onlyPlainApksSkipUnpacking() {
        #expect(!AppPackageFormat.apk.isBundle)
        #expect(AppPackageFormat.allCases.filter(\.isBundle).map(\.rawValue) == ["apks", "xapk", "apkm"])
    }

    @Test func extensionsCoverEveryCaseSoDropFiltersStayInSync() {
        #expect(Set(AppPackageFormat.fileExtensions) == ["apk", "apks", "xapk", "apkm"])
    }
}

@Suite struct AppBundleManifestTests {
    @Test func parsesAnApkPureManifestWithItsSplitsAndExpansions() throws {
        let json = """
        {
          "xapk_version": 2,
          "package_name": "com.example.game",
          "name": "Example Game",
          "version_name": "3.1.0",
          "version_code": "310",
          "split_apks": [
            {"file": "com.example.game.apk", "id": "base"},
            {"file": "config.arm64_v8a.apk", "id": "config.arm64_v8a"}
          ],
          "expansions": [
            {"file": "Android/obb/com.example.game/main.310.com.example.game.obb",
             "install_location": "EXTERNAL_STORAGE",
             "install_path": "Android/obb/com.example.game/main.310.com.example.game.obb"}
          ]
        }
        """
        let manifest = try #require(AppBundleManifest.parse(Data(json.utf8), format: .xapk))
        #expect(manifest.packageName == "com.example.game")
        #expect(manifest.appName == "Example Game")
        #expect(manifest.versionName == "3.1.0")
        #expect(manifest.versionCode == "310")
        #expect(manifest.splitFiles == ["com.example.game.apk", "config.arm64_v8a.apk"])
        #expect(manifest.expansions == [
            AppBundleManifest.Expansion(
                file: "Android/obb/com.example.game/main.310.com.example.game.obb",
                installPath: "Android/obb/com.example.game/main.310.com.example.game.obb"),
        ])
    }

    @Test func readsVersionCodeWhetherItIsAStringOrANumber() throws {
        let numeric = try #require(AppBundleManifest.parse(
            Data(#"{"package_name":"a","version_code":310}"#.utf8), format: .xapk))
        #expect(numeric.versionCode == "310")
        let text = try #require(AppBundleManifest.parse(
            Data(#"{"package_name":"a","version_code":"310"}"#.utf8), format: .xapk))
        #expect(text.versionCode == "310")
    }

    @Test func anExpansionWithoutAnInstallPathFallsBackToItsArchivePath() throws {
        let json = #"{"expansions":[{"file":"Android/obb/com.a/main.1.com.a.obb"}]}"#
        let manifest = try #require(AppBundleManifest.parse(Data(json.utf8), format: .xapk))
        #expect(manifest.expansions.first?.installPath == "Android/obb/com.a/main.1.com.a.obb")
    }

    @Test func parsesAnApkMirrorInfoFile() throws {
        let json = """
        {"apkm_version": 2, "pname": "com.example.app", "app_name": "Example",
         "release_version": "8.4.2", "versioncode": 8402, "variant": "arm64-v8a + xxhdpi"}
        """
        let manifest = try #require(AppBundleManifest.parse(Data(json.utf8), format: .apkm))
        #expect(manifest.packageName == "com.example.app")
        #expect(manifest.appName == "Example")
        #expect(manifest.versionName == "8.4.2")
        #expect(manifest.versionCode == "8402")
        // APKMirror doesn't list the splits — the installer scans instead.
        #expect(manifest.splitFiles.isEmpty)
    }

    @Test func fallsBackToApkTitleWhenApkMirrorOmitsAppName() throws {
        let manifest = try #require(AppBundleManifest.parse(
            Data(#"{"pname":"com.a","apk_title":"Titled"}"#.utf8), format: .apkm))
        #expect(manifest.appName == "Titled")
    }

    @Test func returnsNilForMalformedOrNonObjectJson() {
        #expect(AppBundleManifest.parse(Data("not json".utf8), format: .xapk) == nil)
        #expect(AppBundleManifest.parse(Data("[1,2,3]".utf8), format: .xapk) == nil)
        #expect(AppBundleManifest.parse(Data(), format: .apkm) == nil)
    }

    @Test func missingFieldsBecomeNilRatherThanFailingTheParse() throws {
        let manifest = try #require(AppBundleManifest.parse(Data("{}".utf8), format: .xapk))
        #expect(manifest.packageName == nil)
        #expect(manifest.splitFiles.isEmpty)
        #expect(manifest.expansions.isEmpty)
        // An empty string is as absent as a missing key.
        let blank = try #require(AppBundleManifest.parse(Data(#"{"package_name":""}"#.utf8), format: .xapk))
        #expect(blank.packageName == nil)
    }

    // MARK: path safety

    @Test func rejectsArchivePathsThatEscapeTheirDirectory() {
        #expect(AppBundleManifest.safeRelativePath("Android/obb/com.a/main.obb") == "Android/obb/com.a/main.obb")
        #expect(AppBundleManifest.safeRelativePath("../../etc/passwd") == nil)
        #expect(AppBundleManifest.safeRelativePath("Android/../../evil.obb") == nil)
        #expect(AppBundleManifest.safeRelativePath("/absolute/evil.obb") == nil)
        #expect(AppBundleManifest.safeRelativePath("~/evil.obb") == nil)
        #expect(AppBundleManifest.safeRelativePath("") == nil)
        #expect(AppBundleManifest.safeRelativePath(nil) == nil)
        // Backslash separators normalise, so a Windows-style traversal is caught
        // by the same component check.
        #expect(AppBundleManifest.safeRelativePath(#"Android\..\..\evil.obb"#) == nil)
    }

    @Test func aTraversingEntryIsDroppedFromAnOtherwiseValidManifest() throws {
        let json = """
        {"split_apks": [{"file": "base.apk"}, {"file": "../../escape.apk"}],
         "expansions": [{"file": "../../escape.obb", "install_path": "../../escape.obb"}]}
        """
        let manifest = try #require(AppBundleManifest.parse(Data(json.utf8), format: .xapk))
        #expect(manifest.splitFiles == ["base.apk"])
        #expect(manifest.expansions.isEmpty)
    }

    @Test func aTraversingInstallPathFallsBackToTheSafeArchivePath() throws {
        let json = #"{"expansions":[{"file":"Android/obb/com.a/m.obb","install_path":"../../../evil.obb"}]}"#
        let manifest = try #require(AppBundleManifest.parse(Data(json.utf8), format: .xapk))
        #expect(manifest.expansions.first?.installPath == "Android/obb/com.a/m.obb")
    }

    @Test func onlyContainerFormatsHaveAManifest() {
        #expect(AppBundleManifest.manifestFileName(for: .xapk) == "manifest.json")
        #expect(AppBundleManifest.manifestFileName(for: .apkm) == "info.json")
        #expect(AppBundleManifest.manifestFileName(for: .apk) == nil)
        #expect(AppBundleManifest.manifestFileName(for: .apks) == nil)
    }
}
