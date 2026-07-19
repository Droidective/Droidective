import ADBKit
import AppKit
import SwiftUI

/// Crash browser: every crash in the device's crash buffer (with a
/// main-buffer fallback), split into a filterable list with a highlighted
/// trace, live watch, and Slack/Jira-formatted copy.
struct CrashView: View {
    @Environment(AppState.self) private var state
    @State private var reports: [CrashReport] = []
    @State private var selectedID: CrashReport.ID?
    @State private var loading = false
    @State private var fetched = false
    /// The last fetch errored (adb missing, device dropped mid-read). Cleared
    /// by the next successful fetch; drives the error empty state so a failed
    /// read never masquerades as "still checking" or "no crashes".
    @State private var fetchFailed = false
    @State private var watching = false
    @State private var kindFilter: CrashReport.Kind?
    @State private var processFilter: String?
    @State private var searchInput = ""
    @State private var search = ""
    @State private var showRaw = false
    @State private var confirmClear = false
    /// Hide crashes at or before this timestamp on this serial — set by Clear
    /// buffer, which empties the crash buffer but can't touch the main-buffer
    /// fallback the same crashes would resurface from. Scoped to the serial it
    /// was set on so a device switch never hides another device's crashes.
    /// Logcat timestamps carry no year, so the lexicographic compare mis-hides
    /// only across a Dec→Jan rollover, and only until the view reopens.
    @State private var clearedBefore: (serial: String, mark: String)?
    @State private var refreshToken = 0
    /// Measured pane width — below ~700pt (a narrow split pane) the toolbar
    /// reflows to two rows and the crash list narrows proportionally.
    @State private var paneWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if state.targetSerials.isEmpty {
                NoDeviceView("Connect a device to catch crashes.")
            } else if visibleReports.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    crashList
                    Divider()
                    detail
                }
            }
        }
        .measuringWidth(into: $paneWidth)
        .task(id: "\(state.targetSerials.first ?? "")|\(refreshToken)") {
            await fetch(userInitiated: refreshToken > 0)
        }
        .task(id: "\(watching)|\(state.targetSerials.first ?? "")") {
            guard watching else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await fetch(userInitiated: false)
            }
        }
        .onChange(of: "\(kindFilter?.rawValue ?? "")|\(processFilter ?? "")|\(search)") {
            // Keep something selected when a filter change hides the
            // current selection.
            if selectedReport == nil { selectedID = filteredReports.first?.id }
        }
        .confirmationDialog(
            "Clear the device's crash buffer?", isPresented: $confirmClear
        ) {
            Button("Clear Buffer", role: .destructive) {
                Task { await clearBuffer() }
            }
        } message: {
            Text(
                "Removes every recorded crash from the device (logcat -c -b crash). This can't be undone."
            )
        }
    }

    // MARK: - Toolbar

    /// One row when it fits; in a narrow split pane the fetch/filter controls
    /// and the search/actions split into two rows instead of clipping at the
    /// pane edge (the measured-reflow pattern — see `MeasuredWidth.swift`).
    private var toolbar: some View {
        Group {
            if paneWidth > 0, paneWidth < 700 {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        refreshButton
                        watchToggle
                        kindPicker
                        processPicker
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 12) {
                        filterField
                        Spacer(minLength: 0)
                        selectionActions
                        clearButton
                    }
                }
            } else {
                HStack(spacing: 12) {
                    refreshButton
                    watchToggle
                    kindPicker
                    processPicker
                    filterField
                    Spacer()
                    selectionActions
                    clearButton
                }
            }
        }
        .padding(8)
    }

    private var refreshButton: some View {
        Button {
            refreshToken += 1
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(IconButtonStyle())
        .disabled(loading || state.targetSerials.isEmpty)
        .help("Fetch crashes from the device")
    }

    private var watchToggle: some View {
        Toggle(isOn: $watching) {
            Label(watching ? "Watching" : "Watch",
                  systemImage: watching ? "eye.fill" : "eye")
        }
        .toggleStyle(.button)
        .disabled(state.targetSerials.isEmpty)
        .help(watching
            ? "Watching — checking for new crashes every 5 s. Click to stop."
            : "Watch for new crashes — checks every 5 s and raises a toast when one lands")
    }

    // A plain label + picker pair: LabeledContent is a form-row control that
    // soaks up toolbar width as a label↔content gap.
    private var kindPicker: some View {
        HStack(spacing: 6) {
            Text("Kind")
            Picker("Kind", selection: $kindFilter) {
                Text("All").tag(CrashReport.Kind?.none)
                ForEach(presentKinds, id: \.self) { kind in
                    Text(kind.label).tag(CrashReport.Kind?.some(kind))
                }
            }
            .labelsHidden()
            // No fixed width: the pop-up centers inside a wider frame,
            // which reads as a gap after the label.
            .fixedSize()
        }
        .font(.app(.callout))
    }

    @ViewBuilder private var processPicker: some View {
        if processes.count > 1 {
            HStack(spacing: 6) {
                Text("Process")
                Picker("Process", selection: $processFilter) {
                    Text("All").tag(String?.none)
                    ForEach(processes, id: \.self) { process in
                        Text(process).tag(String?.some(process))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }
            .font(.app(.callout))
        }
    }

    private var filterField: some View {
        TextField("Filter crashes…", text: $searchInput)
            .brandField()
            .frame(maxWidth: 180)
            .help("Show only crashes containing this text")
            .task(id: searchInput) {
                if !search.isEmpty || !searchInput.isEmpty {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                guard !Task.isCancelled else { return }
                search = searchInput
            }
    }

    @ViewBuilder private var selectionActions: some View {
        if let report = selectedReport {
            Menu {
                ForEach(CrashFormat.allCases, id: \.self) { format in
                    Button(copyLabel(for: format)) { copy(report, as: format) }
                }
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .fixedSize()
            .help("Copy this crash for pasting into Slack, Jira, or anywhere")

            Button {
                save(report)
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(IconButtonStyle())
            .help("Save this crash to a file")
        }
    }

    private var clearButton: some View {
        Button {
            confirmClear = true
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(IconButtonStyle())
        .disabled(state.targetSerials.isEmpty)
        .help("Clear the device's crash buffer")
    }

    // MARK: - List

    /// 300pt when the pane affords it; proportional in a narrow split pane so
    /// the detail keeps a usable share instead of being crushed to a sliver.
    private var listWidth: CGFloat {
        guard paneWidth > 0 else { return 300 }
        return min(300, max(180, paneWidth * 0.38))
    }

    private var crashList: some View {
        List(selection: $selectedID) {
            ForEach(filteredReports) { report in
                CrashRow(report: report)
                    .tag(report.id)
            }
        }
        .translucentListBackground()
        .frame(width: listWidth)
        .overlay {
            if filteredReports.isEmpty {
                if search.isEmpty {
                    // Hidden by the Kind/Process pickers, not a search — the
                    // search-styled "No results for ''" would read as broken.
                    ContentUnavailableView(
                        "No matching crashes",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Adjust the Kind or Process filter.")
                    )
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        if let report = selectedReport {
            VStack(spacing: 0) {
                detailHeader(report)
                Divider()
                // Vertical-only: long lines wrap. A two-axis ScrollView
                // proposes nil in both directions, so short content floats
                // centered instead of pinning to the top-left.
                ScrollView {
                    // Equatable: the highlight pass over a 200-line trace is
                    // skipped when watch polls / hovers re-render the view
                    // with the same text.
                    CrashTraceText(text: showRaw ? report.raw : report.body)
                        .equatable()
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView(
                "Select a crash", systemImage: "sidebar.left",
                description: Text("Pick a crash from the list to inspect its trace.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ report: CrashReport) -> some View {
        HStack(spacing: 10) {
            Label(report.kind.label, systemImage: report.kind.icon)
                .font(.app(.caption).weight(.semibold))
                .foregroundStyle(report.kind.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(report.kind.tint.opacity(0.12), in: Capsule())
            if let process = report.process {
                Text(process).font(.app(.caption, design: .monospaced))
            }
            if let pid = report.pid {
                Text("PID \(String(pid))")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            if let timestamp = report.timestamp {
                Text(timestamp)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Raw log", isOn: $showRaw)
                .toggleStyle(.checkbox)
                .font(.app(.caption))
                .help("Show the original logcat lines instead of just the messages")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var emptyState: some View {
        Group {
            if fetchFailed {
                ContentUnavailableView {
                    Label("Couldn't read crashes", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Reading the device's crash buffer failed. Check the connection, then refresh.")
                } actions: {
                    Button("Try Again") { refreshToken += 1 }
                }
            } else if fetched {
                ContentUnavailableView {
                    Label("No crashes detected", systemImage: "checkmark.shield")
                } description: {
                    Text("The crash buffer is clean. Turn on Watch to be told when something crashes.")
                }
            } else {
                ContentUnavailableView {
                    Label("Checking…", systemImage: "checkmark.shield")
                } description: {
                    Text("Reading the device's crash buffer…")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private var visibleReports: [CrashReport] {
        guard let clearedBefore, clearedBefore.serial == state.targetSerials.first else {
            return reports
        }
        return reports.filter { report in
            // A report without a timestamp can't be compared against the
            // mark — keep it visible; resurfacing a cleared crash beats
            // silently hiding a new one.
            guard let timestamp = report.timestamp else { return true }
            return timestamp > clearedBefore.mark
        }
    }

    private var filteredReports: [CrashReport] {
        visibleReports.filter { report in
            if let kindFilter, report.kind != kindFilter { return false }
            if let processFilter, report.process != processFilter { return false }
            if !search.isEmpty,
               !report.title.localizedCaseInsensitiveContains(search),
               !report.raw.localizedCaseInsensitiveContains(search),
               report.process?.localizedCaseInsensitiveContains(search) != true {
                return false
            }
            return true
        }
    }

    private var presentKinds: [CrashReport.Kind] {
        CrashReport.Kind.allCases.filter { kind in visibleReports.contains { $0.kind == kind } }
    }

    private var processes: [String] {
        Array(Set(visibleReports.compactMap(\.process))).sorted()
    }

    private var selectedReport: CrashReport? {
        filteredReports.first { $0.id == selectedID }
    }

    private func fetch(userInitiated: Bool) async {
        guard let serial = state.targetSerials.first else {
            reports = []
            fetched = false
            fetchFailed = false
            return
        }
        if userInitiated { loading = true }
        defer { if userInitiated { loading = false } }
        let result: [CrashReport]?
        if userInitiated {
            result = await CommandLog.userInitiated {
                try? await state.env.engine.crash.crashes(serial: serial)
            }
        } else {
            // Background polling stays out of the Command Log.
            result = try? await state.env.engine.crash.crashes(serial: serial)
        }
        guard !Task.isCancelled else { return }
        guard let result else {
            // Keep the last good list on a transient poll failure, but say so —
            // a swallowed error read as "still checking" forever.
            fetchFailed = true
            if userInitiated {
                state.showToast(Toast(message: "Couldn't read crashes from the device", ok: false))
            }
            return
        }
        fetchFailed = false
        if watching, fetched {
            let known = Set(reports.map(\.id))
            if let newest = result.first(where: { !known.contains($0.id) }) {
                state.showToast(Toast(message: "New crash: \(newest.title)", ok: false))
            }
        }
        // Watch polls mostly return an identical list — skip the state write
        // so the List isn't re-diffed and the trace re-rendered every 5 s.
        if result != reports { reports = result }
        fetched = true
        if selectedID == nil || !result.contains(where: { $0.id == selectedID }) {
            selectedID = filteredReports.first?.id
        }
        if let kind = kindFilter, !presentKinds.contains(kind) { kindFilter = nil }
        if let process = processFilter, !processes.contains(process) { processFilter = nil }
    }

    private func clearBuffer() async {
        guard let serial = state.targetSerials.first else { return }
        let cleared = await CommandLog.userInitiated {
            (try? await state.env.engine.crash.clearCrashBuffer(serial: serial)) != nil
        }
        guard cleared else {
            state.showToast(Toast(message: "Couldn't clear the crash buffer", ok: false))
            return
        }
        if let mark = reports.compactMap(\.timestamp).max() {
            clearedBefore = (serial: serial, mark: mark)
        }
        selectedID = nil
        state.showToast(Toast(message: "Crash buffer cleared", ok: true))
        refreshToken += 1
    }

    // MARK: - Actions

    private func copyLabel(for format: CrashFormat) -> String {
        switch format {
        case .plain: return "Plain text"
        case .slack: return "Slack code block"
        case .jira: return "Jira code block"
        }
    }

    private func copy(_ report: CrashReport, as format: CrashFormat) {
        let text = CrashExtractor.format(showRaw ? report.raw : report.body, as: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        state.showToast(Toast(message: "Crash copied", ok: true))
    }

    private func save(_ report: CrashReport) {
        let stamp = (report.timestamp ?? "crash").replacingOccurrences(of: ":", with: ".")
            .replacingOccurrences(of: " ", with: "_")
        guard let url = state.askSaveLocation(suggestedName: "crash-\(stamp).txt") else { return }
        do {
            try report.raw.write(to: url, atomically: true, encoding: .utf8)
            state.showToast(Toast(message: "Crash saved", ok: true, revealPath: url.path))
        } catch {
            state.showToast(
                Toast(message: "Couldn't save: \(error.localizedDescription)", ok: false))
        }
    }

    // MARK: - Highlighting

    /// Per-line trace highlighting: marker lines red, "Caused by:" orange,
    /// stack frames dimmed — so the exception reads at a glance.
    static func highlighted(_ text: String) -> AttributedString {
        var out = AttributedString()
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            var attributed = AttributedString(line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("FATAL EXCEPTION")
                || trimmed.range(of: "fatal signal", options: .caseInsensitive) != nil
                || trimmed.hasPrefix("ANR in") {
                attributed.foregroundColor = .red
                attributed.font = .app(size: 11, weight: .bold, design: .monospaced)
            } else if trimmed.hasPrefix("Caused by:") {
                attributed.foregroundColor = .orange
                attributed.font = .app(size: 11, weight: .semibold, design: .monospaced)
            } else if trimmed.hasPrefix("at ") || trimmed.hasPrefix("#") {
                attributed.foregroundColor = .secondary
            }
            out += attributed
            if index < lines.count - 1 { out += AttributedString("\n") }
        }
        return out
    }
}

private struct CrashTraceText: View, Equatable {
    let text: String

    var body: some View {
        Text(CrashView.highlighted(text))
            .font(.app(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
    }
}

private struct CrashRow: View {
    let report: CrashReport

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: report.kind.icon)
                .foregroundStyle(report.kind.tint)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.title)
                    .font(.app(.callout))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let process = report.process {
                        Text(process).lineLimit(1)
                    }
                    if let timestamp = report.timestamp {
                        if report.process != nil { Text("·") }
                        Text(timestamp)
                    }
                }
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

extension CrashReport.Kind {
    var icon: String {
        switch self {
        case .java: return "exclamationmark.octagon.fill"
        case .native: return "cpu.fill"
        case .reactNative: return "atom"
        case .anr: return "clock.badge.exclamationmark"
        case .unknown: return "questionmark.diamond"
        }
    }

    var tint: Color {
        switch self {
        case .java: return .red
        case .native: return .orange
        case .reactNative: return .blue
        case .anr: return .yellow
        case .unknown: return .gray
        }
    }
}
