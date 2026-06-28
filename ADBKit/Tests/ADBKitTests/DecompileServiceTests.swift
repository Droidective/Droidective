import Foundation
import Testing
@testable import ADBKit

@Suite struct DecompileServiceTests {
    // MARK: argument builders

    @Test func jadxArgumentsRunTheCliOffTheLibClasspath() {
        #expect(DecompileService.jadxArguments(libDir: "/t/jadx/lib", output: "/out", apk: "/a.apk")
            == ["-cp", "/t/jadx/lib/*", "jadx.cli.JadxCLI", "-d", "/out", "/a.apk"])
    }

    @Test func jadxGuiArgumentsRunTheGuiMainOffTheLibClasspath() {
        #expect(DecompileService.jadxGuiArguments(libDir: "/t/jadx/lib", apk: "/a.apk")
            == ["-cp", "/t/jadx/lib/*", "jadx.gui.JadxGUI", "/a.apk"])
    }

    @Test func apktoolDecodeForcesOverwriteIntoOutput() {
        #expect(DecompileService.apktoolDecodeArguments(jar: "/t/apktool.jar", output: "/out", apk: "/a.apk")
            == ["-jar", "/t/apktool.jar", "d", "-f", "-o", "/out", "/a.apk"])
    }

    @Test func apktoolBuildArguments() {
        #expect(DecompileService.apktoolBuildArguments(jar: "/t/apktool.jar", sourceDir: "/src", output: "/out.apk")
            == ["-jar", "/t/apktool.jar", "b", "/src", "-o", "/out.apk"])
    }

    @Test func jadxLibDirIsTheSiblingOfBinRegardlessOfWrapperDir() {
        #expect(DecompileService.jadxLibDir(forRunnable: "/tools/jadx/v1/jadx-1.5.0/bin/jadx")
            == "/tools/jadx/v1/jadx-1.5.0/lib")
        #expect(DecompileService.jadxLibDir(forRunnable: "/x/bin/jadx") == "/x/lib")
    }

    // MARK: output tree

    @Test func treeListsDirectoriesFirstThenFilesAlphabetically() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dec-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("a/z.smali"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)

        let node = DecompileService.tree(at: root)
        #expect(node.isDirectory)
        #expect(node.children?.map(\.name) == ["a", "b.txt", "c.txt"])  // dir sorts before files
        #expect(node.children?.first?.isDirectory == true)
        #expect(node.children?.first?.children?.map(\.name) == ["z.smali"])
        #expect(node.children?.last?.isDirectory == false)
    }

    // MARK: global search

    @Test func searchFindsMatchesAcrossTextFilesAndSkipsBinaries() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("search-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("com/x"), withIntermediateDirectories: true)
        try "class A { void hello() {} }".write(to: root.appendingPathComponent("com/x/A.java"), atomically: true, encoding: .utf8)
        try "<manifest hello=\"1\"/>".write(to: root.appendingPathComponent("AndroidManifest.xml"), atomically: true, encoding: .utf8)
        try Data([0xFF, 0xD8, 0xFF]).write(to: root.appendingPathComponent("icon.png"))  // binary ext → skipped

        let hits = DecompileService.search(in: root, query: "HELLO")  // case-insensitive
        #expect(hits.count == 2)
        #expect(hits.contains { $0.path.hasSuffix("A.java") && $0.line == 1 })
        #expect(hits.allSatisfy { $0.text.lowercased().contains("hello") })
        #expect(DecompileService.search(in: root, query: "").isEmpty)
    }

    // MARK: error paths

    @Test func decompileThrowsWhenJavaMissing() async throws {
        let service = await Self.makeService(java: nil)
        await #expect(throws: DecompileService.DecompileError.self) {
            try await service.decompile(apkPath: "/a.apk", mode: .jadx, into: Self.tempDir())
        }
    }

    @Test func decompileThrowsWhenManagedToolNotDownloaded() async throws {
        // Java present, but jadx/apktool haven't been downloaded (empty store).
        let service = await Self.makeService(java: "/usr/bin/java")
        await #expect(throws: DecompileService.DecompileError.self) {
            try await service.decompile(apkPath: "/a.apk", mode: .apktool, into: Self.tempDir())
        }
    }

    private static func makeService(java: String?) async -> DecompileService {
        let locator = ToolLocator(runner: MockProcessRunner(), environment: [:])
        await locator.seedJava(java)
        let store = ManagedToolStore(rootDirectory: tempDir())
        return DecompileService(toolchain: ApkToolchain(locator: locator, store: store), runner: MockProcessRunner())
    }

    private static func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dec-out-\(UUID().uuidString)")
    }
}
