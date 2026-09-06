import ADBKit
import AppKit
import SwiftUI

/// Live logcat stream with level/app/text filters, a ⌘F Find bar, pause, and
/// a capped ring buffer. Filter hides non-matching lines; Find highlights
/// matches and steps between them without hiding anything. The whole stream
/// lifecycle hangs off `.task(id:)` — changing any filter (or device) cancels
/// the old stream and starts a fresh one.
struct LogcatView: View {
    static let maxLines = 5000

    @Environment(AppState.self) private var state

    /// The buffer and its filters, held per window by `FeatureStateStore` so
    /// they survive this view being rebuilt — which is what a tab moving to the
    /// other pane, or to another window, does. Resolved per render rather than
    /// stored: the store is a plain dictionary, not observable, so resolving
    /// from `body` writes nothing that could invalidate the read (see
    /// `FeatureStateStore`); the *model* is observable, so reading through it
    /// tracks changes normally.
    private var model: LogcatModel {
        state.featureState(LogcatModel.self, for: "logcat") { LogcatModel() }
    }

    // Accessors, so the buffer's many use sites read exactly as they did when
    // these were `@State`. `nonmutating set` because the storage is the model,
    // not the view.
    private var lines: [LogLine] {
        get { model.lines }
        nonmutating set { model.lines = newValue }
    }
    private var paused: Bool {
        get { model.paused }
        nonmutating set { model.paused = newValue }
    }
    private var level: String {
        get { model.level }
        nonmutating set { model.level = newValue }
    }
    private var packageFilter: String? {
        get { model.packageFilter }
        nonmutating set { model.packageFilter = newValue }
    }
    private var tagFilter: String? {
        get { model.tagFilter }
        nonmutating set { model.tagFilter = newValue }
    }
    /// What the user is typing; debounced into `search` (which triggers a full
    /// re-filter and NSTextView rebuild) so a fast typist over a full buffer
    /// pays for one rebuild per pause, not one per keystroke.
    private var searchInput: String {
        get { model.searchInput }
        nonmutating set { model.searchInput = newValue }
    }
    private var search: String {
        get { model.search }
        nonmutating set { model.search = newValue }
    }
    /// Measured toolbar width — below ~560pt (a narrow split pane) the
    /// toolbar reflows to two rows instead of clipping.
    @State private var toolbarWidth: CGFloat = 0
    /// The Find bar (⌘F): `findInput` debounces into `find` the same way the
    /// filter does; `currentFindID` is the match being stepped to.
    @State private var findVisible = false
    @State private var findInput = ""
    @State private var find = ""
    @State private var currentFindID: UUID?
    @State private var findFocusToken = 0
    @State private var waitingForPackage: String?
    @State private var streamingPid: Int?
    /// pid → process name (a periodic `ps` snapshot) for the process column.
    private var processNames: [String: String] {
        get { model.processNames }
        nonmutating set { model.processNames = newValue }
    }
    /// The live streamer, held so visibility changes can re-pace its flushing
    /// without restarting the stream (a restart would clear the feed).
    @State private var streamer: LogcatStreamer?
    /// Whether this tab is the one on screen. The stream keeps running while
    /// it isn't — only the flushing slows down (`FeedFlushCadence`), because a
    /// mounted hidden tab lays out every row it is handed.
    @Environment(\.tabIsActive) private var tabIsActive
    /// The same answer, in `@State` so the streaming loop can read it *live*.
    /// `.task` captures the view value it started with, and an `@Environment`
    /// read through that capture keeps returning the value from then — so the
    /// loop would re-pace itself back to the visible interval on the next
    /// batch and undo the tab switch. `@State` is reference-backed and reads
    /// current.
    @State private var feedVisible = true
    /// One-shot: the App filter is seeded from the device bar's chosen bundle
    /// the first time the view appears, then left to the user.
    private var seededPackageFilter: Bool {
        get { model.seededPackageFilter }
        nonmutating set { model.seededPackageFilter = newValue }
    }
    /// Mirrors the log pane's edge/scrollability state; drives the jump buttons.
    @State private var edges = LogScrollEdges()
    /// Set by the jump buttons to ask the pane to snap to an edge.
    @State private var jump: LogJumpRequest?
    /// The App menu's add flows — the same sheets the device bar's bundle
    /// pill offers elsewhere (the pill is hidden on logcat; this menu is the
    /// one place to pick the app here).
    @State private var showInstalledApps = false
    @State private var showBundleManager = false
    /// Reversed feed: newest lines at the top instead of the terminal-style
    /// newest-at-bottom. Persisted per feature.
    @AppStorage("logcatNewestFirst") private var newestFirst = false
    /// Show the leading time column. Hiding it buys the message ~20 columns
    /// in narrow panes. Persisted per feature.
    @AppStorage("logcatShowTime") private var showTime = true

