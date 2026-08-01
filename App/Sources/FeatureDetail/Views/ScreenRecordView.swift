import ADBKit
import CoreImage
import Foundation
import SwiftUI

/// Record the device screen via the in-app scrcpy client (bundled server, no
/// separate install, audio on Android 11+). The Record button and status sit up
/// top; tuning lives in a collapsed Advanced drop-down. Stopping opens the clip
/// in the video editor.
struct ScreenRecordView: View {
    @Environment(AppState.self) private var state
    @Environment(\.tabFeatureID) private var tabFeatureID
    @State private var recorder: ScreenRecorder?
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var isBusy = false
    /// Reference date for the elapsed timer, shifted forward on each resume so
    /// the displayed time counts only *active* recording (paused time excluded).
    @State private var startedAt: Date?
    /// When the current pause began; drives the frozen timer and the time-limit
    /// reschedule. `nil` while actively recording.
    @State private var pausedAt: Date?
    @State private var recordedURL: URL?
    /// A finished recording awaiting the Discard/Save/Edit choice.
    @State private var decisionURL: URL?
    /// The serial the active recording targets, watched for disconnects.
    @State private var recordingSerial: String?
    /// The recording device vanished mid-capture: the captured segments are
    /// kept and only Stop (save/edit/discard) remains.
    @State private var deviceLost = false
    @State private var showAdvanced = false
    @State private var limitTask: Task<Void, Never>?
    /// Identifies this view's leave guard so a stale clear can't wipe another's.
    @State private var exitGuardID = UUID()
    /// Live preview of the frames being captured, polled from the recorder's
    /// session while recording so the user sees what's going into the file.
    @State private var previewImage: NSImage?
    @State private var previewTask: Task<Void, Never>?
    /// Reused across the preview poll — a fresh `CIContext` per frame is costly.
    @State private var previewContext = CIContext()

    /// What the live recording is capturing, polled alongside the preview so the
    /// mute chips and mic meter track the recorder without a second timer.
    @State private var audioStatus: ScreenRecorder.AudioStatus?

    @AppStorage("recMaxSize") private var maxSize = 0
    @AppStorage("recBitRate") private var bitRateMbps = 0
    @AppStorage("recMaxFps") private var maxFps = 0
    @AppStorage(RecordAudioPreference.deviceKey) private var deviceSourceRaw =
        DeviceAudioSource.playback.rawValue
    @AppStorage(RecordAudioPreference.hostMicKey) private var usesHostMicrophone = false
    @AppStorage(RecordAudioPreference.inputKey) private var micInputID = ""
    @AppStorage("recTimeLimit") private var timeLimit = 0

    private var deviceSource: Binding<DeviceAudioSource> {
        Binding(
            get: { DeviceAudioSource(rawValue: deviceSourceRaw) ?? .playback },
            set: { deviceSourceRaw = $0.rawValue })
    }

    private var recordOptions: ScreenRecordOptions {
        ScreenRecordOptions(
            maxSize: maxSize, bitRateMbps: bitRateMbps, maxFps: maxFps,
            audio: RecordAudioOptions(
                deviceSource: deviceSource.wrappedValue,
                usesHostMicrophone: usesHostMicrophone,
                microphoneDeviceID: micInputID.isEmpty ? nil : micInputID),
            timeLimitSeconds: timeLimit
        )
    }

    var body: some View {
        Group {
            if let url = recordedURL {
                VideoEditorPane(source: .recording(url)) {
                    try? FileManager.default.removeItem(at: url)
                    recordedURL = nil
                }
                .id(url)
            } else {
                recordControls
            }
        }
        .recordingDecision(url: $decisionURL) { recordedURL = $0 }
        .onAppear { RecordAudioPreference.migrate(.standard) }
        .onChange(of: state.devices) {
            guard isRecording, !isStopping, !deviceLost, let recordingSerial,
                  !state.devices.contains(where: { $0.serial == recordingSerial && $0.isReady })
            else { return }
            Task { await handleDeviceLost() }
        }
        .onChange(of: state.pendingExit?.saving) { _, saving in
            if saving == true, isRecording, state.pendingExitConcerns(tabFeatureID) {
                Task { await saveRecordingForLeave() }
            }
        }
        .onDisappear {
            limitTask?.cancel()
            stopPreviewPolling()
            state.setRecording(false, owner: "screen-record")
            state.clearExitGuard(exitGuardID)
            if isRecording, let recorder { Task { await recorder.abort() } }
            if let url = recordedURL { try? FileManager.default.removeItem(at: url) }
        }
    }

