import Testing

@testable import ADBKit

@Suite struct SimulatorLogParserTests {
    private func event(
        message: String = "hello world",
        type: String = "Default",
        timestamp: String = "2026-07-15 10:11:12.123456+0530",
        pid: Int = 4242,
        imagePath: String = "/Containers/Bundle/Application/ABC/MyApp.app/MyApp",
        subsystem: String = ""
    ) -> String {
        """
        {"eventMessage":"\(message)","messageType":"\(type)","timestamp":"\(timestamp)",\
        "processID":\(pid),"processImagePath":"\(imagePath)","subsystem":"\(subsystem)"}
        """
    }

    @Test func parsesAnNdjsonEvent() {
        let line = SimulatorLogParser.parse(event())
        #expect(line != nil)
        #expect(line?.time == "10:11:12.123")
        #expect(line?.pid == "4242")
        #expect(line?.level == "I")
        #expect(line?.tag == "MyApp")
        #expect(line?.message == "hello world")
        #expect(line?.searchKey == line?.raw.lowercased())
    }

    @Test func mapsMessageTypesOntoLogcatLevels() {
        #expect(SimulatorLogParser.parse(event(type: "Fault"))?.level == "F")
        #expect(SimulatorLogParser.parse(event(type: "Error"))?.level == "E")
        #expect(SimulatorLogParser.parse(event(type: "Debug"))?.level == "D")
        #expect(SimulatorLogParser.parse(event(type: "Info"))?.level == "I")
        #expect(SimulatorLogParser.parse(event(type: "Default"))?.level == "I")
    }

    @Test func subsystemPrefixesTheMessage() {
        let line = SimulatorLogParser.parse(event(message: "tick", subsystem: "com.example.net"))
        #expect(line?.message == "[com.example.net] tick")
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
        #expect(line?.tag == "")
        #expect(line?.level == "I")
        #expect(line?.message == "bare")
    }

    @Test func buildsArgsWithoutALevel() {
        #expect(SimulatorLogParser.buildArgs(udid: "UDID-1", level: nil)
            == ["simctl", "spawn", "UDID-1", "log", "stream", "--style", "ndjson"])
    }

    @Test func buildsArgsWithALevel() {
        #expect(SimulatorLogParser.buildArgs(udid: "UDID-1", level: "debug")
            == ["simctl", "spawn", "UDID-1", "log", "stream", "--style", "ndjson", "--level", "debug"])
    }
}
