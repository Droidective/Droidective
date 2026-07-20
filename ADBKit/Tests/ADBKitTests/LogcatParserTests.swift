import Testing
@testable import ADBKit

@Suite struct LogcatLineParserTests {
    @Test func parsesThreadtimeLine() {
        let line = LogcatLineParser.parse(
            "06-12 14:03:22.123  1234  5678 E ReactNativeJS: TypeError: undefined is not a function"
        )
        #expect(line.time == "06-12 14:03:22.123")
        #expect(line.pid == "1234")
        #expect(line.tid == "5678")
        #expect(line.level == "E")
        #expect(line.tag == "ReactNativeJS")
        #expect(line.message == "TypeError: undefined is not a function")
        // The cached search key backs the view's per-keystroke filter — it
        // must be the lowercased raw line.
        #expect(line.searchKey == line.raw.lowercased())
    }

    @Test func malformedLineHasNoTid() {
        #expect(LogcatLineParser.parse("not a log line").tid == "")
    }

    @Test func parsesProcessNameTable() {
        let output = """
        PID NAME
            1 init
          813 system_server
         3011 com.google.android.gms
        30246 com.google.android.webview:sandboxed_process0:org.chromium.content.app.SandboxedProcessService0:0
        garbage row
        """
        let names = LogcatLineParser.parseProcessNames(output)
        #expect(names["1"] == "init")
        #expect(names["813"] == "system_server")
        #expect(names["3011"] == "com.google.android.gms")
        #expect(names["30246"]?.hasPrefix("com.google.android.webview:sandboxed") == true)
        #expect(names["PID"] == nil)
        #expect(names.count == 4)
    }

    @Test func processNameTableHandlesCRLFAndEmpty() {
        #expect(LogcatLineParser.parseProcessNames("PID NAME\r\n  42 my.app\r\n")["42"] == "my.app")
        #expect(LogcatLineParser.parseProcessNames("").isEmpty)
    }

    @Test func parsesEmptyMessage() {
        let line = LogcatLineParser.parse("06-12 14:03:22.123  1234  5678 D MyTag: ")
        #expect(line.level == "D")
        #expect(line.tag == "MyTag")
        #expect(line.message == "")
    }

    @Test func malformedLineFallsBackToRaw() {
        let raw = "--------- beginning of main"
        let line = LogcatLineParser.parse(raw)
        #expect(line.level == "")
        #expect(line.message == raw)
        #expect(line.raw == raw)
    }

    @Test func tagWithColonInMessageParses() {
        let line = LogcatLineParser.parse("06-12 14:03:22.123  1 2 I Tag: key: value")
        #expect(line.tag == "Tag")
        #expect(line.message == "key: value")
    }

    @Test func buildsArgsWithAllFilters() {
        let filters = LogcatFilters(tail: 100, buffers: ["crash"], level: "W", pid: 4242)
        let args = LogcatLineParser.buildArgs(serial: "S1", filters: filters)
        #expect(args == ["-s", "S1", "logcat", "-v", "threadtime", "-T", "100", "-b", "crash", "--pid", "4242", "*:W"])
    }

    @Test func buildsMinimalArgs() {
        let args = LogcatLineParser.buildArgs(serial: "S1", filters: LogcatFilters())
        #expect(args == ["-s", "S1", "logcat", "-v", "threadtime", "-T", "300"])
    }
}