    private static let levels: [(value: String, label: String)] = [
        ("All", "All levels"), ("V", "Verbose"), ("D", "Debug"),
        ("I", "Info"), ("W", "Warning"), ("E", "Error"), ("F", "Fatal"),
    ]

    private var taskKey: String {
        "\(state.targetSerials.first ?? "none")|\(level)|\(packageFilter ?? "all")"
    }

    var body: some View {
        // Filter once per render — the status count and the list share it,
        // instead of each re-scanning the full buffer while searching.
        let visible = visibleLines
        let findMatches = LogLineFilter.findMatches(in: visible, query: find, newestFirst: newestFirst)
        return VStack(spacing: 0) {
            // With no device there's nothing to filter, pause, export, or clear —
            // hide the toolbar and status strip and let the empty state below
            // carry the "connect a device" message.
            if !state.targetSerials.isEmpty {
                toolbar
                Divider()
                if findVisible {
                    findBar(matches: findMatches)
                    Divider()
                }
                statusBar(visible: visible)
                Divider()
            }
            logList(visible: visible)
        }
        .task(id: taskKey) { await streamLoop() }
        // Re-pace on a tab switch rather than re-keying the stream: a restart
        // would clear the feed. Becoming visible also flushes at once, so the
        // reveal doesn't wait out the hidden interval.
        .onChange(of: tabIsActive) { _, visible in
            feedVisible = visible
            let interval = pacedFlushInterval
            Task { @MainActor in
                await streamer?.setFlushInterval(interval)
                if visible { await streamer?.flushNow() }
            }
        }
        // Open pre-filtered to the bundle chosen in the device bar (changeable
        // from the App picker), and follow when that choice changes later.
        .onAppear {
            feedVisible = tabIsActive
            guard !seededPackageFilter else { return }
            seededPackageFilter = true
            if let bundle = state.selectedBundle { packageFilter = bundle.packageId }
        }
        .onChange(of: state.selectedBundleId) { _, _ in
            packageFilter = state.selectedBundle?.packageId
        }
        .sheet(isPresented: $showInstalledApps) {
            InstalledAppsPickerView()
        }
        .sheet(isPresented: $showBundleManager) {
            BundleManagerView()
        }
    }

    // MARK: - Toolbar

