import Foundation
import Testing

@testable import ADBKit

/// The recording's audio shape: what the device contributes (one stream —
/// playback *or* its own mic) and whether the Mac's microphone is mixed in.
@Suite struct RecordAudioOptionsTests {
    @Test func theDeviceHalfMapsOntoScrcpysAudioSource() {
        #expect(DeviceAudioSource.playback.scrcpySource == .output)
        #expect(DeviceAudioSource.microphone.scrcpySource == .microphone)
        // Off never reaches the server as a source — the stream is simply not
        // requested — but it must not claim to be the microphone either.
        #expect(DeviceAudioSource.off.scrcpySource == .output)
        #expect(!DeviceAudioSource.off.isOn)
        #expect(DeviceAudioSource.playback.isOn && DeviceAudioSource.microphone.isOn)
    }

    @Test func theMixerSeesTwoSourcesOnlyWhenBothSidesAreOn() {
        #expect(RecordAudioOptions(deviceSource: .off, usesHostMicrophone: false).mode == .muted)
        #expect(RecordAudioOptions(deviceSource: .playback, usesHostMicrophone: false).mode
            == .deviceOnly)
        #expect(RecordAudioOptions(deviceSource: .off, usesHostMicrophone: true).mode
            == .microphoneOnly)
        // The device's own mic is still "the device side" as far as mixing goes.
        #expect(RecordAudioOptions(deviceSource: .microphone, usesHostMicrophone: true).mode
            == .deviceAndMicrophone)
        #expect(RecordAudioOptions(deviceSource: .microphone, usesHostMicrophone: true).mode
            .mixesSources)
    }

    @Test func theSummaryNamesEveryCombination() {
        #expect(RecordAudioOptions(deviceSource: .off, usesHostMicrophone: false)
            .summary(microphoneName: "MacBook Pro Microphone") == "No audio")
        #expect(RecordAudioOptions(deviceSource: .playback, usesHostMicrophone: false)
            .summary(microphoneName: "MacBook Pro Microphone") == "Device playback")
        #expect(RecordAudioOptions(deviceSource: .off, usesHostMicrophone: true)
            .summary(microphoneName: "MacBook Pro Microphone") == "MacBook Pro Microphone")
        #expect(RecordAudioOptions(deviceSource: .microphone, usesHostMicrophone: true)
            .summary(microphoneName: "Podcast Mic") == "Device microphone + Podcast Mic")
    }

    @Test func theSummaryStillReadsWithoutAnInputName() {
        #expect(RecordAudioOptions(deviceSource: .playback, usesHostMicrophone: true)
            .summary(microphoneName: nil) == "Device playback + the Mac's microphone")
    }

    @Test func coreAudiosOwnScratchDevicesAreNotOfferedAsMicrophones() {
        // The aggregate macOS builds around the default input is not something
        // anyone means to pick — it shows up as "CADefaultDeviceAggregate-87116-0".
        #expect(!RecordAudioInputs.isSelectable(
            name: "CADefaultDeviceAggregate-87116-0", uniqueID: "CADefaultDeviceAggregate-87116-0"))
        #expect(!RecordAudioInputs.isSelectable(name: "CATapAggregateDevice-1", uniqueID: "x"))
        #expect(!RecordAudioInputs.isSelectable(name: "anything", uniqueID: "AMS2_Aggregate-9"))
    }

    @Test func realMicrophonesStayInTheList() {
        #expect(RecordAudioInputs.isSelectable(
            name: "MacBook Pro Microphone", uniqueID: "BuiltInMicrophoneDevice"))
        #expect(RecordAudioInputs.isSelectable(
            name: "Scarlett Solo USB", uniqueID: "AppleUSBAudioEngine:Focusrite"))
        // A name that merely *contains* the marker is still a real device.
        #expect(RecordAudioInputs.isSelectable(
            name: "My CADefaultDeviceAggregate Clone", uniqueID: "usb-9"))
    }

    @Test func optionsRoundTripThroughCodable() throws {
        let options = RecordAudioOptions(
            deviceSource: .microphone, usesHostMicrophone: true, microphoneDeviceID: "usb-1")
        let data = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(RecordAudioOptions.self, from: data) == options)
    }
}
