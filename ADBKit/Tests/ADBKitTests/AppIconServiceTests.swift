import Testing
@testable import ADBKit

@Suite struct AppIconParsingTests {
    @Test func parsesNamesFromUnzipListing() {
        let output = """
        Archive:  /data/app/com.example-abc==/base.apk
          Length      Date    Time    Name
        ---------  ---------- -----   ----
             4317  01-01-81 01:01   res/drawable-mdpi-v4/ic_launcher.png
            23633  01-01-81 01:01   res/drawable-xxxhdpi-v4/ic_launcher.png
              512  01-01-81 01:01   AndroidManifest.xml
        ---------                     -------
            28462                     3 files
        """
        let names = AppIconService.parseUnzipListing(output)
        #expect(names.contains("res/drawable-mdpi-v4/ic_launcher.png"))
        #expect(names.contains("res/drawable-xxxhdpi-v4/ic_launcher.png"))
        #expect(names.contains("AndroidManifest.xml"))
        #expect(!names.contains { $0.contains("files") }) // total line dropped
        #expect(names.count == 3)
    }

    @Test func picksHighestDensityLauncherRaster() {
        let entries = [
            "res/drawable-mdpi-v4/ic_launcher.png",
            "res/drawable-ldpi-v4/ic_launcher.png",
            "res/drawable-xxxhdpi-v4/ic_launcher.png",
            "res/drawable-xhdpi-v4/ic_launcher.png",
            "res/drawable-hdpi-v4/ic_launcher.png",
        ]
        #expect(AppIconService.pickIconEntry(entries) == "res/drawable-xxxhdpi-v4/ic_launcher.png")
    }

    @Test func prefersPlainLauncherOverRoundAndForeground() {
        // Adaptive-icon app that still ships raster fallbacks (real survey data).
        let entries = [
            "res/drawable/ic_launcher_background.xml",
            "res/drawable/ic_launcher_foreground.xml",
            "res/mipmap-mdpi-v4/ic_launcher.png",
            "res/mipmap-mdpi-v4/ic_launcher_foreground.png",
            "res/mipmap-mdpi-v4/ic_launcher_round.png",
            "res/mipmap-hdpi-v4/ic_launcher.png",
        ]
        // Highest-density *plain* ic_launcher wins over round/foreground.
        #expect(AppIconService.pickIconEntry(entries) == "res/mipmap-hdpi-v4/ic_launcher.png")
    }

    @Test func handlesWebpIcons() {
        let entries = [
            "res/mipmap-anydpi-v26/ic_launcher.xml",
            "res/mipmap-xhdpi-v4/ic_launcher.webp",
            "res/mipmap-hdpi-v4/ic_launcher.webp",
        ]
        #expect(AppIconService.pickIconEntry(entries) == "res/mipmap-xhdpi-v4/ic_launcher.webp")
    }

    @Test func returnsNilWhenOnlyVectorIcons() {
        let entries = [
            "res/mipmap-anydpi-v26/ic_launcher.xml",
            "res/drawable/ic_launcher_foreground.xml",
            "AndroidManifest.xml",
            "classes.dex",
        ]
        #expect(AppIconService.pickIconEntry(entries) == nil)
    }

    @Test func matchesLauncherAndIconNameSynonyms() {
        // Apps that don't use the ic_launcher convention still resolve.
        #expect(AppIconService.pickIconEntry(["res/mipmap-xhdpi-v4/app_icon.png"])
            == "res/mipmap-xhdpi-v4/app_icon.png")
        #expect(AppIconService.pickIconEntry(["res/drawable-hdpi/launcher.webp"])
            == "res/drawable-hdpi/launcher.webp")
    }

    @Test func fallsBackToLargestRasterWhenNamesAreObfuscated() {
        // Resource shrinking flattens names — no ic_launcher/mipmap/icon match,
        // so the biggest raster in a density dir wins over smaller ones.
        let entries = [
            AppIconService.IconEntry(name: "res/xA.png", size: 900),
            AppIconService.IconEntry(name: "res/xB.png", size: 12000),
            AppIconService.IconEntry(name: "res/xB.webp", size: 400),
            AppIconService.IconEntry(name: "classes.dex", size: 50000),
        ]
        // Flat `res/` entries aren't density dirs → no fallback, no crash.
        #expect(AppIconService.pickIconEntry(entries) == nil)

        let densityEntries = [
            AppIconService.IconEntry(name: "res/drawable-xxhdpi-v4/xA.png", size: 900),
            AppIconService.IconEntry(name: "res/drawable-xxhdpi-v4/xB.png", size: 12000),
            AppIconService.IconEntry(name: "classes.dex", size: 50000),
        ]
        #expect(AppIconService.pickIconEntry(densityEntries) == "res/drawable-xxhdpi-v4/xB.png")
    }

    @Test func parsesEntrySizes() {
        let output = """
        Archive:  /data/app/com.example-abc==/base.apk
          Length      Date    Time    Name
        ---------  ---------- -----   ----
             4317  01-01-81 01:01   res/drawable-mdpi-v4/ic_launcher.png
            23633  01-01-81 01:01   res/drawable-xxxhdpi-v4/ic_launcher.png
        ---------                     -------
            27950                     2 files
        """
        let entries = AppIconService.parseUnzipEntries(output)
        #expect(entries.count == 2)
        #expect(entries.first == AppIconService.IconEntry(name: "res/drawable-mdpi-v4/ic_launcher.png", size: 4317))
        #expect(entries.last?.size == 23633)
    }
}