    private var recordControls: some View {
        VStack(spacing: 28) {
            hero
            // Options are irrelevant (and locked) once recording starts; hiding
            // them frees the column for the live preview.
            if !isRecording { optionsCard }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    // MARK: centered record control

    private var hero: some View {
        VStack(spacing: 16) {
            if isRecording {
                recordingPreview
            } else {
                ZStack {
                    Circle()
                        .fill(Color.brandAccent.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: "video.fill")
                        .font(.app(size: 38))
                        .foregroundStyle(.brandAccent)
                }
            }

            VStack(spacing: 4) {
                if isRecording, let startedAt {
                    Group {
                        // Frozen while paused so a paused recording no longer
                        // looks like it's still running; live otherwise.
                        if isPaused {
                            Text(Self.durationLabel(activeElapsed()))
                        } else {
                            Text(startedAt, style: .timer)
                        }
                    }
                    .font(.app(size: 30, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    Text(deviceLost
                        ? "Device disconnected — recording stopped"
                        : (isPaused ? "Paused" : "Recording…"))
                        .font(.app(.subheadline))
                        .foregroundStyle(deviceLost
                            ? Color.orange
                            : (isPaused ? Color.secondary : Color.red))
                } else {
                    Text("Ready to record").font(.app(.title2).weight(.semibold))
                }
            }

            if isRecording, let audioStatus, audioStatus.mode.hasAudio {
                RecordAudioMuteChips(status: audioStatus) { device, microphone in
                    Task { await recorder?.setMuted(device: device, microphone: microphone) }
                }
            }
            recordControlButtons
            hints
        }
        .frame(maxWidth: 420)
    }

    /// Live mirror of the frames being captured. The recorder's session already
    /// decodes every frame for snapshots, so this just renders the latest at a
    /// preview-friendly rate — it freezes on the last frame (dimmed) while paused.
    private var recordingPreview: some View {
        previewContent
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.borderSubtle))
            .overlay(alignment: .topLeading) { recBadge }
            .animation(.easeInOut(duration: 0.2), value: isPaused)
    }

    @ViewBuilder private var previewContent: some View {
        if let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 320)
                .opacity(isPaused ? 0.55 : 1)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .frame(width: 200, height: 300)
                .overlay { ProgressView().controlSize(.large).tint(.white) }
        }
    }

