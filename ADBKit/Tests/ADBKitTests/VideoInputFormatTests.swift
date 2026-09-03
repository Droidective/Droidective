import Testing
@testable import ADBKit

/// The editor's input list. Same shape and same canary as
/// `AppPackageFormatTests`, because it plays the same role: every drop
/// filter, open panel, and Finder document type derives from it, so a case
/// added without the extension list noticing silently widens nothing.
@Suite struct VideoInputFormatTests {
    @Test func detectsEveryContainerCaseInsensitively() {
        #expect(VideoInputFormat.detect(fileName: "clip.mp4") == .mp4)
        // A camera writes .MOV; a transport-stream dump .TS.
        #expect(VideoInputFormat.detect(fileName: "IMG_0042.MOV") == .mov)
        #expect(VideoInputFormat.detect(fileName: "capture.TS") == .ts)
        #expect(VideoInputFormat.detect(fileName: "screencast.WebM") == .webm)
        #expect(VideoInputFormat.detect(fileName: "3gp clip.3gp") == .threeGP)
        // A path with spaces and dots in the name, not just the extension.
        #expect(VideoInputFormat.detect(fileName: "My Recording v1.2.mkv") == .mkv)
        #expect(VideoInputFormat.detect(fileName: "/tmp/a/b/x.m2ts") == .m2ts)
    }

    @Test func rejectsWhatTheEditorCannotOpen() {
        #expect(VideoInputFormat.detect(fileName: "app.apk") == nil)
        #expect(VideoInputFormat.detect(fileName: "notes.txt") == nil)
        #expect(VideoInputFormat.detect(fileName: "song.mp3") == nil)
        #expect(VideoInputFormat.detect(fileName: "poster.png") == nil)
        #expect(VideoInputFormat.detect(fileName: "noextension") == nil)
        // A directory named like a file — the open panel's own check rejects
        // directories, this only answers on the extension.
        #expect(VideoInputFormat.detect(fileName: "/videos/mp4") == nil)
    }

    /// The canary: every case reaches the list the filters are built from.
    @Test func extensionsCoverEveryCaseSoDropFiltersStayInSync() {
        #expect(Set(VideoInputFormat.fileExtensions) == [
            "mp4", "mov", "m4v", "mkv", "webm", "avi", "flv",
            "ts", "m2ts", "mpg", "mpeg", "wmv", "3gp", "ogv", "gif",
        ])
        // Raw values *are* the extensions, which is what makes the list free.
        #expect(VideoInputFormat.fileExtensions.allSatisfy { $0 == $0.lowercased() })
    }

    /// The recorder's own output has to be openable, or Edit from the
    /// recording-decision sheet lands on a rejected file.
    @Test func theRecordersContainerIsAccepted() {
        #expect(VideoInputFormat.detect(fileName: "recording_20260903.mp4") == .mp4)
    }

    /// Every export target that is also a container must round-trip back in,
    /// or a file the editor just wrote can't be reopened. GIF included — it
    /// is both, unlike the input-only and output-only members either side.
    @Test func everyExportTargetCanBeReopened() {
        for format in VideoFormat.allCases {
            #expect(
                VideoInputFormat(rawValue: format.fileExtension) != nil,
                "exported .\(format.fileExtension) cannot be reopened"
            )
        }
    }

    @Test func namesAreDistinctEnoughToShow() {
        let names = VideoInputFormat.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        // mpg and mpeg deliberately share "MPEG"; nothing else may collide.
        #expect(Set(names).count == VideoInputFormat.allCases.count - 1)
    }
}
