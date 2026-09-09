import Foundation
import Testing

@testable import ADBKit

/// The progress bar's idea of "how much has landed" for a split pull.
@Suite struct PullProgressTests {
    private func belongs(_ name: String, to destination: String = "com.x.apk") -> Bool {
        PullProgress.belongsToPull(fileName: name, destinationName: destination)
    }

    @Test func theChosenFileCounts() {
        #expect(belongs("com.x.apk"))
    }

    /// The names `AppInspectionService.splitDestination` produces.
    @Test func everySplitBesideItCounts() {
        #expect(belongs("com.x.split_config.en.apk"))
        #expect(belongs("com.x.split_config.arm64_v8a.apk"))
        #expect(belongs("com.x.split_config.xxhdpi.apk"))
    }

    /// The bug this guards: a neighbour sharing a prefix is a different app,
    /// and counting it would push the bar past 100% or complete it early.
    @Test func aPrefixNeighbourDoesNotCount() {
        #expect(!belongs("com.x2.apk"))
        #expect(!belongs("com.xtra.split_config.en.apk"))
    }

    @Test func anUnrelatedFileInTheSameFolderDoesNotCount() {
        #expect(!belongs("screenshot.png"))
        #expect(!belongs("other.apk"))
        #expect(!belongs("com.x.split_config.en.txt"), "same stem, wrong kind")
    }

    /// A destination the user typed without an extension has no stem/suffix
    /// pair to match splits against, so only the exact file counts — the bar
    /// then behaves as it did before, rather than matching everything.
    @Test func aDestinationWithNoExtensionMatchesOnlyItself() {
        #expect(belongs("bundle", to: "bundle"))
        #expect(!belongs("bundle.split_config.en.apk", to: "bundle"))
    }

    @Test func aDottedAppIdIsNotConfusedForAnExtension() {
        #expect(belongs("com.foo.bar.apk", to: "com.foo.bar.apk"))
        #expect(belongs("com.foo.bar.split_config.en.apk", to: "com.foo.bar.apk"))
        #expect(!belongs("com.foo.baz.apk", to: "com.foo.bar.apk"))
    }
}
