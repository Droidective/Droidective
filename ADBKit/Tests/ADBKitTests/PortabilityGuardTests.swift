import Foundation
import Testing

/// Portability guard over the ADBKit package's own sources.
///
/// CLAUDE.md's load-bearing rule forbids Apple-only framework imports in ADBKit
/// outside the subsystems that are already Apple-bound, and lists the
/// corelibs-Foundation spellings to avoid, because the Windows/Linux port
/// (`feat/cross-platform-core`) compiles these same sources against
/// corelibs-Foundation. macOS CI cannot catch a violation — `import os` builds
/// fine here — so the rule is a test rather than review folklore, in the shape of
/// the registry invariants (`implementedIDsAreAllRealFeatures`).
///
/// The scan is a pure function of (path, contents): the two tree tests feed it the
/// real sources, and the two fixture tests feed it hand-written files so the
/// guard's own teeth are checked on every run. Reading the package's `Sources`
/// directory is the only filesystem fact this suite relies on — it exists
/// wherever the package builds, on any host, and is located from `#filePath`.
@Suite struct PortabilityGuardTests {

    // MARK: - What the rule forbids

    /// Frameworks that exist only on Apple platforms: importing one makes the file
    /// uncompilable against corelibs-Foundation. CLAUDE.md names Network,
    /// CoreMedia, AVFoundation, VideoToolbox, CryptoKit, os and Darwin; the rest
    /// would break the port the same way, and the UI ones must never reach ADBKit
    /// at all.
    private static let appleOnlyModules: Set<String> = [
        "AVFoundation", "AppKit", "Compression", "CoreImage", "CoreMedia", "CryptoKit",
        "Darwin", "IOKit", "Metal", "Network", "QuartzCore", "SwiftUI", "UIKit",
        "VideoToolbox", "Vision", "os",
    ]

    private struct Trap: Sendable {
        /// Reported on a hit, and the name an allowlist entry uses.
        let name: String
        /// Runs on one line of code with its `//` comment removed.
        let matches: @Sendable (String) -> Bool
    }

    /// The corelibs-Foundation traps CLAUDE.md lists, minus the ones a text scan
    /// cannot spot precisely. `readabilityHandler`-as-an-EOF-signal is
    /// deliberately absent: the handler itself is *mandated* here
    /// (`SystemProcessRunner` must not block a cooperative thread) and no pattern
    /// separates the EOF misuse from the correct use, so the check would only cry
    /// wolf. `NSData.decompressed(using:)` is absent for the same reason — it is
    /// spelled like any other Foundation call.
    private static let traps: [Trap] = [
        Trap(name: "OSAllocatedUnfairLock") { $0.contains("OSAllocatedUnfairLock") },
        Trap(name: "NSDataDetector") { $0.contains("NSDataDetector") },
        Trap(name: "FileManager.replaceItemAt") { $0.contains("replaceItemAt") },
        Trap(name: "posix_spawn") { $0.contains("posix_spawn") },
        // `FileHandle.bytes` is `AsyncBytes`, so it is only ever consumed with
        // `await` or through `.lines`. Requiring one of those keeps an unrelated
        // `.bytes` property from tripping the guard; the cost is that a bare
        // `handle.bytes` stored for later goes unseen.
        Trap(name: "FileHandle.bytes") {
            $0.contains(".bytes") && ($0.contains("await") || $0.contains(".bytes.lines"))
        },
    ]

    // MARK: - Where the rule does not apply

    /// Subsystems CLAUDE.md declares already Apple-bound: they may keep their
    /// Apple-only spellings, and the port gates them wholesale. These are path
    /// prefixes relative to `Sources`, so a new file inside the Mirror pipeline is
    /// covered without editing this list.
    private static let appleBoundSubsystems: [String] = [
        "ADBKit/Services/Mirror/",  // CoreMedia + VideoToolbox + AVFoundation + Network
        "ADBKit/Services/ScreenRecorder.swift",  // records through a headless MirrorSession
        "ADBKit/Services/Reactotron/ReactotronServer.swift",  // Network listener + unified log
        "ADBKit/Services/JSConsole/ConsoleLinkDetector.swift",  // NSDataDetector link ranges
        "ADBKit/Support/ProcessStats.swift",  // Darwin process sampling
    ]

