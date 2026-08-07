@testable import ADBKit
import Foundation
import Testing

/// `MetroSymbolicator` — resolving a console call's bundle coordinates back to
/// the file the developer wrote, through Metro's `/symbolicate` endpoint.
/// Payloads here are recorded from a live Metro (React Native 0.82, Hermes).
struct MetroSymbolicatorTests {
    private let bundleURL = "http://localhost:8081/index.bundle//&platform=android&dev=true&app=com.streamlab"

    private func frame(_ line: Int, column: Int = 28, function: String = "anonymous", url: String? = nil) -> CDPCallFrame {
        CDPCallFrame(json: .object([
            "functionName": .string(function),
            "url": .string(url ?? bundleURL),
            "lineNumber": .number(Double(line)),
            "columnNumber": .number(Double(column)),
        ]))
    }

    /// CDP counts lines from zero and Metro from one. Getting this wrong points
    /// at the wrong source line instead of failing, so it's asserted directly.
    @Test func requestBodyIncrementsLineNumbersForMetro() throws {
        let body = MetroSymbolicator.requestBody([frame(87_065, column: 28, function: "emitLog")])
        let root = try JSONDecoder().decode(JSONValue.self, from: body)
        let entry = try #require(root["stack"]?.arrayValue?.first)
        #expect(entry["lineNumber"]?.intValue == 87_066)
        #expect(entry["column"]?.intValue == 28)
        #expect(entry["file"]?.stringValue == bundleURL)
        #expect(entry["methodName"]?.stringValue == "emitLog")
    }

    @Test func requestBodyNamesAnonymousFrames() throws {
        let body = MetroSymbolicator.requestBody([frame(1, function: "")])
        let root = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(root["stack"]?.arrayValue?.first?["methodName"]?.stringValue == "(anonymous)")
    }

    /// Hermes tops some stacks with a `global` frame carrying no URL; Metro
    /// can't resolve one and it would only waste the request.
    @Test func framesWithoutAURLAreNotSent() {
        let frames = [frame(1), frame(2, url: ""), frame(3)]
        let sendable = MetroSymbolicator.sendableFrames(frames)
        #expect(sendable.count == 2)
        #expect(sendable.map(\.lineNumber) == [1, 3])
        #expect(MetroSymbolicator.sendableFrames(Array(repeating: frame(1), count: 40), limit: 8).count == 8)
        #expect(MetroSymbolicator.sendableFrames([]).isEmpty)
    }

    /// The same call site must key to the same cache entry, and different ones
    /// must not collide.
    @Test func cacheKeyFollowsTheFrameCoordinates() {
        #expect(MetroSymbolicator.cacheKey([frame(10)]) == MetroSymbolicator.cacheKey([frame(10)]))
        #expect(MetroSymbolicator.cacheKey([frame(10)]) != MetroSymbolicator.cacheKey([frame(11)]))
        #expect(MetroSymbolicator.cacheKey([frame(10, column: 1)]) != MetroSymbolicator.cacheKey([frame(10, column: 2)]))
        #expect(MetroSymbolicator.cacheKey([frame(10)]) != MetroSymbolicator.cacheKey([frame(10), frame(11)]))
    }

    /// A real `/symbolicate` reply: React Native's console plumbing arrives
    /// flagged `collapse`, and the app's own frame is the one Chrome names.
    @Test func picksTheFirstFrameTheAppOwns() {
        let recorded = """
        {"codeFrame":null,"stack":[
          {"file":"/w/node_modules/@react-native/js-polyfills/console.js","lineNumber":667,"column":37,
           "methodName":"methodName","collapse":true},
          {"file":"/w/node_modules/reactotron-react-native/dist/plugins/trackGlobalLogs.js","lineNumber":18,
           "column":26,"methodName":"console.log","collapse":false},
          {"file":"/w/src/StreamScreen.tsx","lineNumber":142,"column":10,"methodName":"emitComplexLog",
           "collapse":false}
        ]}
        """
        let frames = MetroSymbolicator.parse(Data(recorded.utf8))
        #expect(frames.count == 3)
        #expect(frames[0].collapse)
        let location = MetroSymbolicator.location(in: frames)
        #expect(location?.file == "/w/src/StreamScreen.tsx")
        #expect(location?.line == 142)
        #expect(location?.function == "emitComplexLog")
        #expect(location?.label == "StreamScreen.tsx:142")
    }

