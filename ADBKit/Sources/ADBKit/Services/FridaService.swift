import Foundation

/// Maps an Android ABI list to the architecture token frida uses in its release
/// asset names (`frida-server-<ver>-android-<arch>.xz`).
public enum FridaArch {
    public static func from(abilist: String) -> String? {
        for abi in abilist.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch abi {
            case "arm64-v8a": return "arm64"
            case "armeabi-v7a", "armeabi": return "arm"
            case "x86_64": return "x86_64"
            case "x86": return "x86"
            default: continue
            }
        }
        return nil
    }
}

/// Prepares a device for Frida instrumentation: matches the device architecture,
/// and (on a rooted device) pushes and runs frida-server. The actual
/// instrumentation REPL is the user's own frida / frida-tools client connecting
/// over USB — this service handles the fiddly device-side setup.
///
/// frida-server itself is a managed download (arch-matched, see ManagedTool).
/// Every value sent through `adb shell` is `shellQuote`d; `adb push` uses the
/// sync protocol (no shell).
public struct FridaService: Sendable {
    public static let serverRemotePath = "/data/local/tmp/frida-server"

    let client: AdbClient

    public init(client: AdbClient) {
        self.client = client
    }

    /// frida's arch token for the device, read from its ABI list.
    public func deviceArch(serial: String) async throws(AdbError) -> String? {
        let result = try await client.run(on: serial, ["shell", "getprop", "ro.product.cpu.abilist"])
        return FridaArch.from(abilist: result.stdout)
    }

    /// Push a local frida-server binary to the device and mark it executable.
    public func installServer(localPath: String, serial: String) async throws(AdbError) -> AdbResult {
        _ = try await client.run(on: serial, Self.pushArguments(localPath: localPath), timeout: .seconds(120))
        return try await client.run(on: serial, Self.chmodArguments())
    }

    /// Start frida-server as root, detached (requires a rooted device).
    public func startServer(serial: String) async throws(AdbError) -> AdbResult {
        try await client.run(on: serial, Self.startArguments(), timeout: .seconds(10))
    }

    public func stopServer(serial: String) async throws(AdbError) -> AdbResult {
        try await client.run(on: serial, Self.stopArguments())
    }

    /// Whether a frida-server process is currently running on the device.
    public func isServerRunning(serial: String) async throws(AdbError) -> Bool {
        let result = try await client.run(on: serial, Self.statusArguments())
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Pure argument builders (device-scope; `-s <serial>` is prepended by AdbClient)

    static func pushArguments(localPath: String) -> [String] {
        ["push", localPath, serverRemotePath]
    }

    static func chmodArguments() -> [String] {
        ["shell", "chmod", "755", shellQuote(serverRemotePath)]
    }

    /// `su -c '<path> &'` launches the server in the background so the adb call
    /// returns instead of blocking on the long-lived process.
    static func startArguments() -> [String] {
        ["shell", "su", "-c", shellQuote("\(serverRemotePath) &")]
    }

    static func stopArguments() -> [String] {
        ["shell", "su", "-c", shellQuote("pkill -f frida-server")]
    }

    static func statusArguments() -> [String] {
        ["shell", "pidof", "frida-server"]
    }
}
