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
    @State private var recorder: ScreenRecorder?
    @State private var isRecording = false
    @State private var isPaused = false
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var isBusy = false
    @State private var startedAt: Date?
    @State private var recordedURL: URL?
    /// A finished recording awaiting the Discard/Save/Edit choice.
    @State private var decisionURL: URL?
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

    @AppStorage("recMaxSize") private var maxSize = 0
    @AppStorage("recBitRate") private var bitRateMbps = 0
    @AppStorage("recMaxFps") private var maxFps = 0
    @AppStorage("recCaptureAudio") private var captureAudio = true
    @AppStorage("recTimeLimit") private var timeLimit = 0

    private var recordOptions: ScreenRecordOptions {
        ScreenRecordOptions(
            maxSize: maxSize, bitRateMbps: bitRateMbps, maxFps: maxFps,
            captureAudio: captureAudio, timeLimitSeconds: timeLimit
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
        .onChange(of: state.pendingExit?.saving) { _, saving in
            if saving == true, isRecording { Task { await saveRecordingForLeave() } }
        }
        .onDisappear {
            limitTask?.cancel()
            stopPreviewPolling()
            state.recordingActive = false
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
                        .font(.system(size: 38))
                        .foregroundStyle(.brandAccent)
                }
            }

            VStack(spacing: 4) {
                if isRecording, let startedAt {
                    Text(startedAt, style: .timer)
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                    Text(isPaused ? "Paused" : "Recording…")
                        .font(.subheadline)
                        .foregroundStyle(isPaused ? Color.secondary : Color.red)
                } else {
                    Text("Ready to record").font(.title2.weight(.semibold))
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
        Label(isPaused ? "PAUSED" : "REC", systemImage: isPaused ? "pause.fill" : "record.circle.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isPaused ? Color.secondary : Color.red, in: Capsule())
            .symbolEffect(.pulse, isActive: !isPaused)
            .padding(8)
    }

    @ViewBuilder private var recordControlButtons: some View {
        if isRecording {
            HStack(spacing: 12) {
                Button {
                    Task { isPaused ? await resume() : await pause() }
                } label: {
                    Label(isPaused ? "Resume" : "Pause",
                          systemImage: isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 104)
                }
                .controlSize(.large)
                .disabled(isBusy)

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
            Text("Connect a device to record.").font(.footnote).foregroundStyle(.textMuted)
        }
    }

    // MARK: options (basic outside, the rest under Advanced)

    private var optionsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                labeledRow("Resolution") { resolutionPicker }
                SwitchRow("Capture audio (Android 11+)", isOn: $captureAudio)
                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 14) {
                        labeledRow("Bit rate") { bitRatePicker }
                        labeledRow("Max FPS") { fpsPicker }
                        labeledRow("Time limit") { timeLimitPicker }
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Advanced options").font(.callout.weight(.medium))
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
            startedAt = Date()
            startPreviewPolling()
            // Lock the device/bundle pickers for the duration, as the
            // performance/network recorders do. A recording targets one device;
            // switching it mid-capture would strand this recorder (the view stays
            // mounted on a device switch, so .onDisappear never fires to abort it).
            state.recordingActive = true
            state.setExitGuard(.init(
                id: exitGuardID, style: .recording,
                title: "Recording in progress",
                message: "Leaving will stop the screen recording. Save it first, or discard it."))
            scheduleTimeLimit(options.timeLimitSeconds)
        } catch {
            state.showToast(Toast(message: error.localizedDescription, ok: false))
        }
        isStarting = false
    }

    private func pause() async {
        guard let recorder, !isBusy, !isPaused else { return }
        isBusy = true
        await recorder.pause()
        isPaused = true
        isBusy = false
    }

    private func resume() async {
        guard let recorder, !isBusy, isPaused else { return }
        isBusy = true
        do {
            try await recorder.resume()
            isPaused = false
        } catch {
            state.showToast(Toast(message: error.localizedDescription, ok: false))
        }
        isBusy = false
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
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    private func stopPreviewPolling() {
        previewTask?.cancel()
        previewTask = nil
        previewImage = nil
    }

    /// The server has no time-limit knob, so the UI stops the recording after the
    /// chosen duration (0 = unlimited). Paused time still counts toward the limit.
    private func scheduleTimeLimit(_ seconds: Int) {
        limitTask?.cancel()
        guard seconds > 0 else { return }
        limitTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled, isRecording { await stop() }
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
        isStopping = false
        startedAt = nil
        self.recorder = nil
        stopPreviewPolling()
        state.recordingActive = false
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
        state.recordingActive = false
        guard let recorder else { state.finishExitSave(); return }
        self.recorder = nil
        isRecording = false
        isPaused = false
        startedAt = nil
        stopPreviewPolling()
        do {
            let temp = try await recorder.stop()
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
