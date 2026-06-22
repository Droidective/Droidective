import Foundation

/// Common scrcpy mirroring options. `args(recordingPath:)` builds the CLI flags
/// (excluding `-s <serial>`), kept pure so it's unit-testable.
public struct ScrcpyOptions: Sendable, Equatable {
    /// Longest side in px (0 = unlimited / device size).
    public var maxSize: Int
    /// Video bit-rate in Mbps (0 = scrcpy default).
    public var bitRateMbps: Int
    /// Frame-rate cap (0 = unlimited).
    public var maxFps: Int
    /// `width:height:x:y` crop, or "" for none.
    public var crop: String
    public var stayAwake: Bool
    public var turnScreenOff: Bool
    /// `--no-control` — mirror without controlling the device.
    public var viewOnly: Bool
    public var alwaysOnTop: Bool
    public var fullscreen: Bool

    public init(
        maxSize: Int = 0,
        bitRateMbps: Int = 0,
        maxFps: Int = 0,
        crop: String = "",
        stayAwake: Bool = false,
        turnScreenOff: Bool = false,
        viewOnly: Bool = false,
        alwaysOnTop: Bool = false,
        fullscreen: Bool = false
    ) {
        self.maxSize = maxSize
        self.bitRateMbps = bitRateMbps
        self.maxFps = maxFps
        self.crop = crop
        self.stayAwake = stayAwake
        self.turnScreenOff = turnScreenOff
        self.viewOnly = viewOnly
        self.alwaysOnTop = alwaysOnTop
        self.fullscreen = fullscreen
    }

    public func args(recordingPath: String? = nil) -> [String] {
        var args: [String] = []
        if maxSize > 0 { args += ["--max-size", String(maxSize)] }
        if bitRateMbps > 0 { args += ["--video-bit-rate", "\(bitRateMbps)M"] }
        if maxFps > 0 { args += ["--max-fps", String(maxFps)] }
        if !crop.isEmpty { args += ["--crop", crop] }
        if stayAwake { args.append("--stay-awake") }
        if turnScreenOff { args.append("--turn-screen-off") }
        if viewOnly { args.append("--no-control") }
        if alwaysOnTop { args.append("--always-on-top") }
        if fullscreen { args.append("--fullscreen") }
        if let recordingPath, !recordingPath.isEmpty { args += ["--record", recordingPath] }
        return args
    }
}

/// scrcpy recording options. scrcpy records the H.264/H.265 stream on the Mac
/// side via `--record`, so it has none of `adb shell screenrecord`'s limits
/// (no ~3-min cap, audio by default on Android 11+, survives device rotation).
/// `args(recordingPath:)` builds the flags; recording always runs headless
/// (`--no-playback`, no mirror window).
public struct ScreenRecordOptions: Sendable, Equatable {
    /// Longest side in px (0 = device size) → `--max-size`.
    public var maxSize: Int
    /// Video bit-rate in Mbps (0 = scrcpy default) → `--video-bit-rate`.
    public var bitRateMbps: Int
    /// Frame-rate cap (0 = unlimited) → `--max-fps`.
    public var maxFps: Int
    /// Capture device audio (Android 11+; falls back to video-only otherwise).
    /// When false, emits `--no-audio`.
    public var captureAudio: Bool
    /// Stop after N seconds (0 = unlimited) → `--time-limit`.
    public var timeLimitSeconds: Int

    public init(
        maxSize: Int = 0,
        bitRateMbps: Int = 0,
        maxFps: Int = 0,
        captureAudio: Bool = true,
        timeLimitSeconds: Int = 0
    ) {
        self.maxSize = maxSize
        self.bitRateMbps = bitRateMbps
        self.maxFps = maxFps
        self.captureAudio = captureAudio
        self.timeLimitSeconds = timeLimitSeconds
    }

    public func args(recordingPath: String? = nil) -> [String] {
        var args = ["--no-playback"]
        if let recordingPath, !recordingPath.isEmpty { args += ["--record", recordingPath] }
        if maxSize > 0 { args += ["--max-size", String(maxSize)] }
        if bitRateMbps > 0 { args += ["--video-bit-rate", "\(bitRateMbps)M"] }
        if maxFps > 0 { args += ["--max-fps", String(maxFps)] }
        if !captureAudio { args.append("--no-audio") }
        if timeLimitSeconds > 0 { args += ["--time-limit", String(timeLimitSeconds)] }
        return args
    }
}

/// Shared scrcpy helpers that aren't tied to a specific options struct.
public enum ScreenTools {
    /// Environment a spawned scrcpy needs. scrcpy resolves `adb` itself via
    /// `$ADB` or `PATH`; a Finder-launched app inherits neither, so both must be
    /// injected or scrcpy dies instantly. Pure (takes the base environment in)
    /// so it's unit-testable and shared by the recorder and the mirror launcher.
    public static func scrcpyEnvironment(
        base: [String: String],
        scrcpyPath: String,
        adbPath: String
    ) -> [String: String] {
        var environment = base
        environment["ADB"] = adbPath
        let extraPaths = [
            (adbPath as NSString).deletingLastPathComponent,
            (scrcpyPath as NSString).deletingLastPathComponent,
        ]
        environment["PATH"] = (extraPaths + [base["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        return environment
    }
}
