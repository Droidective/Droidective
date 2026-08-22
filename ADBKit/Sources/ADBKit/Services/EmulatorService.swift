import Foundation

public struct Avd: Sendable, Equatable, Identifiable {
    public let name: String
    /// adb serial (emulator-5554) when this AVD is currently running.
    public var runningSerial: String?

    public init(name: String, runningSerial: String? = nil) {
        self.name = name
        self.runningSerial = runningSerial
    }

    public var id: String { name }
    public var displayName: String { name.replacingOccurrences(of: "_", with: " ") }
}

/// Android emulator management: list AVDs, see which are running, launch
/// (normal / cold boot / wipe data), and stop.
public struct EmulatorService: Sendable {
    let client: AdbClient
    let locator: ToolLocator
    let runner: any ProcessRunning
    /// Where AVDs live — injectable so wipe tests run against a temp dir.
    let avdHome: URL

    public init(
        client: AdbClient, locator: ToolLocator,
        runner: any ProcessRunning = SystemProcessRunner(),
        avdHome: URL? = nil
    ) {
        self.client = client
        self.locator = locator
        self.runner = runner
        self.avdHome = avdHome ?? Self.defaultAvdHome()
    }

    /// The emulator's own lookup order: `$ANDROID_AVD_HOME`, else
    /// `~/.android/avd`.
    static func defaultAvdHome() -> URL {
        if let env = ProcessInfo.processInfo.environment["ANDROID_AVD_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".android")
            .appendingPathComponent("avd")
    }

    public func emulatorInstalled() async -> Bool {
        await locator.resolve(.emulator) != nil
    }

    /// Parse `emulator -list-avds` (skips INFO/warning noise lines).
    /// Splits on CharacterSet.newlines — "\r\n" is ONE Character in Swift,
    /// so splitting on "\n" silently fails on CRLF output.
    public static func parseAvdList(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("INFO") && !$0.contains("|") && !$0.contains(" ") }
    }

    /// All AVDs, with the running ones matched to their adb serial via
    /// `adb emu avd name`.
    public func listAvds(devices: [Device]) async -> [Avd] {
        guard let emulatorPath = await locator.resolve(.emulator) else { return [] }
        let output = await runner.run(
            executable: emulatorPath, arguments: ["-list-avds"],
            timeout: .seconds(15), maxOutputBytes: 1024 * 1024
        )
        var avds = Self.parseAvdList(output.stdoutText).map { Avd(name: $0) }

        for device in devices where device.serial.hasPrefix("emulator-") {
            guard let result = try? await client.run(on: device.serial, ["emu", "avd", "name"]) else { continue }
            // The emu console replies with \r\n — split on .newlines, since
            // "\r\n" is a single Character that "\n"-splitting misses.
            let name = result.stdout.components(separatedBy: .newlines).first
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let name, let index = avds.firstIndex(where: { $0.name == name }) {
                avds[index].runningSerial = device.serial
            }
        }
        return avds
    }

    public struct LaunchOptions: Sendable {
        public var coldBoot: Bool
        public var wipeData: Bool

        public init(coldBoot: Bool = false, wipeData: Bool = false) {
            self.coldBoot = coldBoot
            self.wipeData = wipeData
        }
    }

    /// Launch fully decoupled from the app: the emulator is spawned into its own
    /// session (`POSIX_SPAWN_SETSID`), so it's a standalone process — not in
    /// Droidective's process group, unaffected by signals aimed at the app, and
    /// cleanly outliving it. Its window and Dock icon are the emulator's own.
    public func launch(avd: String, options: LaunchOptions = LaunchOptions()) async -> FeatureResult {
        guard let emulatorPath = await locator.resolve(.emulator) else {
            return FeatureResult(ok: false, message: "Android emulator not found — install it via Android Studio's SDK Manager.")
        }
        var arguments = ["-avd", avd]
        if options.coldBoot {
            arguments.append("-no-snapshot-load")
        }
        if options.wipeData {
            arguments.append("-wipe-data")
        }

        var environment = ProcessInfo.processInfo.environment
        let sdkRoot = (emulatorPath as NSString).deletingLastPathComponent
        environment["ANDROID_HOME"] = environment["ANDROID_HOME"] ?? (sdkRoot as NSString).deletingLastPathComponent

        return Self.spawnDetached(path: emulatorPath, arguments: arguments, environment: environment)
            ? FeatureResult(ok: true, message: "Launching \(avd)…")
            : FeatureResult(ok: false, message: "Couldn't launch the emulator.")
    }