    private var recBadge: some View {
        Label(deviceLost ? "STOPPED" : (isPaused ? "PAUSED" : "REC"),
              systemImage: deviceLost ? "stop.fill" : (isPaused ? "pause.fill" : "record.circle.fill"))
            .font(.app(.caption2).weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(deviceLost ? Color.orange : (isPaused ? Color.secondary : Color.red), in: Capsule())
            .symbolEffect(.pulse, isActive: !isPaused && !deviceLost)
            .padding(8)
    }

    @ViewBuilder private var recordControlButtons: some View {
        if deviceLost {
            Button { Task { await stop() } } label: {
                Label("Stop & Save", systemImage: "stop.fill").frame(width: 140)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            .disabled(isStopping)
        } else if isRecording {
            HStack(spacing: 12) {
                Button {
                    // Claim the busy gate synchronously, before spawning the
                    // task, so a second tap can't start a competing toggle that
                    // reads the just-flipped `isPaused` and fires the opposite
                    // action.
                    guard !isBusy else { return }
                    isBusy = true
                    Task { await togglePauseResume() }
                } label: {
                    Label(isPaused ? "Resume" : "Pause",
                          systemImage: isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 104)
                }
                .controlSize(.large)
                // Also disabled while stopping: a stop (manual or the auto
                // time-limit) is terminal, so there's nothing left to pause.
                .disabled(isBusy || isStopping)

                Button { Task { await stop() } } label: {
                    Label("Stop", systemImage: "stop.fill").frame(width: 104)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                .disabled(isStopping)
            }
        } else {
            Button { Task { await start() } } label: {
                Label(isStarting ? "Starting…" : "Record", systemImage: "record.circle")
                    .frame(width: 220)
            }
            .buttonStyle(.borderedProminent).tint(.brandAccent).controlSize(.large)
            .disabled(isStarting || state.targetSerials.isEmpty)
        }
    }

    @ViewBuilder private var hints: some View {
        if state.targetSerials.isEmpty {
            Text("Connect a device to record.").font(.app(.footnote)).foregroundStyle(.textMuted)
        }
    }

    // MARK: options (basic outside, the rest under Advanced)

    private var optionsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                labeledRow("Resolution") { resolutionPicker }
                RecordAudioOptionsRow(
                    deviceSource: deviceSource,
                    usesHostMicrophone: $usesHostMicrophone,
                    inputID: $micInputID)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showAdvanced.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.app(.caption).weight(.semibold))
                            .foregroundStyle(.textMuted)
                            .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                        Text("Advanced options")
                            .font(.app(.callout).weight(.medium))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showAdvanced {
                    VStack(alignment: .leading, spacing: 14) {
                        labeledRow("Bit rate") { bitRatePicker }
                        labeledRow("Max FPS") { fpsPicker }
                        labeledRow("Time limit") { timeLimitPicker }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: 420)
        .disabled(isRecording)
    }

    private func labeledRow(_ title: String, @ViewBuilder _ control: () -> some View) -> some View {
        HStack {
            Text(title)
            Spacer()
            control()
        }
    }

    private var resolutionPicker: some View {
        Picker("", selection: $maxSize) {
            Text("Device").tag(0)
            Text("1920 px").tag(1920)
            Text("1280 px").tag(1280)
            Text("1024 px").tag(1024)
            Text("800 px").tag(800)
        }
        .labelsHidden().pickerStyle(.menu).fixedSize()
    }

    private var bitRatePicker: some View {
        Picker("", selection: $bitRateMbps) {
            Text("Default").tag(0)
            Text("2 Mbps").tag(2)
            Text("4 Mbps").tag(4)
            Text("8 Mbps").tag(8)
            Text("16 Mbps").tag(16)
        }
        .labelsHidden().pickerStyle(.menu).fixedSize()
    }

    private var fpsPicker: some View {
        Picker("", selection: $maxFps) {
            Text("Unlimited").tag(0)
            Text("30").tag(30)
            Text("60").tag(60)
            Text("120").tag(120)
        }
        .labelsHidden().pickerStyle(.menu).fixedSize()
    }

    private var timeLimitPicker: some View {
        Picker("", selection: $timeLimit) {
            Text("Unlimited").tag(0)
            Text("1 min").tag(60)
            Text("3 min").tag(180)
            Text("5 min").tag(300)
            Text("10 min").tag(600)
        }
        .labelsHidden().pickerStyle(.menu).fixedSize()
    }

    private func start() async {
        guard let serial = state.targetSerials.first, !isStarting else { return }
        guard let server = BundledTools.scrcpyServer() else {
            state.showToast(Toast(message: "Bundled scrcpy server is missing from the app.", ok: false))
            return
        }
        isStarting = true
        let recorder = ScreenRecorder(
            client: state.env.client, server: server, ffmpegPath: BundledTools.ffmpegPath())
        let options = recordOptions
        do {
            try await recorder.start(serial: serial, options: options)
            self.recorder = recorder
            isRecording = true
            isPaused = false
            pausedAt = nil
            recordingSerial = serial
            deviceLost = false
            startedAt = Date()
            startPreviewPolling()
            // Lock the device/bundle pickers for the duration, as the
            // performance/network recorders do. A recording targets one device;
            // switching it mid-capture would strand this recorder (the view stays
            // mounted on a device switch, so .onDisappear never fires to abort it).
            state.setRecording(true, owner: "screen-record")
            state.setExitGuard(.init(
                id: exitGuardID, featureID: tabFeatureID, style: .recording,
                title: "Recording in progress",
                message: "Leaving will stop the screen recording. Save it first, or discard it."))
            scheduleTimeLimit(remaining: TimeInterval(options.timeLimitSeconds))
        } catch {
            state.showToast(Toast(message: error.localizedDescription, ok: false))
        }
        isStarting = false
    }

    /// Pause/resume as a single guarded operation. The button sets `isBusy`
    /// synchronously before spawning this, so exactly one toggle runs at a time;
    /// `defer` guarantees the gate is released even if `resume()` throws or the
    /// task is cancelled mid-await, so the controls can never wedge disabled.
    private func togglePauseResume() async {
        defer { isBusy = false }
        guard let recorder else { return }
        if isPaused {
            do {
                try await recorder.resume()
                // Stop is intentionally left tappable during a resume (its stream
                // bring-up can take a while, and a dead Stop button is the very
                // bug this screen is fixing). So a Stop can land mid-resume:
                //   • already finished  → the session we just re-established is
                //     orphaned; tear it down so the device stream doesn't leak.
                //   • still in flight    → it will finalize this session itself,
                //     so leave the teardown (and state) to it.
                if !isRecording {
                    await recorder.abort()
                    return
                }
                guard !isStopping else { return }
                // Shift the timer's reference forward by the paused gap so the
                // displayed elapsed keeps counting only active recording time.
                if let pausedAt, let startedAt {
                    self.startedAt = startedAt.addingTimeInterval(Date().timeIntervalSince(pausedAt))
                }
                pausedAt = nil
                isPaused = false
                if timeLimit > 0 {
                    scheduleTimeLimit(remaining: TimeInterval(timeLimit) - activeElapsed())
                }
            } catch {
                // Re-establishing the stream failed; stay paused so the user can
                // retry (isBusy is released by the defer above).
                state.showToast(Toast(message: error.localizedDescription, ok: false))
            }
        } else {
            limitTask?.cancel()  // freeze the time limit before tearing down
            await recorder.pause()
            // A concurrent Stop may have finished (or be finishing) the recording
            // during the await; if so it owns the teardown — don't write stale
            // paused state over it.
            guard isRecording, !isStopping else { return }
            pausedAt = Date()
            isPaused = true
        }
    }

    /// The recording device dropped off adb mid-capture. Finalize the segment
    /// being written (keeping it, like a pause) and freeze the UI in a
    /// "recording stopped" state — Stop & Save assembles what was captured.
    private func handleDeviceLost() async {
        guard let recorder, isRecording, !isStopping else { return }
        limitTask?.cancel()
        await recorder.pause()
        guard isRecording, !isStopping else { return }
        deviceLost = true
        pausedAt = Date()
        isPaused = true
    }

    /// Seconds of active (non-paused) recording elapsed so far.
    private func activeElapsed(_ now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (pausedAt ?? now).timeIntervalSince(startedAt))
    }

    /// Format a duration as `m:ss` (or `h:mm:ss`), matching the live `.timer`
    /// style so the frozen paused readout doesn't visually jump.
    private static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Poll the recorder's latest decoded frame and show it as the preview. Kept
    /// running across pause (it returns nil then, so the last frame stays, dimmed)
    /// and cancelled on stop/leave. ~11 fps is plenty to see what's being captured
    /// without loading the main thread.
    private func startPreviewPolling() {
        previewTask?.cancel()
        guard let recorder else { return }
        let context = previewContext
        previewTask = Task { @MainActor in
            while !Task.isCancelled {
                if let snap = await recorder.previewFrame(),
                   let image = MirrorImage.nsImage(from: snap.imageBuffer, context: context) {
                    previewImage = image
                }
                audioStatus = await recorder.audioStatus()
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    private func stopPreviewPolling() {
        previewTask?.cancel()
        previewTask = nil
        previewImage = nil
        audioStatus = nil
    }

    /// The server has no time-limit knob, so the UI stops the recording after the
    /// chosen duration of *active* recording (0 = unlimited). Paused time is
    /// excluded: the task is cancelled on pause and rescheduled for the remaining
    /// time on resume, matching the frozen on-screen timer.
    private func scheduleTimeLimit(remaining: TimeInterval) {
        limitTask?.cancel()
        guard timeLimit > 0 else { return }
        guard remaining > 0 else { Task { await stop() }; return }
        limitTask = Task {
            try? await Task.sleep(for: .seconds(remaining))
            if !Task.isCancelled, isRecording, !isPaused { await stop() }
        }
    }

    private func stop() async {
        guard let recorder, !isStopping else { return }
        limitTask?.cancel()
        limitTask = nil
        isStopping = true
        do {
            let url = try await state.withOperation("Finishing recording…") {
                try await recorder.stop()
            }
            decisionURL = url
        } catch {
            state.showToast(Toast(message: error.localizedDescription, ok: false))
        }
        isRecording = false
        isPaused = false
        pausedAt = nil
        isStopping = false
        startedAt = nil
        recordingSerial = nil
        deviceLost = false
        self.recorder = nil
        stopPreviewPolling()
        state.setRecording(false, owner: "screen-record")
        state.clearExitGuard(exitGuardID)
    }

    /// "Stop & save" from the leave prompt: finalize the recording straight into
    /// the capture folder (skipping the Discard/Save/Edit sheet), then let the
    /// navigation proceed.
    private func saveRecordingForLeave() async {
        limitTask?.cancel()
        // Cleared here, not only in .onDisappear: a Stop & Save that resolves a
        // device switch keeps this view mounted, so onDisappear wouldn't fire to
        // unlock the device/bundle pickers.
        state.setRecording(false, owner: "screen-record")
        guard let recorder else { state.finishExitSave(); return }
        self.recorder = nil
        isRecording = false
        isPaused = false
        pausedAt = nil
        startedAt = nil
        recordingSerial = nil
        deviceLost = false
        stopPreviewPolling()
        do {
            let temp = try await recorder.stop()
            state.confirmCaptureFolderOnce()
            let dir = try ScreenCaptureService.ensureCaptureDir()
            let dest = dir.appendingPathComponent("recording_\(ScreenCaptureService.stamp()).mp4")
            try FileManager.default.moveItem(at: temp, to: dest)
            state.showToast(Toast(message: "Recording saved", ok: true, revealPath: dest.path))
        } catch {
            state.showToast(Toast(message: "Couldn’t save recording: \(error.localizedDescription)", ok: false))
        }
        state.finishExitSave()
    }
}