    /// One row when it fits; in a narrow split pane the pickers and the
    /// filter/actions split into two rows instead of clipping at the pane
    /// edge. Width is measured (not ViewThatFits — the flexible filter field
    /// reports a tiny ideal width, which would always "fit").
    private var toolbar: some View {
        Group {
            if toolbarWidth > 0, toolbarWidth < 560 {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        levelPicker
                        appPicker
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 12) {
                        filterField
                        Spacer(minLength: 0)
                        actionButtons
                    }
                }
            } else {
                HStack(spacing: 12) {
                    levelPicker
                    appPicker
                    filterField
                    Spacer()
                    actionButtons
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .measuringWidth(into: $toolbarWidth)
    }

    // Plain label + picker pairs: LabeledContent is a form-row control that
    // soaks up toolbar width as a label↔content gap.
    private var levelPicker: some View {
        HStack(spacing: 6) {
            Text("Level")
            Picker("Level", selection: Binding(
                get: { model.level }, set: { model.level = $0 })) {
                ForEach(Self.levels, id: \.value) { item in
                    Text(item.label).tag(item.value)
                }
            }
            .labelsHidden()
            // No fixed width: the pop-up centers inside a wider frame,
            // which reads as a gap after the label.
            .fixedSize()
        }
        .font(.app(.callout))
    }

    private var appPicker: some View {
        HStack(spacing: 6) {
            Text("App")
            appMenu
        }
        .font(.app(.callout))
    }

    private var filterField: some View {
        TextField("Filter lines…", text: Binding(
            get: { model.searchInput }, set: { model.searchInput = $0 }))
            .brandField()
            .frame(maxWidth: 220)
            .help("Show only the lines containing this text")
            .task(id: searchInput) {
                if !search.isEmpty || !searchInput.isEmpty {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                guard !Task.isCancelled else { return }
                search = searchInput
            }
    }

    @ViewBuilder private var actionButtons: some View {
        Button {
            findVisible = true
            findFocusToken += 1
        } label: {
            Image(systemName: "text.magnifyingglass")
        }
        .buttonStyle(IconButtonStyle())
        .help("Find & highlight in the log without hiding lines (⌘F)")
        // Registered only while this is the focused pane's tab —
        // keep-alive hidden tabs stay mounted, and a hidden tab winning
        // ⌘F opens an invisible find bar whose focus request lands on the
        // sidebar search.
        .keyboardShortcut(isActiveTab ? KeyboardShortcut("f", modifiers: .command) : nil)

        Button {
            showTime.toggle()
        } label: {
            Image(systemName: showTime ? "clock" : "clock.badge.xmark")
        }
        .buttonStyle(IconButtonStyle())
        .help(showTime ? "Hide the time column" : "Show the time column")

        Button {
            newestFirst.toggle()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .buttonStyle(IconButtonStyle())
        .help(newestFirst
            ? "Newest at top — click to show newest at bottom"
            : "Newest at bottom — click to show newest at top")

        Button {
            paused.toggle()
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(IconButtonStyle())
        .help(paused ? "Resume (new lines are dropped while paused)" : "Pause")

        Button {
            export()
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(IconButtonStyle())
        .help("Export buffer to ~/Downloads/Droidective")
        .disabled(lines.isEmpty)

        Button {
            lines.removeAll()
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(IconButtonStyle())
        .help("Clear")
    }

    // MARK: - Find bar

    private var isActiveTab: Bool { state.activeTabID == "logcat" }

    private func findBar(matches: [UUID]) -> some View {
        LogFindBar(
            text: $findInput,
            countLabel: findCountLabel(matches: matches),
            onNext: { currentFindID = LogLineFilter.advance(from: currentFindID, in: matches, forward: true) },
            onPrevious: { currentFindID = LogLineFilter.advance(from: currentFindID, in: matches, forward: false) },
            onClose: closeFind,
            focusToken: findFocusToken,
            shortcutsActive: isActiveTab
        )
        .task(id: findInput) {
            if !find.isEmpty || !findInput.isEmpty {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled else { return }
            find = findInput
        }
        // A new query starts stepping fresh — the old current match likely
        // isn't a match anymore.
        .onChange(of: find) { _, _ in currentFindID = nil }
    }

    private func findCountLabel(matches: [UUID]) -> String? {
        guard !find.isEmpty else { return nil }
        guard !matches.isEmpty else { return "No matches" }
        if let current = currentFindID, let index = matches.firstIndex(of: current) {
            return "\(index + 1) of \(matches.count)"
        }
        return "\(matches.count) \(matches.count == 1 ? "match" : "matches")"
    }

    private func closeFind() {
        findVisible = false
        findInput = ""
        find = ""
        currentFindID = nil
    }

    /// The app filter with the bundle pill's full powers (pick a saved
    /// bundle, add from the device's installed apps, grab the on-screen app,
    /// manage) — the device bar hides its bundle pill on logcat so there is
    /// exactly one app selector. The add flows select the bundle globally;
    /// `.onChange(of: state.selectedBundleId)` folds that back into the
    /// stream filter.
    private var appMenu: some View {
        Menu {
            Button {
                packageFilter = nil
            } label: {
                if packageFilter == nil {
                    Label("All apps", systemImage: "checkmark")
                } else {
                    Text("All apps")
                }
            }
            ForEach(state.bundles) { bundle in
                Button {
                    packageFilter = bundle.packageId
                } label: {
                    if packageFilter == bundle.packageId {
                        Label(bundle.nickname, systemImage: "checkmark")
                    } else {
                        Text(bundle.nickname)
                    }
                }
            }
            Divider()
            Button {
                showInstalledApps = true
            } label: {
                Label("Add from installed apps", systemImage: "plus.app")
            }
            .disabled(state.targetSerials.isEmpty)
            Button {
                state.adoptForegroundApp()
            } label: {
                Label("Use app on device screen", systemImage: "scope")
            }
            .disabled(state.targetSerials.isEmpty)
            Button {
                showBundleManager = true
            } label: {
                Label("Add manually / manage…", systemImage: "slider.horizontal.3")
            }
        } label: {
            // The cap lives on the label: Menu is flexible and would center
            // its pill inside any frame put on the Menu itself, which reads
            // as a gap after the "App" label. Text hugs short names and
            // truncates long ones.
            Text(packageFilter.map(bundleName) ?? "All apps")
                .lineLimit(1)
                .frame(maxWidth: 160)
        }
        .fixedSize()
        .help("Stream one app's logs — pick a saved bundle or add a new one")
    }

    /// One line of truth about what the stream is actually doing.
    private func statusBar(visible: [LogLine]) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
            if let tagFilter {
                Button {
                    self.tagFilter = nil
                } label: {
                    HStack(spacing: 3) {
                        Text("tag: \(tagFilter)")
                        Image(systemName: "xmark.circle.fill")
                    }
                    .font(.app(.caption))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.brandAccent.opacity(0.15), in: Capsule())
                .help("Remove tag filter")
            }
            Spacer()
            if !search.isEmpty {
                Text("\(visible.count) of \(lines.count) lines match")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            } else {
                Text("\(lines.count) lines")
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bgSurface)
    }

    private var statusColor: Color {
        if state.targetSerials.isEmpty { return .textMuted }
        if waitingForPackage != nil { return .orange }
        return paused ? .yellow : .brandAccent
    }

    private var statusText: String {
        if state.targetSerials.isEmpty { return "No device connected" }
        if let waiting = waitingForPackage {
            return "Waiting for \(bundleName(waiting)) to launch — open it on the device"
        }
        var parts: [String] = [paused ? "Paused" : "Streaming"]
        if level != "All" {
            parts.append("\(Self.levels.first { $0.value == level }?.label ?? level) and above")
        }
        if let packageFilter {
            let pid = streamingPid.map { " (pid \($0))" } ?? ""
            parts.append("\(bundleName(packageFilter))\(pid)")
        }
        return parts.joined(separator: " · ")
    }

    private func bundleName(_ packageId: String) -> String {
        state.bundles.first { $0.packageId == packageId }?.nickname ?? packageId
    }

    // MARK: - Log list

    private var visibleLines: [LogLine] {
        LogLineFilter.visible(lines, tag: tagFilter, filter: search)
    }

    private func logList(visible: [LogLine]) -> some View {
        // An NSTextView-backed pane: real cross-line selection with drag
        // autoscroll (the SwiftUI list trapped selection inside each row).
        // It follows new lines while parked at the bottom and pauses the
        // moment the user scrolls up; the shared jump controls overlay it.
        SelectableLogView(
            lines: visible,
            find: find,
            currentFindID: currentFindID,
            newestFirst: newestFirst,
            showTime: showTime,
            edges: $edges,
            jump: jump,
            onFilterTag: { tagFilter = $0 }
        )
        .overlay {
            LogJumpControls(
                edges: edges,
                enabled: !visible.isEmpty,
                newestEdge: newestFirst ? .top : .bottom,
                onJumpToTop: { requestJump(to: .top) },
                onJumpToBottom: { requestJump(to: .bottom) }
            )
        }
        .translucentFeedBackground()
        .overlay { emptyOverlay }
    }

    private func requestJump(to edge: VerticalEdge) {
        jump = LogJumpRequest(token: (jump?.token ?? 0) + 1, edge: edge)
    }

    private func export() {
        guard let file = state.askSaveLocation(
            suggestedName: "logcat_\(ScreenCaptureService.stamp()).txt"
        ) else { return }
        let content = visibleLines.map(\.raw).joined(separator: "\n")
        do {
            try Data(content.utf8).write(to: file)
            state.showToast(Toast(message: "Exported \(visibleLines.count) lines", ok: true, revealPath: file.path))
        } catch {
            state.showToast(Toast(message: "Export failed: \(error.localizedDescription)", ok: false))
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if state.targetSerials.isEmpty {
            ContentUnavailableView(
                "No device connected", systemImage: "iphone.slash",
                description: Text("Connect a device to stream logs.")
            )
        } else if let waiting = waitingForPackage, lines.isEmpty {
            ContentUnavailableView(
                "\(bundleName(waiting)) isn't running", systemImage: "app.dashed",
                description: Text("Open the app on the device — streaming starts automatically.")
            )
        } else if lines.isEmpty {
            ContentUnavailableView(
                "No log output", systemImage: "scroll",
                description: Text("Logs will appear here as the device emits them.")
            )
        }
    }

    // MARK: - Streaming

    /// How often the streamer should hand this view a batch: the shared feed
    /// rule, given whether anyone can see the tab and how far behind the main
    /// thread already is. Logcat used to run a flat 300 ms in every state —
    /// the streamer is a portable actor that can see neither, so the App layer
    /// has to tell it (`LogcatStreamer.setFlushInterval`).
    private var pacedFlushInterval: Duration {
        FeedFlushCadence.interval(
            appActive: NSApp.isActive,
            watched: feedVisible,
            lateness: MainThreadLoad.shared.lateness)
    }

    /// Owned by `.task(id:)`: cancelled and restarted whenever the device,
    /// level, or app filter changes. Outer loop survives app restarts (pid
    /// changes) and transient stream deaths.
    private func streamLoop() async {
        // Clear only when the *question* changed. `.task(id:)` also restarts
        // this loop when the view is simply rebuilt — which is what moving the
        // tab to another window or pane does — and dropping the buffer there
        // would make a move indistinguishable from a restart.
        // `.task(id:)` also restarts this loop when the view is merely rebuilt —
        // which is what moving the tab to another window or pane does. Clearing
        // there would make a move indistinguishable from a restart, so the
        // buffer is only dropped when the *question* changed.
        let keepingBuffer = model.bufferKey == taskKey && !lines.isEmpty
        if !keepingBuffer {
            lines.removeAll()
            model.bufferKey = taskKey
        }
        waitingForPackage = nil
        streamingPid = nil
        guard let serial = state.targetSerials.first else { return }

        let streamer = LogcatStreamer(client: state.env.client)
        self.streamer = streamer
        // Every exit from this loop drops the reference, so a tab switch can't
        // re-pace a streamer that has already stopped.
        defer { self.streamer = nil }
        await streamer.setFlushInterval(pacedFlushInterval)
        // The process-name column: a ps snapshot up front so the initial tail
        // is named, then refreshed on a slow cadence for processes that spawn
        // mid-stream. Background polling — deliberately not CommandLog-wrapped.
        processNames = await streamer.processNames(serial: serial)
        let nameRefresher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                let refreshed = await streamer.processNames(serial: serial)
                // A transient ps failure comes back empty — keep the last good
                // map rather than blanking the process column for a cycle.
                if !Task.isCancelled, !refreshed.isEmpty { processNames = refreshed }
            }
        }
        defer {
            nameRefresher.cancel()
            Task { await streamer.stop() }
            waitingForPackage = nil
            streamingPid = nil
        }

        // Record the launched logcat command once per filter/device change so
        // it shows in the feature's Recent tab; the pid polling stays out.
        var recordedCommand = false
        while !Task.isCancelled {
            // An app filter means *that app's* logs: if it isn't running,
            // wait for it instead of silently streaming everything.
            var pid: Int?
            if let packageId = packageFilter {
                while !Task.isCancelled {
                    pid = try? await streamer.resolvePid(serial: serial, packageId: packageId)
                    if pid != nil { break }
                    waitingForPackage = packageId
                    try? await Task.sleep(for: .seconds(2))
                }
                waitingForPackage = nil
                if Task.isCancelled { return }
                streamingPid = pid
            }

            // No replay when the buffer is being kept: `adb logcat -T n` opens
            // by reprinting the device's last n lines, which are already held,
            // so a moved tab would show its recent history twice. Starting at
            // the live edge instead costs only the lines emitted during the
            // restart itself — milliseconds, and the trade "buffers, not stream
            // continuity" already accepts.
            let filters = LogcatFilters(
                tail: keepingBuffer ? 0 : LogcatFilters().tail,
                level: level == "All" ? nil : level, pid: pid)
            guard let stream = try? await streamer.start(serial: serial, filters: filters) else { return }

            if !recordedCommand {
                recordedCommand = true
                let command = "adb " + LogcatLineParser.buildArgs(serial: serial, filters: filters).joined(separator: " ")
                await CommandLog.userInitiated {
                    await state.env.commandLog.record(
                        command: command, exitCode: 0, duration: .zero, stdout: "", stderr: ""
                    )
                }
            }

            // `logcat --pid` goes silent forever if the app dies or relaunches
            // with a new pid — watch for that and stop the streamer, which
            // ends the consumption loop and re-enters the wait above.
            var pidWatcher: Task<Void, Never>?
            if let packageId = packageFilter, let activePid = pid {
                pidWatcher = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(3))
                        let current = try? await streamer.resolvePid(serial: serial, packageId: packageId)
                        if current != activePid {
                            await streamer.stop()
                            break
                        }
                    }
                }
            }

            for await batch in stream {
                if Task.isCancelled { break }
                // Re-paced per batch, which is the same cadence the other
                // feeds re-evaluate at — visibility and main-thread load both
                // move while a stream is running.
                await streamer.setFlushInterval(pacedFlushInterval)
                if Task.isCancelled { break }
                if paused { continue }
                // Stamp each line's process name at ingest — rendered rows are
                // immutable, so resolving lazily at render would never fill in.
                lines.append(contentsOf: batch.map { line in
                    var stamped = line
                    stamped.processName = processNames[line.pid]
                    return stamped
                })
                // Hysteresis: once at the cap, trimming exactly per batch
                // meant a head-trim text edit every flush (~120ms). Letting
                // the buffer float a little above the cap turns that into one
                // chunked trim per ~250 lines.
                if lines.count > Self.maxLines + 250 {
                    lines.removeFirst(lines.count - Self.maxLines)
                }
            }
            pidWatcher?.cancel()
            streamingPid = nil
            if Task.isCancelled { return }
            // Unfiltered stream ended (adb hiccup) — brief backoff, retry.
            if packageFilter == nil {
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
