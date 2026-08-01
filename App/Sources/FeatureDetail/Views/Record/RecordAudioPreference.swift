import ADBKit
import Foundation

/// One microphone dropdown instead of a switch plus an input picker: off, the
/// system default, or a named input. Picking an input *is* turning the
/// microphone on, which is one decision rather than two.
enum MicrophoneChoice: Hashable, Sendable {
    case off
    case systemDefault
    case input(String)
}

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

    /// What the microphone dropdown shows for the stored settings.
    static func microphoneChoice(mode: RecordAudioMode, inputID: String) -> MicrophoneChoice {
        guard mode.includesMicrophone else { return .off }
        return inputID.isEmpty ? .systemDefault : .input(inputID)
    }

    /// The settings a dropdown pick implies. Device audio is untouched — the
    /// two sources are independent — and turning the microphone off *keeps* the
    /// chosen input, so switching it back on doesn't lose the choice.
    static func applying(
        _ choice: MicrophoneChoice, mode: RecordAudioMode, inputID: String
    ) -> (mode: RecordAudioMode, inputID: String) {
        let device = mode.includesDevice
        switch choice {
        case .off:
            return (.mode(device: device, microphone: false), inputID)
        case .systemDefault:
            return (.mode(device: device, microphone: true), "")
        case let .input(id):
            return (.mode(device: device, microphone: true), id)
        }
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
