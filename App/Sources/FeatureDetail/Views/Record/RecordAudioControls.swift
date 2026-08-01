import ADBKit
import SwiftUI

/// Asking for microphone access at the moment the user opts in — from the
/// Screen Record picker or the mirror's ⋯ menu — so the system prompt lands on
/// a deliberate choice instead of surprising them when a recording starts.
enum MicrophoneAccess {
    @discardableResult
    static func requestIfNeeded(for mode: RecordAudioMode) async -> MicrophoneCapture.Authorization {
        guard mode.includesMicrophone,
              MicrophoneCapture.authorization() == .notDetermined
        else { return MicrophoneCapture.authorization() }
        _ = await MicrophoneCapture.requestAccess()
        return MicrophoneCapture.authorization()
    }
}

/// The audio choice on the Screen Record screen: two switches — the device's
/// own sound, and the Mac's microphone — because that's what the recording
/// actually has, and either can be on without the other. When the microphone
/// is on it gains an input picker and a level check, so you know it's hearing
/// you before you hit Record.
struct RecordAudioOptionsRow: View {
    @Binding var mode: RecordAudioMode
    /// An `AVCaptureDevice.uniqueID`, or empty for the system default input.
    @Binding var inputID: String

    private var deviceAudio: Binding<Bool> {
        Binding(
            get: { mode.includesDevice },
            set: { mode = .mode(device: $0, microphone: mode.includesMicrophone) })
    }

    private var microphone: Binding<Bool> {
        Binding(
            get: { mode.includesMicrophone },
            set: { mode = .mode(device: mode.includesDevice, microphone: $0) })
    }

    @State private var inputs: [MicrophoneCapture.Input] = []
    @State private var authorization = MicrophoneCapture.authorization()
    @State private var level: Float = 0
    @State private var isTesting = false
    @State private var testTask: Task<Void, Never>?
    @State private var micError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwitchRow(
                "Device audio",
                subtitle: "The app's own sound, from the device (Android 11+)",
                isOn: deviceAudio)
            SwitchRow(
                "Microphone",
                subtitle: "Your voice, from the Mac — narrate what you're showing",
                isOn: microphone)
            if mode.includesMicrophone {
                microphoneRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let message = warning {
                warningRow(message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: mode)
        .animation(.easeInOut(duration: 0.15), value: authorization)
        .onAppear { refreshInputs() }
        .onDisappear { stopTest() }
        .onChange(of: mode) { _, new in modeChanged(to: new) }
        .onChange(of: inputID) { _, _ in if isTesting { restartTest() } }
    }

    private var microphoneRow: some View {
        HStack(spacing: 8) {
            Text("Input")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
            Picker("", selection: $inputID) {
                Text("System default").tag("")
                ForEach(inputs) { input in
                    Text(input.name).tag(input.id)
                }
            }
            .labelsHidden().pickerStyle(.menu)
            .frame(maxWidth: 190)
            .disabled(authorization == .denied)

            AudioLevelMeter(level: level)
                .frame(width: 62)
                .opacity(isTesting ? 1 : 0.35)

            Button(isTesting ? "Stop" : "Test") {
                isTesting ? stopTest() : startTest()
            }
            .controlSize(.small)
            .disabled(authorization == .denied)
            .help("Listen to the selected input without recording")
        }
    }

    /// Whichever of the two problems is worth saying out loud: no access, or an
    /// input that wouldn't start.
    private var warning: String? {
        guard mode.includesMicrophone else { return nil }
        if authorization == .denied {
            return "Microphone access is off, so the recording won’t have mic audio."
        }
        return micError
    }

    private func warningRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if authorization == .denied {
                Button("Open Settings") { openMicrophoneSettings() }
                    .buttonStyle(.link)
                    .font(.app(.footnote))
            }
        }
    }

    // MARK: - Access and inputs

    private func modeChanged(to mode: RecordAudioMode) {
        micError = nil
        guard mode.includesMicrophone else {
            stopTest()
            return
        }
        refreshInputs()
        Task { @MainActor in
            authorization = await MicrophoneAccess.requestIfNeeded(for: mode)
        }
    }

    private func refreshInputs() {
        authorization = MicrophoneCapture.authorization()
        inputs = MicrophoneCapture.availableInputs()
        // The chosen input can vanish (a headset unplugged between recordings);
        // fall back to the system default rather than failing at Record time.
        if !inputID.isEmpty, !inputs.contains(where: { $0.id == inputID }) { inputID = "" }
    }

    private func openMicrophoneSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Level check

    private func startTest() {
        stopTest()
        isTesting = true
        micError = nil
        let deviceID = inputID.isEmpty ? nil : inputID
        testTask = Task { @MainActor in
            let capture = MicrophoneCapture(deviceID: deviceID)
            // bufferingNewest(1): a meter only ever wants the newest level.
            let (levels, sink) = AsyncStream.makeStream(
                of: Float.self, bufferingPolicy: .bufferingNewest(1))
            do {
                try await capture.start { sink.yield($0.level) }
            } catch {
                micError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                isTesting = false
                sink.finish()
                return
            }
            // A forgotten test must not hold the microphone open indefinitely.
            let timeout = Task { try? await Task.sleep(for: .seconds(30)); sink.finish() }
            for await value in levels { level = value }
            timeout.cancel()
            await capture.stop()
            if let failure = await capture.failure() { micError = failure.errorDescription }
            level = 0
            isTesting = false
        }
    }

    private func stopTest() {
        testTask?.cancel()
        testTask = nil
        isTesting = false
        level = 0
    }

    private func restartTest() {
        stopTest()
        startTest()
    }
}

