import ADBKit
import AppKit
import SwiftUI

// MARK: - Value types

/// Severity of a console line, mapped from the CDP `consoleAPICalled` type.
enum JSLevel: String, CaseIterable, Hashable, Sendable {
    case error, warning, info, log, debug

    init(consoleType: String) {
        switch consoleType {
        case "error", "assert": self = .error
        case "warning": self = .warning
        case "info": self = .info
        case "debug": self = .debug
        default: self = .log
        }
    }

    var label: String {
        switch self {
        case .error: "Errors"
        case .warning: "Warnings"
        case .info: "Info"
        case .log: "Logs"
        case .debug: "Debug"
        }
    }

    var icon: String {
        switch self {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .log: "text.alignleft"
        case .debug: "ladybug.fill"
        }
    }
}

/// Connection lifecycle of the console.
enum JSPhase: Equatable {
    case searching
    case targetsAvailable
    case connecting
    case connected
    case failed(String)
}

/// One line in the console feed.
struct JSEntry: Identifiable {
    enum Kind {
        case input(String)
        case result(RemoteObject)
        case evalError(ExceptionDetails)
        case log(level: JSLevel, args: [RemoteObject], stack: CDPStackTrace?)
        case notice(String)
    }

    let id: Int
    let kind: Kind
    let at: Date
    /// Lowercased plain-text rendering, derived once at creation so the filter
    /// and ⌘F never re-tokenize the value tree per flush (a Sentry-reported
    /// main-thread hang during console bursts).
    let searchableText: String

    init(id: Int, kind: Kind, at: Date) {
        self.id = id
        self.kind = kind
        self.at = at
        searchableText = jsEntryPlainText(kind).lowercased()
    }
}

// MARK: - Session

/// The live JS console — discovery, the CDP connection, the log buffer, and
/// command history. Owned by `AppState` (like the Reactotron and terminal
/// sessions) so the buffer survives leaving the feature. The view is a thin
/// renderer over this; all the adb/CDP logic stays out of the view.
@MainActor
@Observable
final class JSConsoleSession {
    static let maxEntries = 2000
    private static let portKey = "jsConsoleMetroPort"
    private static let timestampsKey = "jsConsoleShowTimestamps"
    private static let newestFirstKey = "jsConsoleNewestFirst"

    /// The capped feed plus its filtered (level + text) projection, maintained
    /// incrementally (ADBKit's `FilteredLogBuffer`): a flush filters only the new
    /// batch against searchable text cached per entry, and a full recompute
    /// happens only when the filter itself changes — so a console burst costs
    /// O(batch) per flush, not O(buffer × object size). Chronological (oldest
    /// first); the view reverses it lazily for the inverted scroll.
    private var buffer = FilteredLogBuffer<JSEntry>(capacity: JSConsoleSession.maxEntries)
    var filteredEntries: [JSEntry] { buffer.filtered }
    fileprivate var phase: JSPhase = .searching
    fileprivate var targets: [CDPTarget] = []
    fileprivate var connectedTarget: CDPTarget?

    /// The Metro dev-server port. It varies per app, so it's user-editable and
    /// persisted; changing it re-discovers on the new port.
    var port: Int { didSet { UserDefaults.standard.set(port, forKey: Self.portKey) } }
    var searchText = "" { didSet { refilter() } }
    var hiddenLevels: Set<JSLevel> = [] { didSet { refilter() } }
    var showTimestamps: Bool { didSet { UserDefaults.standard.set(showTimestamps, forKey: Self.timestampsKey) } }
    /// Newest-first puts new logs at the top (anchored there); otherwise the feed
    /// tails at the bottom. Persisted for the JS console only.
    var newestFirst: Bool { didSet { UserDefaults.standard.set(newestFirst, forKey: Self.newestFirstKey) } }

    /// ⌘F find-in-console: highlights matches across the (filtered) feed and
    /// navigates between them — separate from the Filter field, which hides rows.
    var findVisible = false
    var findText = "" { didSet { findIndex = 0; rebuildFindMatches() } }
    private var findIndex = 0
    /// IDs of filtered entries matching the ⌘F query, in feed order — cached so
    /// navigation and the count badge don't re-scan the buffer each render.
    private(set) var findMatchIDs: [Int] = []

    private var history: [String] = []
    private var historyCursor: Int?
    /// The half-typed line stashed when the user starts browsing history, so
    /// arrowing back down past the newest entry restores it (REPL convention).
    private var draft: String?

    private let adb: AdbClient
    private let cdp = JSConsoleClient()
    private var consumeTask: Task<Void, Never>?
    private var connectGeneration = 0
    private var activateGeneration = 0
    private var nextEntryId = 1
    /// Stream events buffered between flushes; never observed (a flush writes the
    /// observed `buffer`), so a replay burst doesn't render.
    @ObservationIgnored private var pendingEntries: [JSEntry] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var welcomeTask: Task<Void, Never>?
    /// Console/exception events received on the current connection — used to tell
    /// when the post-connect replay burst has settled so the welcome can land.
    @ObservationIgnored private var receivedCount = 0
    private var preferredLogicalDeviceId: String?
    /// The logical device we last posted a "connected" notice for, so an
    /// auto-reconnect to the same app doesn't repeat the welcome.
    private var welcomedDeviceId: String?
    private var hasWelcomed = false
    private var serials: [String] = []
    /// port → serials we installed a `reverse tcp:<port>` binding on, so closing
    /// the tab can remove each. A tab *switch* keeps them — re-adding the reverse
    /// on every switch would be surprising, and the binding is what lets the
    /// device keep reaching Metro. Keyed by port so changing the port and
    /// re-reversing doesn't orphan the earlier binding.
    @ObservationIgnored private var reversedTunnels: [Int: Set<String>] = [:]
    weak var app: AppState?

