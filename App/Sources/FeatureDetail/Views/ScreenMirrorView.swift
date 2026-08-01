import ADBKit
import SwiftUI

/// Whether the mirror streams device audio. Off by default — audio costs an
/// extra socket + Core Audio graph and most mirroring is silent triage; the
/// control-bar toggle opts in (and persists).
let mirrorIncludeAudioKey = "mirrorIncludeAudio"

/// Whether the mirror turns on Android's "Show taps" dot (see `ShowTouches`),
/// drawn on the device display itself, so touches read clearly in the mirror
/// and in recordings. Off by default; a live settings write, no session
/// restart.
let mirrorShowTouchesKey = "mirrorShowTouches"

/// How long a hidden mirror keeps streaming before it's torn down. Switching
/// tabs used to stop-and-reconnect instantly, so flipping away and back — even
/// for a moment — flashed the "Connecting…" screen every time. Holding the live
/// session for this window lets a quick return resume in place; only a genuinely
/// abandoned tab pays the teardown to reclaim the video-encode CPU.
let mirrorHiddenGraceSeconds: TimeInterval = 120

/// In-app screen mirror: a native scrcpy client renders the device live, in
/// window. The toolbar takes a screenshot (→ annotate in place) or records
/// (→ video editor on stop) without interrupting the live, controllable mirror.
struct ScreenMirrorView: View {
    @Environment(AppState.self) private var state
    @Environment(\.tabFeatureID) private var tabFeatureID
    @Environment(\.tabIsActive) private var tabIsActive
    @Environment(\.openWindow) private var openWindow
    @AppStorage(mirrorIncludeAudioKey) private var includeAudio = false
    @AppStorage(mirrorShowTouchesKey) private var showTouches = false
    @State private var model: MirrorViewModel?
    /// The in-flight (re)connect, so a newer one can cancel and supersede it.
    @State private var connectTask: Task<Void, Never>?
    /// Identifies this view's leave guard so a stale clear can't wipe another's.
    @State private var exitGuardID = UUID()
    /// Delayed teardown for a hidden tab; cancelled if the tab returns in time.
    @State private var teardownTask: Task<Void, Never>?

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
                // Returned to the tab: cancel any pending teardown so a session
                // still inside its grace window resumes in place (no reconnect
                // flash). Reconnect when there's nothing to resume — torn down,
                // ended while hidden, or the device-bar selection moved on while
                // hidden (resuming then would silently mirror and control the
                // wrong device; a recording always stays on its device).
                teardownTask?.cancel()
                teardownTask = nil
                let action = MirrorTabPolicy.onReturn(
                    hasSession: model != nil,
                    isRecording: model?.isRecording == true,
                    sessionEnded: model?.hasEnded == true,
                    deviceChanged: model?.serial != state.targetSerials.first)
                if action == .reconnect { scheduleReconnect(to: state.targetSerials.first) }
            } else if MirrorTabPolicy.schedulesTeardownOnHide(isRecording: model?.isRecording == true) {
                // Hidden — keep streaming for a grace window instead of tearing
                // down instantly, so a quick tab flip doesn't stop-and-reconnect.
                // Recording sessions must keep capturing regardless.
                scheduleHiddenTeardown()
            }
        }
        .onChange(of: includeAudio) { _, include in
            // Restart the live session with the new audio choice. setAudio
            // no-ops mid-recording (the toggle is disabled then) and on a
            // stopped model; with no model, the choice applies on next connect.
            guard let model else { return }
            Task { await model.setAudio(include) }
        }
        .onChange(of: showTouches) { _, show in
            // A live settings write — no restart; with no model, the choice
            // applies on the next connect.
            guard let model else { return }
            Task { await CommandLog.userInitiated { await model.setShowTouches(show) } }
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
            teardownTask?.cancel()
            connectTask?.cancel()
            let leaving = model
            model = nil
            Task { await leaving?.stop() }
        }
    }

    /// Stop the hidden mirror after the grace window elapses, unless the tab
    /// returns first (which cancels this task). Reclaims the video-encode CPU
    /// of a mirror the user has actually left behind. Runs on the main actor,
    /// so mutating `model` here is safe.
    private func scheduleHiddenTeardown() {
        teardownTask?.cancel()
        teardownTask = Task {
            try? await Task.sleep(for: .seconds(mirrorHiddenGraceSeconds))
            guard !Task.isCancelled else { return }
            // Fired: drop the handle now (before the await) so a fresh
            // hide can't schedule a successor this stale task would clobber.
            teardownTask = nil
            connectTask?.cancel()
            let leaving = model
            model = nil
            await leaving?.stop()
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
            includeAudio: includeAudio,
            showTouches: showTouches)
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
    @AppStorage(mirrorShowTouchesKey) private var showTouches = false
    /// The recording-audio sheet: pick the combination, hear the mic, start.
    @State private var showAudioSheet = false
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
        .sheet(isPresented: $showAudioSheet) {
            RecordAudioSheet(
                start: { Task { await model.startRecording() } },
                blockedReason: recordingBlockedReason)
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

            // Outside the streaming gate: both choices also apply to the next
            // connect, so they stay flippable from the failed/stopped cards.
            optionsMenu
        }
        .fixedSize()
    }

    /// Audio and show-touches live behind one ⋯ menu in both bar layouts:
    /// session options, not per-tap controls, so neither earns an
    /// always-visible bar slot. Audio restarts the session, so it's disabled
    /// mid-recording (the restart would abort the recorder); show-touches is
    /// a live settings write on the device — flipping it *on* mid-recording
    /// is the point (touches stay legible in the captured video).
    @ViewBuilder private var optionsToggles: some View {
        Toggle("Stream audio (restarts mirror)", isOn: $includeAudio)
            .disabled(model.isRecording)
        Toggle("Show touches", isOn: $showTouches)
    }

    private var optionsMenu: some View {
        Menu {
            optionsToggles
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.app(.title3))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Audio and touch options")
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
                optionsToggles
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
            .help("Volume, audio, touch, and window options")
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
            liveAudioMenu
        } else {
            recordControl(buttonWidth: buttonWidth)
        }
    }

    /// Record, plus a chevron opening the audio sheet — set the combination,
    /// hear the microphone, and start the take from there. One control on the
    /// bar, and the options get a panel of their own instead of a row of icons
    /// or a menu that can't show what it's doing.
    private func recordControl(buttonWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            navButton("record.circle", width: buttonWidth, help: "Record — keep mirroring") {
                Task { await model.startRecording() }
            }
            Button {
                showAudioSheet = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.app(.caption2).weight(.semibold))
                    .frame(width: 16, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Recording audio — device playback or mic, plus the Mac's mic")
        }
    }

    /// Why the sheet's Start Recording can't run, or nil when it can.
    private var recordingBlockedReason: String? {
        if model.isRecording { return "A recording is already running." }
        guard model.status == .streaming else { return "The mirror isn’t streaming yet." }
        return nil
    }

    /// Mid-take the sources are fixed (the capture opened on them), so all
    /// that's left is silencing them.
    private var liveAudioMenu: some View {
        Menu {
            if let status = model.recordAudioStatus, status.mode.hasAudio {
                if status.mode.includesDevice {
                    Toggle(
                        status.deviceSource == .microphone ? "Device microphone" : "Device audio",
                        isOn: Binding(
                            get: { !status.deviceMuted },
                            set: { on in
                                Task {
                                    await model.setRecordMuted(
                                        device: !on, microphone: status.microphoneMuted)
                                }
                            }))
                }
                if status.mode.includesMicrophone {
                    Toggle("Microphone", isOn: Binding(
                        get: { !status.microphoneMuted },
                        set: { on in
                            Task {
                                await model.setRecordMuted(
                                    device: status.deviceMuted, microphone: !on)
                            }
                        }))
                }
            } else {
                Text("This recording has no audio")
            }
        } label: {
            Image(systemName: liveAudioSymbol)
                .font(.app(.title3))
                .foregroundStyle(anySourceMuted ? Color.orange : .primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Mute or unmute what's being recorded")
    }

    private var liveAudioSymbol: String {
        guard let status = model.recordAudioStatus else { return "waveform" }
        let device = status.mode.includesDevice && !status.deviceMuted
        let microphone = status.mode.includesMicrophone && !status.microphoneMuted
        if !device, !microphone { return "speaker.slash.fill" }
        return microphone ? "mic.fill" : status.deviceSource.symbolName
    }

    private var anySourceMuted: Bool {
        guard let status = model.recordAudioStatus else { return false }
        return (status.mode.includesDevice && status.deviceMuted)
            || (status.mode.includesMicrophone && status.microphoneMuted)
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

