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
/// and the mirror's recording sheet so both capture the same way.
///
/// Two stored values, one per dropdown: what the device contributes (its
/// playback, its own microphone, or nothing) and which Mac input is mixed in.
enum RecordAudioPreference {
    static let deviceKey = "recDeviceAudio"
    static let hostMicKey = "recHostMic"
    static let inputKey = "recMicInput"
    /// Superseded keys, read once by `migrate`: the original single "capture
    /// device audio" switch, and the four-way mode that replaced it.
    static let legacySwitchKey = "recCaptureAudio"
    static let legacyModeKey = "recAudioMode"

    static func options(from defaults: UserDefaults) -> RecordAudioOptions {
        let input = defaults.string(forKey: inputKey) ?? ""
        return RecordAudioOptions(
            deviceSource: deviceSource(from: defaults),
            usesHostMicrophone: usesHostMicrophone(from: defaults),
            microphoneDeviceID: input.isEmpty ? nil : input)
    }

    static func deviceSource(from defaults: UserDefaults) -> DeviceAudioSource {
        if let stored = defaults.string(forKey: deviceKey),
           let source = DeviceAudioSource(rawValue: stored) {
            return source
        }
        return inheritedMode(from: defaults).includesDevice ? .playback : .off
    }

    static func usesHostMicrophone(from defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: hostMicKey) != nil { return defaults.bool(forKey: hostMicKey) }
        return inheritedMode(from: defaults).includesMicrophone
    }

    /// Carry a superseded setting forward: someone who had audio turned off
    /// keeps recording silently instead of silently regaining it.
    static func inheritedMode(from defaults: UserDefaults) -> RecordAudioMode {
        if let stored = defaults.string(forKey: legacyModeKey),
           let mode = RecordAudioMode(rawValue: stored) {
            return mode
        }
        guard defaults.object(forKey: legacySwitchKey) != nil else { return .deviceOnly }
        return defaults.bool(forKey: legacySwitchKey) ? .deviceOnly : .muted
    }

    /// Fold the superseded keys into the current pair, once, and drop them.
    static func migrate(_ defaults: UserDefaults) {
        let superseded = [legacySwitchKey, legacyModeKey]
        guard superseded.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        if defaults.string(forKey: deviceKey) == nil {
            defaults.set(deviceSource(from: defaults).rawValue, forKey: deviceKey)
        }
        if defaults.object(forKey: hostMicKey) == nil {
            defaults.set(usesHostMicrophone(from: defaults), forKey: hostMicKey)
        }
        superseded.forEach { defaults.removeObject(forKey: $0) }
    }

    // MARK: - The microphone dropdown

    /// What the microphone dropdown shows for the stored settings.
    static func microphoneChoice(usesHostMicrophone: Bool, inputID: String) -> MicrophoneChoice {
        guard usesHostMicrophone else { return .off }
        return inputID.isEmpty ? .systemDefault : .input(inputID)
    }

    /// The settings a dropdown pick implies. Turning the microphone off *keeps*
    /// the chosen input, so switching it back on doesn't lose the choice.
    static func applying(
        _ choice: MicrophoneChoice, inputID: String
    ) -> (usesHostMicrophone: Bool, inputID: String) {
        switch choice {
        case .off: return (false, inputID)
        case .systemDefault: return (true, "")
        case let .input(id): return (true, id)
        }
    }
}