    var isConnected: Bool { connectedTarget != nil }

    init(adb: AdbClient) {
        self.adb = adb
        let savedPort = UserDefaults.standard.integer(forKey: Self.portKey)
        port = (1 ... 65535).contains(savedPort) ? savedPort : 8081
        showTimestamps = UserDefaults.standard.bool(forKey: Self.timestampsKey)
        newestFirst = UserDefaults.standard.bool(forKey: Self.newestFirstKey)
    }

    /// Reset the connection back-references so the next connect re-welcomes.
    private func resetWelcome() {
        hasWelcomed = false
        welcomedDeviceId = nil
    }

    // MARK: Lifecycle

    /// Run discovery + connection for as long as the view is on screen. Driven by
    /// the view's `.task`, so SwiftUI cancels it on disappear; the connection is
    /// then torn down (the log buffer and the sticky target preference persist,
    /// so re-opening the console reconnects to the same app and shows prior logs).
    func activate(serials: [String]) async {
        self.serials = serials
        activateGeneration += 1
        let generation = activateGeneration
        if !isConnected { phase = .searching }
        while !Task.isCancelled {
            let scannedPort = port
            let found = (try? await MetroInspector(port: scannedPort).listTargets()) ?? []
            // Drop a pass whose port changed mid-fetch — its results are stale.
            if !Task.isCancelled, scannedPort == port {
                targets = found
                if connectedTarget == nil {
                    if let candidate = pickCandidate(from: found) {
                        await connect(to: candidate)
                    } else if phase != .connecting {
                        phase = found.isEmpty ? .searching : .targetsAvailable
                    }
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
        // Tear down only if a newer activation hasn't taken over (rapid
        // disappear→reappear), so we never disconnect the new one's socket.
        guard generation == activateGeneration else { return }
        consumeTask?.cancel()
        consumeTask = nil
        welcomeTask?.cancel()
        welcomeTask = nil
        await cdp.disconnect()
        connectedTarget = nil
        phase = .searching
    }

    func updateSerials(_ serials: [String]) { self.serials = serials }

    /// Choose a target to (re)connect to: the previously-connected logical
    /// device if it's back (the stable key across reloads), else a lone target.
    /// Stays hands-off when several apps are debuggable and none was chosen.
    private func pickCandidate(from targets: [CDPTarget]) -> CDPTarget? {
        let hermes = targets.filter(\.isHermes)
        let pool = hermes.isEmpty ? targets : hermes
        if let id = preferredLogicalDeviceId {
            return pool.first { $0.logicalDeviceId == id }
        }
        return pool.count == 1 ? pool.first : nil
    }

    func connect(to target: CDPTarget) async {
        guard let url = URL(string: target.webSocketDebuggerUrl),
              MetroInspector.isLocalDebuggerURL(url) else {
            phase = .failed("That target isn't a local debugger URL.")
            return
        }
        // A generation guard: if a newer connect starts while this one awaits,
        // only the latest commits state — no double-connect, no stale consumer.
        connectGeneration += 1
        let generation = connectGeneration
        phase = .connecting
        preferredLogicalDeviceId = target.logicalDeviceId
        consumeTask?.cancel()
        consumeTask = nil
        welcomeTask?.cancel()
        welcomeTask = nil
        do {
            let stream = try await cdp.connect(to: url)
            guard generation == connectGeneration, !Task.isCancelled else { return }
            connectedTarget = target
            phase = .connected
            receivedCount = 0
            consumeTask = Task { [weak self] in
                for await event in stream {
                    if Task.isCancelled { break }
                    self?.handle(event)
                }
            }
            // A "joined" banner like Chrome's "Welcome to React Native DevTools",
            // once per app — deferred until the replayed history settles so it lands
            // at the connection moment, not pinned to the top of the feed.
            if !hasWelcomed || welcomedDeviceId != target.logicalDeviceId {
                scheduleWelcome(
                    label: "Welcome to Droidective JS Console — connected to \(target.menuLabel) (Hermes).",
                    deviceId: target.logicalDeviceId,
                    generation: generation
                )
            }
        } catch {
            // Reconnection is the discovery loop's job; no notice, so a briefly
            // unreachable target doesn't spam the feed. The status badge reflects it.
            guard generation == connectGeneration, connectedTarget == nil else { return }
            phase = targets.isEmpty ? .searching : .targetsAvailable
        }
    }

    private func handle(_ event: JSConsoleClient.Event) {
        switch event {
        case let .console(call):
            if call.type == "clear" { clearFeedEntries(); return }
            enqueue(.log(level: JSLevel(consoleType: call.type), args: call.args, stack: call.stackTrace))
        case let .exception(details):
            enqueue(.evalError(details))
        case .contextCreated:
            break
        case .contextDestroyed:
            // A JS reload replaced the context — mark it inline (logs keep flowing).
            enqueue(.notice("App reloaded — JS context replaced."))
        case .closed:
            // The discovery loop reconnects (by logical-device id) within ~2s; the
            // status badge shows "Searching…" meanwhile. No feed notice, so a
            // flapping connection doesn't spam. Drop any pending welcome — the
            // reconnect schedules a fresh one (it stays un-welcomed until shown).
            welcomeTask?.cancel()
            welcomeTask = nil
            connectedTarget = nil
            phase = .searching
        }
    }

    // MARK: Evaluate / expand

    func submit(_ raw: String) {
        let expression = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return }
        history.removeAll { $0 == expression }
        history.append(expression)
        historyCursor = nil
        draft = nil
        append(.input(expression))
        guard isConnected else {
            append(.notice("Not connected to a JS target yet."))
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                switch try await self.cdp.evaluate(expression) {
                case let .value(object): self.append(.result(object))
                case let .error(details): self.append(.evalError(details))
                }
            } catch {
                self.append(.notice("Couldn't evaluate: \(error.localizedDescription)"))
            }
        }
    }

    /// A bounded pretty-JSON snapshot for expanding an object. Uses
    /// `callFunctionOn` (returns a string) rather than `getProperties`, whose
    /// native converter crashes Hermes on some object graphs (e.g. a large
    /// array). Returns a message string on failure so the row always resolves.
    func expandedJSON(of objectId: String) async -> String {
        await cdp.snapshotJSON(objectId: objectId) ?? "Couldn't read this value."
    }

    func clear() {
        // A user clear also drops a pending welcome so it can't re-appear after
        // the feed is emptied. (A replayed `console.clear()` event routes through
        // `clearFeedEntries` directly and keeps the welcome, which still belongs
        // at the connection moment.)
        welcomeTask?.cancel()
        welcomeTask = nil
        clearFeedEntries()
        Task { await cdp.releaseConsoleObjects() }
    }

    /// Faithful deep JSON of an object (Copy as JSON), evaluated in the runtime.
    func jsonString(of objectId: String) async -> String? {
        await cdp.deepStringify(objectId: objectId)
    }

    // MARK: Find (⌘F)

    var currentFindID: Int? {
        let ids = findMatchIDs
        guard !ids.isEmpty else { return nil }
        return ids[min(findIndex, ids.count - 1)]
    }

    var findCountLabel: String {
        if findText.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        let ids = findMatchIDs
        return ids.isEmpty ? "No matches" : "\(min(findIndex, ids.count - 1) + 1) of \(ids.count)"
    }

    func openFind() { findVisible = true }

    func closeFind() {
        findVisible = false
        findText = ""
    }

    func findNext() {
        let count = findMatchIDs.count
        guard count > 0 else { return }
        findIndex = (min(findIndex, count - 1) + 1) % count
    }

    func findPrev() {
        let count = findMatchIDs.count
        guard count > 0 else { return }
        findIndex = (min(findIndex, count - 1) - 1 + count) % count
    }

    // MARK: History

    func historyUp(current: String) -> String? {
        guard !history.isEmpty else { return nil }
        if historyCursor == nil { draft = current }
        let index = historyCursor.map { max(0, $0 - 1) } ?? history.count - 1
        historyCursor = index
        return history[index]
    }

    func historyDown() -> String? {
        guard let cursor = historyCursor else { return nil }
        let next = cursor + 1
        if next >= history.count {
            historyCursor = nil
            let restored = draft ?? ""
            draft = nil
            return restored
        }
        historyCursor = next
        return history[next]
    }

    // MARK: Port / adb reverse

    func setPort(_ newPort: Int) {
        guard (1 ... 65535).contains(newPort), newPort != port else { return }
        // Reset the discovery state synchronously so the running loop (which
        // re-reads `port`) can't apply a stale-port result; the socket close is
        // async cleanup that the loop already guards against. Bumping the
        // connect generation also stops a connect that's mid-await against the
        // old port from committing its target after the switch.
        port = newPort
        connectGeneration += 1
        consumeTask?.cancel()
        consumeTask = nil
        welcomeTask?.cancel()
        welcomeTask = nil
        flushTask?.cancel()
        flushTask = nil
        connectedTarget = nil
        preferredLogicalDeviceId = nil
        resetWelcome()
        targets = []
        phase = .searching
        Task { [weak self] in await self?.cdp.disconnect() }
    }

    /// Route the device's Metro port back to the Mac so a USB device can reach
    /// the dev server (and register a debug target).
    func reverseMetro() async {
        guard !serials.isEmpty else { return }
        let metroPort = port
        let serials = serials
        let reversed = await CommandLog.userInitiated {
            var reversed: Set<String> = []
            for serial in serials {
                if let result = try? await adb.run(on: serial, ["reverse", "tcp:\(metroPort)", "tcp:\(metroPort)"]),
                   result.succeeded {
                    reversed.insert(serial)
                }
            }
            return reversed
        }
        if !reversed.isEmpty { reversedTunnels[metroPort, default: []].formUnion(reversed) }
        let ok = reversed.count
        let allOK = ok == serials.count
        app?.showToast(Toast(
            message: allOK
                ? "Reversed tcp:\(metroPort) to Metro on \(serials.count) device\(serials.count == 1 ? "" : "s")."
                : "Reversed tcp:\(metroPort) on \(ok) of \(serials.count) devices — check the others are connected.",
            ok: allOK
        ))
    }

    /// Remove the `adb reverse` bindings this console installed. Called when the
    /// tab closes (mirrors `ReactotronService.stop`), not on a tab switch.
    func removeReverseTunnels() async {
        guard !reversedTunnels.isEmpty else { return }
        let tunnels = reversedTunnels
        reversedTunnels = [:]
        for (metroPort, serials) in tunnels {
            for serial in serials {
                _ = try? await adb.run(on: serial, ["reverse", "--remove", "tcp:\(metroPort)"])
            }
        }
    }

    // MARK: Derived feed (cached)

    /// The active row filter, or nil when everything passes — the fast path:
    /// appends then skip per-entry matching entirely.
    private var activeFilter: ((JSEntry) -> Bool)? {
        let query = ConsoleQuery(searchText)
        let hidden = hiddenLevels
        guard !query.isEmpty || !hidden.isEmpty else { return nil }
        return { entry in
            if case let .log(level, _, _) = entry.kind, hidden.contains(level) { return false }
            return query.matches(entry.searchableText)
        }
    }

    /// Full recompute — only for when the filter itself changes (query text,
    /// level chips) or the feed is cleared; appends go through `appendEntries`.
    private func refilter() {
        buffer.refilter(isIncluded: activeFilter)
        rebuildFindMatches()
    }

    private func rebuildFindMatches() {
        let query = ConsoleQuery(findText)
        guard !query.isEmpty else {
            if !findMatchIDs.isEmpty { findMatchIDs = [] }
            return
        }
        findMatchIDs = buffer.filtered
            .filter { query.matches($0.searchableText) }
            .map(\.id)
    }

    // MARK: Appending (batched)

    /// Stream events — the post-connect replay burst is the hot path — are buffered
    /// and flushed together so a thousand-message burst causes a handful of renders,
    /// not one per message (the fix for the multi-second open stall).
    private func enqueue(_ kind: JSEntry.Kind) {
        pendingEntries.append(JSEntry(id: nextEntryId, kind: kind, at: Date()))
        nextEntryId += 1
        receivedCount += 1
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, !Task.isCancelled else { return }
            self.flushPending()
        }
    }

