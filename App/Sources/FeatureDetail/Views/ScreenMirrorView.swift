import ADBKit
import SwiftUI

/// Whether the mirror streams device audio. Off by default — audio costs an
/// extra socket + Core Audio graph and most mirroring is silent triage; the
/// control-bar toggle opts in (and persists).
let mirrorIncludeAudioKey = "mirrorIncludeAudio"

/// In-app screen mirror: a native scrcpy client renders the device live, in
/// window. The toolbar takes a screenshot (→ annotate in place) or records
/// (→ video editor on stop) without interrupting the live, controllable mirror.
struct ScreenMirrorView: View {
    @Environment(AppState.self) private var state
    @Environment(\.tabFeatureID) private var tabFeatureID
    @Environment(\.tabIsActive) private var tabIsActive
    @Environment(\.openWindow) private var openWindow
    @AppStorage(mirrorIncludeAudioKey) private var includeAudio = false
    @State private var model: MirrorViewModel?
    /// The in-flight (re)connect, so a newer one can cancel and supersede it.
    @State private var connectTask: Task<Void, Never>?
    /// Identifies this view's leave guard so a stale clear can't wipe another's.
    @State private var exitGuardID = UUID()

    var body: some View {
        ZStack {
            if let model {
                // After Edit, take over the whole pane with the editor (full
                // screen, not a sheet) so its tools are fully usable; closing it
                // returns to the live mirror.
                if let url = model.finishedRecording {
                    VideoEditorPane(source: .recording(url)) {
                        try? FileManager.default.removeItem(at: url)
                        model.finishedRecording = nil
                    }
                    .id(url)
                } else if let image = model.editingScreenshot {
                    ScreenshotEditorView(image: image) { model.editingScreenshot = nil }
                } else {
                    MirrorStage(
                        model: model,
                        onReconnect: reconnectCurrent,
                        onPopOut: popOutAction)
                }
            } else {
                ContentUnavailableView(
                    "Connect a device to mirror",
                    systemImage: "iphone",
                    description: Text("Plug in or pair a device, then it shows here live."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .recordingDecision(url: pendingRecording) { url in model?.finishedRecording = url }
        .imageDecision(image: pendingScreenshot) { image in model?.editingScreenshot = image }
        .task {
            // Connect if the mirror is the tab on screen when it's first
            // mounted; a hidden tab connects lazily once it becomes active
            // (below). A hidden mirror is heavy video encode for nothing.
            if tabIsActive, model == nil { scheduleReconnect(to: state.targetSerials.first) }
        }
        .onChange(of: state.targetSerials.first) { _, serial in
            // Follow the selected device: switching it re-targets the live
            // mirror — but never mid-recording, which stays on its device
            // (leaving to switch is gated by the recording exit guard).
            guard tabIsActive, model?.isRecording != true else { return }
            scheduleReconnect(to: serial)
        }
        .onChange(of: tabIsActive) { _, active in
            if active {
                if model == nil { scheduleReconnect(to: state.targetSerials.first) }
            } else if model?.isRecording != true {
                // Pause the live mirror while hidden — unless it's recording,
                // which must keep capturing.
                connectTask?.cancel()
                let leaving = model
                model = nil
                Task { await leaving?.stop() }
            }
        }
        .onChange(of: includeAudio) { _, include in
            // Restart the live session with the new audio choice. setAudio
            // no-ops mid-recording (the toggle is disabled then) and on a
            // stopped model; with no model, the choice applies on next connect.
            guard let model else { return }
            Task { await model.setAudio(include) }
        }
        .onChange(of: model?.recordingError) { _, message in
            guard let message else { return }
            state.showToast(Toast(message: message, ok: false))
            model?.recordingError = nil
        }
        .onChange(of: model?.isRecording) { _, recording in
            if recording == true {
                state.setExitGuard(.init(
                    id: exitGuardID, featureID: tabFeatureID, style: .recording,
                    title: "Recording in progress",
                    message: "Leaving will stop the screen recording. Save it first, or discard it."))
            } else {
                state.clearExitGuard(exitGuardID)
            }
        }
        .onChange(of: state.pendingExit?.saving) { _, saving in
            if saving == true, model?.isRecording == true, state.pendingExitConcerns(tabFeatureID) {
                Task { await saveRecordingForLeave() }
            }
        }
        .onDisappear {
            state.clearExitGuard(exitGuardID)
            connectTask?.cancel()
            let leaving = model
            model = nil
            Task { await leaving?.stop() }
        }
    }

    /// "Stop & save" from the leave prompt: finalize the in-mirror recording into
    /// the capture folder (skipping the Discard/Save/Edit sheet), then proceed.
    private func saveRecordingForLeave() async {
        guard let model else { state.finishExitSave(); return }
        if let temp = await model.finishRecordingForLeave() {
            state.confirmCaptureFolderOnce()
            do {
                let dir = try ScreenCaptureService.ensureCaptureDir()
                let dest = dir.appendingPathComponent("recording_\(ScreenCaptureService.stamp()).mp4")
                try FileManager.default.moveItem(at: temp, to: dest)
                state.showToast(Toast(message: "Recording saved", ok: true, revealPath: dest.path))
            } catch {
                state.showToast(Toast(message: "Couldn’t save recording: \(error.localizedDescription)", ok: false))
            }
        }
        state.finishExitSave()
    }

    /// Reconnect the selected device in place — the stopped/failed cards' button.
    private func reconnectCurrent() {
        scheduleReconnect(to: state.targetSerials.first)
    }

    /// Pop-out is offered only in the tab host — the window host has nowhere
    /// further to pop.
    private var popOutAction: (() -> Void)? {
        guard tabFeatureID != MirrorWindow.featureID else { return nil }
        return { popOut() }
    }

    /// Move the mirror to its own window: open (or focus) the mirror window —
    /// which connects its own session to the selected device — and close this
    /// tab so the same device isn't encoded twice.
    private func popOut() {
        openWindow(id: MirrorWindow.windowID)
        state.closeTab(tabFeatureID)
    }

    /// Serialize (re)connects: cancel the in-flight one and chain the new one
    /// behind its teardown, so rapid device switches can't interleave two
    /// connects or leave an orphaned session streaming in the background.
    private func scheduleReconnect(to serial: String?) {
        let previous = connectTask
        previous?.cancel()
        connectTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await reconnect(to: serial)
        }
    }

    private func reconnect(to serial: String?) async {
        if let existing = model {
            model = nil
            await existing.stop()
        }
        guard let serial, !Task.isCancelled else { return }
        let viewModel = MirrorViewModel(
            adb: state.env.engine.client,
            locator: state.env.engine.locator,
            serial: serial,
            includeAudio: includeAudio)
        model = viewModel
        await viewModel.start()
    }

    private var pendingRecording: Binding<URL?> {
        Binding(get: { model?.pendingRecording }, set: { model?.pendingRecording = $0 })
    }

    private var pendingScreenshot: Binding<NSImage?> {
        Binding(get: { model?.pendingScreenshot }, set: { model?.pendingScreenshot = $0 })
    }
}

private struct MirrorStage: View {
    @Bindable var model: MirrorViewModel
    @AppStorage(mirrorIncludeAudioKey) private var includeAudio = false
    /// Reconnect the current device in place (the stopped/failed cards' button).
    let onReconnect: () -> Void
    /// Move the mirror to its own window; nil when already hosted in one.
    let onPopOut: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                MirrorVideoView(
                    renderer: model.renderer,
                    videoSize: model.videoSize,
                    onTouch: { action, point in model.touch(action, at: point) },
                    onKeycode: { keycode, action in model.key(keycode, action) },
                    onText: { model.text($0) },
                    onPaste: { model.pasteToDevice() },
                    onCopy: { model.copyFromDevice(cut: false) },
                    onCut: { model.copyFromDevice(cut: true) })

                switch model.status {
                case .connecting:
                    ProgressView("Connecting…").controlSize(.large).tint(.white)
                case let .failed(message):
                    statusCard(icon: "exclamationmark.triangle", text: message, retry: true)
                case .stopped:
                    statusCard(icon: "stop.circle", text: "Mirror stopped.", retry: true)
                case .streaming:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            controlBar
        }
    }

    /// Controls below the mirror: device nav keys, then screenshot + record.
    /// The bar adapts to the pane instead of overflowing into the pane clip
    /// (which hid its trailing buttons in a narrow split): full layout, then
    /// tighter spacing, then a compact bar that folds volume / audio / pop-out
    /// into an overflow menu.
    private var controlBar: some View {
        ViewThatFits(in: .horizontal) {
            fullBar(spacing: 16, buttonWidth: 44)
            fullBar(spacing: 6, buttonWidth: 34)
            compactBar
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func fullBar(spacing: CGFloat, buttonWidth: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Group {
                navCluster(buttonWidth: buttonWidth)

                Divider().frame(height: 22)

                captureCluster(buttonWidth: buttonWidth)

                Divider().frame(height: 22)

                // Device volume (one step per tap) + one-shot mute/unmute.
                navButton("speaker.wave.1.fill", width: buttonWidth, help: "Volume down") { model.tapKey(25) }
                navButton("speaker.wave.3.fill", width: buttonWidth, help: "Volume up") { model.tapKey(24) }
                navButton("speaker.slash.fill", width: buttonWidth, help: "Mute / unmute") { model.tapKey(164) }

                // Pop out to a window — hidden while recording, which must stay
                // with this session (the window would connect a fresh one).
                if let onPopOut, !model.isRecording {
                    Divider().frame(height: 22)
                    navButton("macwindow.on.rectangle", width: buttonWidth, help: "Open in a separate window") { onPopOut() }
                }
            }
            .disabled(model.status != .streaming)

            Divider().frame(height: 22)

            // Outside the streaming gate: the audio choice also applies to the
            // next connect, so it stays flippable from the failed/stopped cards.
            // Disabled mid-recording — the restart would abort the recorder.
            Toggle("Audio", isOn: $includeAudio)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Stream device audio — flipping this restarts the mirror")
                .disabled(model.isRecording)
        }
        .fixedSize()
    }

    /// The narrow-pane bar: nav / screenshot / record stay one-tap buttons,
    /// the rest moves into an overflow menu with the same per-item gating.
    private var compactBar: some View {
        HStack(spacing: 6) {
            Group {
                navCluster(buttonWidth: 34)
                Divider().frame(height: 22)
                captureCluster(buttonWidth: 34)
            }
            .disabled(model.status != .streaming)

            Divider().frame(height: 22)

            Menu {
                Section("Volume") {
                    // Same order as the full bar: down, up, mute.
                    Button("Volume down") { model.tapKey(25) }
                    Button("Volume up") { model.tapKey(24) }
                    Button("Mute / unmute") { model.tapKey(164) }
                }
                .disabled(model.status != .streaming)
                Divider()
                Toggle("Stream audio (restarts mirror)", isOn: $includeAudio)
                    .disabled(model.isRecording)
                if let onPopOut, !model.isRecording {
                    Divider()
                    Button("Open in a separate window") { onPopOut() }
                        .disabled(model.status != .streaming)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.app(.title3))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Volume, audio, and window options")
        }
        .fixedSize()
    }

    private func navCluster(buttonWidth: CGFloat) -> some View {
        Group {
            navButton("chevron.backward", width: buttonWidth, help: "Back") { model.tapKey(4) }
            navButton("circle", width: buttonWidth, help: "Home") { model.tapKey(3) }
            navButton("square", width: buttonWidth, help: "Recent apps") { model.tapKey(187) }
        }
    }

    @ViewBuilder private func captureCluster(buttonWidth: CGFloat) -> some View {
        navButton("camera", width: buttonWidth, help: "Screenshot — edit in place") {
            Task { await model.takeScreenshot() }
        }

        if model.isRecording {
            navButton(
                model.isPaused ? "play.fill" : "pause.fill",
                width: buttonWidth,
                help: model.isPaused ? "Resume recording" : "Pause recording"
            ) {
                Task { model.isPaused ? await model.resumeRecording() : await model.pauseRecording() }
            }
            navButton("stop.circle.fill", tint: .red, width: buttonWidth, help: "Stop recording") {
                Task { await model.stopRecording() }
            }
        } else {
            navButton("record.circle", width: buttonWidth, help: "Record — keep mirroring") {
                Task { await model.startRecording() }
            }
        }
    }

    private func navButton(
        _ systemImage: String, tint: Color? = nil, width: CGFloat = 44, help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.app(.title3))
                .foregroundStyle(tint ?? .primary)
                .frame(width: width, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func statusCard(icon: String, text: String, retry: Bool = false) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.app(size: 34))
            Text(text).multilineTextAlignment(.center)
            if retry {
                Button("Reconnect") { onReconnect() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
}

