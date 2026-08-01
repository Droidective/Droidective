import ADBKit
import Foundation

/// Where the recording-audio choice lives, shared by the Screen Record screen
/// and the mirror's record button so both capture the same way.
enum RecordAudioPreference {
    static let modeKey = "recAudioMode"
    static let inputKey = "recMicInput"
    /// The pre-microphone key: one "capture device audio" switch.
    static let legacyModeKey = "recCaptureAudio"

    static func options(from defaults: UserDefaults) -> RecordAudioOptions {
        let stored = defaults.string(forKey: modeKey).flatMap(RecordAudioMode.init(rawValue:))
        let input = defaults.string(forKey: inputKey) ?? ""
        return RecordAudioOptions(
            mode: stored ?? inheritedMode(from: defaults),
            microphoneDeviceID: input.isEmpty ? nil : input)
    }

    /// Carry the old single switch forward: someone who had device audio turned
    /// off keeps recording silently instead of silently regaining audio.
    static func inheritedMode(from defaults: UserDefaults) -> RecordAudioMode {
        guard defaults.object(forKey: legacyModeKey) != nil else { return .deviceOnly }
        return defaults.bool(forKey: legacyModeKey) ? .deviceOnly : .muted
    }

    /// Fold the old key into the new one, once, and drop it.
    static func migrate(_ defaults: UserDefaults) {
        guard defaults.object(forKey: legacyModeKey) != nil else { return }
        if defaults.string(forKey: modeKey) == nil {
            defaults.set(options(from: defaults).mode.rawValue, forKey: modeKey)
        }
        defaults.removeObject(forKey: legacyModeKey)
    }
}