    private func flushPending() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingEntries.isEmpty else { return }
        let batch = pendingEntries
        pendingEntries.removeAll(keepingCapacity: true)
        appendEntries(batch)
    }

    /// An entry that must appear now (user input, eval result, the welcome banner).
    /// Drain any buffered stream entries first so the feed stays in order.
    private func append(_ kind: JSEntry.Kind) {
        flushPending()
        appendEntries([JSEntry(id: nextEntryId, kind: kind, at: Date())])
        nextEntryId += 1
    }

    private func appendEntries(_ newEntries: [JSEntry]) {
        buffer.append(newEntries, isIncluded: activeFilter)
        rebuildFindMatches()
    }

    private func clearFeedEntries() {
        flushTask?.cancel()
        flushTask = nil
        pendingEntries.removeAll(keepingCapacity: true)
        buffer.removeAll()
        findMatchIDs = []
    }

    // MARK: Welcome banner

    /// Show the "connected" banner at the connection moment — after Hermes has
    /// replayed its buffered history and before live logs — by waiting for the
    /// replay burst to go quiet, mirroring Chrome's inline "Welcome to React Native
    /// DevTools". Once per app (logical device).
    private func scheduleWelcome(label: String, deviceId: String?, generation: Int) {
        welcomeTask?.cancel()
        welcomeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.waitForReplayToSettle()
            guard !Task.isCancelled, generation == self.connectGeneration, self.connectedTarget != nil else { return }
            self.hasWelcomed = true
            self.welcomedDeviceId = deviceId
            self.append(.notice(label))
        }
    }

    /// Return once no new console events have arrived for a quiet window, capped so
    /// an endlessly-chatty app still gets its banner.
    private func waitForReplayToSettle() async {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(1500))
        var last = receivedCount
        while !Task.isCancelled, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            if receivedCount == last { return }
            last = receivedCount
        }
    }

}

