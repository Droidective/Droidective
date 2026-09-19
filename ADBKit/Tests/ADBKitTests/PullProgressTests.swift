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

    /// What the strip says under the bar.
    ///
    /// The sizes themselves are `ByteCountFormatter`'s and are localized, so
    /// what is asserted here is the decision — when there is a caption at all,
    /// and that both halves of it are the formatter's own answer, which is
    /// what keeps the strip agreeing with the File Explorer row above it.
    @Test func aKnownTotalIsCountedTowards() {
        let size = { (bytes: Int) in
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        #expect(PullProgress.caption(copied: 1_000, total: 4_000) == "\(size(1_000)) of \(size(4_000))")
    }

    /// A directory pull, and a file adb gave no size for: there is no total to
    /// count towards, so the strip says nothing rather than inventing one.
    @Test func noTotalMeansNoCaption() {
        #expect(PullProgress.caption(copied: 900, total: nil) == nil)
        #expect(PullProgress.caption(copied: 0, total: 0) == nil)
    }

    /// adb writes in blocks and a file system can report the allocated size,
    /// so copied passing total is ordinary — "1.1 GB of 1.0 GB" is not.
    @Test func copiedNeverOutrunsTheTotal() {
        let both = PullProgress.caption(copied: 300, total: 200)
        #expect(both == PullProgress.caption(copied: 200, total: 200))
    }
}
