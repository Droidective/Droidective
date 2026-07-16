import Testing
@testable import ADBKit

@Suite struct CrashParserTests {
    @Test func parsesAJavaCrashWithMetadata() throws {
        let buffer = """
        --------- beginning of crash
        06-12 10:00:02.000  3123  3123 E AndroidRuntime: FATAL EXCEPTION: main
        06-12 10:00:02.001  3123  3123 E AndroidRuntime: Process: com.example.app, PID: 3123
        06-12 10:00:02.002  3123  3123 E AndroidRuntime: java.lang.NullPointerException: boom
        06-12 10:00:02.003  3123  3123 E AndroidRuntime: \tat com.example.Main.run(Main.java:10)
        """
        let reports = CrashParser.parse(buffer, source: .crashBuffer)
        #expect(reports.count == 1)
        let crash = try #require(reports.first)
        #expect(crash.kind == .java)
        #expect(crash.timestamp == "06-12 10:00:02.000")
        #expect(crash.process == "com.example.app")
        #expect(crash.pid == 3123)
        #expect(crash.title == "java.lang.NullPointerException: boom")
        #expect(crash.raw.contains("06-12 10:00:02.000"))
        // The body is prefix-stripped — messages only.
        #expect(crash.body.hasPrefix("FATAL EXCEPTION: main"))
        #expect(!crash.body.contains("AndroidRuntime"))
    }

    @Test func splitsSeveralCrashesInChronologicalOrder() {
        let buffer = """
        E AndroidRuntime: FATAL EXCEPTION: main
        E AndroidRuntime: java.lang.IllegalStateException: first boom
        E AndroidRuntime: \tat com.app.First.run(First.java:1)
        E AndroidRuntime: FATAL EXCEPTION: main
        E AndroidRuntime: java.lang.NullPointerException: second boom
        E AndroidRuntime: \tat com.app.Second.run(Second.java:9)
        """
        let reports = CrashParser.parse(buffer, source: .crashBuffer)
        #expect(reports.count == 2)
        #expect(reports[0].title.contains("first boom"))
        #expect(reports[1].title.contains("second boom"))
        #expect(reports[0].raw.contains("First.run"))
        #expect(!reports[0].raw.contains("second boom"))
    }

    @Test func nativeCrashMergesSignalLineAndTombstone() throws {
        let buffer = """
        06-12 11:00:00.000  4001  4001 F libc    : Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0 in tid 4001 (com.app.native)
        06-12 11:00:00.100  4100  4100 F DEBUG   : *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
        06-12 11:00:00.101  4100  4100 F DEBUG   : Build fingerprint: 'google/panther/panther:14'
        06-12 11:00:00.102  4100  4100 F DEBUG   : pid: 4001, tid: 4001, name: app.native  >>> com.app.native <<<
        06-12 11:00:00.103  4100  4100 F DEBUG   : signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0
        06-12 11:00:00.104  4100  4100 F DEBUG   :       #00 pc 000000000004f6f0  /apex/libc.so
        """
        let reports = CrashParser.parse(buffer, source: .crashBuffer)
        #expect(reports.count == 1)
        let crash = try #require(reports.first)
        #expect(crash.kind == .native)
        #expect(crash.title == "Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR)")
        #expect(crash.process == "com.app.native")
        #expect(crash.raw.contains("#00 pc"))
    }

    @Test func twoNativeCrashesSplitOnTheirSignalLines() {
        let buffer = """
        F libc    : Fatal signal 11 (SIGSEGV), fault addr 0x0 in tid 1 (a)
        F DEBUG   : *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
        F DEBUG   : pid: 1, tid: 1, name: a  >>> com.app.a <<<
        F libc    : Fatal signal 6 (SIGABRT), fault addr ------ in tid 2 (b)
        F DEBUG   : *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
        F DEBUG   : pid: 2, tid: 2, name: b  >>> com.app.b <<<
        """
        let reports = CrashParser.parse(buffer, source: .crashBuffer)
        #expect(reports.count == 2)
        #expect(reports[0].process == "com.app.a")
        #expect(reports[1].process == "com.app.b")
    }

    @Test func reactNativeErrorParsedFromMainBuffer() throws {
        let buffer = """
        06-12 12:00:00.000  5000  5000 I ReactNativeJS: app booted
        06-12 12:00:01.000  5000  5000 E ReactNativeJS: TypeError: undefined is not a function
        06-12 12:00:01.001  5000  5000 E ReactNativeJS: at onPress (index.bundle:100:20)
        06-12 12:00:02.000  5001  5001 I OtherApp: unrelated noise
        """
        let reports = CrashParser.parse(buffer, source: .mainBuffer)
        #expect(reports.count == 1)
        let crash = try #require(reports.first)
        #expect(crash.kind == .reactNative)
        #expect(crash.title == "TypeError: undefined is not a function")
        #expect(crash.raw.contains("onPress"))
        #expect(!crash.raw.contains("unrelated noise"))
        #expect(!crash.raw.contains("app booted"))
    }

