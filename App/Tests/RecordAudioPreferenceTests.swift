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

    @Test func aFreshInstallRecordsTheDevicesPlaybackOnly() {
        let options = RecordAudioPreference.options(from: makeDefaults())
        #expect(options.deviceSource == .playback)
        #expect(!options.usesHostMicrophone)
        #expect(options.microphoneDeviceID == nil)
        #expect(options.mode == .deviceOnly)
    }

    @Test func bothDropdownsAreReadBack() {
        let defaults = makeDefaults([
            RecordAudioPreference.deviceKey: DeviceAudioSource.microphone.rawValue,
            RecordAudioPreference.hostMicKey: true,
            RecordAudioPreference.inputKey: "AppleUSBAudioEngine:Focusrite",
        ])
        let options = RecordAudioPreference.options(from: defaults)
        #expect(options.deviceSource == .microphone)
        #expect(options.usesHostMicrophone)
        #expect(options.microphoneDeviceID == "AppleUSBAudioEngine:Focusrite")
        // Device mic + Mac mic is still two sources to mix.
        #expect(options.mode == .deviceAndMicrophone)
    }

    @Test func anEmptyInputMeansTheSystemDefaultNotADeviceNamedEmpty() {
        let defaults = makeDefaults([
            RecordAudioPreference.hostMicKey: true,
            RecordAudioPreference.inputKey: "",
        ])
        #expect(RecordAudioPreference.options(from: defaults).microphoneDeviceID == nil)
    }

    @Test func anUnknownStoredSourceFallsBackInsteadOfLosingAudio() {
        let defaults = makeDefaults([RecordAudioPreference.deviceKey: "quadraphonic"])
        #expect(RecordAudioPreference.options(from: defaults).deviceSource == .playback)
    }

    // MARK: - Superseded settings

    @Test func theOriginalSingleSwitchCarriesForward() {
        // Someone who had "capture audio" off must stay silent, not silently
        // start recording device audio again.
        let off = makeDefaults([RecordAudioPreference.legacySwitchKey: false])
        #expect(RecordAudioPreference.options(from: off).deviceSource == .off)
        #expect(!RecordAudioPreference.options(from: off).usesHostMicrophone)

        let on = makeDefaults([RecordAudioPreference.legacySwitchKey: true])
        #expect(RecordAudioPreference.options(from: on).deviceSource == .playback)
    }

    @Test func theFourWayModeCarriesForwardToBothDropdowns() {
        let defaults = makeDefaults([
            RecordAudioPreference.legacyModeKey: RecordAudioMode.microphoneOnly.rawValue,
        ])
        let options = RecordAudioPreference.options(from: defaults)
        #expect(options.deviceSource == .off)
        #expect(options.usesHostMicrophone)
    }

    @Test func anExplicitChoiceWinsOverASupersededOne() {
        let defaults = makeDefaults([
            RecordAudioPreference.legacyModeKey: RecordAudioMode.muted.rawValue,
            RecordAudioPreference.deviceKey: DeviceAudioSource.microphone.rawValue,
            RecordAudioPreference.hostMicKey: true,
        ])
        let options = RecordAudioPreference.options(from: defaults)
        #expect(options.deviceSource == .microphone)
        #expect(options.usesHostMicrophone)
    }

    @Test func migrationWritesTheNewKeysAndDropsTheOldOnes() {
        let defaults = makeDefaults([
            RecordAudioPreference.legacyModeKey: RecordAudioMode.microphoneOnly.rawValue,
        ])
        RecordAudioPreference.migrate(defaults)
        #expect(defaults.string(forKey: RecordAudioPreference.deviceKey)
            == DeviceAudioSource.off.rawValue)
        #expect(defaults.bool(forKey: RecordAudioPreference.hostMicKey))
        #expect(defaults.object(forKey: RecordAudioPreference.legacyModeKey) == nil)
        #expect(defaults.object(forKey: RecordAudioPreference.legacySwitchKey) == nil)
        // Idempotent: running again on the migrated store changes nothing.
        RecordAudioPreference.migrate(defaults)
        let options = RecordAudioPreference.options(from: defaults)
        #expect(options.deviceSource == .off)
        #expect(options.usesHostMicrophone)
    }

    @Test func migrationLeavesAStoreThatNeverHadTheOldKeysAlone() {
        let defaults = makeDefaults()
        RecordAudioPreference.migrate(defaults)
        #expect(defaults.string(forKey: RecordAudioPreference.deviceKey) == nil)
        #expect(RecordAudioPreference.options(from: defaults).deviceSource == .playback)
    }

    // MARK: - The microphone dropdown

    @Test func theDropdownShowsWhatIsStored() {
        #expect(RecordAudioPreference.microphoneChoice(usesHostMicrophone: false, inputID: "")
            == .off)
        // An input is remembered while off, but off is still what's shown.
        #expect(RecordAudioPreference.microphoneChoice(usesHostMicrophone: false, inputID: "usb-1")
            == .off)
        #expect(RecordAudioPreference.microphoneChoice(usesHostMicrophone: true, inputID: "")
            == .systemDefault)
        #expect(RecordAudioPreference.microphoneChoice(usesHostMicrophone: true, inputID: "usb-1")
            == .input("usb-1"))
    }

    @Test func pickingAnInputTurnsTheMicrophoneOn() {
        let named = RecordAudioPreference.applying(.input("usb-1"), inputID: "")
        #expect(named.usesHostMicrophone)
        #expect(named.inputID == "usb-1")

        let systemDefault = RecordAudioPreference.applying(.systemDefault, inputID: "usb-1")
        #expect(systemDefault.usesHostMicrophone)
        // "System default" means exactly that — the named input is cleared.
        #expect(systemDefault.inputID == "")
    }

    @Test func turningTheMicrophoneOffKeepsTheChosenInputForNextTime() {
        let off = RecordAudioPreference.applying(.off, inputID: "usb-1")
        #expect(!off.usesHostMicrophone)
        #expect(off.inputID == "usb-1")
    }

    @Test func theDropdownRoundTripsThroughEveryState() {
        for (on, input) in [(false, ""), (true, ""), (true, "usb-1"), (false, "usb-1")] {
            let choice = RecordAudioPreference.microphoneChoice(
                usesHostMicrophone: on, inputID: input)
            let applied = RecordAudioPreference.applying(choice, inputID: input)
            #expect(applied.usesHostMicrophone == on)
            #expect(applied.inputID == input)
        }
    }
}
