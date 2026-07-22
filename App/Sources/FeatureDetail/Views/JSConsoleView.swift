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
    /// Lowercased plain-text head for the filter and ⌘F, derived once at
    /// creation so they never re-tokenize the value tree per flush (a
    /// Sentry-reported main-thread hang during console bursts). Capped like
    /// Reactotron's search text AND built without materializing full values —
    /// copying a replayed multi-megabyte string per entry just to keep this
    /// head was the bulk of the reload CPU spike. Matching runs on the head.
    let searchableText: String
    /// Rough retained size (the string payloads dominate; O(1) per arg) —
    /// drives the buffer's byte budget.
    let approximateBytes: Int

    init(id: Int, kind: Kind, at: Date) {
        self.id = id
        self.kind = kind
        self.at = at
        let size = Self.approximateSize(kind)
        approximateBytes = size
        if size > 1_000_000 {
            PerfLog.console.warning("ingested huge console entry: ~\(size, privacy: .public) bytes")
        }
        searchableText = Self.boundedSearchable(kind)
    }

    private static func boundedSearchable(_ kind: Kind, limit: Int = 2000) -> String {
        switch kind {
        case let .input(text): return String(text.prefix(limit)).lowercased()
        case let .result(object): return object.inlineSummary(limit: limit).lowercased()
        case let .evalError(details): return String(details.message.prefix(limit)).lowercased()
        case let .notice(text): return String(text.prefix(limit)).lowercased()
        case let .log(_, args, _):
            var out = ""
            for arg in args {
                let remaining = limit - out.utf8.count
                guard remaining > 0 else { break }
                if !out.isEmpty { out += " " }
                out += arg.inlineSummary(limit: remaining)
            }
            return out.lowercased()
        }
    }

    private static func approximateSize(_ kind: Kind) -> Int {
        switch kind {
        case let .input(text): text.utf8.count + 256
        case let .result(object): object.approximateBytes
        case let .evalError(details): details.message.utf8.count + 512
        case let .notice(text): text.utf8.count + 256
        case let .log(_, args, _): args.reduce(256) { $0 + $1.approximateBytes }
        }
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
    private static let newestFirstKey = "jsConsoleNewestFirst"

    /// The capped feed plus its filtered (level + text) projection, maintained
    /// incrementally (ADBKit's `FilteredLogBuffer`): a flush filters only the new
    /// batch against searchable text cached per entry, and a full recompute
    /// happens only when the filter itself changes — so a console burst costs
    /// O(batch) per flush, not O(buffer × object size). Chronological (oldest
    /// first); the feed renders it as-is (newest at the bottom) or reversed
    /// when `newestFirst` is on.
    // The 128 MB byte budget (Reactotron's figure) matters as much as the
    // count cap: 2000 entries each holding a multi-megabyte logged string
    // would otherwise retain gigabytes.
    private var buffer = FilteredLogBuffer<JSEntry>(
        capacity: JSConsoleSession.maxEntries,
        byteBudget: 128 << 20,
        cost: { $0.approximateBytes }
    )
    var filteredEntries: [JSEntry] { buffer.filtered }
    fileprivate var phase: JSPhase = .searching
    fileprivate var targets: [CDPTarget] = []
    fileprivate var connectedTarget: CDPTarget?

    /// The Metro dev-server port. It varies per app, so it's user-editable and
    /// persisted; changing it re-discovers on the new port.
    var port: Int { didSet { UserDefaults.standard.set(port, forKey: Self.portKey) } }
    var searchText = "" { didSet { refilter() } }
    var hiddenLevels: Set<JSLevel> = [] { didSet { refilter() } }
    /// Reversed feed: newest at the top instead of Chrome's newest-at-bottom.
    /// Persisted per feature; the ⌘F match order follows the display order, so
    /// flipping rebuilds the matches and restarts from the first visible one.
    var newestFirst: Bool {
        didSet {
            UserDefaults.standard.set(newestFirst, forKey: Self.newestFirstKey)
            findIndex = 0
            rebuildFindMatches()
        }
    }

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
    /// The discovery/connection loop, owned by the session so tab close and
    /// window close can stop it without going through a view update.
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    /// Console/exception events received on the current connection — used to tell
    /// when the post-connect replay burst has settled so the welcome can land.
    @ObservationIgnored private var receivedCount = 0
    private var preferredLogicalDeviceId: String?
    /// The application id we last connected to — the reconnect key that
    /// survives the proxy handing the app a fresh logical device id (app
    /// relaunch, phone sleep, Metro restart).
    private var preferredAppId: String?
    /// Set when the server closed us because another debugger (React Native
    /// DevTools, usually) attached to the same app. Auto-reconnecting would
    /// kick that debugger right back off, so discovery stands down until the
    /// user picks a target (or the session restarts / the port changes).
    private var autoReconnectSuspended = false
    /// Drops the re-replayed console history on reconnects to the same app so
    /// the persistent feed doesn't duplicate.
    @ObservationIgnored private var replayGate = ConsoleReplayGate()
    /// Auto-connect waits for a target to survive two discovery passes —
    /// attaching the instant it first registered crashed Hermes mid-boot
    /// (`TargetStabilityTracker`). Manual picks bypass this.
    @ObservationIgnored private var targetStability = TargetStabilityTracker()
    /// Whether the "connected" notice was posted for the current app — an
    /// auto-reconnect to the same app doesn't repeat the welcome.
    private var hasWelcomed = false
    private var serials: [String] = []
    /// port → serials we installed a `reverse tcp:<port>` binding on, so closing
    /// the tab can remove each. A tab *switch* keeps them — re-adding the reverse
    /// on every switch would be surprising, and the binding is what lets the
    /// device keep reaching Metro. Keyed by port so changing the port and
    /// re-reversing doesn't orphan the earlier binding.
    @ObservationIgnored private var reversedTunnels: [Int: Set<String>] = [:]
    /// port → per-serial auto-reverse try count, capped at `autoReverseTryLimit`
    /// so the 2s loop doesn't respawn adb forever for a device that keeps
    /// failing — while a transient failure still gets retried instead of
    /// stranding the device on its first bad pass. A serial that leaves the
    /// device list is forgotten (a replug drops the binding device-side, so it
    /// must be re-attempted).
    @ObservationIgnored private var autoReverseAttempts: [Int: [String: Int]] = [:]
    private let autoReverseTryLimit = 3
    weak var app: AppState?

    var isConnected: Bool { connectedTarget != nil }

    /// Whether the console holds any output at all (unfiltered). The filter row
    /// keys off this, so an active filter that hides every row still leaves a
    /// way to clear it.
    var hasEntries: Bool { !buffer.entries.isEmpty }

    init(adb: AdbClient) {
        self.adb = adb
        let savedPort = UserDefaults.standard.integer(forKey: Self.portKey)
        port = (1 ... 65535).contains(savedPort) ? savedPort : 8081
        newestFirst = UserDefaults.standard.bool(forKey: Self.newestFirstKey)
    }

    /// Reset the connection back-references so the next connect re-welcomes.
    private func resetWelcome() {
        hasWelcomed = false
    }

    // MARK: Lifecycle

    /// Begin discovery + connection. Idempotent: a running loop is kept. The
    /// session owns the loop's `Task` (not the view's `.task`) so `AppState`
    /// can stop it when the tab or the main window closes — a view inside a
    /// closed-but-retained window may never process another update, so view-
    /// keyed cancellation can't be trusted for that.
    func start(serials: [String]) {
        self.serials = serials
        guard discoveryTask == nil else { return }
        discoveryTask = Task { [weak self] in
            await self?.activate(serials: serials)
        }
    }

    /// Stop discovery and drop the connection. The log buffer and the sticky
    /// target preference persist, so a later `start` reconnects to the same app
    /// and shows prior logs. Idempotent.
    func stop() {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    // MARK: View attach/detach

    /// Views currently showing this session. Moving the tab between split
    /// panes REMOUNTS the view, and SwiftUI may fire the new pane's onAppear
    /// before the old pane's onDisappear — a hard `stop()` there killed the
    /// live connection and dropped the chosen target. So the view lifecycle
    /// counts attachments and only stops once no view has claimed the session
    /// for a beat; the direct `start`/`stop` remain for AppState's explicit
    /// paths (tab close, window close, reopen).
    @ObservationIgnored private var attachedViews = 0

    func viewAppeared(serials: [String]) {
        attachedViews += 1
        start(serials: serials)
    }

    func viewDisappeared() {
        attachedViews = max(0, attachedViews - 1)
        guard attachedViews == 0 else { return }
        // Deferred: on a pane move the replacement view attaches within the
        // same UI beat (in either onAppear/onDisappear order) and vetoes the
        // stop. Only a real teardown leaves the count at zero.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, self.attachedViews == 0 else { return }
            self.stop()
        }
    }

    /// Run discovery + connection until cancelled; tears the connection down on
    /// the way out.
    private func activate(serials: [String]) async {
        self.serials = serials
        activateGeneration += 1
        let generation = activateGeneration
        autoReconnectSuspended = false
        if !isConnected { phase = .searching }
        while !Task.isCancelled {
            // Self-heal a half-dead connection: the socket is gone but its
            // close event was never consumed (a torn-down consumer during a
            // reconnect race) — without this, discovery idles forever
            // believing it's connected while the status shows a green dot
            // over a silent feed. Restarting the feature used to be the fix.
            if connectedTarget != nil, !(await cdp.isConnected) {
                connectedTarget = nil
                phase = .searching
            }
            if connectedTarget == nil { await autoReverse() }
            let scannedPort = port
            let found = (try? await MetroInspector(port: scannedPort).listTargets()) ?? []
            // Drop a pass whose port changed mid-fetch — its results are stale.
            if !Task.isCancelled, scannedPort == port {
                targets = found
                targetStability.recordPass(ids: found.map(\.id))
                // A takeover stand-down holds while any target is still
                // listed; once the list is empty there's no debugger left to
                // kick off and discovery should self-heal again.
                if autoReconnectSuspended, found.isEmpty {
                    autoReconnectSuspended = false
                    phase = .searching
                }
                if connectedTarget == nil, !autoReconnectSuspended {
                    // Auto-connect only once the candidate has survived two
                    // consecutive scans: attaching the instant an app first
                    // registers hit Hermes mid-boot and crashed it. A booting
                    // app waits one extra pass; a long-listed target (JS
                    // reload, socket drop) reconnects immediately; the user's
                    // pick from the target menu skips the gate entirely.
                    if let candidate = MetroInspector.autoConnectCandidate(
                        from: found,
                        preferredDeviceId: preferredLogicalDeviceId,
                        preferredAppId: preferredAppId
                    ), targetStability.isStable(candidate.id) {
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

    func updateSerials(_ serials: [String]) {
        // A serial that vanished is forgotten so a replugged device gets its
        // reverse re-attempted — replugging drops the binding device-side.
        let removed = Set(self.serials).subtracting(serials)
        if !removed.isEmpty {
            for key in autoReverseAttempts.keys {
                for serial in removed { autoReverseAttempts[key]?[serial] = nil }
            }
            for key in reversedTunnels.keys { reversedTunnels[key]?.subtract(removed) }
        }
        self.serials = serials
    }

    /// Install the device→Mac Metro binding automatically while searching, so
    /// a USB device can register with Metro without the user knowing to click
    /// "adb reverse" first (`react-native run-android` does the same on every
    /// launch — its absence was why the console often found no target until
    /// the feature was poked). A failed reverse stays eligible on later scan
    /// passes, up to a few tries per device+port — a transient adb hiccup
    /// shouldn't strand the device; the manual button stays as the fallback.
    /// Background work, so deliberately not CommandLog-wrapped.
    private func autoReverse() async {
        let metroPort = port
        let eligible = serials.filter {
            autoReverseAttempts[metroPort, default: [:]][$0, default: 0] < autoReverseTryLimit
        }
        guard !eligible.isEmpty else { return }
        var reversed: Set<String> = []
        for serial in eligible where !Task.isCancelled {
            if let result = try? await adb.run(on: serial, ["reverse", "tcp:\(metroPort)", "tcp:\(metroPort)"]),
               result.succeeded {
                autoReverseAttempts[metroPort, default: [:]][serial] = autoReverseTryLimit
                reversed.insert(serial)
            } else {
                autoReverseAttempts[metroPort, default: [:]][serial, default: 0] += 1
            }
        }
        if !reversed.isEmpty { reversedTunnels[metroPort, default: []].formUnion(reversed) }
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
        autoReconnectSuspended = false
        // Reconnecting to the app whose history the feed already holds? Then
        // the post-connect replay is a duplicate and the gate should drop it.
        let resumingSameApp = (target.logicalDeviceId != nil
            && target.logicalDeviceId == preferredLogicalDeviceId)
            || (target.appId != nil && target.appId == preferredAppId)
        preferredLogicalDeviceId = target.logicalDeviceId
        preferredAppId = target.appId
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
            replayGate.connectionOpened(resumingSameApp: resumingSameApp)
            consumeTask = Task { [weak self] in
                for await event in stream {
                    if Task.isCancelled { break }
                    self?.handle(event)
                }
            }
            // A "joined" banner like Chrome's "Welcome to React Native DevTools",
            // once per app — deferred until the replayed history settles so it lands
            // at the connection moment, not pinned to the top of the feed.
            if !hasWelcomed || !resumingSameApp {
                scheduleWelcome(
                    label: "Welcome to Droidective JS Console — connected to \(target.menuLabel) (Hermes).",
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
            // Gate before the clear check: a *replayed* console.clear would
            // otherwise wipe the feed the gate is preserving.
            guard replayGate.admit(call.timestamp) else { return }
            if call.type == "clear" { clearFeedEntries(); return }
            enqueue(.log(level: JSLevel(consoleType: call.type), args: call.args, stack: call.stackTrace))
        case let .exception(details, timestamp):
            guard replayGate.admit(timestamp) else { return }
            enqueue(.evalError(details))
        case .contextCreated:
            break
        case .contextDestroyed:
            // A JS reload replaced the context — mark it inline (logs keep flowing).
            enqueue(.notice("App reloaded — JS context replaced."))
        case let .closed(_, takeover):
            // The discovery loop reconnects (device id, then app id) within
            // ~2s; the status badge shows "Searching…" meanwhile. No feed
            // notice, so a flapping connection doesn't spam. Drop any pending
            // welcome — the reconnect schedules a fresh one. The exception:
            // another debugger took the app over — reconnecting would kick it
            // straight back off, so stand down and say so instead.
            welcomeTask?.cancel()
            welcomeTask = nil
            connectedTarget = nil
            if takeover {
                autoReconnectSuspended = true
                phase = .targetsAvailable
                append(.notice(
                    "Another debugger (React Native DevTools?) took over this app. "
                        + "Pick the target above to reconnect here."
                ))
            } else {
                phase = .searching
            }
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

    /// A bounded, ordered snapshot tree for expanding an object. Uses
    /// `callFunctionOn` (returns a string) rather than `getProperties`, whose
    /// native converter crashes Hermes on some object graphs (e.g. a large
    /// array). The tree is rendered client-side, so expansion never touches the
    /// device again.
    func snapshot(of objectId: String) async -> SnapNode? {
        guard let json = await cdp.snapshotJSON(objectId: objectId) else { return nil }
        return SnapNode.parse(json)
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
        preferredAppId = nil
        autoReconnectSuspended = false
        resetWelcome()
        targets = []
        // Sightings from the old port say nothing about the new one.
        targetStability = TargetStabilityTracker()
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

    /// Reload the app's JS bundle: `Page.reload` over the live CDP socket —
    /// what React Native DevTools' ⌘R sends, handled natively by the app's
    /// inspector integration. Runtimes without native reload support answer
    /// with an error; fall back to the dev-menu double-R keyevent then.
    func reloadJS() {
        guard isConnected else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await cdp.reloadPage()
            } catch {
                await reloadViaKeyevent()
            }
        }
    }

    private func reloadViaKeyevent() async {
        let serials = serials
        guard !serials.isEmpty else {
            app?.showToast(Toast(message: "Reload failed — the runtime didn't accept Page.reload.", ok: false))
            return
        }
        await CommandLog.userInitiated {
            for serial in serials {
                _ = try? await adb.run(on: serial, ["shell", "input", "keyevent", "46", "46"])
            }
        }
    }

    /// Force-stop and relaunch the app under debug. While connected the app is
    /// auto-detected: the target's `appId` (the application id Metro reports
    /// for the exact app being debugged), else the user's last manual pick,
    /// else the selected bundle. Disconnected — or when detection/relaunch
    /// fails — the installed-apps picker opens instead. Discovery reconnects
    /// by logical-device id once the app is back.
    func restartApp(clearing scope: RestartClearScope? = nil) {
        Task { [weak self] in await self?.performRestart(clearing: scope) }
    }

    /// Drives the fallback installed-apps picker sheet.
    var restartPickerVisible = false
    /// The user's manual pick from the restart sheet, reused on later restarts
    /// whenever the connected target doesn't report its own `appId`.
    private var manualRestartPackage: String?
    /// What the restart currently in flight (including one waiting on the
    /// fallback picker) should clear first, if anything.
    private var pendingClear: RestartClearScope?

    private func performRestart(clearing scope: RestartClearScope?) async {
        pendingClear = scope
        guard !serials.isEmpty else {
            app?.showToast(Toast(message: "Can't restart — no device selected.", ok: false))
            return
        }
        // Disconnected: no target reports an appId, and guessing from a stale
        // pick or the selected bundle could restart the wrong app — ask.
        let detected: String? = isConnected
            ? connectedTarget?.appId ?? manualRestartPackage ?? app?.selectedBundle?.packageId
            : nil
        if let detected, await restart(package: detected, clearing: scope) { return }
        restartPickerVisible = true
    }

    /// A pick from the fallback sheet: restart it and remember the choice.
    func restartPicked(_ package: String) {
        manualRestartPackage = package
        let scope = pendingClear
        Task { [weak self] in
            guard let self else { return }
            if !(await restart(package: package, clearing: scope)) {
                app?.showToast(Toast(
                    message: "Couldn't relaunch \(package) — is it installed on the selected device?",
                    ok: false
                ))
            }
        }
    }

    /// Force-stop + relaunch on every target device (the service's `.restart`
    /// verb), optionally clearing the app's cache (`pm clear --cache-only`,
    /// Android 14+ — best-effort, bounded) or its whole data (`pm clear`)
    /// first — the restart proceeds either way, and the toast reports what the
    /// clear did. True when any relaunch worked (failures fall back to the
    /// picker).
    private func restart(package: String, clearing scope: RestartClearScope?) async -> Bool {
        let serials = serials
        let control = AppControlService(client: adb)
        let (relaunched, cleared) = await CommandLog.userInitiated {
            var relaunched = 0
            var cleared = true
            for serial in serials {
                if let scope, !(await control.clear(scope, serial: serial, package: package)) {
                    cleared = false
                }
                if let result = try? await control.control(serial: serial, packageId: package, action: .restart),
                   result.ok {
                    relaunched += 1
                }
            }
            return (relaunched, cleared)
        }
        guard relaunched > 0 else { return false }
        let message = switch scope {
        case nil: "Restarting \(package)…"
        case .cache:
            cleared
                ? "Cleared cache — restarting \(package)…"
                : "Cache clear didn't finish — restarting \(package)…"
        case .data:
            cleared
                ? "Cleared data — restarting \(package)…"
                : "Data clear failed — restarting \(package)…"
        }
        app?.showToast(Toast(message: message, ok: true))
        return true
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
        PerfLog.measure(PerfLog.console, "refilter \(buffer.filtered.count) entries") {
            buffer.refilter(isIncluded: activeFilter)
        }
        rebuildFindMatches()
    }

    private func rebuildFindMatches() {
        let query = ConsoleQuery(findText)
        guard !query.isEmpty else {
            if !findMatchIDs.isEmpty { findMatchIDs = [] }
            return
        }
        findMatchIDs = PerfLog.measure(PerfLog.console, "find scan over \(buffer.filtered.count) entries") {
            let ids = buffer.filtered
                .filter { query.matches($0.searchableText) }
                .map(\.id)
            // Match order follows the display order, so ⏎/⇧⏎ walk down/up the
            // feed regardless of which end is newest.
            return newestFirst ? ids.reversed() : ids
        }
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
        PerfLog.measure(PerfLog.console, "flush \(batch.count) entries into \(buffer.filtered.count)") {
            appendEntries(batch)
        }
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
    /// DevTools". Once per app.
    private func scheduleWelcome(label: String, generation: Int) {
        welcomeTask?.cancel()
        welcomeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.waitForReplayToSettle()
            guard !Task.isCancelled, generation == self.connectGeneration, self.connectedTarget != nil else { return }
            self.hasWelcomed = true
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
    /// Measured connection-bar width — below ~640pt (a narrow split pane)
    /// the bar reflows to two rows instead of squeezing its labels.
    @State private var connectionBarWidth: CGFloat = 0
    @State private var inputHeight: CGFloat = 26
    @State private var showLevels = false
    /// The "Clear data and restart" confirmation (it signs the user out).
    @State private var confirmClearDataRestart = false
    @FocusState private var findFocused: Bool
    /// This tab stays mounted when the user switches away (see `TabHostView`).
    /// The input is a bare `NSTextView`, which `installFocusRelease` can't
    /// resign, so it hands this down to relinquish first responder when hidden.
    @Environment(\.tabIsActive) private var tabIsActive

    private var session: JSConsoleSession { state.jsConsoleSession }

    /// The filter row earns its space once the console is live or already holds
    /// output. Gated on the *unfiltered* buffer (`hasEntries`), so an active
    /// filter that hides every row can't strand the user with no way to clear it.
    private var showFilterBar: Bool {
        session.isConnected || session.hasEntries
    }

    var body: some View {
        VStack(spacing: 0) {
            connectionBar
            Divider()
            // The filter / levels / find / clear row is only useful once there's
            // something in the console. While it's waiting for a target with an
            // empty buffer, hide it (and the find bar it opens) — the connection
            // bar above stays so the target can still be chosen.
            if showFilterBar {
                filterBar
                Divider()
                if session.findVisible {
                    findBar
                    Divider()
                }
            }
            logArea
            Divider()
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { session.viewAppeared(serials: state.targetSerials) }
        // Fires on a real unmount: tab closed, or the tab MOVED between split
        // panes (a remount — the attach count and its deferred zero-check in
        // the session keep the connection alive through that). AppState also
        // stops the session on tab/window close; every path is idempotent.
        .onDisappear { session.viewDisappeared() }
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
            Text(session.findCountLabel).font(.app(.caption).monospacedDigit()).foregroundStyle(.secondary).fixedSize()
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

    /// One row when it fits; in a narrow split pane the fixed-size status and
    /// target picker squeezed the port label into a mid-word wrap and the
    /// buttons into truncated stubs — below the threshold the bar reflows to
    /// two rows instead. Width is measured (flexible fields make ViewThatFits
    /// unreliable).
    private var connectionBar: some View {
        @Bindable var session = state.jsConsoleSession
        return Group {
            if connectionBarWidth > 0, connectionBarWidth < 640 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        statusBadge
                        Spacer(minLength: 8)
                        portField
                    }
                    HStack(spacing: 10) {
                        targetPicker
                        Spacer(minLength: 8)
                        // At the 30% pane floor even the two-row bar can't
                        // afford button titles — icons + tooltips keep every
                        // action visible and clickable instead of ellipsized.
                        if connectionBarWidth < 500 {
                            connectionActions.labelStyle(.iconOnly)
                        } else {
                            connectionActions
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    statusBadge
                    targetPicker
                    portField
                    Spacer(minLength: 8)
                    connectionActions
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .measuringWidth(into: $connectionBarWidth)
        .sheet(isPresented: $session.restartPickerVisible) {
            RestartAppPickerSheet(serial: state.targetSerials.first) { package in
                session.restartPicked(package)
            }
        }
    }

    @ViewBuilder private var connectionActions: some View {
        let session = state.jsConsoleSession
        if session.isConnected {
            Button { session.reloadJS() } label: {
                Label("Reload JS", systemImage: "arrow.clockwise")
            }
            .help("Reload the JS bundle — what ⌘R in React Native DevTools does")
        }
        if !state.targetSerials.isEmpty {
            // A split button: the primary click restarts, the chevron reveals
            // the clearing variants — cache (pm clear --cache-only) or full
            // data (pm clear, behind a confirmation), then relaunch.
            Menu {
                Button {
                    session.restartApp(clearing: .cache)
                } label: {
                    Label("Clear cache and restart", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) {
                    confirmClearDataRestart = true
                } label: {
                    Label("Clear data and restart", systemImage: "trash")
                }
            } label: {
                Label("Restart app", systemImage: "restart.circle")
            } primaryAction: {
                session.restartApp()
            }
            .fixedSize()
            .help(session.isConnected
                ? "Force-stop and relaunch the connected app on the device"
                : "Pick an app to force-stop and relaunch")
            .confirmationDialog(
                "Clear all data for the app and restart? This signs you out and wipes local storage.",
                isPresented: $confirmClearDataRestart
            ) {
                Button("Clear Data & Restart", role: .destructive) {
                    session.restartApp(clearing: .data)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        if !state.targetSerials.isEmpty, !session.isConnected {
            Button {
                commitTypedPort()
                Task { await session.reverseMetro() }
            } label: {
                Label("adb reverse", systemImage: "arrow.left.arrow.right")
            }
            .help("Route the device's tcp:\(session.port) to Metro on your Mac (USB devices)")
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1)
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
            Text("Port").font(.app(.caption)).foregroundStyle(.secondary)
                .fixedSize()
            TextField("8081", text: $portText)
                .frame(width: 52)
                .multilineTextAlignment(.center)
                .onSubmit { commitTypedPort() }
                .help("Metro dev-server port — varies per app")
        }
    }

    /// Apply whatever's typed in the port field. Clicking a button doesn't
    /// fire the field's onSubmit, so "type a new port → adb reverse" would
    /// otherwise reverse the old port — the reverse buttons commit first.
    /// Unparseable text snaps the field back to the port actually in use, so
    /// the reverse never silently targets a port other than the one shown.
    private func commitTypedPort() {
        if let value = Int(portText) {
            session.setPort(value)
        } else {
            portText = String(session.port)
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
            Button {
                session.openFind()
                // Re-focus when the bar is already open — the onChange
                // focuser only fires on the closed→open transition. Deferred:
                // a synchronous @FocusState write doesn't take while another
                // field (e.g. the sidebar search) still holds focus.
                Task { @MainActor in findFocused = true }
            } label: { Image(systemName: "text.magnifyingglass") }
                .buttonStyle(IconButtonStyle())
                .help("Find & highlight in console (⌘F)")
                // Active-tab only — a hidden keep-alive tab winning ⌘F sends
                // the focus request into an invisible view and it falls
                // through to the sidebar search.
                .keyboardShortcut(state.activeTabID == "js-console"
                    ? KeyboardShortcut("f", modifiers: .command) : nil)
            Button { session.newestFirst.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                .buttonStyle(IconButtonStyle())
                .help(session.newestFirst
                    ? "Newest at top — click to show newest at bottom"
                    : "Newest at bottom — click to show newest at top")
            Menu {
                Button("Save as JSON…") { exportToFile() }
                Button("Copy to Clipboard") { exportToClipboard() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(IconButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Export the filtered console — save as a JSON file or copy to the clipboard")
            .disabled(session.filteredEntries.isEmpty)
            Button { session.clear() } label: { Image(systemName: "trash") }
                .buttonStyle(IconButtonStyle())
                .help("Clear the console")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: Export

    /// What Export writes: exactly the rows the feed is showing — the level
    /// and text filters apply, in display (chronological) order.
    private var exportJSON: String? {
        ConsoleExport.json(session.filteredEntries.map { entry in
            let (type, level): (String, String?) = switch entry.kind {
            case .input: ("input", nil)
            case .result: ("result", nil)
            case .evalError: ("error", nil)
            case .notice: ("notice", nil)
            case let .log(logLevel, _, _): ("log", logLevel.rawValue)
            }
            return ConsoleExportEntry(at: entry.at, type: type, level: level, text: jsEntryPlainText(entry.kind))
        })
    }

    private func exportToFile() {
        let count = session.filteredEntries.count
        guard let file = state.askSaveLocation(
            suggestedName: "js-console_\(ScreenCaptureService.stamp()).json"
        ) else { return }
        guard let json = exportJSON else {
            state.showToast(Toast(message: "Export failed: entries couldn't be encoded", ok: false))
            return
        }
        do {
            try Data(json.utf8).write(to: file)
            state.showToast(Toast(message: "Exported \(count) entries", ok: true, revealPath: file.path))
        } catch {
            state.showToast(Toast(message: "Export failed: \(error.localizedDescription)", ok: false))
        }
    }

    private func exportToClipboard() {
        let count = session.filteredEntries.count
        guard let json = exportJSON else {
            state.showToast(Toast(message: "Copy failed: entries couldn't be encoded", ok: false))
            return
        }
        copyToPasteboard(json)
        state.showToast(Toast(message: "Copied \(count) entries as JSON", ok: true))
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
                Image(systemName: "chevron.down").font(.app(size: 9, weight: .semibold))
            }
            .font(.app(.caption))
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
            Text("Show levels").font(.app(.caption).weight(.semibold)).foregroundStyle(.secondary)
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
            .font(.app(.caption))
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
        // The Chrome-dark surface keeps its hue but joins the glass — the
        // card step, not full opacity, whenever the window is translucent.
        .background(JSConsoleFeedBackground())
        .environment(\.colorScheme, .dark)
        // Terminal convention for the linkified URLs in the rows: ⌘-click
        // opens the browser; a plain click stays inert so click-drag text
        // selection can't accidentally navigate away.
        .environment(\.openURL, OpenURLAction { _ in
            NSEvent.modifierFlags.contains(.command) ? .systemAction : .handled
        })
    }

    /// Chrome-style newest-at-bottom by default, flipped when the toolbar's
    /// reverse button turns `newestFirst` on. LogTailViewV2 tails the newest
    /// edge, pauses when the user scrolls off (new lines keep rendering without
    /// moving their reading), overlays the jump-to-top/bottom buttons, and
    /// drives the ⌘F match into view via `focusID`.
    @ViewBuilder
    private func scrollingLog(_ visible: [JSEntry]) -> some View {
        // No connection gate on the jump buttons: the buffer outlives the
        // connection, and scrolling those logs is exactly what a disconnected
        // session is for.
        if session.newestFirst {
            LogTailViewV2(entries: visible.reversed(), newestEdge: .top,
                          focusID: session.currentFindID) { jsRow($0) }
        } else {
            LogTailViewV2(entries: visible, newestEdge: .bottom,
                          focusID: session.currentFindID) { jsRow($0) }
        }
    }

    @ViewBuilder
    private func jsRow(_ entry: JSEntry) -> some View {
        let band = levelBand(entry)
        JSEntryRow(entry: entry, session: session)
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
                Button("Run adb reverse for the device") {
                    commitTypedPort()
                    Task { await session.reverseMetro() }
                }
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
        Droidective routes the device's port to Metro automatically (adb reverse); \
        the button below retries it. Targets appear automatically.
        """
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.app(.body, design: .monospaced))
                .foregroundStyle(session.isConnected ? Color.accentColor : .secondary)
                .padding(.bottom, 5)
            ZStack(alignment: .topLeading) {
                if input.isEmpty {
                    Text("Evaluate JavaScript…  (⇧⏎ for a new line)")
                        .font(.app(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                JSCodeEditor(
                    text: $input,
                    height: $inputHeight,
                    isActive: tabIsActive,
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
    @State private var hovering = false
    @State private var copied = false
    /// Bumped by a click anywhere on the row; the primary expandable value
    /// observes it and toggles, so the whole row is the disclosure target —
    /// not just the value's own summary line.
    @State private var rowToggleToken = 0

    private var query: String { session.findText.trimmingCharacters(in: .whitespaces) }
    private var isCurrentFind: Bool { session.findVisible && session.currentFindID == entry.id }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            glyph
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            // Always in the layout — hidden, not removed, when idle — so
            // hovering can't change the row's width and reflow its text.
            copyButton
                .opacity(hovering || copied ? 1 : 0)
                .allowsHitTesting(hovering || copied)
            Text(entry.at, format: .dateTime.hour().minute().second())
                .font(.app(.caption2).monospacedDigit())
                .foregroundStyle(JSConsoleTheme.muted)
                .padding(.top, 1)
        }
        .contentShape(Rectangle())
        // Whitespace, glyph, and timestamp clicks toggle the row's expandable
        // value too (the value's own header still works). Text keeps its
        // selection gesture — this only catches clicks nothing else claims.
        .onTapGesture {
            if primaryObjectID != nil { rowToggleToken += 1 }
        }
        .onHover { hovering = $0 }
        // Hovering the row is what reveals its URLs' underlines.
        .environment(\.consoleLinkUnderline, hovering)
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

    /// Hover copy affordance (the Reactotron rows' pattern): copies the row's
    /// plain text with a checkmark flash; the right-click menu keeps the
    /// deep "Copy as JSON".
    private var copyButton: some View {
        Button {
            copyToPasteboard(jsEntryPlainText(entry.kind))
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.app(.caption))
                .foregroundStyle(copied ? .green : JSConsoleTheme.muted)
                // Fixed footprint for both glyphs, so neither hover nor the
                // copy→checkmark swap nudges the layout.
                .frame(width: 14)
        }
        .buttonStyle(.plain)
        .padding(.top, 1)
        .help("Copy this entry (right-click for JSON)")
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
            .font(.app(.caption))
            .foregroundStyle(style)
            .frame(width: 14)
            .padding(.top, 2)
    }

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case let .input(text):
            line(text, base: JSConsoleTheme.muted)
        case let .result(object):
            JSValueView(object: object, session: session, scrollTargetID: entry.id, toggleToken: rowToggleToken)
        case let .evalError(details):
            errorContent(details)
        case let .log(level, args, stack):
            logContent(level: level, args: args, stack: stack)
        case let .notice(text):
            line(text, base: JSConsoleTheme.muted)
        }
    }

    private func line(_ text: String, base: Color) -> some View {
        highlightedText(text, query: query, base: base, current: isCurrentFind, underlineLinks: hovering)
            .font(.app(.callout, design: .monospaced))
            .lineSpacing(2)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func logContent(level: JSLevel, args: [RemoteObject], stack: CDPStackTrace?) -> some View {
        let rows = argRows(args)
        // The row-level click toggles the first expandable object — the one
        // "Copy as JSON" also targets.
        let primaryRowID = rows.first { if case .object = $0.kind { true } else { false } }?.id
        return VStack(alignment: .leading, spacing: 3) {
            // Each expandable object renders exactly once, as its own disclosure
            // row in argument order — it used to appear twice (inline in the
            // message line AND repeated below), which doubled every logged object.
            // Scalar runs keep the level tint for errors/warnings and VSCode-style
            // syntax colors otherwise.
            ForEach(rows) { row in
                switch row.kind {
                case let .scalars(text, tokens):
                    if level == .error || level == .warning {
                        line(text, base: level.consoleTextColor)
                    } else {
                        coloredTokenText(tokens, query: query, current: isCurrentFind, underlineLinks: hovering)
                            .font(.app(.callout, design: .monospaced))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case let .object(arg):
                    JSValueView(
                        object: arg, session: session, scrollTargetID: entry.id,
                        toggleToken: row.id == primaryRowID ? rowToggleToken : 0
                    )
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
    /// The owning log row's id — set for a top-level object so expanding it
    /// scrolls that row's header into view instead of leaving the viewport at
    /// the object's end (the flipped-layout jump).
    var scrollTargetID: AnyHashable?
    /// Bumped by the owning row when the user clicks anywhere on it — the
    /// whole log row acts as this value's disclosure toggle.
    var toggleToken = 0
    @Environment(\.logTailScrollToHeader) private var scrollToHeader
    @Environment(\.logTailPauseFollow) private var pauseFollow
    @Environment(\.consoleLinkUnderline) private var underlineLinks
    @State private var expanded = false
    @State private var snapshot: SnapNode?
    @State private var failed = false
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
                    toggleExpanded()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.app(size: 10, weight: .bold))
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
            .onChange(of: toggleToken) { _, _ in toggleExpanded() }
        } else {
            summaryText
                .fixedSize(horizontal: false, vertical: true)
                .contextMenu { copyButtons }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleExpanded() {
        expanded.toggle()
        if expanded {
            // Expanding means the user is reading — pause tail-follow so
            // streaming lines can't scroll the object away (same affordances
            // as Reactotron: the jump button or scrolling back resumes).
            pauseFollow()
            if snapshot == nil, !loading { load() } else { scrollHeaderToTop() }
        }
    }

    private var summaryText: some View {
        coloredTokenText(object.tokens, query: query, current: false, underlineLinks: underlineLinks)
            .font(.app(.callout, design: .monospaced))
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
        } else if let snapshot {
            // An interactive tree rendered from a bounded snapshot fetched via
            // callFunctionOn (not getProperties, which crashes Hermes). All
            // further expansion is client-side over this snapshot — no more
            // device round-trips. The owning row scrolls its header to the top
            // on expand (see scrollHeaderToTop) so the object reads from its
            // start rather than the feed reflowing to its end.
            ExpandedTree(node: snapshot, session: session)
        } else if failed {
            Text("Couldn't read this value.").font(.app(.caption)).foregroundStyle(.tertiary)
        }
    }

    private func load() {
        guard let objectId = object.objectId else { return }
        loading = true
        Task {
            let node = await session.snapshot(of: objectId)
            snapshot = node
            failed = node == nil
            loading = false
            if node != nil { scrollHeaderToTop() }
        }
    }

    /// Bring the object's header to the top after expanding. The child rows
    /// aren't lazy, so a big object takes a few frames to lay out; re-issue the
    /// scroll over a short window so it lands on the settled position, not an
    /// early estimate (which left the viewport at the object's end).
    private func scrollHeaderToTop() {
        guard let id = scrollTargetID else { return }
        Task {
            for delay in [30, 120, 260] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard expanded else { return }
                scrollToHeader(id)
            }
        }
    }
}

// MARK: - Snapshot tree (client-side, no getProperties)

/// An expanded object/array: a "find in object" field over the tree, rendered
/// inline (the feed grows to fit — no nested scroll). Typing shows a clickable
/// result list (`SnapNode.findMatches`, pure in ADBKit); clicking a result
/// expands the tree along its path and highlights the node in place. The
/// scroll jump on expand is handled by the owning row scrolling its header
/// into view.
private struct ExpandedTree: View {
    let node: SnapNode
    let session: JSConsoleSession
    @State private var search = ""
    /// Ordinal paths ("0/3/1") of the containers currently open — hoisted here
    /// so a clicked find result can expand its whole ancestor chain.
    @State private var expandedPaths: Set<String> = []
    /// The last revealed find result, tinted until the next find/reveal.
    @State private var highlightedPath: String?

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        VStack(alignment: .leading, spacing: 4) {
            SearchField(prompt: "Find in object…", text: $search)
                .controlSize(.small)
                .frame(maxWidth: 260)
            if query.isEmpty {
                SnapChildrenView(
                    node: node, session: session, path: "",
                    expandedPaths: $expandedPaths, highlightedPath: highlightedPath
                )
            } else {
                SnapMatchList(matches: node.findMatches(query: query), onSelect: reveal)
            }
        }
        // A newly typed query drops the previous reveal's tint (reveal itself
        // clears the field, so its own highlight survives this).
        .onChange(of: search) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespaces).isEmpty { highlightedPath = nil }
        }
    }

    /// Open every container down to the match, mark it, and swap back to the
    /// tree so the user lands on the node.
    private func reveal(_ match: TreeMatch) {
        var path = ""
        for index in match.path {
            path = path.isEmpty ? String(index) : "\(path)/\(index)"
            expandedPaths.insert(path)
        }
        highlightedPath = path
        search = ""
    }
}

/// The clickable results of a find inside one object — location, then value.
private struct SnapMatchList: View {
    let matches: [TreeMatch]
    let onSelect: (TreeMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if matches.isEmpty {
                Text("No matches").font(.app(.caption)).foregroundStyle(.tertiary)
            }
            ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                Button {
                    onSelect(match)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.app(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text("\(match.displayPath):")
                            .font(.app(.callout, design: .monospaced))
                            .foregroundStyle(jsColor(.key))
                        Text(match.preview)
                            .font(.app(.callout, design: .monospaced))
                            .foregroundStyle(jsColor(match.isContainer ? .className : .plain))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reveal in the tree")
            }
            if matches.count >= 200 {
                Text("…first 200 matches — narrow the search")
                    .font(.app(.caption)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The ordered child rows of a container `SnapNode` — array items with index
/// labels, or object entries with key labels. `path` is the container's own
/// ordinal path; expansion state lives in the owning `ExpandedTree` so find
/// results can drive it.
private struct SnapChildrenView: View {
    let node: SnapNode
    let session: JSConsoleSession
    let path: String
    @Binding var expandedPaths: Set<String>
    let highlightedPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if node.type == "array", let items = node.items {
                if items.isEmpty { emptyRow }
                ForEach(Array(items.enumerated()), id: \.offset) { index, child in
                    SnapValueView(
                        label: String(index), node: child, session: session,
                        path: childPath(index), expandedPaths: $expandedPaths,
                        highlightedPath: highlightedPath
                    )
                }
                if let hidden = node.hiddenCount, hidden > 0 { moreRow("…(+\(hidden) more)") }
            } else if let entries = node.entries {
                if entries.isEmpty { emptyRow }
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    SnapValueView(
                        label: entry.name, node: entry.node, session: session,
                        path: childPath(index), expandedPaths: $expandedPaths,
                        highlightedPath: highlightedPath
                    )
                }
                if node.truncated == true { moreRow("…(more)") }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func childPath(_ index: Int) -> String {
        path.isEmpty ? String(index) : "\(path)/\(index)"
    }

    private var emptyRow: some View {
        Text(node.type == "array" ? "(empty array)" : "(no enumerable properties)")
            .font(.app(.caption)).foregroundStyle(.tertiary)
    }

    private func moreRow(_ text: String) -> some View {
        Text(text).font(.app(.caption)).foregroundStyle(.tertiary)
    }
}

/// One row in the snapshot tree: a primitive `key: value`, or a collapsible
/// container header whose children (another `SnapChildrenView`) indent below.
/// The row revealed by a find result carries a highlight tint.
private struct SnapValueView: View {
    let label: String?
    let node: SnapNode
    let session: JSConsoleSession
    let path: String
    @Binding var expandedPaths: Set<String>
    let highlightedPath: String?
    @Environment(\.logTailPauseFollow) private var pauseFollow
    @Environment(\.consoleLinkUnderline) private var underlineLinks

    /// Text highlighted in rows: the ⌘F find query.
    private var highlight: String { session.findText.trimmingCharacters(in: .whitespaces) }
    private var isOpen: Bool { expandedPaths.contains(path) }
    private var isRevealed: Bool { path == highlightedPath }

    var body: some View {
        if node.isContainer {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if isOpen {
                        expandedPaths.remove(path)
                    } else {
                        expandedPaths.insert(path)
                        // Reading a nested node is still reading — keep the
                        // feed from scrolling it away.
                        pauseFollow()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.app(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        labelText
                        highlightedText(node.containerSummary, query: highlight, base: jsColor(.className))
                            .font(.app(.callout, design: .monospaced))
                    }
                    .contentShape(Rectangle())
                    .background(revealTint)
                }
                .buttonStyle(.plain)
                if isOpen {
                    SnapChildrenView(
                        node: node, session: session, path: path,
                        expandedPaths: $expandedPaths, highlightedPath: highlightedPath
                    )
                    .padding(.leading, 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                labelText
                highlightedText(
                    node.primitivePreview, query: highlight, base: jsColor(kind),
                    underlineLinks: underlineLinks
                )
                .font(.app(.callout, design: .monospaced))
                .textSelection(.enabled)
            }
            .background(revealTint)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var revealTint: some View {
        if isRevealed {
            RoundedRectangle(cornerRadius: 3).fill(JSConsoleTheme.findMatch.opacity(0.22))
        }
    }

    @ViewBuilder private var labelText: some View {
        if let label {
            highlightedText("\(label):", query: highlight, base: jsColor(.key))
                .font(.app(.callout, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var kind: JSTokenKind {
        switch node.type {
        case "string": return .string
        case "number", "bigint": return .number
        case "boolean": return .boolean
        case "null": return .null
        case "undefined": return .undefined
        case "function": return .function
        case "symbol": return .symbol
        default: return .plain
        }
    }
}

private struct StackView: View {
    let stack: CDPStackTrace

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(stack.callFrames.prefix(8)) { frame in
                Text(frame.display)
                    .font(.app(.caption2).monospaced())
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
    var isActive: Bool
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
        // The tab went to the background but stays mounted (TabHostView), and a
        // standalone NSTextView isn't a field editor, so nothing else resigns it
        // — leaving it first responder means every keystroke lands in this hidden
        // input while the visible pane looks keyboard-dead. Hand focus back to the
        // window. Deferred so we never touch first responder during a view update.
        if !isActive, let window = textView.window, window.firstResponder === textView {
            Task { @MainActor in
                if window.firstResponder === textView { window.makeFirstResponder(nil) }
            }
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

/// The most characters one console text block renders. A `console.log` of a
/// multi-megabyte string otherwise becomes a `Text` whose layout stalls the
/// app for seconds and skews the lazy feed's height estimates into a huge
/// blank scroll canvas (the "empty space, then logs, then a hang" report).
/// Copy paths keep the untruncated value; the cutoff note says what's hidden.
let jsDisplayCharacterLimit = 10_000

private func jsTruncationNote(hiddenCharacters: Int) -> AttributedString {
    var note = AttributedString("  …(+\(hiddenCharacters) more characters — truncated for display)")
    note.foregroundColor = JSConsoleTheme.muted
    return note
}

/// Whether detected URLs in console text draw their underline — set true by
/// the hovered row, so links read as plain text until pointed at.
private struct ConsoleLinkUnderlineKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var consoleLinkUnderline: Bool {
        get { self[ConsoleLinkUnderlineKey.self] }
        set { self[ConsoleLinkUnderlineKey.self] = newValue }
    }
}

/// Syntax-colored `Text` for a value's tokens, with find matches highlighted
/// and http(s) URLs linkified. Bounded to `jsDisplayCharacterLimit` characters.
func coloredTokenText(_ tokens: [JSToken], query: String, current: Bool, underlineLinks: Bool = false) -> Text {
    var attr = AttributedString()
    var remaining = jsDisplayCharacterLimit
    var hidden = 0
    for token in tokens {
        // utf8.count is O(1) on native strings; .count would re-walk a 3MB
        // token's characters on every render just to size the note.
        let tokenLength = token.text.utf8.count
        guard remaining > 0 else { hidden += tokenLength; continue }
        let piece = tokenLength <= remaining ? token.text : String(token.text.prefix(remaining))
        hidden += tokenLength - piece.utf8.count
        remaining -= piece.utf8.count
        var segment = AttributedString(piece)
        segment.foregroundColor = jsColor(token.kind)
        attr += segment
    }
    if hidden > 0 {
        PerfLog.console.warning("row render truncated: \(hidden, privacy: .public) chars over the display cap")
        attr += jsTruncationNote(hiddenCharacters: hidden)
    }
    applyFindHighlight(&attr, query: query, current: current)
    applyLinkAttributes(&attr, underlined: underlineLinks)
    return Text(attr)
}

/// A single-color `Text` (input/notice/error lines) with find matches
/// highlighted and http(s) URLs linkified. Bounded to
/// `jsDisplayCharacterLimit` characters.
func highlightedText(
    _ string: String, query: String, base: Color, current: Bool = false, underlineLinks: Bool = false
) -> Text {
    var attr = AttributedString(String(string.prefix(jsDisplayCharacterLimit)))
    attr.foregroundColor = base
    let hidden = string.utf8.count - jsDisplayCharacterLimit
    if hidden > 0 {
        PerfLog.console.warning("line render truncated: \(hidden, privacy: .public) chars over the display cap")
        attr += jsTruncationNote(hiddenCharacters: hidden)
    }
    applyFindHighlight(&attr, query: query, current: current)
    applyLinkAttributes(&attr, underlined: underlineLinks)
    return Text(attr)
}

/// Attach `.link` to http(s) URLs — underlined only while the owning row is
/// hovered (`underlined`), so a URL-heavy feed doesn't read as a wall of
/// underlines — letting the console's ⌘-click `openURL` gate send them to the
/// browser. Detection — including the explicit-scheme guard and the
/// UTF-16 → Character offset mapping — is `ConsoleLinkDetector` (pure, tested
/// in ADBKit); this only applies the SwiftUI attributes at the returned
/// offsets.
func applyLinkAttributes(_ attr: inout AttributedString, underlined: Bool) {
    let plain = String(attr.characters)
    for span in ConsoleLinkDetector.linkSpans(in: plain) {
        let lower = attr.index(attr.startIndex, offsetByCharacters: span.start)
        let upper = attr.index(lower, offsetByCharacters: span.count)
        attr[lower ..< upper].link = span.url
        if underlined {
            attr[lower ..< upper].swiftUI.underlineStyle = .single
        }
    }
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

/// The console feed's fill: the Chrome-dark theme color at the card step
/// while the window is glass, exactly the themed opaque surface otherwise.
private struct JSConsoleFeedBackground: View {
    @Environment(\.windowOpacity) private var windowOpacity

    var body: some View {
        JSConsoleTheme.background.opacity(WindowEffects.cardAlpha(root: windowOpacity))
    }
}
