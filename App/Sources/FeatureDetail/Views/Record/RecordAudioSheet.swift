import ADBKit
import SwiftUI

/// The mirror's recording setup: pick what the recording captures, hear the
/// microphone, then start the take from the same place.
///
/// A sheet rather than more buttons on the mirror bar — the bar is already
/// eleven controls wide, and the audio combination is something you set up
/// once and then check, which reads badly as a row of icons.
struct RecordAudioSheet: View {
    @AppStorage(RecordAudioPreference.deviceKey) private var deviceSourceRaw =
        DeviceAudioSource.playback.rawValue
    @AppStorage(RecordAudioPreference.hostMicKey) private var usesHostMicrophone = false
    @AppStorage(RecordAudioPreference.inputKey) private var inputID = ""

    @Environment(\.dismiss) private var dismiss
    /// Starts a take. Present even when it can't run right now — the button is
    /// disabled with a reason instead of vanishing, because a control that
    /// silently isn't there reads as a broken one.
    let start: () -> Void
    /// Why recording is unavailable, or nil when it's ready.
    let blockedReason: String?

    private var deviceSource: Binding<DeviceAudioSource> {
        Binding(
            get: { DeviceAudioSource(rawValue: deviceSourceRaw) ?? .playback },
            set: { deviceSourceRaw = $0.rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recording audio").font(.app(.title3).weight(.semibold))
                Text("Mixed into one track, so the clip plays everywhere.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }

            controls

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    summaryLabel
                    if let blockedReason {
                        Text(blockedReason)
                            .font(.app(.footnote))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 12)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    dismiss()
                    start()
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                .disabled(blockedReason != nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var controls: some View {
        RecordAudioOptionsRow(
            deviceSource: deviceSource,
            usesHostMicrophone: $usesHostMicrophone,
            inputID: $inputID)
    }

    /// Spells out the resulting combination, so "what will this capture?" is
    /// answered on the sheet rather than after playback.
    private var summaryLabel: some View {
        let options = RecordAudioOptions(
            deviceSource: deviceSource.wrappedValue,
            usesHostMicrophone: usesHostMicrophone,
            microphoneDeviceID: inputID.isEmpty ? nil : inputID)
        return Label(
            options.summary(microphoneName: nil),
            systemImage: options.mode.hasAudio ? "waveform" : "speaker.slash.fill")
            .font(.app(.footnote))
            .foregroundStyle(.textMuted)
            .lineLimit(2)
    }
}
