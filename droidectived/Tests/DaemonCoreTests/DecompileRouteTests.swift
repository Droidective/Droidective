import ADBKit
import Foundation
import Testing

@testable import DaemonCore

/// The decompile routes, and the confinement that keeps three of them from
/// being a read of any file the developer can read.
@Suite struct DecompileRouteTests {

    // MARK: - Confinement

    /// The check is on the *resolved* path, so these are the traversals a
    /// caller would actually try. Written as a table because the failure mode
    /// is one spelling slipping through, not the idea being wrong.
    @Suite struct Confinement {
        @Test func aPathInsideTheRootIsAllowed() {
            #expect(DecompileProtocol.confined("/cache/out/com/app/Main.java", to: "/cache/out"))
        }

        @Test func theRootItselfIsInsideItself() {
            // The search route passes the root as the path.
            #expect(DecompileProtocol.confined("/cache/out", to: "/cache/out"))
        }

        @Test func dotDotOutOfTheRootIsRefused() {
            #expect(!DecompileProtocol.confined("/cache/out/../../etc/passwd", to: "/cache/out"))
        }

        @Test func dotDotThatLandsBackInsideIsAllowed() {
            // Resolved, not pattern-matched: this really is inside.
            #expect(DecompileProtocol.confined("/cache/out/a/../b/C.java", to: "/cache/out"))
        }

        @Test func anUnrelatedPathIsRefused() {
            #expect(!DecompileProtocol.confined("/etc/passwd", to: "/cache/out"))
        }

        /// The trap a plain `hasPrefix` falls into: a sibling whose name starts
        /// with the root's name is not inside it.
        @Test func aSiblingSharingThePrefixIsRefused() {
            #expect(!DecompileProtocol.confined("/cache/out-evil/x.java", to: "/cache/out"))
        }

        @Test func aParentOfTheRootIsRefused() {
            #expect(!DecompileProtocol.confined("/cache", to: "/cache/out"))
        }

        /// The circularity guard: the client hands the root back on every call,
        /// so a root outside the daemon's own cache must be refused before the
        /// path is even compared to it.
        @Test func aRootOutsideTheCacheIsNotAnOutputRoot() {
            let cache = URL(fileURLWithPath: "/cache/decompiled")
            #expect(!DecompileProtocol.isOutputRoot("/", cache: cache))
            #expect(!DecompileProtocol.isOutputRoot("/etc", cache: cache))
            #expect(DecompileProtocol.isOutputRoot("/cache/decompiled/app-1234-jadx", cache: cache))
        }
    }

    // MARK: - Routes

    private struct StubBackend: DaemonBackend {
        var tree: DecompileProtocol.Tree?
        var file: DecompileProtocol.FileText?
        var hits: DecompileProtocol.Hits?
        var rebuilt: DecompileProtocol.RebuildResponse?
        var thrown: (any Error)?

        func decompileApk(
            _ request: DecompileProtocol.Request
        ) async throws -> DecompileProtocol.Tree {
            if let thrown { throw thrown }
            return tree ?? DecompileProtocol.Tree(
                root: "/r", tree: DecompileProtocol.Node(FileNode(name: "r", path: "/r")))
        }

        func decompiledFile(
            _ request: DecompileProtocol.FileRequest
        ) async -> DecompileProtocol.FileText? { file }

        func searchDecompiled(
            _ request: DecompileProtocol.SearchRequest
        ) async -> DecompileProtocol.Hits? { hits }

        func rebuildDecompiled(
            _ request: DecompileProtocol.RebuildRequest
        ) async throws -> DecompileProtocol.RebuildResponse? {
            if let thrown { throw thrown }
            return rebuilt
        }
    }

    private static func body(_ value: some Encodable) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    @Test func aDecompileAnswersTheTree() async throws {
        let node = FileNode(
            name: "out", path: "/r/out",
            children: [FileNode(name: "Main.java", path: "/r/out/Main.java")])
        let backend = StubBackend(
            tree: DecompileProtocol.Tree(root: "/r/out", tree: DecompileProtocol.Node(node)))
        let (status, data) = await DecompileRoutes.run(
            body: Self.body(DecompileProtocol.Request(path: "/a.apk", mode: .jadx)),
            backend: backend)
        #expect(status == 200)
        let answer = try JSONDecoder().decode(DecompileProtocol.Tree.self, from: data)
        #expect(answer.root == "/r/out")
        #expect(answer.tree.children?.first?.name == "Main.java")
    }

    /// A file has no `children` and a directory does, which is what puts a
    /// disclosure triangle on the right rows.
    @Test func aFileCarriesNoChildrenAndAnEmptyDirectoryCarriesSome() {
        let file = DecompileProtocol.Node(FileNode(name: "A.java", path: "/r/A.java"))
        let directory = DecompileProtocol.Node(FileNode(name: "res", path: "/r/res", children: []))
        #expect(file.children == nil)
        #expect(directory.children == [])
    }

