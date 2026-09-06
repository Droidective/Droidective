import ADBKit
import Foundation
import Testing

/// The drop router and the app's Finder document types have to agree.
///
/// A format declared openable from Finder but with no route is a file that
/// double-clicks into the app and then does nothing — which is the exact
/// failure this whole feature exists to remove. The two lists live in
/// different files (`project.yml` and `FileDropRouter`), so a test holds them
/// together rather than review folklore.
@Suite struct DropRoutingContractTests {
    /// The repo root, from this file's own compile-time path.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // App/Tests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // repo
    }

    /// Every file extension the app tells Launch Services it can be handed.
    ///
    /// Two places declare them and both count: `CFBundleTypeExtensions` on a
    /// document type, and `public.filename-extension` on a declared UTI (which
    /// is how the Android formats arrive — macOS has no type for any of them).
    private static func declaredExtensions() throws -> Set<String> {
        let yaml = try String(contentsOf: repoRoot.appending(path: "project.yml"), encoding: .utf8)
        var found: Set<String> = []
        var collecting = false
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("CFBundleTypeExtensions:")
                || trimmed.hasPrefix("public.filename-extension:") {
                collecting = true
                continue
            }
            guard collecting else { continue }
            guard trimmed.hasPrefix("- ") else {
                if !trimmed.isEmpty, !trimmed.hasPrefix("#") { collecting = false }
                continue
            }
            let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            // The next block opens with `- UTTypeIdentifier: …`, which is also
            // a `- ` line: a scalar list item never carries a colon.
            guard !item.contains(":") else { collecting = false; continue }
            found.insert(item.lowercased())
        }
        return found
    }

    @Test func projectYmlActuallyDeclaresExtensions() throws {
        // Guards the parser above: a silent empty set would make every other
        // assertion here vacuously true.
        #expect(try Self.declaredExtensions().count >= 10)
    }

    @Test func everyFinderOpenableExtensionHasARoute() throws {
        for ext in try Self.declaredExtensions() {
            let dropped = [DroppedPath(path: "/tmp/sample.\(ext)")]
            let routes = FileDropRouter.routes(for: dropped, hasDevice: false)
            #expect(routes.count == 1, "\(ext) should resolve to exactly one route")
            if case .unsupported = routes.first {
                Issue.record("\(ext) is declared in project.yml but the router can't place it")
            }
            if case .copyToDevice = routes.first {
                Issue.record("\(ext) is Finder-openable but the router only copies it to a device")
            }
        }
    }

    @Test func everyRoutableFormatIsAlsoFinderOpenable() throws {
        // The other direction: a format the router knows about but Finder
        // can't hand over is a half-wired format.
        let declared = try Self.declaredExtensions()
        for ext in AppPackageFormat.fileExtensions + ["aab"] + VideoInputFormat.fileExtensions {
            #expect(declared.contains(ext), "\(ext) has a route but no CFBundleTypeExtensions entry")
        }
    }
}