    /// Known debt on `main`: the exact Apple-only imports and traps each file is
    /// allowed to keep, so everything else can be enforced now. The fixes belong
    /// on `feat/cross-platform-core`, which already gates all of these behind
    /// `#if canImport(...)` — repeating them here would only conflict with that
    /// branch. `everyKnownDebtEntryIsStillALiveViolation` fails on a stale entry,
    /// so the list shrinks as the port lands instead of rotting.
    private static let knownDebt: [String: Set<String>] = [
        // `import os` for OSAllocatedUnfairLock; the port keeps it under
        // canImport(Darwin) and uses Synchronization's Mutex elsewhere.
        "ADBKit/Support/NetworkTrafficMeter.swift": ["os", "OSAllocatedUnfairLock"],
        // CryptoKit SHA256 over a downloaded asset; the port falls back to swift-crypto.
        "ADBKit/Tools/ManagedToolStore.swift": ["CryptoKit"],
        // CryptoKit SHA256 for the decompile output-directory name; same fallback.
        "ADBKit/Services/DecompileService.swift": ["CryptoKit"],
        // Darwin getifaddrs for the Mac's LAN address; the port adds a Glibc branch.
        "ADBKit/Services/HostNetwork.swift": ["Darwin"],
        // FileManager.replaceItemAt for the atomic store write; corelibs has no such method.
        "ADBKit/Persistence/JSONStore.swift": ["FileManager.replaceItemAt"],
        // Raw posix_spawn to detach a booting emulator from the app's process group.
        "ADBKit/Services/EmulatorService.swift": ["posix_spawn"],
        // FileHandle.bytes line iteration over a long-running stream; no AsyncBytes in corelibs.
        "ADBKit/Services/LogcatStream.swift": ["FileHandle.bytes"],
        "ADBKit/Services/SimulatorLogStream.swift": ["FileHandle.bytes"],
    ]

    // MARK: - The scan

    private enum Violation: Equatable, Sendable {
        case appleOnlyImport
        case corelibsTrap
    }

    private struct Finding: Sendable, CustomStringConvertible {
        let path: String
        let line: Int
        /// The module or trap name — also the key an allowlist entry uses.
        let item: String
        let kind: Violation

        var description: String { "\(path):\(line) \(item)" }
    }

    /// Every Apple-only import and corelibs trap in one file, skipping whatever a
    /// platform gate already makes portable.
    private static func findings(in source: String, path: String) -> [Finding] {
        var found: [Finding] = []
        var gates: [String] = []
        // Split on `.newlines`, not "\n" — the project convention, and a file with
        // CRLF endings must scan identically.
        for (offset, rawLine) in source.components(separatedBy: .newlines).enumerated() {
            if let directive = conditionalDirective(in: rawLine) {
                apply(directive, to: &gates)
                continue
            }
            let code = strippingLineComment(rawLine)
            let line = offset + 1
            if let module = importedModule(in: code), appleOnlyModules.contains(module),
                !gates.contains(where: { gatesImport($0, module: module) }) {
                found.append(Finding(path: path, line: line, item: module, kind: .appleOnlyImport))
            }
            guard !gates.contains(where: isPlatformGate) else { continue }
            for trap in traps where trap.matches(code) {
                found.append(Finding(path: path, line: line, item: trap.name, kind: .corelibsTrap))
            }
        }
        return found
    }

    /// `#if canImport(X)` is the only gate that makes `import X` portable by
    /// construction — the compiler drops the import where the module is absent,
    /// which is exactly how the port branch carries the Apple-only spellings. It
    /// is matched per module, so a `canImport(os)` gate cannot launder an
    /// `import Network` sitting inside it, and `#if DEBUG` or `#if os(macOS)`
    /// launder nothing at all.
    private static func gatesImport(_ gate: String, module: String) -> Bool {
        gate.contains("canImport(\(module))") && !gate.contains("!canImport(")
    }

    /// A trap has no module to match against, so any un-negated platform gate
    /// counts: the Apple-only spelling then only compiles where it exists.
    private static func isPlatformGate(_ gate: String) -> Bool {
        (gate.contains("canImport(") || gate.contains("os(")) && !gate.contains("!")
    }

    private enum Directive {
        case begin(String)
        case alternative(String)
        case end
    }