extension CDPTarget {
    /// A human label for the picker: app id (or title) and the device.
    var menuLabel: String {
        let name = appId ?? (detail.isEmpty ? title : detail)
        return deviceName.isEmpty ? name : "\(name) · \(deviceName)"
    }
}

// MARK: - View

struct JSConsoleView: View {
    @Environment(AppState.self) private var state
    @State private var input = ""
    @State private var portText = ""
    @State private var inputHeight: CGFloat = 26
    @State private var showLevels = false
    @FocusState private var findFocused: Bool

    private var session: JSConsoleSession { state.jsConsoleSession }

    var body: some View {
        VStack(spacing: 0) {
            connectionBar
            Divider()
            filterBar
            Divider()
            if session.findVisible {
                findBar
                Divider()
            }
            logArea
            Divider()
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await session.activate(serials: state.targetSerials) }
        .onChange(of: state.targetSerials) { _, serials in session.updateSerials(serials) }
        .onAppear { portText = String(session.port) }
        .onChange(of: session.port) { _, newPort in portText = String(newPort) }
        .onChange(of: session.findVisible) { _, visible in if visible { findFocused = true } }
    }

    // MARK: Find bar (⌘F)

    private var findBar: some View {
        @Bindable var session = state.jsConsoleSession
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in console", text: $session.findText)
                .textFieldStyle(.plain)
                .focused($findFocused)
                .onSubmit { session.findNext() }
                .onKeyPress(.escape) { session.closeFind(); return .handled }
            Text(session.findCountLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            Button { session.findPrev() } label: { Image(systemName: "chevron.up") }
                .buttonStyle(IconButtonStyle(size: .small))
                .disabled(session.findMatchIDs.isEmpty)
            Button { session.findNext() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(IconButtonStyle(size: .small))
                .disabled(session.findMatchIDs.isEmpty)
            Button { session.closeFind() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(IconButtonStyle(size: .small))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.07))
    }

    // MARK: Connection bar

    private var connectionBar: some View {
        HStack(spacing: 10) {
            statusBadge
            targetPicker
            portField
            Spacer(minLength: 8)
            if !state.targetSerials.isEmpty, !session.isConnected {
                Button { Task { await session.reverseMetro() } } label: {
                    Label("adb reverse", systemImage: "arrow.left.arrow.right")
                }
                .help("Route the device's tcp:\(session.port) to Metro on your Mac (USB devices)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .fixedSize()
    }

    private var statusColor: Color {
        switch session.phase {
        case .connected: .green
        case .failed: .red
        default: .orange
        }
    }

    private var statusText: String {
        switch session.phase {
        case .searching: "Searching for a target on :\(session.port)…"
        case .targetsAvailable: "Choose a target to connect"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case let .failed(message): message
        }
    }

    private var targetPicker: some View {
        Menu {
            if session.targets.isEmpty {
                Text("No targets found")
            } else {
                ForEach(session.targets) { target in
                    Button {
                        Task { await session.connect(to: target) }
                    } label: {
                        Label(
                            target.menuLabel,
                            systemImage: session.connectedTarget?.id == target.id ? "checkmark" : "iphone.gen3"
                        )
                    }
                }
            }
        } label: {
            Label(session.connectedTarget?.menuLabel ?? "Choose target", systemImage: "iphone.gen3")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(session.targets.isEmpty)
    }

    private var portField: some View {
        HStack(spacing: 4) {
            Text("Port").font(.caption).foregroundStyle(.secondary)
            TextField("8081", text: $portText)
                .frame(width: 52)
                .multilineTextAlignment(.center)
                .onSubmit { if let value = Int(portText) { session.setPort(value) } }
                .help("Metro dev-server port — varies per app")
        }
    }

    // MARK: Filter bar

    private var filterBar: some View {
        @Bindable var session = state.jsConsoleSession
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                TextField("Filter", text: $session.searchText)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 120, maxWidth: 240)
            }
            Spacer(minLength: 8)
            levelFilter
            Button { session.openFind() } label: { Image(systemName: "text.magnifyingglass") }
                .buttonStyle(IconButtonStyle())
                .help("Find & highlight in console (⌘F)")
                .keyboardShortcut("f", modifiers: .command)
            Button { session.newestFirst.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                .buttonStyle(IconButtonStyle())
                .help("Order: \(session.newestFirst ? "newest first" : "oldest first") — tap to flip")
            Toggle("Time", isOn: $session.showTimestamps).toggleStyle(.checkbox).font(.caption)
            Button { session.clear() } label: { Image(systemName: "trash") }
                .buttonStyle(IconButtonStyle())
                .help("Clear the console")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Multi-select level filter: one dropdown that toggles several levels at
    /// once (the popover stays open), with Show-/Hide-all shortcuts. Replaces the
    /// old per-level chips + reopen-per-toggle menu.
    private var levelFilter: some View {
        let shown = JSLevel.allCases.count - session.hiddenLevels.count
        let allShown = session.hiddenLevels.isEmpty
        return Button {
            showLevels.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(allShown ? "All levels" : "Levels \(shown)/\(JSLevel.allCases.count)")
                    .fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(allShown ? 0 : 0.7), in: Capsule())
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.25)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Choose which log levels to show")
        .popover(isPresented: $showLevels, arrowEdge: .bottom) { levelPicker }
    }

    private var levelPicker: some View {
        @Bindable var session = state.jsConsoleSession
        return VStack(alignment: .leading, spacing: 8) {
            Text("Show levels").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(JSLevel.allCases, id: \.self) { level in
                Toggle(isOn: Binding(
                    get: { !session.hiddenLevels.contains(level) },
                    set: { show in
                        if show { session.hiddenLevels.remove(level) } else { session.hiddenLevels.insert(level) }
                    }
                )) {
                    Label {
                        Text(level.label)
                    } icon: {
                        Image(systemName: level.icon).foregroundStyle(level.consoleIconColor)
                    }
                }
                .toggleStyle(.checkbox)
            }
            Divider()
            HStack {
                Button("Show All") { session.hiddenLevels.removeAll() }
                    .disabled(session.hiddenLevels.isEmpty)
                Spacer()
                Button("Hide All") { session.hiddenLevels = Set(JSLevel.allCases) }
                    .disabled(session.hiddenLevels.count == JSLevel.allCases.count)
            }
            .font(.caption)
            .buttonStyle(.link)
        }
        .padding(12)
        .frame(width: 190)
    }

    // MARK: Log area

    private var logArea: some View {
        let visible = session.filteredEntries
        // The feed is a self-contained Chrome-style dark console: a fixed dark
        // surface with forced dark scheme, so the rows, level bands, AND the empty
        // state read the same in the app's light or dark theme.
        return Group {
            if visible.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrollingLog(visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JSConsoleTheme.background)
        .environment(\.colorScheme, .dark)
    }

    /// Newest at the top in "newest first", the bottom otherwise — LogTailView
    /// tails the correct edge, pauses when the user scrolls off, and drives the
    /// ⌘F match into view via `focusID`. LazyVStack + `.scrollPosition` (never
    /// `defaultScrollAnchor`) keeps the big connect-time replay burst from
    /// laying out every row up front — the 20–30s stall the old flip trick dodged.
    @ViewBuilder
    private func scrollingLog(_ visible: [JSEntry]) -> some View {
        if session.newestFirst {
            LogTailView(entries: visible.reversed(), newestEdge: .top,
                        focusID: session.currentFindID) { jsRow($0) }
        } else {
            LogTailView(entries: visible, newestEdge: .bottom,
                        focusID: session.currentFindID) { jsRow($0) }
        }
    }

    @ViewBuilder
    private func jsRow(_ entry: JSEntry) -> some View {
        let band = levelBand(entry)
        JSEntryRow(entry: entry, session: session, showTimestamp: session.showTimestamps)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(band?.fill ?? .clear)
            .overlay(alignment: .leading) {
                if let band { Rectangle().fill(band.rule).frame(width: 3) }
            }
        Divider().opacity(0.18)
    }

    /// The Chrome-style row band (fill + left rule) for error and warning rows;
    /// nil for the levels that sit on the plain console surface.
    private func levelBand(_ entry: JSEntry) -> (fill: Color, rule: Color)? {
        switch entry.kind {
        case let .log(level, _, _): level.consoleBand
        case .evalError: (JSConsoleTheme.errorBackground, JSConsoleTheme.errorRule)
        default: nil
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: "chevron.left.forwardslash.chevron.right")
        } description: {
            Text(emptyDescription)
        } actions: {
            if !state.targetSerials.isEmpty, !session.isConnected {
                Button("Run adb reverse for the device") { Task { await session.reverseMetro() } }
            }
        }
    }

    private var emptyTitle: String {
        session.isConnected ? "Console ready" : "Waiting for a React Native app"
    }

    private var emptyDescription: String {
        if session.isConnected {
            return "Type an expression below, or trigger console output in the app."
        }
        return """
        Open a dev build running Hermes with Metro on port \(session.port). \
        The app must be connected to Metro — for a USB device, tap “adb reverse” so it can reach the dev server. \
        Targets appear automatically.
        """
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(session.isConnected ? Color.accentColor : .secondary)
                .padding(.bottom, 5)
            ZStack(alignment: .topLeading) {
                if input.isEmpty {
                    Text("Evaluate JavaScript…  (⇧⏎ for a new line)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                JSCodeEditor(
                    text: $input,
                    height: $inputHeight,
                    onSubmit: run,
                    historyUp: { session.historyUp(current: $0) },
                    historyDown: { session.historyDown() }
                )
                .frame(height: inputHeight)
            }
            Button("Run", action: run)
                .controlSize(.small)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.bottom, 2)
        }
        .padding(10)
    }

    // MARK: Actions

    private func run() {
        session.submit(input)
        input = ""
    }
}

// MARK: - Entry row

private struct JSEntryRow: View {
    let entry: JSEntry
    let session: JSConsoleSession
    let showTimestamp: Bool

    private var query: String { session.findText.trimmingCharacters(in: .whitespaces) }
    private var isCurrentFind: Bool { session.findVisible && session.currentFindID == entry.id }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            glyph
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            if showTimestamp {
                Text(entry.at, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(JSConsoleTheme.muted)
                    .padding(.top, 1)
            }
        }
        .contextMenu {
            Button("Copy") { copyToPasteboard(jsEntryPlainText(entry.kind)) }
            if let objectID = primaryObjectID {
                Button("Copy as JSON") {
                    Task {
                        let json = await session.jsonString(of: objectID) ?? jsEntryPlainText(entry.kind)
                        copyToPasteboard(json)
                    }
                }
            }
        }
    }

    /// The object handle to deep-copy as JSON (result value, or the first
    /// expandable log arg).
    private var primaryObjectID: String? {
        switch entry.kind {
        case let .result(object): object.isExpandable ? object.objectId : nil
        case let .log(_, args, _): args.first(where: \.isExpandable)?.objectId
        default: nil
        }
    }

    @ViewBuilder private var glyph: some View {
        switch entry.kind {
        case .input:
            icon("chevron.right", JSConsoleTheme.muted)
        case .result:
            icon("arrow.turn.down.right", JSConsoleTheme.muted)
        case .evalError:
            icon("xmark.octagon.fill", JSConsoleTheme.errorText)
        case let .log(level, _, _):
            icon(level.icon, level.consoleIconColor)
        case .notice:
            icon("info.circle", JSConsoleTheme.muted)
        }
    }

    private func icon(_ name: String, _ style: some ShapeStyle) -> some View {
        Image(systemName: name)
            .font(.caption)
            .foregroundStyle(style)
            .frame(width: 14)
            .padding(.top, 2)
    }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case let .input(text):
            line(text, base: JSConsoleTheme.muted)
        case let .result(object):
            JSValueView(object: object, session: session)
        case let .evalError(details):
            errorContent(details)
        case let .log(level, args, stack):
            logContent(level: level, args: args, stack: stack)
        case let .notice(text):
            line(text, base: JSConsoleTheme.muted)
        }
    }

