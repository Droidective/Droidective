import Testing

@testable import ADBKit

@Suite struct SimulatorLogParserTests {
    private func event(
        message: String = "hello world",
        type: String = "Default",
        timestamp: String = "2026-07-15 10:11:12.123456+0530",
        pid: Int = 4242,
        imagePath: String = "/Containers/Bundle/Application/ABC/MyApp.app/MyApp",
        subsystem: String = "com.example.net",
        category: String = "session"
    ) -> String {
        """
        {"eventMessage":"\(message)","messageType":"\(type)","timestamp":"\(timestamp)",\
        "processID":\(pid),"processImagePath":"\(imagePath)","subsystem":"\(subsystem)",\
        "category":"\(category)"}
        """
    }

    @Test func parsesAnNdjsonEvent() {
        let line = SimulatorLogParser.parse(event())
        #expect(line != nil)
        #expect(line?.time == "10:11:12.123")
        #expect(line?.pid == "4242")
        #expect(line?.level == .notice)
        #expect(line?.process == "MyApp")
        #expect(line?.subsystem == "com.example.net")
        #expect(line?.category == "session")
        #expect(line?.message == "hello world")
    }

    @Test func searchKeyCoversEveryFilterableField() {
        let line = SimulatorLogParser.parse(event(message: "Hello"))
        #expect(line?.searchKey == "myapp com.example.net session hello")
    }

    @Test func mapsMessageTypesOntoLevels() {
        #expect(SimulatorLogParser.parse(event(type: "Fault"))?.level == .fault)
        #expect(SimulatorLogParser.parse(event(type: "Error"))?.level == .error)
        #expect(SimulatorLogParser.parse(event(type: "Debug"))?.level == .debug)
        #expect(SimulatorLogParser.parse(event(type: "Info"))?.level == .info)
        #expect(SimulatorLogParser.parse(event(type: "Default"))?.level == .notice)
    }

    @Test func preambleAndNonJSONLinesAreDropped() {
        #expect(SimulatorLogParser.parse("Filtering the log data using \"process == 1\"") == nil)
        #expect(SimulatorLogParser.parse("") == nil)
    }

    @Test func eventWithoutAMessageIsDropped() {
        #expect(SimulatorLogParser.parse(#"{"messageType":"Default","processID":1}"#) == nil)
        #expect(SimulatorLogParser.parse(event(message: "")) == nil)
    }

    @Test func missingFieldsFallBackToEmpty() {
        let line = SimulatorLogParser.parse(#"{"eventMessage":"bare"}"#)
        #expect(line != nil)
        #expect(line?.time == "")
        #expect(line?.pid == "")
        #expect(line?.process == "")
        #expect(line?.subsystem == "")
        #expect(line?.level == .notice)
        #expect(line?.message == "bare")
    }

    @Test func appsScopeAddsThePredicate() {
        #expect(SimulatorLogParser.buildArgs(udid: "UDID-1", scope: .apps, emit: nil) == [
            "simctl", "spawn", "UDID-1", "log", "stream", "--style", "ndjson",
            "--predicate", #"processImagePath CONTAINS "/Containers/Bundle/Application/""#,
        ])
    }

    @Test func everythingScopeStreamsUnfiltered() {
        #expect(SimulatorLogParser.buildArgs(udid: "UDID-1", scope: .everything, emit: nil)
            == ["simctl", "spawn", "UDID-1", "log", "stream", "--style", "ndjson"])
    }

    @Test func emitWidensTheLevel() {
        #expect(SimulatorLogParser.buildArgs(udid: "U", scope: .everything, emit: "debug")
            == ["simctl", "spawn", "U", "log", "stream", "--style", "ndjson", "--level", "debug"])
    }

    @Test func exportTextCarriesTheStructuredFields() {
        let line = SimulatorLogParser.parse(event(message: "tick", type: "Error"))
        #expect(line?.exportText == "10:11:12.123 MyApp(4242) Error [com.example.net:session]: tick")
    }
}

@Suite struct SimulatorLogFilterTests {
    private func line(
        process: String = "MyApp", level: SimLogLevel = .notice, message: String = "hello"
    ) -> SimLogLine {
        SimLogLine(
            time: "10:00:00.000", process: process, pid: "1", level: level,
            subsystem: "com.example", category: "general", message: message
        )
    }

    @Test func levelSetFilters() {
        let error = line(level: .error)
        let debug = line(level: .debug)
        let visible = SimulatorLogFilter.visible(
            [error, debug], levels: [.error, .fault], process: nil, filter: "")
        #expect(visible == [error])
    }

    @Test func processFilterIsExact() {
        let mine = line(process: "MyApp")
        let other = line(process: "MyAppHelper")
        let visible = SimulatorLogFilter.visible(
            [mine, other], levels: Set(SimLogLevel.allCases), process: "MyApp", filter: "")
        #expect(visible == [mine])
    }

    @Test func textFilterIsCaseInsensitiveAndCoversSubsystem() {
        let hit = line(message: "Connection FAILED")
        let bySubsystem = line(message: "ok")
        let miss = SimLogLine(
            time: "", process: "Other", pid: "2", level: .notice,
            subsystem: "io.acme", category: "db", message: "ok"
        )
        let all = Set(SimLogLevel.allCases)
        #expect(SimulatorLogFilter.visible([hit, miss], levels: all, process: nil, filter: "failed") == [hit])
        #expect(SimulatorLogFilter.visible([bySubsystem, miss], levels: all, process: nil, filter: "example") == [bySubsystem])
    }

    @Test func filtersCombine() {
        let match = line(process: "MyApp", level: .error, message: "timeout")
        let wrongLevel = line(process: "MyApp", level: .info, message: "timeout")
        let wrongProcess = line(process: "Other", level: .error, message: "timeout")
        let visible = SimulatorLogFilter.visible(
            [match, wrongLevel, wrongProcess],
            levels: [.error], process: "MyApp", filter: "time")
        #expect(visible == [match])
    }

    @Test func findMatchesFollowStreamOrder() {
        let first = line(message: "hit one")
        let second = line(message: "miss")
        let third = line(message: "hit two")
        #expect(SimulatorLogFilter.findMatches(in: [first, second, third], query: "HIT")
            == [first.id, third.id])
        #expect(SimulatorLogFilter.findMatches(in: [first], query: "").isEmpty)
    }

    @Test func processCountsAreBusiestFirstThenAlphabetical() {
        let lines = [
            line(process: "Beta"), line(process: "Alpha"),
            line(process: "Beta"), line(process: "Gamma"),
            SimLogLine(
                time: "", process: "", pid: "", level: .notice,
                subsystem: "", category: "", message: "no process"
            ),
        ]
        let counts = SimulatorLogFilter.processCounts(lines)
        #expect(counts.map(\.name) == ["Beta", "Alpha", "Gamma"])
        #expect(counts.map(\.count) == [2, 1, 1])
    }

    @Test func levelsAreOrderedBySeverity() {
        #expect(SimLogLevel.debug < .info)
        #expect(SimLogLevel.info < .notice)
        #expect(SimLogLevel.notice < .error)
        #expect(SimLogLevel.error < .fault)
    }
}
