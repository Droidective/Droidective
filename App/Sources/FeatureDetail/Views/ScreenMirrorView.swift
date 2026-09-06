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
    /// The device this mirror is pinned to, instead of following the device
    /// bar. The pop-out windows use it: one window per device, so a window that
    /// re-targeted on every click in the main window would mirror whatever was
    /// last selected rather than the device it was opened for.
    var pinnedSerial: String?

    @Environment(AppState.self) private var state
    @Environment(\.tabFeatureID) private var tabFeatureID
    @Environment(\.tabIsActive) private var tabIsActive
    @Environment(\.openWindow) private var openWindow
    @AppStorage(mirrorIncludeAudioKey) private var includeAudio = false
    @AppStorage(mirrorShowTouchesKey) private var showTouches = false
    /// Delayed teardown for a hidden tab; cancelled if the tab returns in time.
    /// The one piece of this that really is the view's: it is about the tab
    /// being hidden *here*, and a tab that moves is not hidden any more.
    @State private var teardownTask: Task<Void, Never>?
    /// The session and the two editors' state when this mirror is a *window*
    /// rather than a tab — see `editor`.
    @State private var windowMirror = MirrorTabModel()
    @State private var windowEditor = ScreenshotEditorModel()
    @State private var windowVideoEditor = VideoEditorModel()

    /// The live session, held by the window rather than by this view so a tab
    /// moving keeps the stream it already has. See `MirrorTabModel`.
    private var mirrorTab: MirrorTabModel {
        tabFeatureID == MirrorWindow.featureID
            ? windowMirror
            : state.featureState(MirrorTabModel.self, for: tabFeatureID) { MirrorTabModel() }
    }

    private var model: MirrorViewModel? {
        get { mirrorTab.session }
        nonmutating set { mirrorTab.session = newValue }
    }
    private var connectTask: Task<Void, Never>? {
        get { mirrorTab.connectTask }
        nonmutating set { mirrorTab.connectTask = newValue }
    }
    private var exitGuardID: UUID { mirrorTab.exitGuardID }

    /// Where the screenshot editor keeps the capture and its markup.
    ///
    /// A tab's editor lives in the window's `FeatureStateStore`, so annotations
    /// survive the tab moving to another window. A pop-out mirror window is not
    /// a tab: it cannot move, and it reads whichever workspace is frontmost, so
    /// a store entry would be shared with the other pop-outs and would follow
    /// the user between windows. It keeps its own instead.
    private var editor: ScreenshotEditorModel {
        tabFeatureID == MirrorWindow.featureID
            ? windowEditor
            : state.featureState(ScreenshotEditorModel.self, for: tabFeatureID) { ScreenshotEditorModel() }
    }

    /// The video editor a finished recording opens in, kept the same way.
    private var videoEditor: VideoEditorModel {
        tabFeatureID == MirrorWindow.featureID
            ? windowVideoEditor
            : state.featureState(VideoEditorModel.self, for: tabFeatureID) { VideoEditorModel() }
    }

    var body: some View {
        ZStack {
            // The editor takes the whole pane ahead of the mirror: an
            // annotation in progress is unsaved work, and a device that
            // disconnects (which drops `model`) must not take it down with it.
            if editor.image != nil {
                ScreenshotEditorView(model: editor)
            } else if let source = videoEditor.source {
                // After Edit, take over the whole pane with the editor (full
                // screen, not a sheet) so its tools are fully usable; closing
                // it returns to the live mirror.
                VideoEditorPane(source: source) {
                    try? FileManager.default.removeItem(at: source.url)
                    videoEditor.close()
                }
            } else if let model {
                MirrorStage(
                    model: model,
                    onReconnect: reconnectCurrent,
                    onPopOut: popOutAction)
            } else {
                ContentUnavailableView(
                    "Connect a device to mirror",
                    systemImage: "iphone",
                    description: Text("Plug in or pair a device, then it shows here live."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .recordingDecision(url: pendingRecording) { videoEditor.open(.recording($0)) }
        .imageDecision(image: pendingScreenshot) { editor.open($0) }
        .task {
            // Connect if the mirror is the tab on screen when it's first
            // mounted; a hidden tab connects lazily once it becomes active
            // (below). A hidden mirror is heavy video encode for nothing.
            // A tab that just moved here arrives with its session already
            // streaming, and takes neither branch.
            if tabIsActive, model == nil { scheduleReconnect(to: targetSerial) }
            // Re-publish what this window is mirroring, and re-arm a recording
            // that crossed with the tab. Neither can ride `onChange`: the new
            // window inherits nothing, and from its point of view nothing has
            // changed — only which window is asking.
            publishClaims(model?.serial)
            armRecordingGuard(model?.isRecording == true)
        }
        .onChange(of: state.targetSerials.first) { _, serial in
            // Follow the selected device: switching it re-targets the live
            // mirror — but never mid-recording, which stays on its device
            // (leaving to switch is gated by the recording exit guard). A pinned
            // mirror ignores the bar entirely.
            guard pinnedSerial == nil, tabIsActive, model?.isRecording != true else { return }
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
                    deviceChanged: model?.serial != targetSerial)
                if action == .reconnect { scheduleReconnect(to: targetSerial) }
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
        .onChange(of: model?.serial) { _, serial in
            publishClaims(serial)
        }
        .onChange(of: model?.recordingError) { _, message in
            guard let message else { return }
            state.showToast(Toast(message: message, ok: false))
            model?.recordingError = nil
        }
        .onChange(of: model?.isRecording) { _, recording in
            armRecordingGuard(recording == true)
        }
        .onChange(of: state.pendingExit?.saving) { _, saving in
            if saving == true, model?.isRecording == true, state.pendingExitConcerns(tabFeatureID) {
                Task { await saveRecordingForLeave() }
            }
        }
        .onDisappear {
            // Only this window's grace timer is cancelled. The session itself
            // stays: this also runs when the tab is merely moving, and
            // `stopBackgroundWork` is where a close and a move are told apart.
            teardownTask?.cancel()
            if tabFeatureID == MirrorWindow.featureID {
                // A pop-out window is not a tab, so this teardown is final: an
                // unsaved annotation or edit in it goes with the window, its
                // guards have to go too or nothing would ever clear them, and
                // the session has nothing left to come back to.
                state.clearExitGuard(editor.exitGuardID)
                state.clearExitGuard(videoEditor.exitGuardID)
                state.clearExitGuard(exitGuardID)
                mirrorTab.shutDown()
            }
        }
    }

    /// Publish what this mirror is actually streaming, so the Mirror Wall
    /// doesn't put a second encoder on the same device (a split pane can show
    /// both at once). Claims come from *live* sessions, which is why a merely
    /// open tab isn't enough. The pop-out windows are registered by `AppCore`
    /// instead — it holds all of them, and one write here would clobber its
    /// siblings.
    private func publishClaims(_ serial: String?) {
        guard tabFeatureID != MirrorWindow.featureID else { return }
        state.noteMirrorClaims(serial.map { [$0] } ?? [], featureID: tabFeatureID)
    }

    /// Register (or withdraw) the guard for a recording running through this
    /// mirror. It survives a move because the recording does — the session
    /// crosses with the tab and keeps writing — while closing the tab still
    /// asks, because that really does stop it.
    private func armRecordingGuard(_ recording: Bool) {
        guard recording else {
            state.clearExitGuard(exitGuardID)
            return
        }
        state.setExitGuard(.init(
            id: exitGuardID, featureID: tabFeatureID, style: .recording,
            title: "Recording in progress",
            message: "Leaving will stop the screen recording. Save it first, or discard it.",
            survivesAMove: true))
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

    /// The device this view mirrors: its pin, or the device bar's selection.
    private var targetSerial: String? { pinnedSerial ?? state.targetSerials.first }

    /// Reconnect the current device in place — the stopped/failed cards' button.
    private func reconnectCurrent() {
        scheduleReconnect(to: targetSerial)
    }

    /// Pop-out is offered only in the tab host — the window host has nowhere
    /// further to pop.
    private var popOutAction: (() -> Void)? {
        guard tabFeatureID != MirrorWindow.featureID else { return nil }
        return { popOut() }
    }

    /// Move the mirror to its own window: open (or focus) the window for *this
    /// device* — which connects its own session — and close this tab so the same
    /// device isn't encoded twice.
    private func popOut() {
        guard let serial = targetSerial else { return }
        // The windows read their adb client and toasts from whichever workspace
        // popped one out; the device rides in the window's own presented value.
        state.prepareMirrorWindow(serial: serial)
        openWindow(id: MirrorWindow.windowID, value: serial)
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
    @Environment(AppState.self) private var state
    /// A hidden keep-alive tab keeps its drop regions, and a region deeper
    /// than the window-level router wins over it — so the mirror only offers
    /// one while it is the tab on screen. See `DeviceDropTarget`.
    @Environment(\.tabIsActive) private var tabIsActive
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
            .deviceDropTarget(
                serial: model.serial, deviceName: deviceName, isActive: tabIsActive)
            .overlay(alignment: .topLeading) {
                TransferChipsView(serial: model.serial, showsHint: model.status == .streaming)
            }

            controlBar
        }
        .sheet(isPresented: $showAudioSheet) {
            RecordAudioSheet(
                start: { Task { await model.startRecording() } },
                blockedReason: recordingBlockedReason)
        }
    }

    /// The device this stage is streaming, named the way the rest of the app
    /// names it — the drop overlay says it out loud before anything lands.
    private var deviceName: String {
        state.devices.first { $0.serial == model.serial }
            .map(state.deviceDisplayName) ?? model.serial
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

