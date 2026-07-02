import Foundation
import Testing
@testable import ADBKit

@Suite struct CacheTrashTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adbkit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func setAsideRenamesTheDirectoryWithContentsIntact() throws {
        let parent = try tempDir()
        let cache = parent.appendingPathComponent("decompiled", isDirectory: true)
        let nested = cache.appendingPathComponent("com.example/classes", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("class A {}".utf8).write(to: nested.appendingPathComponent("A.java"))

        let trashed = CacheTrash.setAside(cache)

        let trashURL = try #require(trashed)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(trashURL.deletingLastPathComponent().path == parent.path)
        #expect(trashURL.lastPathComponent.hasPrefix("decompiled.trash-"))
        // A rename, not a copy: the tree arrives whole at the new name.
        let movedFile = trashURL.appendingPathComponent("com.example/classes/A.java")
        #expect(FileManager.default.fileExists(atPath: movedFile.path))
    }

    @Test func setAsideOfMissingDirectoryIsANoOp() throws {
        let parent = try tempDir()
        let cache = parent.appendingPathComponent("decompiled", isDirectory: true)

        #expect(CacheTrash.setAside(cache) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }

    @Test func repeatedSetAsideProducesDistinctTrashSiblings() throws {
        let parent = try tempDir()
        let cache = parent.appendingPathComponent("decompiled", isDirectory: true)
        var trashURLs: [URL] = []
        for _ in 0..<2 {
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            trashURLs.append(try #require(CacheTrash.setAside(cache)))
        }

        #expect(trashURLs[0].lastPathComponent != trashURLs[1].lastPathComponent)
        for url in trashURLs {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func sweepRemovesOnlyMatchingTrashSiblings() throws {
        let parent = try tempDir()
        let cache = parent.appendingPathComponent("decompiled", isDirectory: true)
        let survivors = [
            cache,
            parent.appendingPathComponent("decompiled-live", isDirectory: true),
            parent.appendingPathComponent("other.trash-123", isDirectory: true),
        ]
        let trash = [
            parent.appendingPathComponent("decompiled.trash-\(UUID().uuidString)", isDirectory: true),
            parent.appendingPathComponent("decompiled.trash-\(UUID().uuidString)", isDirectory: true),
        ]
        for dir in survivors + trash {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: dir.appendingPathComponent("file.txt"))
        }

        CacheTrash.sweep(around: cache)

        for dir in survivors {
            #expect(FileManager.default.fileExists(atPath: dir.path))
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("file.txt").path))
        }
        for dir in trash {
            #expect(!FileManager.default.fileExists(atPath: dir.path))
        }
    }

    @Test func sweepOfNonexistentParentIsANoOp() throws {
        let parent = try tempDir().appendingPathComponent("never-created", isDirectory: true)
        let cache = parent.appendingPathComponent("decompiled", isDirectory: true)

        CacheTrash.sweep(around: cache)

        #expect(!FileManager.default.fileExists(atPath: parent.path))
    }
}
