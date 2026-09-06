import ADBKit
import AppKit
import SwiftUI

/// Live unified-log stream for the booted iOS Simulator, built around how
/// that log actually behaves: unfiltered it is the whole OS (thousands of
/// lines a second), so the stream is scoped to installed apps by default and
/// the feed *freezes while you're in scrollback* — new lines accumulate
/// behind a "N new" pill instead of yanking the view. Rows are structured
/// unified-log entries (process, subsystem · category, level) rather than
/// flat text.
struct SimulatorLogsView: View {
    static let maxLines = 5000

    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    /// The frozen, rendered buffer. Only mutated while following the tail —
    /// scrollback reads a stable list.
    /// The buffer and its filters, kept per window so they survive this view
    /// being rebuilt — see `SimulatorLogsModel`.
    private var model: SimulatorLogsModel {
        state.featureState(SimulatorLogsModel.self, for: "ios-logs") { SimulatorLogsModel() }
    }
    private var lines: [SimLogLine] {
        get { model.lines }
        nonmutating set { model.lines = newValue }
    }
    /// Batches received while frozen (scrolled up) wait here.
    @State private var pending: [SimLogLine] = []
    /// True once `pending` overflowed and dropped its oldest lines.
    @State private var pendingOverflowed = false
    private var paused: Bool {
        get { model.paused }
        nonmutating set { model.paused = newValue }
    }
    /// What the simulator emits: installed apps only, or the whole OS.
    @AppStorage("iosLogsScope") private var scopeRaw = SimulatorLogScope.apps.rawValue
    /// Which levels the feed *shows*; checking Info/Debug also widens what
    /// the simulator emits (a stream restart).
    private var shownLevels: Set<SimLogLevel> {
        get { model.shownLevels }
        nonmutating set { model.shownLevels = newValue }
    }
    /// Right-click / Process-menu pick; narrows the feed to one process.
    private var processFilter: String? {
        get { model.processFilter }
        nonmutating set { model.processFilter = newValue }
    }
    /// Free-text filter, debounced from `searchInput` into `search`.
    private var searchInput: String {
        get { model.searchInput }
        nonmutating set { model.searchInput = newValue }
    }
    private var search: String {
        get { model.search }
        nonmutating set { model.search = newValue }
    }
    /// Whether this tab is the one on screen. The stream keeps running while
    /// it isn't — only the flushing slows down (`FeedFlushCadence`), because a
    /// mounted hidden tab lays out every row it is handed.
    @Environment(\.tabIsActive) private var tabIsActive
    /// The same answer, in `@State` so the streaming loop can read it *live*:
    /// `.task` captures the view value it started with, and an `@Environment`
    /// read through that capture is frozen at that moment (see `LogcatView`).
    @State private var feedVisible = true
    /// The live streamer, held so visibility changes can re-pace its flushing
    /// without restarting the stream (a restart would clear the feed).
    @State private var streamer: SimulatorLogStreamer?
    /// Xcode's console Metadata toggle: the time · process · subsystem line
    /// under each message.
    @AppStorage("iosLogsShowMetadata") private var showMetadata = true
    /// The Find bar (⌘F): highlights matches without hiding lines.
    @State private var findVisible = false
    @State private var findInput = ""
    @State private var find = ""
    @State private var currentFindID: UUID?
    @State private var findFocusToken = 0
    /// The row parked at the viewport's bottom edge. Written to pin the tail;
    /// read back to detect the user returning to it.
    @State private var scrolledID: UUID?
    /// The freeze/follow switch. Scrolling up (a real wheel/trackpad event —
    /// not a layout read-back, which lags programmatic pins under load) sets
    /// it false; the pill, reaching the tail, or a filter change set it back.
    @State private var followsTail = true
    /// The last few visible row ids when the tail was last pinned — read-backs
    /// landing here mean the user scrolled back down to the tail.
    @State private var tailIDs: [UUID] = []
    @State private var wheelMonitor: Any?

    private var scope: SimulatorLogScope {
        SimulatorLogScope(rawValue: scopeRaw) ?? .apps
    }

    /// The emission floor the stream asks for, derived from the level menu —
    /// part of `taskKey`, so widening restarts the stream.
    private var emitLevel: String? {
        if shownLevels.contains(.debug) { return "debug" }
        if shownLevels.contains(.info) { return "info" }
        return nil
    }

