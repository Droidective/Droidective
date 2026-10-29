import Foundation
import Testing

/// The relaunch helper is a real shell, so it is run for real: it must wait
/// for the process to exit, and then pass the bundle path through untouched.
@Suite struct AppRelaunchTests {
    @Test func opensOnlyAfterTheProcessExitsAndPassesThePathIntact() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relaunch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Spaces, a quote and a `$` — the path has to arrive as one argument,
        // never re-read by the shell.
        let opened = dir.appendingPathComponent("My \"Apps\" $HOME.app")

        let app = Process()
        app.executableURL = URL(fileURLWithPath: "/bin/sleep")
        app.arguments = ["1"]
        try app.run()

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // `touch` stands in for `open`: it leaves a file named exactly as the
        // path it was handed.
        helper.arguments = AppRelaunch.helperArguments(
            waitingFor: app.processIdentifier, appPath: opened.path, opener: "/usr/bin/touch")
        try helper.run()

        try await Task.sleep(for: .milliseconds(400))
        #expect(app.isRunning)
        #expect(!FileManager.default.fileExists(atPath: opened.path))

        app.waitUntilExit()
        helper.waitUntilExit()
        #expect(helper.terminationStatus == 0)
        #expect(FileManager.default.fileExists(atPath: opened.path))
    }

    @Test func aProcessThatIsAlreadyGoneOpensRightAway() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relaunch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let opened = dir.appendingPathComponent("Droidective.app")

        let gone = Process()
        gone.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try gone.run()
        gone.waitUntilExit()

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = AppRelaunch.helperArguments(
            waitingFor: gone.processIdentifier, appPath: opened.path, opener: "/usr/bin/touch")
        try helper.run()
        helper.waitUntilExit()
        #expect(FileManager.default.fileExists(atPath: opened.path))
    }
}
