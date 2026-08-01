import Foundation

/// Parameters for the device-side `scrcpy-server`, started via `app_process`.
///
/// Unlike the desktop scrcpy binary's CLI flags, these are the
/// `key=value` arguments the server itself parses. The in-app mirror reuses
/// scrcpy's server but speaks its protocol directly, so we launch the server
/// ourselves over `adb shell`. Kept pure/`Equatable` so the argument building is
/// unit-testable without spawning anything.
///
/// Confirmed against scrcpy 4.0 (`server.c` `execute_server` + live capture);
/// re-checked against the 4.1 server diff (additive only — a new
/// `ignore_video_encoder_constraints` option and control type 22):
/// only non-default values are emitted — the server fills in its own defaults,
/// matching how the stock client builds the command.
public struct ScrcpyServerParams: Sendable, Equatable {
    /// Session id; also names the local abstract socket (`scrcpy_<scid>`).
    public var scid: UInt32
    public var logLevel: String
    public var video: Bool
    public var audio: Bool
    /// Audio codec the server should encode with. Defaults to `raw` (PCM
    /// s16le, 48 kHz, stereo) so the client can play it without an Opus/AAC
    /// decoder; only consulted when `audio` is on.
    public var audioCodec: String
    /// Which device-side source the server captures: its playback ("output",
    /// the server's default) or the device's own microphone ("mic"). One
    /// session carries one source — scrcpy captures a single audio stream — so
    /// this is a choice, not a set. Only consulted when `audio` is on.
    public var audioSource: AudioSource
    public var control: Bool

    /// scrcpy's `audio_source` values. The server accepts several mic variants;
    /// these are the two the recorder offers.
    public enum AudioSource: String, Sendable, Equatable, CaseIterable {
        case output
        case microphone = "mic"
    }
    /// Longest side in px (0 = device size).
    public var maxSize: Int
    /// Video bit-rate in bits/sec (0 = server default, ~8 Mbps).
    public var videoBitRate: Int
    /// Frame-rate cap (0 = unlimited).
    public var maxFps: Int
    /// Forward tunnel: the server listens and the client connects.
    public var tunnelForward: Bool
    /// Ask the server to turn on the device's "Show taps" setting for the
    /// session (scrcpy's `--show-touches`): it flips the system setting on
    /// start and its CleanUp restores it when the session dies.
    public var showTouches: Bool

    public init(
        scid: UInt32,
        logLevel: String = "info",
        video: Bool = true,
        audio: Bool = false,
        audioCodec: String = "raw",
        audioSource: AudioSource = .output,
        control: Bool = false,
        maxSize: Int = 0,
        videoBitRate: Int = 0,
        maxFps: Int = 0,
        tunnelForward: Bool = true,
        showTouches: Bool = false
    ) {
        self.scid = scid
        self.logLevel = logLevel
        self.video = video
        self.audio = audio
        self.audioCodec = audioCodec
        self.audioSource = audioSource
        self.control = control
        self.maxSize = maxSize
        self.videoBitRate = videoBitRate
        self.maxFps = maxFps
        self.tunnelForward = tunnelForward
        self.showTouches = showTouches
    }

    /// The local abstract socket name the server listens on.
    public var socketName: String { String(format: "scrcpy_%08x", scid) }

    /// The `key=value` parameters, in scrcpy's own order. `scid` and `log_level`
    /// are always present; the rest are emitted only when they differ from the
    /// server's defaults (`video`/`audio`/`control` default on, caps default off).
    public func parameters() -> [String] {
        var params = [
            String(format: "scid=%08x", scid),
            "log_level=\(logLevel)",
        ]
        if !video { params.append("video=false") }
        if videoBitRate > 0 { params.append("video_bit_rate=\(videoBitRate)") }
        if audio {
            // The server's default audio codec is Opus; request the configured
            // one (raw PCM) so the client plays it without bundling a decoder.
            if audioCodec != "opus" { params.append("audio_codec=\(audioCodec)") }
            // `output` is the server's default, so it's left unsaid.
            if audioSource != .output { params.append("audio_source=\(audioSource.rawValue)") }
        } else {
            params.append("audio=false")
        }
        if maxSize > 0 { params.append("max_size=\(maxSize)") }
        if maxFps > 0 { params.append("max_fps=\(maxFps)") }
        if tunnelForward { params.append("tunnel_forward=true") }
        if !control { params.append("control=false") }
        if showTouches { params.append("show_touches=true") }
        return params
    }

    /// Full `adb shell` arguments (append after `-s <serial>`): runs the server
    /// jar through `app_process`. `serverVersion` MUST match the pushed jar or the
    /// server aborts with a version-mismatch error.
    public func shellArguments(serverVersion: String, remoteJarPath: String) -> [String] {
        [
            "shell",
            "CLASSPATH=\(remoteJarPath)",
            "app_process", "/",
            "com.genymobile.scrcpy.Server", serverVersion,
        ] + parameters()
    }
}