    private var taskKey: String {
        "\(simulatorUdid ?? "none")|\(scopeRaw)|\(emitLevel ?? "notice")"
    }

    /// The selected device's UDID, only when it is an iOS Simulator — an
    /// Android selection is handled upstream by `PlatformUnsupportedView`.
    private var simulatorUdid: String? {
        guard let serial = state.targetSerials.first,
              let device = state.devices.first(where: { $0.serial == serial }),
              device.platform == .iosSimulator else { return nil }
        return serial
    }

    var body: some View {
        let visible = SimulatorLogFilter.visible(
            lines, levels: shownLevels, process: processFilter, filter: search)
        let findMatches = SimulatorLogFilter.findMatches(in: visible, query: find)
        return VStack(spacing: 0) {
            if simulatorUdid != nil {
                toolbar
                Divider()
                if findVisible {
                    findBar(matches: findMatches)
                    Divider()
                }
            }
            feed(visible: visible, findMatches: findMatches)
            if simulatorUdid != nil {
                Divider()
                statusBar(visible: visible)
            }
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
        .onAppear { feedVisible = tabIsActive }
        // A changed filter re-tails the feed — the frozen position loses its
        // meaning when the row set changes.
        .onChange(of: "\(shownLevels.hashValue)|\(processFilter ?? "")|\(search)") { _, _ in
            followsTail = true
            applyPending()
        }
        // Resume when the user scrolls back down to the tail on their own.
        .onChange(of: scrolledID) { _, id in
            guard !followsTail, let id, tailIDs.contains(id) else { return }
            followsTail = true
            applyPending()
        }
        .onAppear(perform: installWheelMonitor)
        .onDisappear(perform: removeWheelMonitor)
    }

    /// Scrolling up is the freeze signal. A local event monitor sees the real
    /// gesture the moment it happens — the `scrollPosition` read-back can't
    /// be trusted for this, because it also fires (late, and pointing at
    /// stale rows) for our own programmatic pins while batches land.
    private func installWheelMonitor() {
        guard wheelMonitor == nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated {
                if event.scrollingDeltaY > 0.5 { followsTail = false }
            }
            return event
        }
    }

