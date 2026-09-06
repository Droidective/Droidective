import Testing
@testable import ADBKit

@Suite struct FileDropRouterTests {
    private func file(_ path: String) -> DroppedPath { DroppedPath(path: path) }
    private func folder(_ path: String) -> DroppedPath { DroppedPath(path: path, isDirectory: true) }

    // MARK: - Classification

    @Test func everyInstallableFormatIsAPackage() {
        for format in AppPackageFormat.allCases {
            #expect(FileDropRouter.kind(of: file("/tmp/app.\(format.rawValue)")) == .appPackage(format))
        }
    }

    @Test func extensionMatchIsCaseInsensitive() {
        #expect(FileDropRouter.kind(of: file("/tmp/APP-RELEASE.APK")) == .appPackage(.apk))
        #expect(FileDropRouter.kind(of: file("/tmp/CLIP.MP4")) == .video(.mp4))
    }

    @Test func aabIsABundleNotAPackage() {
        #expect(FileDropRouter.kind(of: file("/tmp/app.aab")) == .appBundle)
    }

    @Test func aDirectoryIsAFolderWhateverItsName() {
        // A folder called "Something.apk" is still a folder — installing it
        // would fail with a parse error a long way from the drop.
        #expect(FileDropRouter.kind(of: folder("/tmp/Something.apk")) == .folder)
    }

    @Test func anythingElseIsJustAFile() {
        #expect(FileDropRouter.kind(of: file("/tmp/notes.pdf")) == .other)
        #expect(FileDropRouter.kind(of: file("/tmp/no-extension")) == .other)
    }

    // MARK: - A drop on a device surface

    @Test func packagesInstallAndEverythingElseCopies() {
        let plan = FileDropRouter.plan([
            file("/tmp/app.apk"), file("/tmp/notes.pdf"), file("/tmp/clip.mp4"), folder("/tmp/assets"),
        ])
        #expect(plan.installs == ["/tmp/app.apk"])
        #expect(plan.copies == ["/tmp/notes.pdf", "/tmp/clip.mp4", "/tmp/assets"])
        #expect(plan.bundles.isEmpty)
        #expect(plan.destination == "/sdcard/Download")
    }

    @Test func aVideoOnAMirrorIsAFileNotAnEditorSession() {
        // The editor is where an *unclaimed* video goes. On a phone screen the
        // only sensible reading is "put this on the phone".
        let plan = FileDropRouter.plan([file("/tmp/clip.mkv")])
        #expect(plan.copies == ["/tmp/clip.mkv"])
        #expect(plan.installs.isEmpty)
    }

    @Test func onlyAPackageDropOffersTheCopyAlternative() {
        #expect(FileDropRouter.plan([file("/tmp/app.apk")]).hasAlternative)
        #expect(FileDropRouter.plan([file("/tmp/app.aab")]).hasAlternative)
        #expect(!FileDropRouter.plan([file("/tmp/notes.pdf")]).hasAlternative)
    }

    @Test func copyingEverythingKeepsTheArrivalOrder() {
        let plan = FileDropRouter.plan([file("/a.apk"), file("/b.pdf"), file("/c.aab")])
        #expect(plan.copyingEverything.copies == ["/a.apk", "/c.aab", "/b.pdf"])
        #expect(plan.copyingEverything.installs.isEmpty)
        #expect(plan.copyingEverything.hasAlternative == false)
    }

    @Test func anEmptyDropPlansNothing() {
        #expect(FileDropRouter.plan([]).isEmpty)
    }

    // MARK: - A drop on a surface that claims nothing

