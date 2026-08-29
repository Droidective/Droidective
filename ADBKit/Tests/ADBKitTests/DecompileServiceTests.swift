import Foundation
import Testing
@testable import ADBKit

// Test fixtures write with `atomically: false` on purpose. An atomic write is
// write-a-temp-then-rename, and on Windows CI that rename is what a scanner
// refuses with ERROR_SHARING_VIOLATION — the transient `FileRetry` exists for
// in the shipping code. A fixture writing a brand-new file into a brand-new
// unique temp directory has nothing for atomicity to protect, so it does not
// pay that cost.
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

    // MARK: cache directory naming

    @Test func outputDirNameSeparatesSameNamedApksFromDifferentFolders() {
        let debug = DecompileService.outputDirName(apkPath: "/builds/debug/app.apk", mode: .jadx)
        let release = DecompileService.outputDirName(apkPath: "/builds/release/app.apk", mode: .jadx)
        #expect(debug != release)
        #expect(debug.hasPrefix("app-"))
        #expect(debug.hasSuffix("-jadx"))
    }

    @Test func outputDirNameIsStableForTheSamePathAndVariesByMode() {
        let first = DecompileService.outputDirName(apkPath: "/x/a.apk", mode: .jadx)
        #expect(first == DecompileService.outputDirName(apkPath: "/x/a.apk", mode: .jadx))
        #expect(first != DecompileService.outputDirName(apkPath: "/x/a.apk", mode: .apktool))
    }

    // MARK: output tree

    @Test func treeListsDirectoriesFirstThenFilesAlphabetically() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dec-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("a/z.smali"), atomically: false, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("b.txt"), atomically: false, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("c.txt"), atomically: false, encoding: .utf8)

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
        try "class A { void hello() {} }".write(to: root.appendingPathComponent("com/x/A.java"), atomically: false, encoding: .utf8)
        try "<manifest hello=\"1\"/>".write(to: root.appendingPathComponent("AndroidManifest.xml"), atomically: false, encoding: .utf8)
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

    @Test func decompileReusesExistingOutputWithoutNeedingTools() async throws {
        // A previous decompile of the same APK+mode is reused: with no Java and no
        // downloaded tool, decompile still returns the cached dir instead of
        // throwing toolMissing — proving it never tried to run the decompiler.
        let out = Self.tempDir()
        let dir = out.appendingPathComponent(
            DecompileService.outputDirName(apkPath: "/x/a.apk", mode: .jadx), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "class A {}".write(to: dir.appendingPathComponent("A.java"), atomically: false, encoding: .utf8)
        let service = await Self.makeService(java: nil)
        let result = try await service.decompile(apkPath: "/x/a.apk", mode: .jadx, into: out)
        #expect(result == dir)
    }

    @Test func decompileDoesNotReuseACacheFromASameNamedApkElsewhere() async throws {
        // /debug/a.apk was decompiled earlier; /release/a.apk must not be served
        // that cache — with no tools available the fresh run fails loudly instead.
        let out = Self.tempDir()
        let cached = out.appendingPathComponent(
            DecompileService.outputDirName(apkPath: "/debug/a.apk", mode: .jadx), isDirectory: true)
        try FileManager.default.createDirectory(at: cached, withIntermediateDirectories: true)
        try "class A {}".write(to: cached.appendingPathComponent("A.java"), atomically: false, encoding: .utf8)
        let service = await Self.makeService(java: nil)
        await #expect(throws: DecompileService.DecompileError.self) {
            try await service.decompile(apkPath: "/release/a.apk", mode: .jadx, into: out)
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