    @Test func anEmptyPathIsABadRequest() async {
        let (status, _) = await DecompileRoutes.run(
            body: Self.body(DecompileProtocol.Request(path: "", mode: .jadx)),
            backend: StubBackend())
        #expect(status == 400)
    }

    @Test func aBodyThatIsNotARequestIsABadRequest() async {
        let (status, _) = await DecompileRoutes.run(
            body: Data("not json".utf8), backend: StubBackend())
        #expect(status == 400)
    }

    /// A missing tool and a tool that would not finish send someone to
    /// different places, so they do not share a code.
    @Test func aMissingToolIsToldApartFromAFailedRun() async throws {
        let missing = StubBackend(thrown: DecompileService.DecompileError.toolMissing("jadx"))
        let (status, data) = await DecompileRoutes.run(
            body: Self.body(DecompileProtocol.Request(path: "/a.apk", mode: .jadx)),
            backend: missing)
        #expect(status == 422)
        #expect(try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: data).error.code
            == "tool_missing")

        let failed = StubBackend(thrown: DecompileService.DecompileError.failed("boom"))
        let (_, other) = await DecompileRoutes.run(
            body: Self.body(DecompileProtocol.Request(path: "/a.apk", mode: .apktool)),
            backend: failed)
        #expect(try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: other).error.code
            == "tool_failed")
    }

    /// The backend answers nil for a path it will not read, and that has to
    /// reach the client as a refusal — not as an empty file, which would read
    /// as "this file is blank".
    @Test func aPathOutsideTheRootIsRefusedRatherThanEmpty() async throws {
        let (status, data) = await DecompileRoutes.file(
            body: Self.body(
                DecompileProtocol.FileRequest(root: "/r", path: "/etc/passwd")),
            backend: StubBackend(file: nil))
        #expect(status == 403)
        #expect(try JSONDecoder().decode(DaemonProtocol.ErrorBody.self, from: data).error.code
            == "outside_root")
    }

    @Test func aReadableFileComesBackWithItsTruncationFlag() async throws {
        let backend = StubBackend(
            file: DecompileProtocol.FileText(text: "class A {}", truncated: true, byteCount: 99))
        let (status, data) = await DecompileRoutes.file(
            body: Self.body(DecompileProtocol.FileRequest(root: "/r", path: "/r/A.java")),
            backend: backend)
        #expect(status == 200)
        let text = try JSONDecoder().decode(DecompileProtocol.FileText.self, from: data)
        #expect(text.truncated)
        #expect(text.byteCount == 99)
    }

    @Test func aSearchOutsideTheRootIsRefused() async {
        let (status, _) = await DecompileRoutes.search(
            body: Self.body(DecompileProtocol.SearchRequest(root: "/etc", query: "x")),
            backend: StubBackend(hits: nil))
        #expect(status == 403)
    }

    @Test func aCappedSearchSaysSo() async throws {
        let hit = DecompileService.SearchHit(path: "/r/A.java", line: 3, text: "x")
        let backend = StubBackend(
            hits: DecompileProtocol.Hits(hits: [DecompileProtocol.Hit(hit)], capped: true))
        let (status, data) = await DecompileRoutes.search(
            body: Self.body(DecompileProtocol.SearchRequest(root: "/r", query: "x")),
            backend: backend)
        #expect(status == 200)
        let answer = try JSONDecoder().decode(DecompileProtocol.Hits.self, from: data)
        #expect(answer.capped)
        #expect(answer.hits.first?.line == 3)
    }

    @Test func aRebuildOutsideTheRootIsRefused() async {
        let (status, _) = await DecompileRoutes.rebuild(
            body: Self.body(
                DecompileProtocol.RebuildRequest(
                    root: "/r", sourceDir: "/etc", output: "/out.apk")),
            backend: StubBackend(rebuilt: nil))
        #expect(status == 403)
    }

    @Test func aRebuildAnswersWhereItLanded() async throws {
        let backend = StubBackend(
            rebuilt: DecompileProtocol.RebuildResponse(output: "/out.apk"))
        let (status, data) = await DecompileRoutes.rebuild(
            body: Self.body(
                DecompileProtocol.RebuildRequest(
                    root: "/r", sourceDir: "/r/src", output: "/out.apk")),
            backend: backend)
        #expect(status == 200)
        #expect(try JSONDecoder().decode(DecompileProtocol.RebuildResponse.self, from: data).output
            == "/out.apk")
    }

    /// The wire mode has to keep meaning the service mode. A case added to one
    /// and not the other would decode to something that runs the wrong tool.
    @Test func everyWireModeMapsToAServiceMode() {
        #expect(DecompileProtocol.Mode.allCases.count == DecompileService.Mode.allCases.count)
        for mode in DecompileProtocol.Mode.allCases {
            #expect(mode.service.rawValue == mode.rawValue)
        }
    }
}
