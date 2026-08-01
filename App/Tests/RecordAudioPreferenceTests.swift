import ADBKit
import Foundation
import Testing

/// The bundle compiles `RecordAudioPreference.swift` directly (see project.yml),
/// so there is no app module to import.
@Suite struct RecordAudioPreferenceTests {
    /// A defaults store of its own per test — the suite must not read or write
    /// the developer's real preferences.
    private func makeDefaults(_ values: [String: Any] = [:]) -> UserDefaults {
        let suiteName = "RecordAudioPreferenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("a fresh suite name always opens")
        }
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    @Test func aFreshInstallRecordsDeviceAudioOnly() {
        let options = RecordAudioPreference.options(from: makeDefaults())
        #expect(options.mode == .deviceOnly)
        #expect(options.microphoneDeviceID == nil)
    }

    @Test func theStoredModeAndInputAreReadBack() {
        let defaults = makeDefaults([
            RecordAudioPreference.modeKey: RecordAudioMode.deviceAndMicrophone.rawValue,
            RecordAudioPreference.inputKey: "AppleUSBAudioEngine:Focusrite",
        ])
        let options = RecordAudioPreference.options(from: defaults)
        #expect(options.mode == .deviceAndMicrophone)
        #expect(options.microphoneDeviceID == "AppleUSBAudioEngine:Focusrite")
    }

    @Test func anEmptyInputMeansTheSystemDefaultNotADeviceNamedEmpty() {
        let defaults = makeDefaults([
            RecordAudioPreference.modeKey: RecordAudioMode.microphoneOnly.rawValue,
            RecordAudioPreference.inputKey: "",
        ])
        #expect(RecordAudioPreference.options(from: defaults).microphoneDeviceID == nil)
    }

    @Test func anUnknownStoredModeFallsBackInsteadOfLosingAudio() {
        let defaults = makeDefaults([RecordAudioPreference.modeKey: "quadraphonic"])
        #expect(RecordAudioPreference.options(from: defaults).mode == .deviceOnly)
    }

    @Test func theOldSingleSwitchCarriesForward() {
        // Someone who had "capture audio" off must stay silent, not silently
        // start recording device audio again.
        let off = makeDefaults([RecordAudioPreference.legacyModeKey: false])
        #expect(RecordAudioPreference.options(from: off).mode == .muted)

        let on = makeDefaults([RecordAudioPreference.legacyModeKey: true])
        #expect(RecordAudioPreference.options(from: on).mode == .deviceOnly)
    }

    @Test func anExplicitChoiceWinsOverTheOldSwitch() {
        let defaults = makeDefaults([
            RecordAudioPreference.legacyModeKey: false,
            RecordAudioPreference.modeKey: RecordAudioMode.deviceAndMicrophone.rawValue,
        ])
        #expect(RecordAudioPreference.options(from: defaults).mode == .deviceAndMicrophone)
    }

    @Test func migrationWritesTheNewKeyAndDropsTheOldOne() {
        let defaults = makeDefaults([RecordAudioPreference.legacyModeKey: false])
        RecordAudioPreference.migrate(defaults)
        #expect(defaults.string(forKey: RecordAudioPreference.modeKey)
            == RecordAudioMode.muted.rawValue)
        #expect(defaults.object(forKey: RecordAudioPreference.legacyModeKey) == nil)
        // Idempotent: running again on the migrated store changes nothing.
        RecordAudioPreference.migrate(defaults)
        #expect(RecordAudioPreference.options(from: defaults).mode == .muted)
    }

    @Test func migrationLeavesAStoreThatNeverHadTheOldKeyAlone() {
        let defaults = makeDefaults()
        RecordAudioPreference.migrate(defaults)
        #expect(defaults.string(forKey: RecordAudioPreference.modeKey) == nil)
        #expect(RecordAudioPreference.options(from: defaults).mode == .deviceOnly)
    }

    @Test func migrationKeepsAnExplicitChoiceWhileDroppingTheOldKey() {
        let defaults = makeDefaults([
            RecordAudioPreference.legacyModeKey: false,
            RecordAudioPreference.modeKey: RecordAudioMode.microphoneOnly.rawValue,
        ])
        RecordAudioPreference.migrate(defaults)
        #expect(RecordAudioPreference.options(from: defaults).mode == .microphoneOnly)
        #expect(defaults.object(forKey: RecordAudioPreference.legacyModeKey) == nil)
    }
}