    @Test func mainBufferNoiseBetweenCrashLinesSealsTheBlock() throws {
        let buffer = """
        06-12 12:00:00.000  100  100 E AndroidRuntime: FATAL EXCEPTION: main
        06-12 12:00:00.001  100  100 E AndroidRuntime: java.lang.RuntimeException: boom
        06-12 12:00:00.002  999  999 I Noise: interleaved line
        06-12 12:00:00.003  100  100 E AndroidRuntime: \tat late.frame(Late.java:1)
        """
        let reports = CrashParser.parse(buffer, source: .mainBuffer)
        #expect(reports.count == 1)
        let crash = try #require(reports.first)
        #expect(!crash.raw.contains("interleaved"))
        // The block sealed at the noise line — the late frame is dropped
        // rather than glued to a block foreign lines interrupted.
        #expect(!crash.raw.contains("late.frame"))
    }

    @Test func anrLineFromActivityManager() throws {
        let buffer = """
        06-12 13:00:00.000  800  900 E ActivityManager: ANR in com.example.app (com.example.app/.MainActivity)
        06-12 13:00:00.001  800  900 E ActivityManager: PID: 7777
        06-12 13:00:00.002  800  900 E ActivityManager: Reason: Input dispatching timed out
        """
        let reports = CrashParser.parse(buffer, source: .mainBuffer)
        #expect(reports.count == 1)
        let crash = try #require(reports.first)
        #expect(crash.kind == .anr)
        #expect(crash.process == "com.example.app")
        #expect(crash.title.hasPrefix("ANR in com.example.app"))
        #expect(crash.raw.contains("Input dispatching timed out"))
    }

    @Test func crlfInputSplitsCleanly() {
        let buffer = "E AndroidRuntime: FATAL EXCEPTION: main\r\n"
            + "E AndroidRuntime: java.lang.RuntimeException: crlf boom\r\n"
            + "E AndroidRuntime: \tat com.app.A.b(A.java:1)"
        let reports = CrashParser.parse(buffer, source: .crashBuffer)
        #expect(reports.count == 1)
        #expect(reports.first?.title == "java.lang.RuntimeException: crlf boom")
    }

    @Test func emptyAndCrashFreeInputYieldNothing() {
        #expect(CrashParser.parse("", source: .crashBuffer).isEmpty)
        #expect(CrashParser.parse("   \n\n", source: .crashBuffer).isEmpty)
        #expect(CrashParser.parse(
            "06-12 10:00:00.000 1 1 I Tag: all good", source: .mainBuffer
        ).isEmpty)
    }

    @Test func crashBufferContentWithoutAMarkerSurfacesAsOneReport() throws {
        // Some native traces don't hit any start marker; the buffer must
        // still surface rather than silently reading as "no crashes".
        let reports = CrashParser.parse(
            "F DEBUG: unusual trace, fault addr 0xdeadbeef", source: .crashBuffer
        )
        #expect(reports.count == 1)
        let crash = try #require(reports.first)
        #expect(crash.kind == .unknown)
        #expect(crash.raw == "F DEBUG: unusual trace, fault addr 0xdeadbeef")
        #expect(crash.title == "unusual trace, fault addr 0xdeadbeef")
    }

    @Test func markerlessMainBufferYieldsNothing() {
        // The whole-buffer fallback is crash-buffer only — the main buffer is
        // mostly noise, so no marker there means no crash.
        #expect(CrashParser.parse("I Tag: fine\nI Tag: also fine", source: .mainBuffer).isEmpty)
    }

    @Test func identicalCrashesGetDistinctStableIDs() {
        let one = "E AndroidRuntime: FATAL EXCEPTION: main\nE AndroidRuntime: java.lang.X: same"
        let reports = CrashParser.parse(one + "\n" + one, source: .crashBuffer)
        #expect(reports.count == 2)
        #expect(reports[0].id != reports[1].id)
        // Re-parsing the same buffer reproduces the same ids, so list
        // selection survives a refresh.
        let again = CrashParser.parse(one + "\n" + one, source: .crashBuffer)
        #expect(again.map(\.id) == reports.map(\.id))
    }

    @Test func hugeCrashIsBounded() throws {
        let buffer = (["E AndroidRuntime: FATAL EXCEPTION: main",
                       "E AndroidRuntime: java.lang.OutOfMemoryError: big"]
            + (1...2000).map { "E AndroidRuntime: \tat com.app.F\($0).run(F.java:\($0))" })
            .joined(separator: "\n")
        let reports = CrashParser.parse(buffer, source: .crashBuffer)
        let crash = try #require(reports.first)
        #expect(crash.raw.components(separatedBy: "\n").count <= 200)
        #expect(crash.raw.contains("FATAL EXCEPTION"))
        #expect(crash.raw.contains("lines elided"))
    }
}
