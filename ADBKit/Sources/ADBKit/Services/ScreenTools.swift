import Foundation

/// Which audio a recording captures. The device's own audio arrives over the
/// scrcpy stream (Android 11+); the microphone is a host input. When both are
/// on they are summed into one AAC track so the file plays everywhere — see
/// `PCMMixdown`.
public enum RecordAudioMode: String, Sendable, Equatable, Codable, CaseIterable {
    case deviceAndMicrophone
    case deviceOnly
    case microphoneOnly
    case muted

    public var includesDevice: Bool {
        self == .deviceAndMicrophone || self == .deviceOnly
    }

    public var includesMicrophone: Bool {
        self == .deviceAndMicrophone || self == .microphoneOnly
    }

    /// Both sources feed one track, so their samples must be summed on a shared
    /// timeline rather than appended as they arrive.
    public var mixesSources: Bool { includesDevice && includesMicrophone }

    /// Whether the recording carries an audio track at all.
    public var hasAudio: Bool { self != .muted }

    public static func mode(device: Bool, microphone: Bool) -> RecordAudioMode {
        switch (device, microphone) {
        case (true, true): return .deviceAndMicrophone
        case (true, false): return .deviceOnly
        case (false, true): return .microphoneOnly
        case (false, false): return .muted
        }
    }

    /// The mode actually achievable when the session never asked the device for
    /// audio: an in-mirror recording can only record what its stream carries.
    public func limited(deviceAudioAvailable: Bool) -> RecordAudioMode {
        deviceAudioAvailable
            ? self
            : Self.mode(device: false, microphone: includesMicrophone)
    }

    /// UI label. It lives here so the picker and the recorder can't drift apart.
    public var title: String {
        switch self {
        case .deviceAndMicrophone: return "Device + Microphone"
        case .deviceOnly: return "Device only"
        case .microphoneOnly: return "Microphone only"
        case .muted: return "No audio"
        }
    }

    /// SF Symbol *name* — ADBKit stays UI-free, so this is a string, like the
    /// feature icons.
    public var symbolName: String {
        switch self {
        case .deviceAndMicrophone: return "waveform.badge.mic"
        case .deviceOnly: return "speaker.wave.2.fill"
        case .microphoneOnly: return "mic.fill"
        case .muted: return "speaker.slash.fill"
        }
    }
}

/// The audio half of `ScreenRecordOptions`: what to capture, and which host
/// input to capture the microphone from.
public struct RecordAudioOptions: Sendable, Equatable, Codable {
    public var mode: RecordAudioMode
    /// Host input device id (an `AVCaptureDevice.uniqueID`), or nil for the
    /// system default input. Ignored when the mode excludes the microphone.
    public var microphoneDeviceID: String?

    public init(mode: RecordAudioMode = .deviceOnly, microphoneDeviceID: String? = nil) {
        self.mode = mode
        self.microphoneDeviceID = microphoneDeviceID
    }
}

/// Screen-recording options. The recorder maps these onto `ScrcpyServerParams`
/// for the in-app scrcpy client (bundled server) — no external scrcpy process.
/// `timeLimitSeconds` is enforced by the recording UI (the server has no
/// time-limit knob).
public struct ScreenRecordOptions: Sendable, Equatable {
    /// Longest side in px (0 = device size) → `max_size`.
    public var maxSize: Int
    /// Video bit-rate in Mbps (0 = server default) → `video_bit_rate`.
    public var bitRateMbps: Int
    /// Frame-rate cap (0 = unlimited) → `max_fps`.
    public var maxFps: Int
    /// What to capture: device audio (Android 11+; falls back to video-only
    /// otherwise), the Mac's microphone, both, or neither.
    public var audio: RecordAudioOptions
    /// Stop after N seconds (0 = unlimited); enforced by the UI.
    public var timeLimitSeconds: Int

    public init(
        maxSize: Int = 0,
        bitRateMbps: Int = 0,
        maxFps: Int = 0,
        audio: RecordAudioOptions = RecordAudioOptions(),
        timeLimitSeconds: Int = 0
    ) {
        self.maxSize = maxSize
        self.bitRateMbps = bitRateMbps
        self.maxFps = maxFps
        self.audio = audio
        self.timeLimitSeconds = timeLimitSeconds
    }
}
