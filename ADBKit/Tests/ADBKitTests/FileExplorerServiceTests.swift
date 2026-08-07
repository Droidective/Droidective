import Testing
@testable import ADBKit

@Suite struct FileExplorerServiceTests {
    private func makeService(_ runner: MockProcessRunner) async -> FileExplorerService {
        FileExplorerService(client: await makeTestClient(runner: runner))
    }

    @Test func cleanSuccessReportsPlainMessage() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "mkdir"], stdout: "", stderr: "", exitCode: 0)
        let result = try await makeService(runner).makeDirectory(serial: "S1", path: "/sdcard/New Folder")
        #expect(result.ok)
        #expect(result.message == "Folder created")
    }

    @Test func zeroExitWithStderrSucceedsWithWarning() async throws {
        // A toybox warning printed on a zero exit (the op still happened) must
        // not be misreported as a failure.
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "cp"],
            stdout: "", stderr: "cp: can't open 'sub': Permission denied", exitCode: 0
        )
        let result = try await makeService(runner).copy(serial: "S1", from: "/a", toDir: "/b")
        #expect(result.ok)
        #expect(result.message.contains("with warnings"))
    }

    @Test func nonZeroExitReportsFailure() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "shell", "rm"],
            stdout: "", stderr: "rm: No such file or directory", exitCode: 1
        )
        let result = try await makeService(runner).delete(serial: "S1", path: "/missing")
        #expect(!result.ok)
    }

    @Test func devicePathsAreShellQuoted() async throws {
        // Paths with spaces/metacharacters must reach the device shell quoted.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "mkdir"], stdout: "", exitCode: 0)
        _ = try await makeService(runner).makeDirectory(serial: "S1", path: "/sdcard/a b;c")
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "S1", "shell", "mkdir", "-p", "'/sdcard/a b;c'"]
        })
    }

    @Test func deletePathIsShellQuoted() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "rm"], stdout: "", exitCode: 0)
        _ = try await makeService(runner).delete(serial: "S1", path: "/sdcard/a b;rm -rf /")
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "S1", "shell", "rm", "-rf", "'/sdcard/a b;rm -rf /'"]
        })
    }

    @Test func copySourceAndDestinationAreShellQuoted() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "cp"], stdout: "", exitCode: 0)
        _ = try await makeService(runner).copy(serial: "S1", from: "/sdcard/a b", toDir: "/sdcard/c;d")
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "S1", "shell", "cp", "-r", "'/sdcard/a b'", "'/sdcard/c;d'"]
        })
    }

    @Test func listDirectoryIsShellQuotedWithATrailingSlash() async throws {
        // The trailing slash makes a symlinked dir (/sdcard → /storage/self/
        // primary) list its contents rather than the link, and it has to be
        // inside the quotes or the shell sees a bare `/`.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "ls"], stdout: "", exitCode: 0)
        _ = try await makeService(runner).list(serial: "S1", dir: "/sdcard/a b;rm -rf ~")
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "S1", "shell", "ls", "-la", "'/sdcard/a b;rm -rf ~/'"]
        })
    }

    @Test func infoPathIsShellQuoted() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "stat"], stdout: "", exitCode: 0)
        _ = try await makeService(runner).info(serial: "S1", path: "/sdcard/a b;whoami")
        #expect(runner.invocations.contains {
            $0.arguments == [
                "-s", "S1", "shell", "stat", "-c", "'%F|%s|%U|%A|%y|%z'", "'/sdcard/a b;whoami'",
            ]
        })
    }

    @Test func aRootedOperationQuotesTheWholeLineForSu() async throws {
        // `su -c` takes one argument, so the joined command is quoted again —
        // and the inner path stays quoted inside it. Getting this wrong is a
        // root shell running a device-supplied path unquoted.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "su"], stdout: "", exitCode: 0)
        _ = try await makeService(runner).delete(
            serial: "S1", path: "/data/a b;rm -rf /", asRoot: true)
        #expect(runner.invocations.contains {
            $0.arguments == [
                "-s", "S1", "shell", "su", "-c", #"'rm -rf '\''/data/a b;rm -rf /'\'''"#,
            ]
        })
    }

    @Test func moveSourceAndDestinationAreShellQuoted() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell", "mv"], stdout: "", exitCode: 0)
        _ = try await makeService(runner).move(serial: "S1", from: "/sdcard/a b", toDir: "/sdcard/c;d")
        #expect(runner.invocations.contains {
            $0.arguments == ["-s", "S1", "shell", "mv", "'/sdcard/a b'", "'/sdcard/c;d'"]
        })
    }
}
