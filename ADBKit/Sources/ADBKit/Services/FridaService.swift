import Foundation

/// Maps an Android ABI list to the architecture token frida uses in its release
/// asset names (`frida-server-<ver>-android-<arch>.xz`).
public enum FridaArch {
    public static func from(abilist: String) -> String? {
        // Trim newlines too: raw `getprop` output keeps its trailing "\n", and a
        // single-ABI list (64-bit-only devices, e.g. "arm64-v8a") has no comma to
        // separate it off, so ".whitespaces" alone would leave "arm64-v8a\n".
        for abi in abilist.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
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

    /// Launch frida-server detached so the `adb shell` call returns at once.
    /// A bare `&` is not enough: the backgrounded server inherits the shell's
    /// stdout/stderr, so adb's shell service never sees EOF and the call hangs
    /// until it times out — and the cancelled adb child takes the server down
    /// with it. `setsid` plus redirecting all three std streams to /dev/null
    /// severs it from the adb pipe and the shell's session, so the call returns
    /// immediately and the server survives.
    static func startArguments() -> [String] {
        ["shell", "su", "-c", shellQuote("setsid \(serverRemotePath) </dev/null >/dev/null 2>&1 &")]
    }

    static func stopArguments() -> [String] {
        ["shell", "su", "-c", shellQuote("pkill -f frida-server")]
    }

    static func statusArguments() -> [String] {
        ["shell", "pidof", "frida-server"]
    }
}
