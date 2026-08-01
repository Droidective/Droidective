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
let server = DaemonServer(backend: LiveBackend(monitor: DeviceMonitor(client: client)), token: token)

do {
    let bound = try await server.start(port: options.port)
    // The one line the UI parses. Flushed immediately: the parent blocks on it,
    // so a buffered stdout would look like a hung daemon.
    print("droidectived listening 127.0.0.1:\(bound.port)")
    fflush(stdout)
} catch {
    FileHandle.standardError.write(Data("droidectived: cannot bind: \(error)\n".utf8))
    exit(1)
}

// Exit with the UI rather than outliving it and holding adb children.
if let parent = options.parentPID {
    Task {
        while true {
            try? await Task.sleep(for: .seconds(2))
            if kill(parent, 0) != 0 {
                await server.stop()
                exit(0)
            }
        }
    }
}

try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
