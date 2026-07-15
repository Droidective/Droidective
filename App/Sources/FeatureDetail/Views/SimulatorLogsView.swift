import ADBKit
import SwiftUI

/// Live unified-log stream for the booted iOS Simulator — Logcat's simctl
/// twin, sharing the same pane, Filter field, and ⌘F Find bar. Filter hides
/// non-matching lines; Find highlights and steps through matches without
/// hiding anything. The stream lifecycle hangs off `.task(id:)` — changing
/// the level (or simulator) cancels the old stream and starts a fresh one.
struct SimulatorLogsView: View {
    static let maxLines = 5000

    @Environment(AppState.self) private var state
    @State private var lines: [LogLine] = []
    @State private var paused = false
    @State private var level = "Default"
    /// Set from the pane's right-click "Filter by tag" — the tag is the
    /// process name here, so this narrows the feed to one app.
    @State private var processFilter: String?
    /// Debounced free-text filter, same pattern as Logcat.
    @State private var searchInput = ""
    @State private var search = ""
    /// The Find bar (⌘F): `findInput` debounces into `find`; `currentFindID`
    /// is the match being stepped to.
    @State private var findVisible = false
    @State private var findInput = ""
    @State private var find = ""
    @State private var currentFindID: UUID?
    @State private var edges = LogScrollEdges()
    @State private var jump: LogJumpRequest?
    @AppStorage("iosLogsNewestFirst") private var newestFirst = false

    /// Unlike logcat's severity floor, the unified log's level *widens* what
    /// the simulator emits: Default is the OS default; Info and Debug include
    /// the chattier levels.
    private static let levels: [(value: String, label: String)] = [
        ("Default", "Default"), ("Info", "Info"), ("Debug", "Debug"),
    ]

    private var taskKey: String {
        "\(simulatorUdid ?? "none")|\(level)"
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
        let visible = visibleLines
        let findMatches = LogLineFilter.findMatches(in: visible, query: find, newestFirst: newestFirst)
        return VStack(spacing: 0) {
            if simulatorUdid != nil {
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
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            LabeledContent("Level") {
                Picker("Level", selection: $level) {
                    ForEach(Self.levels, id: \.value) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
            .font(.app(.callout))
            .help("How much the simulator emits — Info and Debug widen the stream beyond the OS default")

            TextField("Filter lines…", text: $searchInput)
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

            Spacer()

            Button {
                findVisible = true
            } label: {
                Image(systemName: "text.magnifyingglass")
            }
            .buttonStyle(IconButtonStyle())
            .help("Find & highlight in the log without hiding lines (⌘F)")
            .keyboardShortcut("f", modifiers: .command)

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
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Find bar

    private func findBar(matches: [UUID]) -> some View {
        LogFindBar(
            text: $findInput,
            countLabel: findCountLabel(matches: matches),
            onNext: { currentFindID = LogLineFilter.advance(from: currentFindID, in: matches, forward: true) },
            onPrevious: { currentFindID = LogLineFilter.advance(from: currentFindID, in: matches, forward: false) },
            onClose: closeFind
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

    // MARK: - Status bar

    private func statusBar(visible: [LogLine]) -> some View {
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
                        Text("process: \(processFilter)")
                        Image(systemName: "xmark.circle.fill")
                    }
                    .font(.app(.caption))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.brandAccent.opacity(0.15), in: Capsule())
                .help("Remove process filter")
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
        .background(Color.bgSurface)
    }

    private var statusText: String {
        var parts: [String] = [paused ? "Paused" : "Streaming"]
        if level != "Default" {
            parts.append("\(level) level")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Log list

    private var visibleLines: [LogLine] {
        LogLineFilter.visible(lines, tag: processFilter, filter: search)
    }

    private func logList(visible: [LogLine]) -> some View {
        SelectableLogView(
            lines: visible,
            find: find,
            currentFindID: currentFindID,
            newestFirst: newestFirst,
            edges: $edges,
            jump: jump,
            onFilterTag: { processFilter = $0 }
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
        .background(.background)
        .overlay { emptyOverlay }
    }

    private func requestJump(to edge: VerticalEdge) {
        jump = LogJumpRequest(token: (jump?.token ?? 0) + 1, edge: edge)
    }

    private func export() {
        guard let file = state.askSaveLocation(
            suggestedName: "ios-logs_\(ScreenCaptureService.stamp()).txt"
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
        if simulatorUdid == nil {
            ContentUnavailableView(
                "No simulator selected", systemImage: "apple.logo",
                description: Text("Boot an iOS Simulator to stream its logs.")
            )
        } else if lines.isEmpty {
            ContentUnavailableView(
                "No log output", systemImage: "scroll",
                description: Text("Logs will appear here as the simulator emits them.")
            )
        }
    }

    // MARK: - Streaming

    /// Owned by `.task(id:)`: cancelled and restarted whenever the simulator
    /// or level changes. The outer loop survives transient stream deaths.
    private func streamLoop() async {
        lines.removeAll()
        guard let udid = simulatorUdid else { return }

        let streamer = SimulatorLogStreamer()
        defer { Task { await streamer.stop() } }

        // nil keeps the OS default level; info/debug widen it.
        let levelFlag = level == "Default" ? nil : level.lowercased()

        // Record the launched command once per level/simulator change so it
        // shows in the feature's Recent tab.
        var recordedCommand = false
        while !Task.isCancelled {
            guard let stream = try? await streamer.start(udid: udid, level: levelFlag) else { return }

            if !recordedCommand {
                recordedCommand = true
                let command = "xcrun " + SimulatorLogParser.buildArgs(udid: udid, level: levelFlag)
                    .joined(separator: " ")
                await CommandLog.userInitiated {
                    await state.env.commandLog.record(
                        command: command, exitCode: 0, duration: .zero, stdout: "", stderr: ""
                    )
                }
            }

            for await batch in stream {
                if Task.isCancelled { break }
                if paused { continue }
                lines.append(contentsOf: batch)
                if lines.count > Self.maxLines {
                    lines.removeFirst(lines.count - Self.maxLines)
                }
            }
            if Task.isCancelled { return }
            // Stream ended (simulator shut down, log hiccup) — brief backoff,
            // retry.
            try? await Task.sleep(for: .seconds(2))
        }
    }
}
