import ADBKit
import DaemonCore
import Foundation

// Thin entry point: everything worth testing lives in DaemonCore.

let arguments = Array(CommandLine.arguments.dropFirst())
let options: DaemonOptions
do {
    options = try DaemonOptions.parse(arguments)
} catch {
    FileHandle.standardError.write(Data("droidectived: \(error)\n".utf8))
    exit(2)
}

let token = DaemonToken.generate()
if let path = options.tokenFile {
    do {
        let restricted = try DaemonToken.write(token, to: path)
        if !restricted {
            FileHandle.standardError.write(
                Data("droidectived: token file is not mode 0600 on this host\n".utf8))
        }
    } catch {
        FileHandle.standardError.write(Data("droidectived: cannot write token file: \(error)\n".utf8))
        exit(2)
    }
} else {
    FileHandle.standardError.write(Data("droidectived: token \(token)\n".utf8))
}

let locator = ToolLocator()
let client = AdbClient(locator: locator)
let monitor = DeviceMonitor(client: client)
// Same on-disk home as the Mac app, via ADBKit's own path helper — so a
// developer running both does not end up with two divergent overrides files.
let engine = FeatureEngine(
    client: client, locator: locator, monitor: monitor,
    overridesStore: JSONStore<OverridesMap>(filename: "overrides.json", default: [:]),
    toolsDirectory: AppPaths.supportDir.appendingPathComponent("tools"))
let server = DaemonServer(
    backend: LiveBackend(
        monitor: monitor, engine: engine, client: client,
        emulators: EmulatorService(client: client, locator: locator)),
    token: token,
    streamSource: LiveStreamSource(
        monitor: monitor, streamer: LogcatStreamer(client: client),
        performance: PerformanceService(client: client),
        networkSpeed: NetworkSpeedService(client: client)))

do {
    let bound = try await server.start(port: options.port)
    // The one line the UI parses. Written through the file handle rather than
    // `print` + `fflush(stdout)`: `stdout` is a shared mutable global that
    // Swift 6 strict concurrency rejects on Linux, and a FileHandle write is
    // unbuffered anyway — which is what matters here, since the parent blocks
    // on this line and a buffered stdout would look like a hung daemon.
    FileHandle.standardOutput.write(
        Data("droidectived listening 127.0.0.1:\(bound.port)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("droidectived: cannot bind: \(error)\n".utf8))
    exit(1)
}

// Exit with the UI rather than outliving it and holding adb children.
if let parent = options.parentPID {
    Task {
        while true {
            try? await Task.sleep(for: .seconds(2))
            if !ParentWatch.isAlive(parent) {
                await server.stop()
                exit(0)
            }
        }
    }
}

try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