    private func removeWheelMonitor() {
        if let wheelMonitor {
            NSEvent.removeMonitor(wheelMonitor)
        }
        wheelMonitor = nil
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Scope", selection: $scopeRaw) {
                ForEach(SimulatorLogScope.allCases, id: \.rawValue) { scope in
                    Text(scope.label).tag(scope.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("My apps streams only installed apps' processes — Everything is the entire simulator OS, thousands of lines a second")

            levelsMenu
            processMenu

            TextField("Filter…", text: Binding(get: { model.searchInput }, set: { model.searchInput = $0 }))
                .brandField()
                .frame(maxWidth: 200)
                .help("Show only lines whose process, subsystem, category, or message contains this text")
                .task(id: searchInput) {
                    if !search.isEmpty || !searchInput.isEmpty {
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                    guard !Task.isCancelled else { return }
                    search = searchInput
                }

            Spacer()

            Button {
                showMetadata.toggle()
            } label: {
                Image(systemName: showMetadata ? "tag.fill" : "tag")
            }
            .buttonStyle(IconButtonStyle())
            .help(showMetadata
                ? "Hide the metadata line (time · process · subsystem) under each message"
                : "Show the metadata line under each message")

            Button {
                findVisible = true
                findFocusToken += 1
            } label: {
                Image(systemName: "text.magnifyingglass")
            }
            .buttonStyle(IconButtonStyle())
            .help("Find & highlight in the log without hiding lines (⌘F)")
            // Active-tab only — a hidden keep-alive tab winning ⌘F opens an
            // invisible find bar and the focus request falls through to the
            // sidebar search.
            .keyboardShortcut(isActiveTab ? KeyboardShortcut("f", modifiers: .command) : nil)

            Button {
                paused.toggle()
            } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(IconButtonStyle())
            .help(paused ? "Resume (new lines are dropped while paused)" : "Pause the stream")

            Button {
                export(visible: SimulatorLogFilter.visible(
                    lines, levels: shownLevels, process: processFilter, filter: search))
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(IconButtonStyle())
            .help("Export the shown lines to ~/Downloads/Droidective")
            .disabled(lines.isEmpty)

            Button {
                lines.removeAll()
                pending.removeAll()
                pendingOverflowed = false
                currentFindID = nil
                scrolledID = nil
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(IconButtonStyle())
            .help("Clear")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    /// Multi-select level menu; Info/Debug widen what the simulator emits.
    private var levelsMenu: some View {
        Menu {
            ForEach(SimLogLevel.allCases.reversed(), id: \.self) { level in
                Toggle(level.label, isOn: Binding(
                    get: { shownLevels.contains(level) },
                    set: { shown in
                        if shown { shownLevels.insert(level) } else { shownLevels.remove(level) }
                        // An empty set shows nothing forever — keep one on.
                        if shownLevels.isEmpty { shownLevels = [level] }
                    }
                ))
            }
        } label: {
            Text(levelsLabel)
        }
        .fixedSize()
        .help("Which levels to show — Info and Debug also widen what the simulator emits")
    }

    private var levelsLabel: String {
        switch shownLevels {
        case Set(SimLogLevel.allCases): return "All levels"
        case [.notice, .error, .fault]: return "Notice & up"
        case [.error, .fault]: return "Errors only"
        case [.fault]: return "Faults only"
        default: return "Levels (\(shownLevels.count))"
        }
    }

    /// Self-populating from the stream: the processes seen in the buffer,
    /// busiest first.
    private var processMenu: some View {
        Menu {
            Button {
                processFilter = nil
            } label: {
                if processFilter == nil {
                    Label("All processes", systemImage: "checkmark")
                } else {
                    Text("All processes")
                }
            }
            let counts = SimulatorLogFilter.processCounts(lines).prefix(20)
            if !counts.isEmpty {
                Divider()
            }
            ForEach(counts, id: \.name) { entry in
                Button {
                    processFilter = entry.name
                } label: {
                    if processFilter == entry.name {
                        Label("\(entry.name)  —  \(entry.count)", systemImage: "checkmark")
                    } else {
                        Text("\(entry.name)  —  \(entry.count)")
                    }
                }
            }
        } label: {
            Text(processFilter ?? "All processes")
                .lineLimit(1)
        }
        .frame(maxWidth: 180)
        .fixedSize(horizontal: true, vertical: false)
        .help("Narrow the feed to one process — right-click a line for the same")
    }

    // MARK: - Find bar

    private var isActiveTab: Bool { state.activeTabID == "ios-logs" }

    private func findBar(matches: [UUID]) -> some View {
        LogFindBar(
            text: $findInput,
            countLabel: findCountLabel(matches: matches),
            onNext: { stepFind(in: matches, forward: true) },
            onPrevious: { stepFind(in: matches, forward: false) },
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
        .onChange(of: find) { _, _ in currentFindID = nil }
    }

    private func stepFind(in matches: [UUID], forward: Bool) {
        currentFindID = LogLineFilter.advance(from: currentFindID, in: matches, forward: forward)
        // Jumping to a match parks it at the viewport edge; the feed freezes
        // there naturally until the user returns to the tail.
        if let currentFindID {
            scrolledID = currentFindID
        }
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

    // MARK: - Feed

    private func feed(visible: [SimLogLine], findMatches: [UUID]) -> some View {
        let matchSet = Set(findMatches)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visible) { line in
                    SimLogRow(
                        line: line,
                        showMetadata: showMetadata,
                        isFindMatch: !find.isEmpty && matchSet.contains(line.id),
                        isCurrentFind: line.id == currentFindID,
                        onFilterProcess: { processFilter = $0 },
                        onCopyLine: { copyToPasteboard($0) }
                    )
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrolledID, anchor: .bottom)
        .translucentFeedBackground()
        .overlay(alignment: .bottom) {
            if !followsTail && !visible.isEmpty {
                newLinesPill
            }
        }
        .overlay { emptyOverlay(visible: visible) }
    }

    private var newLinesPill: some View {
        Button {
            followsTail = true
            applyPending()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                Text(pending.isEmpty
                    ? "Latest"
                    : "\(pendingOverflowed ? "\(pending.count)+" : "\(pending.count)") new")
            }
            .font(.app(.caption))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.brandAccent, in: Capsule())
            .foregroundStyle(Color.brandAccent.contrastingForeground(for: colorScheme))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
        .help("Jump back to the live tail")
    }

    /// Fold the waiting lines into the rendered buffer and pin to the tail.
    private func applyPending() {
        if !pending.isEmpty {
            lines.append(contentsOf: pending)
            pending.removeAll()
            pendingOverflowed = false
            if lines.count > Self.maxLines {
                lines.removeFirst(lines.count - Self.maxLines)
            }
        }
        let visible = SimulatorLogFilter.visible(
            lines, levels: shownLevels, process: processFilter, filter: search)
        tailIDs = visible.suffix(6).map(\.id)
        scrolledID = visible.last?.id
    }

    @ViewBuilder
    private func emptyOverlay(visible: [SimLogLine]) -> some View {
        if simulatorUdid == nil {
            ContentUnavailableView(
                "No simulator selected", systemImage: "apple.logo",
                description: Text("Boot an iOS Simulator to stream its logs.")
            )
        } else if lines.isEmpty && pending.isEmpty {
            ContentUnavailableView(
                "No log output", systemImage: "scroll",
                description: Text(scope == .apps
                    ? "Waiting for your apps to log — launch an app in the simulator, or switch the scope to Everything for system logs."
                    : "Logs will appear here as the simulator emits them.")
            )
        } else if visible.isEmpty {
            ContentUnavailableView(
                "Nothing matches the filters", systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Loosen the level, process, or text filter to see the buffered lines.")
            )
        }
    }

    // MARK: - Status bar

    private func statusBar(visible: [SimLogLine]) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(paused ? Color.yellow : .brandAccent)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
            if let processFilter {
                Button {
                    self.processFilter = nil
                } label: {
                    HStack(spacing: 3) {
                        Text(processFilter)
                        Image(systemName: "xmark.circle.fill")
                    }
                    .font(.app(.caption))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.brandAccent.opacity(0.15), in: Capsule())
                .help("Remove the process filter")
            }
            severityChips
            Spacer()
            Text(countText(visible: visible))
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bgSurface)
    }

    private var statusText: String {
        var parts = [paused ? "Paused" : "Streaming"]
        parts.append(scope.label)
        if levelsLabel != "Notice & up" { parts.append(levelsLabel) }
        return parts.joined(separator: " · ")
    }

    /// Live error/fault tallies over the whole buffer (level filter ignored,
    /// so they never read zero just because errors are filtered out) — click
    /// to flip the level menu to Errors only and back.
    @ViewBuilder private var severityChips: some View {
        let errors = lines.count { $0.level == .error }
        let faults = lines.count { $0.level == .fault }
        if errors + faults > 0 {
            Button {
                shownLevels = shownLevels == [.error, .fault]
                    ? [.notice, .error, .fault]
                    : [.error, .fault]
            } label: {
                HStack(spacing: 6) {
                    if faults > 0 {
                        Label("\(faults)", systemImage: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                    if errors > 0 {
                        Label("\(errors)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.app(.caption))
                .monospacedDigit()
            }
            .buttonStyle(.plain)
            .help(shownLevels == [.error, .fault]
                ? "Show all levels again"
                : "Show only the errors and faults")
        }
    }

    private func countText(visible: [SimLogLine]) -> String {
        let shown = visible.count == lines.count
            ? "\(lines.count) lines"
            : "\(visible.count) of \(lines.count) lines"
        return pending.isEmpty ? shown : "\(shown) · \(pending.count) waiting"
    }

    // MARK: - Actions

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func export(visible: [SimLogLine]) {
        guard let file = state.askSaveLocation(
            suggestedName: "ios-logs_\(ScreenCaptureService.stamp()).txt"
        ) else { return }
        let content = visible.map(\.exportText).joined(separator: "\n")
        do {
            try Data(content.utf8).write(to: file)
            state.showToast(Toast(message: "Exported \(visible.count) lines", ok: true, revealPath: file.path))
        } catch {
            state.showToast(Toast(message: "Export failed: \(error.localizedDescription)", ok: false))
        }
    }

    // MARK: - Streaming

    /// Owned by `.task(id:)`: cancelled and restarted whenever the simulator,
    /// scope, or emission level changes. The outer loop survives transient
    /// stream deaths.
    /// How often the streamer should hand this view a batch: the shared feed
    /// rule, given whether anyone can see the tab and how far behind the main
    /// thread already is (`SimulatorLogStreamer.setFlushInterval`).
    private var pacedFlushInterval: Duration {
        FeedFlushCadence.interval(
            appActive: NSApp.isActive,
            watched: feedVisible,
            lateness: MainThreadLoad.shared.lateness)
    }

    private func streamLoop() async {
        // Only when the *question* changed: `.task(id:)` also restarts this on
        // a plain rebuild, which is what moving the tab does, and clearing
        // there would make a move indistinguishable from a restart.
        if model.bufferKey != taskKey {
            lines.removeAll()
            model.bufferKey = taskKey
        }
        pending.removeAll()
        pendingOverflowed = false
        scrolledID = nil
        guard let udid = simulatorUdid else { return }

        let streamer = SimulatorLogStreamer()
        self.streamer = streamer
        await streamer.setFlushInterval(pacedFlushInterval)
        defer {
            self.streamer = nil
            Task { await streamer.stop() }
        }

        let scope = scope
        let emit = emitLevel

        // Record the launched command once per restart key so it shows in
        // the feature's Recent tab.
        var recordedCommand = false
        while !Task.isCancelled {
            guard let stream = try? await streamer.start(udid: udid, scope: scope, emit: emit)
            else { return }

            if !recordedCommand {
                recordedCommand = true
                let command = "xcrun " + SimulatorLogParser
                    .buildArgs(udid: udid, scope: scope, emit: emit)
                    .joined(separator: " ")
                await CommandLog.userInitiated {
                    await state.env.commandLog.record(
                        command: command, exitCode: 0, duration: .zero, stdout: "", stderr: ""
                    )
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
                absorb(batch)
            }
            if Task.isCancelled { return }
            // Stream ended (simulator shut down, log hiccup) — brief backoff,
            // retry.
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// New lines land in `pending`; the rendered list moves only while the
    /// user is at the tail. Frozen scrollback stays put — that's what makes
    /// the feed scrollable under load.
    private func absorb(_ batch: [SimLogLine]) {
        pending.append(contentsOf: batch)
        if pending.count > Self.maxLines {
            pending.removeFirst(pending.count - Self.maxLines)
            pendingOverflowed = true
        }
        if followsTail {
            applyPending()
        }
    }
}

/// One unified-log entry, Xcode-console style: the message leads, with a
/// muted metadata line (time · process(pid) · subsystem · category) beneath
/// it — toggleable, like Xcode's Metadata switch — a severity color bar on
/// the left, and error/fault rows tinted like Xcode's.
private struct SimLogRow: View {
    let line: SimLogLine
    let showMetadata: Bool
    let isFindMatch: Bool
    let isCurrentFind: Bool
    let onFilterProcess: (String) -> Void
    let onCopyLine: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(levelColor)
                .frame(width: 3)
                .padding(.vertical, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.level <= .info ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showMetadata {
                    HStack(spacing: 8) {
                        Text(line.time)
                            .monospacedDigit()
                        Text(processLabel)
                            .fontWeight(.medium)
                        if line.level >= .error {
                            Text(line.level.label)
                                .fontWeight(.semibold)
                                .foregroundStyle(levelColor)
                        }
                        if !line.subsystem.isEmpty {
                            Text(line.category.isEmpty
                                ? line.subsystem
                                : "\(line.subsystem) · \(line.category)")
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, showMetadata ? 3 : 1)
        .background(rowBackground)
        .contextMenu {
            Button("Copy Message") { onCopyLine(line.message) }
            Button("Copy Line") { onCopyLine(line.exportText) }
            if !line.process.isEmpty {
                Divider()
                Button("Filter by \u{201C}\(line.process)\u{201D}") { onFilterProcess(line.process) }
            }
        }
    }

    private var processLabel: String {
        if line.process.isEmpty { return "—" }
        return line.pid.isEmpty ? line.process : "\(line.process) (\(line.pid))"
    }

    private var levelColor: Color {
        switch line.level {
        case .fault: return .red
        case .error: return .orange
        case .notice: return .secondary.opacity(0.5)
        case .info: return .secondary.opacity(0.3)
        case .debug: return .secondary.opacity(0.2)
        }
    }

    private var rowBackground: Color {
        if isCurrentFind { return .orange.opacity(0.28) }
        if isFindMatch { return .yellow.opacity(0.12) }
        if line.level == .fault { return .red.opacity(0.07) }
        if line.level == .error { return .yellow.opacity(0.05) }
        return .clear
    }
}