    private func line(_ text: String, base: Color) -> some View {
        highlightedText(text, query: query, base: base, current: isCurrentFind)
            .font(.system(.callout, design: .monospaced))
            .lineSpacing(2)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func logContent(level: JSLevel, args: [RemoteObject], stack: CDPStackTrace?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // Each expandable object renders exactly once, as its own disclosure
            // row in argument order — it used to appear twice (inline in the
            // message line AND repeated below), which doubled every logged object.
            // Scalar runs keep the level tint for errors/warnings and VSCode-style
            // syntax colors otherwise.
            ForEach(argRows(args)) { row in
                switch row.kind {
                case let .scalars(text, tokens):
                    if level == .error || level == .warning {
                        line(text, base: level.consoleTextColor)
                    } else {
                        coloredTokenText(tokens, query: query, current: isCurrentFind)
                            .font(.system(.callout, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case let .object(arg):
                    JSValueView(object: arg, session: session)
                }
            }
            if level == .error, let stack { StackView(stack: stack) }
        }
    }

    /// The visual rows for one log call's arguments: consecutive scalars merge
    /// into one line; each expandable object becomes its own row.
    private struct ArgRow: Identifiable {
        enum Kind {
            case scalars(String, [JSToken])
            case object(RemoteObject)
        }

        let id: Int
        let kind: Kind
    }

    private func argRows(_ args: [RemoteObject]) -> [ArgRow] {
        var rows: [ArgRow] = []
        var run: [RemoteObject] = []
        func flushRun() {
            guard !run.isEmpty else { return }
            let text = run.map(\.inlineSummary).joined(separator: " ")
            rows.append(ArgRow(id: rows.count, kind: .scalars(text, argTokens(run))))
            run = []
        }
        for arg in args {
            if arg.isExpandable {
                flushRun()
                rows.append(ArgRow(id: rows.count, kind: .object(arg)))
            } else {
                run.append(arg)
            }
        }
        flushRun()
        return rows
    }

    private func argTokens(_ args: [RemoteObject]) -> [JSToken] {
        var tokens: [JSToken] = []
        for (index, arg) in args.enumerated() {
            if index > 0 { tokens.append(JSToken(" ", .plain)) }
            tokens.append(contentsOf: arg.tokens)
        }
        return tokens
    }

    private func errorContent(_ details: ExceptionDetails) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            line(details.message, base: JSConsoleTheme.errorText)
            if let stack = details.stackTrace { StackView(stack: stack) }
        }
    }
}

// MARK: - Expandable value

private struct JSValueView: View {
    let object: RemoteObject
    let session: JSConsoleSession
    @State private var expanded = false
    @State private var expandedText: String?
    @State private var loading = false

