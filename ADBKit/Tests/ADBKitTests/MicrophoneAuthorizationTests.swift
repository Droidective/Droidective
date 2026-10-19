#if canImport(AVFoundation)
import AVFoundation
#endif
import Testing

@testable import ADBKit

/// What the recording controls may tell someone about the Mac's microphone
/// permission. The rule that matters: System Settings is only offered when it
/// holds a Droidective switch to turn on — macOS lists an app there only once
/// it has asked, and a restricted Mac has no switch at all.
@Suite struct MicrophoneAuthorizationTests {
    @Test func onlyARefusalIsFixedInSystemSettings() {
        #expect(MicrophoneAuthorization.denied.isFixableInSettings)
        // Never asked: Droidective isn't in the list yet, so it must ask.
        #expect(!MicrophoneAuthorization.notDetermined.isFixableInSettings)
        // Screen Time or a management profile: there's no switch to flip.
        #expect(!MicrophoneAuthorization.restricted.isFixableInSettings)
        #expect(!MicrophoneAuthorization.authorized.isFixableInSettings)
    }

    @Test func aRecordingIsWarnedOnlyWhenItWontGetTheMicrophone() {
        #expect(MicrophoneAuthorization.authorized.recordingNotice == nil)
        // Still able to ask, so nothing has gone wrong yet.
        #expect(MicrophoneAuthorization.notDetermined.recordingNotice == nil)
        let denied = MicrophoneAuthorization.denied.recordingNotice
        let restricted = MicrophoneAuthorization.restricted.recordingNotice
        #expect(denied != nil && restricted != nil)
        // A restricted Mac must not read as a switch the user forgot to flip.
        #expect(denied != restricted)
        #expect(restricted?.contains("restricts") == true)
    }

    #if canImport(AVFoundation)
    @Test func aRestrictedMacIsNotReportedAsADenial() {
        #expect(MicrophoneCapture.authorization(for: .restricted) == .restricted)
        #expect(MicrophoneCapture.authorization(for: .denied) == .denied)
        #expect(MicrophoneCapture.authorization(for: .notDetermined) == .notDetermined)
        #expect(MicrophoneCapture.authorization(for: .authorized) == .authorized)
    }

    @Test func aCaptureRefusalCarriesWhetherSettingsCanFixIt() {
        let denied = MicrophoneCapture.CaptureError.notAuthorized(.denied)
        #expect(denied.isFixableInSettings)
        #expect(denied.errorDescription == MicrophoneAuthorization.denied.recordingNotice)

        #expect(!MicrophoneCapture.CaptureError.notAuthorized(.restricted).isFixableInSettings)
        #expect(!MicrophoneCapture.CaptureError.noInputDevice.isFixableInSettings)

        // A refusal that never reached the prompt leaves the app unlisted, so it
        // still explains itself but doesn't point at System Settings.
        let unprompted = MicrophoneCapture.CaptureError.notAuthorized(.notDetermined)
        #expect(!unprompted.isFixableInSettings)
        #expect(unprompted.errorDescription == "Droidective doesn’t have microphone access.")
    }
    #endif
}
