import Foundation
@testable import ADBKit

/// Scripted process runner: matches invocations against argument prefixes and
/// records every call for assertion.
final class MockProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var scripts: [(argsPrefix: [String], output: ProcessOutput)] = []
    private var recorded: [Invocation] = []

    var invocations: [Invocation] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Respond to any invocation whose arguments start with `argsPrefix`.
    /// The most recently registered matching script wins, so tests can lay
    /// down defaults and override specific commands afterwards.
    func script(argsPrefix: [String], stdout: String = "", stderr: String = "", exitCode: Int32? = 0, timedOut: Bool = false) {
        lock.lock()
        scripts.append((
            argsPrefix,
            ProcessOutput(stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), exitCode: exitCode, timedOut: timedOut)
        ))
        lock.unlock()
    }

    func run(executable: String, arguments: [String], timeout: Duration, maxOutputBytes: Int) async -> ProcessOutput {
        recordAndMatch(executable: executable, arguments: arguments)
            ?? ProcessOutput(stdout: Data(), stderr: Data("unscripted invocation".utf8), exitCode: 1, timedOut: false)
    }

    private func recordAndMatch(executable: String, arguments: [String]) -> ProcessOutput? {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(Invocation(executable: executable, arguments: arguments))
        return scripts.last { arguments.starts(with: $0.argsPrefix) }?.output
    }
}

/// A client whose locator is pre-seeded with a fake adb path, so tests never
/// touch the filesystem or login shell.
func makeTestClient(runner: MockProcessRunner) async -> AdbClient {
    let locator = ToolLocator(runner: runner, environment: [:])
    await locator.seed(.adb, path: "/fake/adb")
    return AdbClient(locator: locator, runner: runner, log: CommandLog())
}

/// An overrides store rooted in a unique temp directory.
func makeTempOverridesStore() -> JSONStore<OverridesMap> {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("adbkit-overrides-\(UUID().uuidString)")
    return JSONStore(filename: "overrides.json", default: [:], directory: dir)
}

/// A stub binary at `url` that the host's own `isExecutableFile` will accept.
///
/// On Windows that has to be a real PE image. `isExecutableFile` there asks
/// Windows what kind of binary the file is, so a shell script named `.exe` is
/// not executable and every SDK tool "resolves" as missing — which surfaces
/// far away, as a nil package name rather than as a missing tool. Copying a
/// system binary keeps the real predicate (the one production uses) under
/// test instead of stubbing out the resolution the test exists to exercise;
/// `MockProcessRunner` intercepts the spawn, so the stub is never run.
func createExecutableStub(at url: URL) throws {
    let fm = FileManager.default
    #if os(Windows)
    let source = ProcessInfo.processInfo.environment["ComSpec"]
        ?? #"C:\Windows\System32\cmd.exe"#
    try? fm.removeItem(at: url)
    try fm.copyItem(atPath: source, toPath: url.path)
    #else
    _ = fm.createFile(
        atPath: url.path, contents: Data("#!/bin/sh\n".utf8),
        attributes: [.posixPermissions: 0o755])
    #endif
    // Checked rather than assumed: a stub the host declines to call
    // executable makes the tool resolve as missing, and the resulting failure
    // names neither the stub nor the tool.
    guard fm.isExecutableFile(atPath: url.path) else {
        throw StubNotExecutable(path: url.path, exists: fm.fileExists(atPath: url.path))
    }
}

struct StubNotExecutable: Error, CustomStringConvertible {
    let path: String
    let exists: Bool
    var description: String {
        "the host does not consider \(path) executable (file exists: \(exists))"
    }
}
