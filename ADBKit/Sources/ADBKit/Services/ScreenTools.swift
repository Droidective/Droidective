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

/// What the device contributes to a recording. scrcpy captures **one** audio
/// stream per session, so the device's playback and its own microphone are
/// alternatives, not a pair — picking `microphone` records what the phone
/// hears (the room, a call's uplink) instead of what it plays.
public enum DeviceAudioSource: String, Sendable, Equatable, Codable, CaseIterable {
    case off
    case playback
    case microphone

    public var isOn: Bool { self != .off }

    public var title: String {
        switch self {
        case .off: return "Off"
        case .playback: return "Device playback"
        case .microphone: return "Device microphone"
        }
    }

    /// SF Symbol *name* — ADBKit stays UI-free, so this is a string.
    public var symbolName: String {
        switch self {
        case .off: return "speaker.slash.fill"
        case .playback: return "speaker.wave.2.fill"
        case .microphone: return "mic.and.signal.meter.fill"
        }
    }

    var scrcpySource: ScrcpyServerParams.AudioSource {
        self == .microphone ? .microphone : .output
    }
}

/// Which host inputs are worth offering in a picker.
public enum RecordAudioInputs {
    /// Core Audio's own scratch devices — the aggregate macOS builds around the
    /// current default input (`CADefaultDeviceAggregate-…`) and the tap/loopback
    /// shims some apps install — are implementation details, not microphones
    /// anyone means to pick. Hiding them keeps the list to real hardware.
    public static func isSelectable(name: String, uniqueID: String) -> Bool {
        let hidden = ["CADefaultDeviceAggregate", "CATapAggregateDevice", "AMS2_Aggregate"]
        return !hidden.contains { name.hasPrefix($0) || uniqueID.hasPrefix($0) }
    }
}

/// The audio half of `ScreenRecordOptions`: what the device contributes, and
/// which host input (if any) is mixed in alongside it.
public struct RecordAudioOptions: Sendable, Equatable, Codable {
    /// The device's own contribution — its playback, its microphone, or
    /// nothing.
    public var deviceSource: DeviceAudioSource
    /// Whether the Mac's microphone is mixed in.
    public var usesHostMicrophone: Bool
    /// Host input device id (an `AVCaptureDevice.uniqueID`), or nil for the
    /// system default input. Ignored when the host microphone is off.
    public var microphoneDeviceID: String?

    public init(
        deviceSource: DeviceAudioSource = .playback,
        usesHostMicrophone: Bool = false,
        microphoneDeviceID: String? = nil
    ) {
        self.deviceSource = deviceSource
        self.usesHostMicrophone = usesHostMicrophone
        self.microphoneDeviceID = microphoneDeviceID
    }

    /// Which sources the mixer has to reconcile — the device stream (whatever
    /// it carries) and the host microphone.
    public var mode: RecordAudioMode {
        .mode(device: deviceSource.isOn, microphone: usesHostMicrophone)
    }

    /// One line naming exactly what a recording will capture, for the UI to
    /// show before the user commits to a take.
    public func summary(microphoneName: String?) -> String {
        let host = microphoneName ?? "the Mac's microphone"
        switch (deviceSource, usesHostMicrophone) {
        case (.off, false): return "No audio"
        case (.off, true): return host
        case (let source, false): return source.title
        case (let source, true): return "\(source.title) + \(host)"
        }
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