    @Test func eachKindGoesToTheFeatureThatOwnsIt() {
        let routes = FileDropRouter.routes(
            for: [file("/a.apk"), file("/b.aab"), file("/c.mp4"), file("/d.pdf")], hasDevice: true)
        #expect(routes == [
            .openPackages(["/a.apk"]),
            .convertBundles(["/b.aab"]),
            .openVideos(["/c.mp4"]),
            .copyToDevice(["/d.pdf"]),
        ])
    }

    @Test func groupOrderIsStableForAMixedDrop() {
        let shuffled = FileDropRouter.routes(
            for: [file("/d.pdf"), file("/c.mp4"), file("/b.aab"), file("/a.apk")], hasDevice: true)
        #expect(shuffled.map(routeName) == ["packages", "bundles", "videos", "copy"])
    }

    @Test func withNoDeviceAPlainFileIsRefusedRatherThanDropped() {
        let routes = FileDropRouter.routes(for: [file("/d.pdf")], hasDevice: false)
        #expect(routes == [.unsupported(["/d.pdf"])])
    }

    @Test func packagesStillRouteWithNoDeviceConnected() {
        // Opening the package screen doesn't need a device — it is where you
        // go to pick one.
        let routes = FileDropRouter.routes(for: [file("/a.apk")], hasDevice: false)
        #expect(routes == [.openPackages(["/a.apk"])])
    }

    @Test func nothingDroppedRoutesNowhere() {
        #expect(FileDropRouter.routes(for: [], hasDevice: true).isEmpty)
    }

    private func routeName(_ route: DropRoute) -> String {
        switch route {
        case .openPackages: "packages"
        case .convertBundles: "bundles"
        case .openVideos: "videos"
        case .copyToDevice: "copy"
        case .unsupported: "unsupported"
        }
    }

    // MARK: - Wording

    @Test func aSinglePackageNamesTheDeviceAndTheFile() {
        let plan = FileDropRouter.plan([file("/tmp/app-release.apk")])
        let said = FileDropRouter.announcement(for: plan, deviceName: "Pixel 7")
        #expect(said.verb == "Install on Pixel 7")
        #expect(said.detail == "app-release.apk")
        #expect(said.alternative == "…or copy to /sdcard/Download")
        #expect(said.refusal == false)
    }

    @Test func aFileDropNamesTheDestination() {
        let plan = FileDropRouter.plan([file("/tmp/notes.pdf")])
        let said = FileDropRouter.announcement(for: plan, deviceName: "Pixel 7")
        #expect(said.verb == "Copy to Pixel 7")
        #expect(said.detail == "notes.pdf → /sdcard/Download")
        #expect(said.alternative == nil)
    }

    @Test func aMixedDropSaysBothHalves() {
        let plan = FileDropRouter.plan([file("/a.apk"), file("/b.pdf"), file("/c.pdf")])
        let said = FileDropRouter.announcement(for: plan, deviceName: "Pixel 7")
        #expect(said.verb == "Install · Copy 2 files on Pixel 7")
    }

    @Test func hoveringTheAlternativeCommitsToCopyingEverything() {
        let plan = FileDropRouter.plan([file("/a.apk")])
        let said = FileDropRouter.announcement(for: plan, deviceName: "Pixel 7", copyingInstead: true)
        #expect(said.verb == "Copy to Pixel 7")
        #expect(said.detail == "a.apk → /sdcard/Download")
        // The alternative is where the pointer already is; offering it again
        // would say the drop has a choice it no longer has.
        #expect(said.alternative == nil)
    }

    @Test func aBundleNamesNoDeviceBecauseConvertingHappensOnTheMac() {
        // Promising "on Pixel 7" would overstate it: the drop opens the
        // converter with the bundle staged, and the install is a later step.
        let plan = FileDropRouter.plan([file("/tmp/app.aab")])
        let said = FileDropRouter.announcement(for: plan, deviceName: "Pixel 7")
        #expect(said.verb == "Convert to APK")
        #expect(said.detail == "app.aab")
        #expect(said.alternative == "…or copy to /sdcard/Download")
    }

    @Test func aBundleBesideAPackageStillNamesTheDevice() {
        let plan = FileDropRouter.plan([file("/a.apk"), file("/b.aab")])
        #expect(FileDropRouter.announcement(for: plan, deviceName: "Pixel 7").verb
            == "Install · Convert to APK on Pixel 7")
    }

    @Test func aRoutedDropNamesTheFeatureItIsAboutToOpen() {
        let routes = FileDropRouter.routes(for: [file("/c.mp4")], hasDevice: false)
        let said = FileDropRouter.announcement(for: routes)
        #expect(said?.verb == "Open in Video Editor")
        #expect(said?.detail == "c.mp4")
        #expect(said?.refusal == false)
    }

    @Test func anUnsupportedDropReadsAsARefusalAndSaysWhatWouldHelp() {
        let routes = FileDropRouter.routes(for: [file("/d.pdf")], hasDevice: false)
        let said = FileDropRouter.announcement(for: routes)
        #expect(said?.refusal == true)
        #expect(said?.verb == "Droidective can't open d.pdf")
        #expect(said?.detail == "Connect a device to copy files instead.")
    }

    @Test func nothingDroppedSaysNothing() {
        #expect(FileDropRouter.announcement(for: []) == nil)
    }

    @Test func everyPackageFormatAnnouncesAsAnInstall() {
        // A format added to AppPackageFormat must widen the mirror drop too,
        // not quietly become a file copy.
        for format in AppPackageFormat.allCases {
            let plan = FileDropRouter.plan([file("/tmp/app.\(format.rawValue)")])
            #expect(plan.installs.count == 1, "\(format.rawValue) should install")
        }
    }

    @Test func everyVideoFormatRoutesToTheEditorWhenUnclaimed() {
        for format in VideoInputFormat.allCases {
            let routes = FileDropRouter.routes(for: [file("/tmp/clip.\(format.rawValue)")], hasDevice: true)
            #expect(routes == [.openVideos(["/tmp/clip.\(format.rawValue)"])], "\(format.rawValue)")
        }
    }
}
