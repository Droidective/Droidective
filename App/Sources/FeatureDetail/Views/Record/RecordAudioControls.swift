import ADBKit
import SwiftUI

/// Asking for microphone access at the moment the user opts in, so the system
/// prompt lands on a deliberate choice instead of surprising them when a
/// recording starts.
enum MicrophoneAccess {
    @discardableResult
    static func requestIfNeeded(forHostMicrophone on: Bool) async
        -> MicrophoneCapture.Authorization {
        guard on, MicrophoneCapture.authorization() == .notDetermined else {
            return MicrophoneCapture.authorization()
        }
        _ = await MicrophoneCapture.requestAccess()
        return MicrophoneCapture.authorization()
    }

    /// macOS only ever prompts once, so a denied app can only be fixed here.
    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The recording's audio, as two independent dropdowns:
///
/// - **Device audio** — off, the device's playback, or the device's own
///   microphone. scrcpy carries one device stream per session, so these are
///   alternatives rather than a set.
/// - **Microphone** — off, the Mac's default input, or a named input.
///
/// Any pairing works, and the summary line spells out the result so nobody has
/// to hold the combination in their head.
struct RecordAudioOptionsRow: View {
    @Binding var deviceSource: DeviceAudioSource
    @Binding var usesHostMicrophone: Bool
    /// An `AVCaptureDevice.uniqueID`, or empty for the system default input.
    @Binding var inputID: String

    @State private var inputs: [MicrophoneCapture.Input] = []
    @State private var authorization = MicrophoneCapture.authorization()
    @State private var level: Float = 0
    @State private var isTesting = false
    @State private var testTask: Task<Void, Never>?
    @State private var micError: String?

    /// What the current pairing will record, in words.
    var summary: String {
        RecordAudioOptions(
            deviceSource: deviceSource,
            usesHostMicrophone: usesHostMicrophone,
            microphoneDeviceID: inputID.isEmpty ? nil : inputID
        ).summary(microphoneName: usesHostMicrophone ? selectedInputName : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: devicePlayback) {
                rowLabel(
                    "Device audio",
                    subtitle: "The sound the app itself plays (Android 11+)")
            }
            Toggle(isOn: deviceMicrophone) {
                rowLabel(
                    "Device microphone",
                    subtitle: "What the phone's own mic hears")
            }
            if deviceSource == .microphone {
                Text("The device sends one audio stream, so its mic replaces its playback.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
                    .transition(.opacity)
            }
            labeledRow(
                "Mac microphone",
                subtitle: "Your voice — narrate what you're showing"
            ) { microphonePicker }
            if usesHostMicrophone {
                levelCheckRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let message = warning {
                warningRow(message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: usesHostMicrophone)
        .animation(.easeInOut(duration: 0.15), value: deviceSource)
        .animation(.easeInOut(duration: 0.15), value: authorization)
        .onAppear { refreshInputs() }
        .onDisappear { stopTest() }
        .onChange(of: usesHostMicrophone) { _, on in microphoneToggled(on) }
        .onChange(of: inputID) { _, _ in if isTesting { restartTest() } }
    }

    /// The device's playback and its own microphone are one checkbox each, but
    /// scrcpy carries a single device stream — so ticking one unticks the
    /// other, with a line of text saying why rather than a silently ignored
    /// setting.
    private var devicePlayback: Binding<Bool> {
        Binding(
            get: { deviceSource == .playback },
            set: { deviceSource = $0 ? .playback : .off })
    }

    private var deviceMicrophone: Binding<Bool> {
        Binding(
            get: { deviceSource == .microphone },
            set: { deviceSource = $0 ? .microphone : .off })
    }

    private func rowLabel(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(subtitle)
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
        }
    }

    private var microphonePicker: some View {
        // No `Divider()` in here: a divider inside a Picker breaks tag matching,
        // and SwiftUI then *writes back* a coerced selection — which silently
        // turned the microphone on at launch.
        Picker("", selection: microphoneChoice) {
            Text("Off").tag(MicrophoneChoice.off)
            Text("System default").tag(MicrophoneChoice.systemDefault)
            ForEach(inputs) { input in
                Text(input.name).tag(MicrophoneChoice.input(input.id))
            }
        }
        .labelsHidden().pickerStyle(.menu)
        .frame(maxWidth: 210)
        .disabled(authorization == .denied)
    }

    private var microphoneChoice: Binding<MicrophoneChoice> {
        Binding(
            get: {
                RecordAudioPreference.microphoneChoice(
                    usesHostMicrophone: usesHostMicrophone, inputID: inputID)
            },
            set: { choice in
                let applied = RecordAudioPreference.applying(choice, inputID: inputID)
                usesHostMicrophone = applied.usesHostMicrophone
                inputID = applied.inputID
            })
    }

    private var selectedInputName: String {
        guard !inputID.isEmpty else { return inputs.first?.name ?? "System default" }
        return inputs.first(where: { $0.id == inputID })?.name ?? "Selected input"
    }

    /// Hear the chosen input before committing to a take.
    private var levelCheckRow: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
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

    private func labeledRow(
        _ title: String, subtitle: String, @ViewBuilder _ control: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }
            Spacer(minLength: 12)
            control()
        }
    }

    /// Whichever of the two problems is worth saying out loud: no access, or an
    /// input that wouldn't start.
    private var warning: String? {
        guard usesHostMicrophone else { return nil }
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
                Button("Open Settings") { MicrophoneAccess.openSettings() }
                    .buttonStyle(.link)
                    .font(.app(.footnote))
            }
        }
    }

    // MARK: - Access and inputs

    private func microphoneToggled(_ on: Bool) {
        micError = nil
        guard on else {
            stopTest()
            return
        }
        refreshInputs()
        Task { @MainActor in
            authorization = await MicrophoneAccess.requestIfNeeded(forHostMicrophone: true)
        }
    }

    private func refreshInputs() {
        authorization = MicrophoneCapture.authorization()
        inputs = MicrophoneCapture.availableInputs()
        // The chosen input can vanish (a headset unplugged between recordings);
        // fall back to the system default rather than failing at Record time.
        if !inputID.isEmpty, !inputs.contains(where: { $0.id == inputID }) { inputID = "" }
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
                    title: status.deviceSource == .microphone ? "Device mic" : "Device",
                    symbol: status.deviceSource.symbolName,
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