    private var query: String { session.findText.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        if object.isExpandable {
            // Custom disclosure (not macOS DisclosureGroup, which right-aligns its
            // content): a chevron header with children indented straight below.
            // Collapsed previews truncate Chrome-style instead of wrapping the
            // whole object — expanding is how you read the rest.
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    expanded.toggle()
                    if expanded, expandedText == nil, !loading { load() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        summaryText
                            .lineLimit(expanded ? 1 : 2)
                            .truncationMode(.tail)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { copyButtons }
                if expanded { expandedChildren.padding(.leading, 18) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            summaryText
                .fixedSize(horizontal: false, vertical: true)
                .contextMenu { copyButtons }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryText: some View {
        coloredTokenText(object.tokens, query: query, current: false)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
    }

    @ViewBuilder private var copyButtons: some View {
        Button("Copy") { copyToPasteboard(object.inlineSummary) }
        if let objectId = object.objectId, object.isExpandable {
            Button("Copy as JSON") {
                Task {
                    let json = await session.jsonString(of: objectId) ?? object.inlineSummary
                    copyToPasteboard(json)
                }
            }
        }
    }

    @ViewBuilder private var expandedChildren: some View {
        if loading {
            ProgressView().controlSize(.small)
        } else if let expandedText {
            // A bounded pretty-JSON snapshot fetched via callFunctionOn (not
            // getProperties, which crashes Hermes). Rendered read-only; the
            // collapsed preview above stays the interactive summary.
            highlightedText(expandedText, query: query, base: jsColor(.plain))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() {
        guard let objectId = object.objectId else { return }
        loading = true
        Task {
            let text = await session.expandedJSON(of: objectId)
            expandedText = text
            loading = false
        }
    }
}

private struct StackView: View {
    let stack: CDPStackTrace

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(stack.callFrames.prefix(8)) { frame in
                Text(frame.display)
                    .font(.caption2.monospaced())
                    .foregroundStyle(JSConsoleTheme.muted)
            }
        }
        .padding(.leading, 4)
    }
}

// MARK: - Multi-line code input

/// An `NSTextView`-backed editor for the Evaluate field. SwiftUI's `TextField`
/// can't reliably do "⏎ submits, ⇧⏎ inserts a newline" on macOS (⇧⏎ extends the
/// selection), so this drives key handling directly. It also grows with content
/// up to a cap, then scrolls.
private struct JSCodeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onSubmit: () -> Void
    var historyUp: (String) -> String?
    var historyDown: () -> String?

    private let minHeight: CGFloat = 22
    private let maxHeight: CGFloat = 140

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 3)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        let coordinator = context.coordinator
        Task { @MainActor in coordinator.recalculateHeight() }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.recalculateHeight()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSCodeEditor
        weak var textView: NSTextView?

        init(_ parent: JSCodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // ⇧⏎ → let AppKit insert a newline; plain ⏎ → submit.
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
                parent.onSubmit()
                return true
            case #selector(NSResponder.moveUp(_:)):
                guard !textView.string.contains("\n"), let recalled = parent.historyUp(textView.string) else {
                    return false
                }
                replace(textView, with: recalled)
                return true
            case #selector(NSResponder.moveDown(_:)):
                guard !textView.string.contains("\n"), let recalled = parent.historyDown() else { return false }
                replace(textView, with: recalled)
                return true
            default:
                return false
            }
        }

        private func replace(_ textView: NSTextView, with string: String) {
            textView.string = string
            parent.text = string
            textView.setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let textView, let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
            let clamped = min(max(used, parent.minHeight), parent.maxHeight)
            guard abs(clamped - parent.height) > 0.5 else { return }
            // Defer to the next tick so we never mutate @State during a view update.
            Task { @MainActor [weak self] in self?.parent.height = clamped }
        }
    }
}

// MARK: - Rendering helpers

/// Plain-text rendering of one console entry — the single source for the search
/// filter, find (both via `JSEntry.searchableText`, cached at ingest), and copy,
/// so they never drift. `RemoteObject.inlineSummary` (pure, in ADBKit) does the
/// value rendering.
func jsEntryPlainText(_ kind: JSEntry.Kind) -> String {
    switch kind {
    case let .input(text): text
    case let .result(object): object.inlineSummary
    case let .evalError(details): details.message
    case let .log(_, args, _): args.map(\.inlineSummary).joined(separator: " ")
    case let .notice(text): text
    }
}

func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

/// Value/token colors — the Chrome dark-console palette (see `JSConsoleTheme`),
/// since the feed renders on a fixed dark surface.
func jsColor(_ kind: JSTokenKind) -> Color {
    JSConsoleTheme.token(kind)
}

/// Syntax-colored `Text` for a value's tokens, with find matches highlighted.
func coloredTokenText(_ tokens: [JSToken], query: String, current: Bool) -> Text {
    var attr = AttributedString()
    for token in tokens {
        var segment = AttributedString(token.text)
        segment.foregroundColor = jsColor(token.kind)
        attr += segment
    }
    applyFindHighlight(&attr, query: query, current: current)
    return Text(attr)
}

/// A single-color `Text` (input/notice/error lines) with find matches highlighted.
func highlightedText(_ string: String, query: String, base: Color, current: Bool = false) -> Text {
    var attr = AttributedString(string)
    attr.foregroundColor = base
    applyFindHighlight(&attr, query: query, current: current)
    return Text(attr)
}

/// Overlay a highlight background on every case-insensitive occurrence of
/// `query` — yellow, or orange for the current find match.
func applyFindHighlight(_ attr: inout AttributedString, query: String, current: Bool) {
    guard !query.isEmpty else { return }
    let plain = String(attr.characters)
    var offsets: [(Int, Int)] = []
    var start = plain.startIndex
    while let range = plain.range(of: query, options: .caseInsensitive, range: start ..< plain.endIndex) {
        offsets.append((
            plain.distance(from: plain.startIndex, to: range.lowerBound),
            plain.distance(from: plain.startIndex, to: range.upperBound)
        ))
        start = range.upperBound
    }
    for (low, high) in offsets {
        let lower = attr.index(attr.startIndex, offsetByCharacters: low)
        let upper = attr.index(attr.startIndex, offsetByCharacters: high)
        attr[lower ..< upper].backgroundColor = current ? JSConsoleTheme.findCurrent : JSConsoleTheme.findMatch
        attr[lower ..< upper].foregroundColor = .black
    }
}
