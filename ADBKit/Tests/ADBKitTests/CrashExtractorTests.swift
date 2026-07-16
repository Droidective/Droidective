import Testing
@testable import ADBKit

@Suite struct CrashExtractorTests {
    @Test func formatsForDestinations() {
        #expect(CrashExtractor.format("boom", as: .slack) == "```\nboom\n```")
        #expect(CrashExtractor.format("boom", as: .jira) == "{code}\nboom\n{code}")
        #expect(CrashExtractor.format("boom", as: .plain) == "boom")
    }

    @Test func crashesQueriesTheCrashBufferWithExactArgs() async throws {
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "logcat", "-d", "-b", "crash"],
            stdout: "E AndroidRuntime: FATAL EXCEPTION: main\nE AndroidRuntime: java.lang.X: boom"
        )
        let extractor = CrashExtractor(client: await makeTestClient(runner: runner))

        let reports = try await extractor.crashes(serial: "S1")
        #expect(reports.count == 1)
        #expect(reports.first?.title == "java.lang.X: boom")
        let invocation = try #require(runner.invocations.first { $0.arguments.contains("logcat") })
        #expect(invocation.arguments == [
            "-s", "S1", "logcat", "-d", "-b", "crash", "-v", "threadtime", "-t", "1000",
        ])
        // Main buffer never queried when the crash buffer has content.
        #expect(!runner.invocations.contains { $0.arguments.contains("main") })
    }

    @Test func crashesAreNewestFirst() async throws {
        let runner = MockProcessRunner()
        let buffer = """
        E AndroidRuntime: FATAL EXCEPTION: main
        E AndroidRuntime: java.lang.IllegalStateException: first boom
        E AndroidRuntime: FATAL EXCEPTION: main
        E AndroidRuntime: java.lang.NullPointerException: second boom
        """
        runner.script(argsPrefix: ["-s", "S1", "logcat", "-d", "-b", "crash"], stdout: buffer)
        let extractor = CrashExtractor(client: await makeTestClient(runner: runner))

        let reports = try await extractor.crashes(serial: "S1")
        #expect(reports.count == 2)
        #expect(reports.first?.title.contains("second boom") == true)
        #expect(reports.last?.title.contains("first boom") == true)
    }

    @Test func crashBufferContentWithoutAPatternMatchIsShownAsIs() async throws {
        // Some traces don't hit the crash pattern; the buffer must still surface.
        let runner = MockProcessRunner()
        runner.script(
            argsPrefix: ["-s", "S1", "logcat", "-d", "-b", "crash"],
            stdout: "F DEBUG: signal 11 (SIGSEGV), fault addr 0xdeadbeef"
        )
        let extractor = CrashExtractor(client: await makeTestClient(runner: runner))

        let reports = try await extractor.crashes(serial: "S1")
        #expect(reports.count == 1)
        #expect(reports.first?.raw == "F DEBUG: signal 11 (SIGSEGV), fault addr 0xdeadbeef")
    }

    @Test func fallsBackToMainBufferWhenCrashBufferEmpty() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "logcat", "-d", "-b", "crash"], stdout: "\n")
        runner.script(
            argsPrefix: ["-s", "S1", "logcat", "-d", "-b", "main"],
            stdout: "I Boring: x\nE ReactNativeJS: TypeError: boom\nE ReactNativeJS: stack line"
        )
        let extractor = CrashExtractor(client: await makeTestClient(runner: runner))

        let reports = try await extractor.crashes(serial: "S1")
        #expect(reports.first?.title == "TypeError: boom")
        let mainQuery = try #require(runner.invocations.first { $0.arguments.contains("main") })
        #expect(mainQuery.arguments == [
            "-s", "S1", "logcat", "-d", "-b", "main", "-v", "threadtime", "-t", "2000",
        ])
    }

    @Test func noCrashAnywhereReturnsNothing() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "logcat", "-d", "-b", "crash"], stdout: "")
        runner.script(argsPrefix: ["-s", "S1", "logcat", "-d", "-b", "main"], stdout: "I Tag: fine")
        let extractor = CrashExtractor(client: await makeTestClient(runner: runner))

        #expect(try await extractor.crashes(serial: "S1").isEmpty)
    }

    @Test func clearCrashBufferSendsExactArgs() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "logcat", "-c"], stdout: "")
        let extractor = CrashExtractor(client: await makeTestClient(runner: runner))

        try await extractor.clearCrashBuffer(serial: "S1")
        let invocation = try #require(runner.invocations.first { $0.arguments.contains("-c") })
        #expect(invocation.arguments == ["-s", "S1", "logcat", "-c", "-b", "crash"])
    }

    @Test func boundedBlockKeepsShortInputUnchanged() {
        let s = "line1\nline2\nline3"
        #expect(CrashExtractor.boundedBlock(s) == s)
    }

    @Test func boundedBlockKeepsHeadAndMostRecentTail() {
        let many = (1...1000).map { "line \($0)" }.joined(separator: "\n")
        let bounded = CrashExtractor.boundedBlock(many, maxLines: 50, maxChars: 1_000_000)
        let lines = bounded.split(separator: "\n")
        #expect(lines.count <= 50)
        // The head (the exception line in a real crash) is never dropped...
        #expect(lines.first == "line 1")
        // ...and the most recent lines survive too, with the middle elided.
        #expect(lines.last == "line 1000")
        #expect(bounded.contains("lines elided"))
    }

    @Test func boundedBlockExactlyAtLineLimitIsUntouched() {
        let exact = (1...50).map { "line \($0)" }.joined(separator: "\n")
        #expect(CrashExtractor.boundedBlock(exact, maxLines: 50, maxChars: 1_000_000) == exact)
    }

    @Test func boundedBlockCapsAHugeSingleLineAndKeepsBothEnds() {
        let huge = "HEAD" + String(repeating: "x", count: 200_000) + "TAIL"
        let bounded = CrashExtractor.boundedBlock(huge, maxChars: 64 * 1024)
        #expect(bounded.count <= 64 * 1024 + 64)
        #expect(bounded.hasPrefix("HEAD"))
        #expect(bounded.hasSuffix("TAIL"))
    }
}