/// A segmented input meter. Speech RMS sits low (roughly 0.05–0.2 of full
/// scale), so the segments follow a square-root curve — a linear bar would look
/// dead for a perfectly good signal — and the top two turn orange as a clipping
/// warning.
struct AudioLevelMeter: View {
    let level: Float
    var segments = 10

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< segments, id: \.self) { index in
                Capsule()
                    .fill(isLit(index) ? color(index) : Color.primary.opacity(0.12))
                    .frame(height: 9)
            }
        }
        .animation(.linear(duration: 0.08), value: level)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(scaled * 100)) percent")
    }

    private var scaled: Float { min(1, level.squareRoot() * 1.25) }

    private func isLit(_ index: Int) -> Bool {
        scaled * Float(segments) >= Float(index) + 0.5
    }

    private func color(_ index: Int) -> Color {
        index >= segments - 2 ? .orange : .brandAccent
    }
}

/// The mute controls shown while recording — one chip per source that's being
/// captured. Muting writes silence rather than stopping the capture, so the
/// chips stay live and unmuting is instant.
struct RecordAudioMuteChips: View {
    let status: ScreenRecorder.AudioStatus
    let setMuted: (_ device: Bool, _ microphone: Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if status.mode.includesDevice {
                chip(
                    title: "Device",
                    symbol: "speaker.wave.2.fill",
                    mutedSymbol: "speaker.slash.fill",
                    isMuted: status.deviceMuted,
                    level: nil
                ) { setMuted(!status.deviceMuted, status.microphoneMuted) }
            }
            if status.mode.includesMicrophone {
                chip(
                    title: "Mic",
                    symbol: "mic.fill",
                    mutedSymbol: "mic.slash.fill",
                    isMuted: status.microphoneMuted,
                    level: status.microphoneFailure == nil ? status.microphoneLevel : nil
                ) { setMuted(status.deviceMuted, !status.microphoneMuted) }
            }
            if let failure = status.microphoneFailure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }

    private func chip(
        title: String,
        symbol: String,
        mutedSymbol: String,
        isMuted: Bool,
        level: Float?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isMuted ? mutedSymbol : symbol)
                    .font(.app(.caption).weight(.semibold))
                Text(title).font(.app(.caption))
                if let level, !isMuted {
                    AudioLevelMeter(level: level, segments: 5).frame(width: 30)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isMuted ? Color.primary.opacity(0.08) : Color.brandAccent.opacity(0.16)))
            .overlay(Capsule().strokeBorder(.borderSubtle))
            .foregroundStyle(isMuted ? Color.secondary : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Unmute \(title.lowercased())" : "Mute \(title.lowercased())")
    }
}