    /// A log genuinely emitted from inside a dependency has no app frame — name
    /// the library rather than showing nothing.
    @Test func fallsBackWhenEveryFrameIsALibrary() {
        let json = """
        {"stack":[
          {"file":"/w/node_modules/a/index.js","lineNumber":3,"column":1,"methodName":"warn","collapse":true},
          {"file":"/w/node_modules/b/index.js","lineNumber":9,"column":1,"methodName":"emit","collapse":false}
        ]}
        """
        let location = MetroSymbolicator.location(in: MetroSymbolicator.parse(Data(json.utf8)))
        #expect(location?.label == "index.js:9")

        let allCollapsed = """
        {"stack":[{"file":"/w/node_modules/a/index.js","lineNumber":3,"column":1,"methodName":"w","collapse":true}]}
        """
        #expect(MetroSymbolicator.location(in: MetroSymbolicator.parse(Data(allCollapsed.utf8)))?.label == "index.js:3")
    }

    @Test func malformedAndEmptyRepliesResolveToNothing() {
        #expect(MetroSymbolicator.parse(Data("not json".utf8)).isEmpty)
        #expect(MetroSymbolicator.parse(Data(#"{"stack":[]}"#.utf8)).isEmpty)
        #expect(MetroSymbolicator.parse(Data(#"{}"#.utf8)).isEmpty)
        // Metro answers an unresolvable frame with an empty file — nothing to name.
        #expect(MetroSymbolicator.parse(Data(#"{"stack":[{"file":"","lineNumber":1}]}"#.utf8)).isEmpty)
        #expect(MetroSymbolicator.location(in: []) == nil)
    }

    /// A resolved stack reads as source lines, with the frames the reader
    /// didn't write marked so the view can dim them.
    @Test func resolvedFramesReadAsSourceLines() {
        let json = """
        {"stack":[
          {"file":"/w/node_modules/@react-native/js-polyfills/console.js","lineNumber":667,"column":37,
           "methodName":"methodName","collapse":true},
          {"file":"/w/src/StreamScreen.tsx","lineNumber":192,"column":10,"methodName":"emitComplexError",
           "collapse":false},
          {"file":"/w/src/App.tsx","lineNumber":15,"column":2,"methodName":"","collapse":false}
        ]}
        """
        let frames = MetroSymbolicator.parse(Data(json.utf8))
        #expect(frames[0].display == "methodName  console.js:667")
        #expect(frames[0].isLibrary)
        #expect(frames[1].display == "emitComplexError  StreamScreen.tsx:192")
        #expect(!frames[1].isLibrary)
        // An anonymous frame is named, not blank.
        #expect(frames[2].display == "(anonymous)  App.tsx:15")
        // Identity survives a re-render without collapsing distinct frames.
        #expect(Set(frames.map(\.id)).count == 3)
    }

    /// The label's file name, without `NSString` bridging — ADBKit compiles for
    /// Linux and Windows, and the path is whatever the machine running Metro
    /// reports.
    @Test func fileNameTakesTheLastPathComponent() {
        #expect(MetroSymbolicator.fileName("/w/src/StreamScreen.tsx") == "StreamScreen.tsx")
        #expect(MetroSymbolicator.fileName(#"D:\w\src\App.tsx"#) == "App.tsx")
        #expect(MetroSymbolicator.fileName("bare.js") == "bare.js")
        #expect(MetroSymbolicator.fileName("") == "")
        #expect(MetroSymbolicator.fileName("/") == "/")
    }

    @Test func dependencyPathsAreRecognizedAnywhereInTheTree() {
        #expect(MetroSymbolicator.isDependency("/w/node_modules/react-native/index.js"))
        #expect(MetroSymbolicator.isDependency("/w/packages/app/node_modules/x/y.js"))
        #expect(!MetroSymbolicator.isDependency("/w/src/node_modules_helper.ts"))
        #expect(!MetroSymbolicator.isDependency("/w/src/StreamScreen.tsx"))
    }

    /// Nothing to symbolicate must never reach the network.
    @Test func emptyStacksResolveWithoutARequest() async {
        // Port 1 has nothing listening; a request would fail slowly instead of
        // returning at once.
        let symbolicator = MetroSymbolicator(port: 1, timeout: 30)
        #expect(await symbolicator.symbolicate([]).isEmpty)
        #expect(await symbolicator.symbolicate([frame(1, url: "")]).isEmpty)
    }
}
