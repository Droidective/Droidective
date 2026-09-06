import ADBKit
import Foundation
import Testing

@Suite struct DragPasteboardTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "droidective-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func aDirectoryIsReportedAsOneEvenWhenItsNameLooksInstallable() throws {
        // The router trusts `isDirectory` over the extension, so this is where
        // the fact has to be right: a folder called "Build.apk" handed to
        // `adb install` fails with a parse error a long way from the drop.
        let dir = try makeTempDir()
        let disguised = dir.appending(path: "Build.apk")
        try FileManager.default.createDirectory(at: disguised, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let dropped = DragPasteboard.paths(from: [disguised])
        #expect(dropped.count == 1)
        #expect(dropped[0].isDirectory)
        #expect(FileDropRouter.kind(of: dropped[0]) == .folder)
        #expect(FileDropRouter.plan(dropped).installs.isEmpty)
    }

    @Test func aRealFileIsNotADirectory() throws {
        let dir = try makeTempDir()
        let file = dir.appending(path: "app.apk")
        try Data("not really an apk".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: dir) }

        let dropped = DragPasteboard.paths(from: [file])
        #expect(dropped[0].isDirectory == false)
        #expect(FileDropRouter.plan(dropped).installs == [file.path])
    }

    @Test func nonFileURLsAreDropped() {
        // `dropDestination(for: URL.self)` accepts any URL, a dragged web link
        // included. Pushing one to a device is not a thing.
        let mixed = [URL(string: "https://example.com/a.apk")!, URL(fileURLWithPath: "/tmp/b.txt")]
        #expect(DragPasteboard.paths(from: mixed).map(\.path) == ["/tmp/b.txt"])
    }

    @Test func aPathThatNoLongerExistsIsStillCarriedAsAFile() {
        // Deleted between the drag starting and the drop: `fileExists` says
        // no, and the honest answer is "a file", so the copy reports adb's
        // own error rather than the drop silently doing nothing.
        let dropped = DragPasteboard.paths(from: [URL(fileURLWithPath: "/tmp/definitely-gone-\(UUID()).txt")])
        #expect(dropped.count == 1)
        #expect(dropped[0].isDirectory == false)
    }
}