    private static func conditionalDirective(in line: String) -> Directive? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#if ") { return .begin(String(trimmed.dropFirst("#if ".count))) }
        if trimmed.hasPrefix("#elseif ") { return .alternative(String(trimmed.dropFirst("#elseif ".count))) }
        // An `#else` branch holds where its `#if` condition does *not*, so it
        // carries no gate — the empty condition matches neither check above.
        if trimmed == "#else" { return .alternative("") }
        if trimmed == "#endif" { return .end }
        return nil
    }

    private static func apply(_ directive: Directive, to gates: inout [String]) {
        switch directive {
        case let .begin(condition):
            gates.append(condition)
        case let .alternative(condition):
            if !gates.isEmpty { gates.removeLast() }
            gates.append(condition)
        case .end:
            if !gates.isEmpty { gates.removeLast() }
        }
    }

    /// The module a top-level `import` line brings in, tolerating attributes,
    /// access-level imports and the `import struct Foundation.Data` form. Anything
    /// else — a `let`, a call, a stripped comment — is nil.
    private static func importedModule(in line: String) -> String? {
        var tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = tokens.first, first.hasPrefix("@") || importModifiers.contains(first) {
            tokens.removeFirst()
        }
        guard tokens.first == "import", tokens.count > 1 else { return nil }
        var module = tokens[1]
        if declarationKinds.contains(module), tokens.count > 2 { module = tokens[2] }
        return module.split(separator: ".").first.map(String.init)
    }

    private static let importModifiers: Set<String> = [
        "fileprivate", "internal", "package", "private", "public",
    ]

    private static let declarationKinds: Set<String> = [
        "actor", "class", "enum", "func", "let", "macro", "protocol", "struct", "typealias", "var",
    ]

    /// Cut a `//` comment off a line, so a trap or import *named in prose* is not
    /// a hit. A `//` inside a string literal (a URL) truncates the rest of that
    /// line too, which can only hide a violation, never invent one.
    private static func strippingLineComment(_ line: String) -> String {
        guard let marker = line.range(of: "//") else { return line }
        return String(line[line.startIndex..<marker.lowerBound])
    }

    // MARK: - The source tree

    private struct MissingSourceTree: Error, CustomStringConvertible {
        let path: String
        var description: String { "ADBKit sources are not readable at \(path)" }
    }

    /// `<package>/Tests/ADBKitTests/PortabilityGuardTests.swift` →
    /// `<package>/Sources`, derived from `#filePath` so the suite carries no
    /// hardcoded host path and does not depend on the working directory.
    private static var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ADBKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the package root
            .appendingPathComponent("Sources")
    }

    /// Every Swift file under `Sources`, keyed by its path relative to it
    /// (`ADBKit/Services/HostNetwork.swift`, `ReactotronMCP/McpResources.swift`).
    private static func sourceFiles() throws -> [(path: String, contents: String)] {
        let root = sourcesRoot
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw MissingSourceTree(path: root.path)
        }
        var files: [(path: String, contents: String)] = []
        for case let relativePath as String in walker where relativePath.hasSuffix(".swift") {
            let file = root.appendingPathComponent(relativePath)
            files.append((relativePath, try String(contentsOf: file, encoding: .utf8)))
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Findings across the real tree, minus the Apple-bound subsystems.
    private static func liveFindings() throws -> [Finding] {
        try sourceFiles()
            .filter { file in !appleBoundSubsystems.contains(where: { file.path.hasPrefix($0) }) }
            .flatMap { findings(in: $0.contents, path: $0.path) }
    }

    private static func isKnownDebt(_ finding: Finding) -> Bool {
        knownDebt[finding.path]?.contains(finding.item) ?? false
    }

    // MARK: - The guard

    @Test func noAppleOnlyImportsOutsideTheAppleBoundSubsystems() throws {
        let offenders = try Self.liveFindings()
            .filter { $0.kind == .appleOnlyImport && !Self.isKnownDebt($0) }
        #expect(
            offenders.isEmpty,
            """
            Apple-only import in ADBKit: \(offenders.map(\.description).joined(separator: ", ")). \
            These sources also compile against corelibs-Foundation on the Windows/Linux port, \
            where the module does not exist. Use a portable API, or move the code into its own \
            file behind `#if canImport(<Module>)`.
            """
        )
    }

    @Test func noCorelibsFoundationTrapsOutsideTheAppleBoundSubsystems() throws {
        let offenders = try Self.liveFindings()
            .filter { $0.kind == .corelibsTrap && !Self.isKnownDebt($0) }
        #expect(
            offenders.isEmpty,
            """
            corelibs-Foundation trap in ADBKit: \(offenders.map(\.description).joined(separator: ", ")). \
            Each of these has a portable spelling on `feat/cross-platform-core`; a Darwin-only one \
            here becomes a rebase conflict there.
            """
        )
    }

    @Test func everyKnownDebtEntryIsStillALiveViolation() throws {
        // The allowlist is an inventory, not a licence: when the port's fix lands
        // (or the code goes away) the entry has to go with it, or it silently
        // exempts a file that no longer needs exempting.
        let live = Set(try Self.liveFindings().map { "\($0.path) \($0.item)" })
        for (path, items) in Self.knownDebt {
            for item in items {
                #expect(
                    live.contains("\(path) \(item)"),
                    "knownDebt still allows \(item) in \(path), which no longer uses it — delete the entry"
                )
            }
        }
    }

    @Test func theGuardWalksTheWholeSourceTree() throws {
        // Without this, a wrong `sourcesRoot` would make every check above pass by
        // scanning nothing at all.
        let files = try Self.sourceFiles()
        #expect(files.count > 100, "expected the whole ADBKit tree, found \(files.count) Swift files")
        #expect(files.contains { $0.path == "ADBKit/Features/FeatureRegistry.swift" })
        #expect(files.contains { $0.path == "ReactotronMCP/McpToolRegistry.swift" })
    }

    // MARK: - The guard's own teeth

    @Test func theScanFlagsUngatedImportsAndAcceptsOnlyAMatchingCanImportGate() {
        func items(_ source: String) -> [String] {
            Self.findings(in: source, path: "ADBKit/Services/NewService.swift").map(\.item)
        }

        #expect(items("import Foundation\nimport Network\n") == ["Network"])
        #expect(items("@preconcurrency import CryptoKit\n") == ["CryptoKit"])
        #expect(items("internal import class AppKit.NSWindow\n") == ["AppKit"])
        // The gate that makes the import portable.
        #expect(items("#if canImport(Network)\nimport Network\n#endif\n").isEmpty)
        // A gate for a different module launders nothing…
        #expect(items("#if canImport(os)\nimport Network\n#endif\n") == ["Network"])
        // …nor does the `#else` branch of one…
        #expect(items("#if canImport(os)\nimport os\n#else\nimport Network\n#endif\n") == ["Network"])
        // …nor a gate that is not about module availability.
        #expect(items("#if DEBUG\nimport CryptoKit\n#endif\n") == ["CryptoKit"])
        #expect(items("#if !canImport(os)\nimport os\n#endif\n") == ["os"])
        // Prose is not a use.
        #expect(items("// import Network — never do this\n/// `import os` is out too\n").isEmpty)
    }

    @Test func theScanFlagsTheTrapsItClaimsToCatchAndLeavesLookalikesAlone() {
        func items(_ source: String) -> [String] {
            Self.findings(in: source, path: "ADBKit/Services/NewService.swift").map(\.item)
        }

        #expect(items("private let state = OSAllocatedUnfairLock(initialState: 0)\n")
            == ["OSAllocatedUnfairLock"])
        #expect(items("let detector = try NSDataDetector(types: 0)\n") == ["NSDataDetector"])
        #expect(items("_ = try FileManager.default.replaceItemAt(url, withItemAt: temp)\n")
            == ["FileManager.replaceItemAt"])
        #expect(items("guard posix_spawn(&pid, path, nil, nil, argv, envp) == 0 else { return }\n")
            == ["posix_spawn"])
        #expect(items("for try await line in handle.bytes.lines {\n") == ["FileHandle.bytes"])
        // A platform gate is the portable spelling, so it is not a finding.
        #expect(items("#if canImport(Darwin)\nposix_spawn(&pid, path, nil, nil)\n#endif\n").isEmpty)
        // An unrelated `.bytes` property, a doc comment, and a name that merely
        // contains a trap word are all left alone.
        #expect(items("let count = packet.bytes.count\n").isEmpty)
        #expect(items("/// Never use OSAllocatedUnfairLock or posix_spawn here.\n").isEmpty)
        #expect(items("let compression = CompressionLevel.none\n").isEmpty)
    }
}
