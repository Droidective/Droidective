import ADBKit
import SwiftUI

/// Live logcat stream with level/app/text filters, pause, and a capped ring
/// buffer. The whole stream lifecycle hangs off `.task(id:)` — changing any
/// filter (or device) cancels the old stream and starts a fresh one.
struct LogcatView: View {
    static let maxLines = 5000

    @Environment(AppState.self) private var state
    @State private var lines: [LogLine] = []
    @State private var paused = false
    @State private var level = "All"
    @State private var packageFilter: String?
    @State private var tagFilter: String?
    /// What the user is typing; debounced into `search` (which triggers a full
    /// re-filter and NSTextView rebuild) so a fast typist over a full buffer
    /// pays for one rebuild per pause, not one per keystroke.
    @State private var searchInput = ""
    @State private var search = ""
    @State private var waitingForPackage: String?
    @State private var streamingPid: Int?
    /// One-shot: the App filter is seeded from the device bar's chosen bundle
    /// the first time the view appears, then left to the user.
    @State private var seededPackageFilter = false
    /// Mirrors the log pane's edge/scrollability state; drives the jump buttons.
    @State private var edges = LogScrollEdges()
    /// Set by the jump buttons to ask the pane to snap to an edge.
    @State private var jump: LogJumpRequest?
    /// Reversed feed: newest lines at the top instead of the terminal-style
    /// newest-at-bottom. Persisted per feature.
    @AppStorage("logcatNewestFirst") private var newestFirst = false

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
        return VStack(spacing: 0) {
            // With no device there's nothing to filter, pause, export, or clear —
            // hide the toolbar and status strip and let the empty state below
            // carry the "connect a device" message.
            if !state.targetSerials.isEmpty {
                toolbar
                Divider()
                statusBar(visible: visible)
                Divider()
            }
            logList(visible: visible)
        }
        .task(id: taskKey) { await streamLoop() }
        // Open pre-filtered to the bundle chosen in the device bar (changeable
        // from the App picker), and follow when that choice changes later.
        .onAppear {
            guard !seededPackageFilter else { return }
            seededPackageFilter = true
            if let bundle = state.selectedBundle { packageFilter = bundle.packageId }
        }
        .onChange(of: state.selectedBundleId) { _, _ in
            packageFilter = state.selectedBundle?.packageId
        }
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

            LabeledContent("App") {
                Picker("App", selection: $packageFilter) {
                    Text("All apps").tag(String?.none)
                    ForEach(state.bundles) { bundle in
                        Text(bundle.nickname).tag(Optional(bundle.packageId))
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            .font(.app(.callout))

            TextField("Search lines…", text: $searchInput)
                .brandField()
                .frame(maxWidth: 220)
                .task(id: searchInput) {
                    if !search.isEmpty || !searchInput.isEmpty {
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                    guard !Task.isCancelled else { return }
                    search = searchInput
                }

            Spacer()

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
        .background(Color.bgSurface)
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
        // Lowercase the query once and match the per-line cached `searchKey` —
        // this runs on every streamed batch, and a locale-aware scan over a
        // full 5000-line buffer was the hottest part of searching while
        // streaming.
        let query = search.lowercased()
        return lines.filter { line in
            if let tagFilter, line.tag != tagFilter { return false }
            if !query.isEmpty && !line.searchKey.contains(query) { return false }
            return true
        }
    }

    private func logList(visible: [LogLine]) -> some View {
        // An NSTextView-backed pane: real cross-line selection with drag
        // autoscroll (the SwiftUI list trapped selection inside each row).
        // It follows new lines while parked at the bottom and pauses the
        // moment the user scrolls up; the shared jump controls overlay it.
        SelectableLogView(
            lines: visible,
            search: search,
            newestFirst: newestFirst,
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
        .background(.background)
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

    /// Owned by `.task(id:)`: cancelled and restarted whenever the device,
    /// level, or app filter changes. Outer loop survives app restarts (pid
    /// changes) and transient stream deaths.
    private func streamLoop() async {
        lines.removeAll()
        waitingForPackage = nil
        streamingPid = nil
        guard let serial = state.targetSerials.first else { return }

        let streamer = LogcatStreamer(client: state.env.client)
        defer {
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

            let filters = LogcatFilters(level: level == "All" ? nil : level, pid: pid)
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
                if paused { continue }
                lines.append(contentsOf: batch)
                if lines.count > Self.maxLines {
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
