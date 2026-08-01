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

    // MARK: - The microphone dropdown

    @Test func theDropdownShowsWhatIsStored() {
        #expect(RecordAudioPreference.microphoneChoice(mode: .deviceOnly, inputID: "") == .off)
        // An input is remembered while off, but off is still what's shown.
        #expect(RecordAudioPreference.microphoneChoice(mode: .muted, inputID: "usb-1") == .off)
        #expect(RecordAudioPreference.microphoneChoice(mode: .microphoneOnly, inputID: "")
            == .systemDefault)
        #expect(RecordAudioPreference.microphoneChoice(mode: .deviceAndMicrophone, inputID: "usb-1")
            == .input("usb-1"))
    }

    @Test func pickingAnInputTurnsTheMicrophoneOnAndLeavesDeviceAudioAlone() {
        let on = RecordAudioPreference.applying(.input("usb-1"), mode: .deviceOnly, inputID: "")
        #expect(on.mode == .deviceAndMicrophone)
        #expect(on.inputID == "usb-1")

        let micOnly = RecordAudioPreference.applying(.systemDefault, mode: .muted, inputID: "usb-1")
        #expect(micOnly.mode == .microphoneOnly)
        // "System default" means exactly that — the named input is cleared.
        #expect(micOnly.inputID == "")
    }

    @Test func turningTheMicrophoneOffKeepsTheChosenInputForNextTime() {
        let off = RecordAudioPreference.applying(
            .off, mode: .deviceAndMicrophone, inputID: "usb-1")
        #expect(off.mode == .deviceOnly)
        #expect(off.inputID == "usb-1")
        // Device audio off stays off, too.
        #expect(RecordAudioPreference.applying(.off, mode: .microphoneOnly, inputID: "").mode
            == .muted)
    }

    @Test func theDropdownRoundTripsThroughEveryState() {
        for (mode, input) in [
            (RecordAudioMode.muted, ""), (.deviceOnly, ""), (.microphoneOnly, ""),
            (.deviceAndMicrophone, "usb-1"),
        ] as [(RecordAudioMode, String)] {
            let choice = RecordAudioPreference.microphoneChoice(mode: mode, inputID: input)
            let applied = RecordAudioPreference.applying(choice, mode: mode, inputID: input)
            #expect(applied.mode == mode)
            #expect(applied.inputID == input)
        }
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