    /// Spawn a long-lived GUI process in its own session, detached from this app.
    /// `POSIX_SPAWN_SETSID` makes the child a session/process-group leader, so it
    /// never receives signals sent to the app's group and survives independently;
    /// stdio is routed to `/dev/null` so it neither inherits nor holds the app's
    /// descriptors. Returns false if the spawn fails.
    static func spawnDetached(path: String, arguments: [String], environment: [String: String]) -> Bool {
        #if canImport(Darwin)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)

        // Duplicate every argv/envp string, bailing (and freeing what we took) if
        // any allocation fails — a mid-array nil would otherwise make posix_spawn
        // silently truncate the arguments instead of failing loudly.
        var allocations: [UnsafeMutablePointer<CChar>] = []
        defer { for pointer in allocations { free(pointer) } }
        func dup(_ string: String) -> UnsafeMutablePointer<CChar>? {
            guard let copy = strdup(string) else { return nil }
            allocations.append(copy)
            return copy
        }

        var argv: [UnsafeMutablePointer<CChar>?] = []
        for argument in [path] + arguments {
            guard let copy = dup(argument) else { return false }
            argv.append(copy)
        }
        argv.append(nil)

        var envp: [UnsafeMutablePointer<CChar>?] = []
        for (key, value) in environment {
            guard let copy = dup("\(key)=\(value)") else { return false }
            envp.append(copy)
        }
        envp.append(nil)

        var pid: pid_t = 0
        return posix_spawn(&pid, path, &fileActions, &attr, argv, envp) == 0
        #else
        // Same intent without Apple's posix_spawn extensions: Linux makes the
        // child a session leader via util-linux's `setsid --fork` (the
        // POSIX_SPAWN_SETSID equivalent); Windows children are independent of
        // the parent's lifetime by default. Stdio still goes to the null device.
        let process = Process()
        #if os(Windows)
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        #else
        process.executableURL = URL(fileURLWithPath: "/usr/bin/setsid")
        process.arguments = ["--fork", path] + arguments
        #endif
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
        #endif
    }

    // MARK: - Wipe data

    /// The per-AVD files a data wipe deletes — the set Android Studio's
    /// "Wipe Data" removes: user data (recreated from the base image on the
    /// next launch), caches, the SD card images, and every snapshot (stale
    /// once the data under it is gone).
    static let wipeArtifacts = [
        "userdata-qemu.img", "userdata-qemu.img.qcow2",
        "cache.img", "cache.img.qcow2",
        "sdcard.img.qcow2",
        "snapshots",
    ]

    /// The `path=` line of an AVD's `<name>.ini` — where its data folder
    /// lives (CRLF-safe).
    public static func parseAvdIniPath(_ ini: String) -> String? {
        for line in ini.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("path=") else { continue }
            let value = String(trimmed.dropFirst("path=".count)).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Factory-reset a *stopped* AVD without launching it: delete its user
    /// data, caches, and snapshots. The next launch recreates user data from
    /// the base image — the standalone counterpart of `-wipe-data`, which
    /// can only wipe by booting. Runs detached because a snapshots folder
    /// can be gigabytes and unlinking it must not park a cooperative thread.
    public func wipeData(avd: String) async -> FeatureResult {
        let ini = avdHome.appendingPathComponent("\(avd).ini")
        let iniText = (try? String(contentsOf: ini, encoding: .utf8)) ?? ""
        let dataDir = Self.parseAvdIniPath(iniText).map(URL.init(fileURLWithPath:))
            ?? avdHome.appendingPathComponent("\(avd).avd")
        guard FileManager.default.fileExists(atPath: dataDir.path) else {
            return FeatureResult(ok: false, message: "Couldn't find the AVD's data folder at \(dataDir.path).")
        }
        let failure = await Task.detached(priority: .utility) { () -> String? in
            for name in Self.wipeArtifacts {
                let target = dataDir.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: target.path) else { continue }
                do {
                    try FileManager.default.removeItem(at: target)
                } catch {
                    return "Couldn't remove \(name): \(error.localizedDescription)"
                }
            }
            return nil
        }.value
        if let failure {
            return FeatureResult(ok: false, message: failure)
        }
        return FeatureResult(ok: true, message: "Wiped \(avd) — the next launch starts factory-fresh.")
    }

    /// Graceful shutdown via the emulator console.
    public func stop(serial: String) async throws(AdbError) -> FeatureResult {
        let result = try await client.run(on: serial, ["emu", "kill"])
        return result.succeeded
            ? FeatureResult(ok: true, message: "Stopping emulator…")
            : FeatureResult(ok: false, message: friendlyAdbError(result, fallback: "Couldn't stop the emulator"))
    }

    /// pid of the process listening on the emulator's console port (the number
    /// in "emulator-5554"). That port is held by exactly that qemu process, so
    /// `lsof` maps the serial to the right pid even with several emulators up.
    /// Runs through the non-blocking runner so it can't park a cooperative
    /// thread (the reason this lives here, not in the view).
    public func consolePID(serial: String) async -> Int32? {
        guard let port = serial.split(separator: "-").last.flatMap({ Int($0) }) else { return nil }
        let output = await runner.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"],
            timeout: .seconds(5), maxOutputBytes: 64 * 1024
        )
        return Self.parseLsofPID(output.stdoutText)
    }

    /// First pid from `lsof -t` output (one pid per line; tolerates CRLF).
    /// Typed `Int32` rather than `pid_t`: they are the same type on POSIX, and
    /// `pid_t` does not exist on Windows.
    static func parseLsofPID(_ output: String) -> Int32? {
        output.split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            .first
    }
}
