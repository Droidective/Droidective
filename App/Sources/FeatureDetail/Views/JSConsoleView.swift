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

/// Where a row sits in the `console.group` nesting: how far it indents, which
/// headers it hangs under (so collapsing one hides exactly its block), and
/// whether it *is* a header. Everything the console says on its own — input,
/// results, notices — sits at the top level.
struct JSGroupSlot: Equatable {
    var depth = 0
    var path: [Int] = []
    var isHeader = false

    /// Whether any of the enclosing headers is collapsed, i.e. this row is
    /// inside a folded block.
    func isHidden(by collapsed: Set<Int>) -> Bool {
        !collapsed.isEmpty && path.contains(where: collapsed.contains)
    }
}

/// One line in the console feed.
struct JSEntry: Identifiable {
    enum Kind {
        case input(String)
        case result(RemoteObject)
        case evalError(ExceptionDetails)
        /// `isTable` marks a `console.table` call, which Chrome draws as a grid
        /// over the argument rather than as its one-line preview.
        case log(level: JSLevel, args: [RemoteObject], stack: CDPStackTrace?, isTable: Bool = false)
        case notice(String)
    }

    let id: Int
    let kind: Kind
    let at: Date
    let group: JSGroupSlot
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

    /// The call stack of the `console.*` call behind this row, when there is
    /// one — what the source label at the right edge is resolved from.
    var stack: CDPStackTrace? {
        switch kind {
        case let .log(_, _, stack, _): stack
        case let .evalError(details): details.stackTrace
        default: nil
        }
    }

    init(id: Int, kind: Kind, at: Date, group: JSGroupSlot = JSGroupSlot()) {
        self.id = id
        self.kind = kind
        self.at = at
        self.group = group
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
        case let .log(_, args, _, _):
            var out = ""
            for arg in args {
                let remaining = limit - out.utf8.count
                guard remaining > 0 else { break }
                if !out.isEmpty { out += " " }
                // The console-argument rendering, so the filter matches the
                // unquoted text a log row actually shows.
                out += arg.inlineSummary(limit: remaining, style: .consoleArgument)
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
        case let .log(_, args, _, _): args.reduce(256) { $0 + $1.approximateBytes }
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
    // would otherwise retain gigabytes. Shared with the pending early-flush
    // bound so the two can't drift apart when retuned.
    private static let bufferByteBudget = 128 << 20
    private var buffer = FilteredLogBuffer<JSEntry>(
        capacity: JSConsoleSession.maxEntries,
        byteBudget: JSConsoleSession.bufferByteBudget,
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
    /// Entry ids of the `console.group` headers currently folded — every row
    /// naming one in its path is hidden, which is how Chrome's collapsed groups
    /// (and `console.groupCollapsed`) behave.
    private(set) var collapsedGroups: Set<Int> = [] {
        didSet { if collapsedGroups != oldValue { refilter() } }
    }
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
    /// Which mounted views can see the feed — per window, but a split shows it
    /// in both panes, so this is an audience rather than a flag
    /// (`FeedAudience`). Distinct from `attachedViews`, which is about keeping
    /// the *connection* alive: a hidden tab stays attached and streaming, it
    /// just stops paying for layout nobody is reading.
    @ObservationIgnored private var audience = FeedAudience()
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
    /// The running `console.group` nesting the incoming stream is inside.
    @ObservationIgnored private var groups = ConsoleGroupTracker()
    /// Resolves a row's bundle coordinates to the file the developer wrote, for
    /// the source label at the right edge. Rebuilt whenever the Metro port
    /// changes — its cache belongs to one dev server.
    @ObservationIgnored private var symbolicator = MetroSymbolicator()
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
        let resolvedPort = (1 ... 65535).contains(savedPort) ? savedPort : 8081
        port = resolvedPort
        symbolicator = MetroSymbolicator(port: resolvedPort)
        newestFirst = UserDefaults.standard.bool(forKey: Self.newestFirstKey)
    }

    /// Fold or unfold a `console.group` block from its header row.
    func toggleGroup(_ id: Int) {
        if collapsedGroups.contains(id) {
            collapsedGroups.remove(id)
        } else {
            collapsedGroups.insert(id)
        }
    }

    func isGroupCollapsed(_ id: Int) -> Bool { collapsedGroups.contains(id) }

    /// Where a row's `console.*` call was made, for the source label Chrome
    /// prints at the right edge. Resolved lazily by the row that's on screen —
    /// the feed never pays for rows nobody is looking at — and cached in the
    /// symbolicator, so scrolling back over a row costs nothing.
    func symbolicated(_ stack: CDPStackTrace?) async -> [SymbolicatedFrame] {
        guard let stack else { return [] }
        return await symbolicator.symbolicate(stack.callFrames)
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
        // The session outlives its views (AppState parks the workspace on a
        // background-mode close), so forget the audience with it — a viewer
        // left behind here would price the feed as watched for the rest of the
        // session. Views re-report on their next appearance.
        audience.removeAll()
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
            publishDiagnostics()
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
        // Session over — a later hang must not read as "the console did it".
        Telemetry.shared.setDiagnosticContext("js_console", nil)
        Telemetry.shared.breadcrumb(category: "js-console", "session stopped")
        publishedDiagnostics = nil
    }

    // MARK: Diagnostics

    /// The last stream shape shipped to telemetry, so re-publishing only
    /// happens on change (each publish crosses both SDKs).
    private struct StreamDiagnostics: Equatable {
        var connected: Bool
        /// Buffered entries, rounded to hundreds — precision isn't the point.
        var bufferedEntries: Int
        /// Ingest rate over the last pass, bucketed to its decade so a noisy
        /// stream doesn't re-publish every 2 s.
        var ingestPerMinute: Int
    }

    @ObservationIgnored private var publishedDiagnostics: StreamDiagnostics?
    @ObservationIgnored private var lastRateCount = 0
    @ObservationIgnored private var lastRateTime = ContinuousClock.now

    /// Ship the stream's shape as always-on diagnostic context (a Sentry
    /// context + PostHog super-properties), so any hang/crash/perf event that
    /// fires carries "what the console was doing" — the missing fact when
    /// diagnosing the 3.7.0 hang burst from telemetry alone. Runs on the 2 s
    /// discovery pass; publishes only when a bucketed value changes.
    private func publishDiagnostics() {
        let now = ContinuousClock.now
        let elapsed = lastRateTime.duration(to: now)
        let seconds = max(0.001, Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) * 1e-18)
        let perMinute = Double(receivedCount - lastRateCount) / seconds * 60
        lastRateCount = receivedCount
        lastRateTime = now
        let snapshot = StreamDiagnostics(
            connected: isConnected,
            bufferedEntries: (buffer.entries.count / 100) * 100,
            ingestPerMinute: ConsoleRateBucket.decade(perMinute)
        )
        guard snapshot != publishedDiagnostics else { return }
        if ConsoleRateBucket.isBurst(
            from: publishedDiagnostics?.ingestPerMinute, to: snapshot.ingestPerMinute
        ) {
            Telemetry.shared.breadcrumb(
                category: "js-console", "stream burst: ~\(snapshot.ingestPerMinute)/min")
        }
        publishedDiagnostics = snapshot
        Telemetry.shared.setDiagnosticContext("js_console", [
            "connected": snapshot.connected,
            "buffered_entries": snapshot.bufferedEntries,
            "ingest_per_min": snapshot.ingestPerMinute,
        ])
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
            // A new stream starts outside every group the old one left open.
            groups.reset()
            // No target identity in the crumb — bundle ids stay out of
            // telemetry (the Settings ▸ Privacy promise).
            Telemetry.shared.breadcrumb(category: "js-console", "connected to a Hermes target")
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
            switch groups.placement(for: call.type, id: nextEntryId) {
            case .groupEnd:
                // `console.groupEnd` closes the block and shows nothing — a row
                // for it is the empty line that used to trail every group.
                return
            case let .entry(depth, path):
                enqueue(
                    .log(
                        level: JSLevel(consoleType: call.type), args: call.args,
                        stack: call.stackTrace, isTable: call.type == "table"
                    ),
                    group: JSGroupSlot(depth: depth, path: path)
                )
            case let .groupStart(depth, path, collapsed):
                if collapsed { collapsedGroups.insert(nextEntryId) }
                enqueue(
                    .log(level: JSLevel(consoleType: call.type), args: call.args, stack: call.stackTrace),
                    group: JSGroupSlot(depth: depth, path: path, isHeader: true)
                )
            }
        case let .exception(details, timestamp):
            guard replayGate.admit(timestamp) else { return }
            enqueue(.evalError(details), group: JSGroupSlot(depth: groups.depth, path: groups.open))
        case .contextCreated:
            break
        case .contextDestroyed:
            // A JS reload replaced the context — mark it inline (logs keep flowing).
            // The old context's unclosed groups went with it; leaving them open
            // would indent the whole next session under a group that's gone.
            groups.reset()
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
            Telemetry.shared.breadcrumb(
                category: "js-console", takeover ? "closed: debugger takeover" : "connection closed")
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

    /// Grids already built for `console.table` rows, keyed by entry. Rows are
    /// lazy, so without this every scroll back over a table would snapshot the
    /// value on the device again. Bounded — `console.table` is rare, and a feed
    /// full of them still can't grow this without limit.
    @ObservationIgnored private var tables: [Int: ConsoleTable] = [:]
    private static let maxCachedTables = 50

    /// The grid for a `console.table` row, snapshotted once per entry.
    func table(for entryID: Int, objectId: String) async -> ConsoleTable? {
        if let cached = tables[entryID] { return cached }
        guard let node = await snapshot(of: objectId), let table = ConsoleTable.from(node) else { return nil }
        if tables.count >= Self.maxCachedTables { tables.removeAll(keepingCapacity: true) }
        tables[entryID] = table
        return table
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
        // Sightings from the old port say nothing about the new one, and a
        // source map's line numbers belong to one dev server.
        targetStability = TargetStabilityTracker()
        symbolicator = MetroSymbolicator(port: newPort)
        groups.reset()
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
        let collapsed = collapsedGroups
        guard !query.isEmpty || !hidden.isEmpty || !collapsed.isEmpty else { return nil }
        return { entry in
            if entry.group.isHidden(by: collapsed) { return false }
            if case let .log(level, _, _, _) = entry.kind, hidden.contains(level) { return false }
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
    private func enqueue(_ kind: JSEntry.Kind, group: JSGroupSlot = JSGroupSlot()) {
        let entry = JSEntry(id: nextEntryId, kind: kind, at: Date(), group: group)
        pendingEntries.append(entry)
        pendingBytes += entry.approximateBytes
        nextEntryId += 1
        receivedCount += 1
        // A burst of huge payloads must not sit unrendered for a whole flush
        // window — flush early once pending holds a quarter of the buffer's
        // byte budget, so pending memory stays bounded at any cadence.
        if pendingBytes >= Self.bufferByteBudget / 4 {
            flushPending()
        } else {
            scheduleFlush()
        }
    }

    /// Bytes waiting in `pendingEntries`, for the early-flush bound.
    @ObservationIgnored private var pendingBytes = 0

    /// Flush pacing: each flush re-diffs the whole visible feed (a 2000-row
    /// ForEach), so the old 16 ms cadence meant up to 60 full diffs a second
    /// under a chatty Metro stream — the sustained main-thread churn behind
    /// the js-console hang cluster (Sentry DROIDECTIVE-MAC-2N and the 3.7.0
    /// hang burst; logcat shipped the same 300 ms fix in v3.6.1). Entries
    /// keep accumulating between flushes; only rendering is paced.
    ///
    /// The intervals moved to `FeedFlushCadence` when the Reactotron timeline
    /// turned out to have missed this fix entirely — the rule is shared so a
    /// feed cannot be added without it.
    private var flushInterval: Duration {
        // Visibility and main-thread load both feed the pace: a hidden tab
        // still lays out every row it flushes, and a thread already behind
        // must not be asked for a turn as often (`MainThreadLoad`).
        FeedFlushCadence.interval(
            appActive: NSApp.isActive,
            watched: audience.isWatched,
            lateness: MainThreadLoad.shared.lateness)
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        let interval = flushInterval
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: interval)
            guard let self, !Task.isCancelled else { return }
            self.flushPending()
        }
    }

    /// One view reported whether it can see the feed. Becoming visible flushes
    /// at once — the hidden pace is several seconds, and waiting it out would
    /// show a feed that looks stalled at the moment the user switched to it.
    func noteVisibility(view id: UUID, visible: Bool) {
        guard audience.update(view: id, visible: visible), visible else { return }
        flushPending()
    }

    private func flushPending() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingEntries.isEmpty else { return }
        let batch = pendingEntries
        pendingEntries.removeAll(keepingCapacity: true)
        pendingBytes = 0
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
        pendingBytes = 0
        buffer.removeAll()
        findMatchIDs = []
        tables.removeAll(keepingCapacity: true)
        // The headers those ids named are gone; a later group would otherwise
        // inherit a fold nobody asked for once ids wrap around a long session.
        collapsedGroups = []
        groups.reset()
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

/// The console feed's coordinate space: rows report their frames in it and a
/// drag reads them back to work out which rows it crossed.
let jsFeedSpace = "js-feed"

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
    /// Rows the reader picked out — ⌘-click one, ⇧-click a range, drag across
    /// them — so a handful of logs can be copied out of a streaming console.
    /// `RowSelection` in ADBKit holds the rules.
    @State private var selection = RowSelection<JSEntry.ID>()
    /// Each visible row's frame in the feed's space, for the drag's hit-testing.
    @State private var rowFrames = LogRowFrames<JSEntry.ID>()
    /// A sweep ends with a mouse-up that AppKit also delivers as a click; without
    /// this the row would read it as a plain click and drop the selection just
    /// made.
    @State private var suppressNextPlainClick = false
    /// The row a sweep started on, fixed when the button went down. Held as an
    /// *id*, not a y: this feed streams, so the row under a given y changes while
    /// the pointer is still held — which made a sweep start from whatever row had
    /// drifted under the press point.
    @State private var sweepAnchor: JSEntry.ID?
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
        // Separate from the attach count above: that keeps the *connection*
        // alive across a pane move, this only says whether anyone can see the
        // feed. A hidden tab keeps streaming and stops paying for layout.
        .reportsFeedVisibility { session.noteVisibility(view: $0, visible: $1) }
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
            Circle().fill(statusColor).frame(width: 8, height: 8).frame(width: 8)
            Text(statusText)
                .font(.app(.caption)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
        }
        // Deliberately NOT fixedSize. Nothing in this bar may demand more width
        // than the pane it sits in: an incompressible child sets the minimum for
        // the whole pane, every row below is then laid out at that width, and
        // the pane's clip cuts the lot — which reads as the tab beside it
        // covering the console.
        .layoutPriority(-1)
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
                // The middle goes first: an app id's tail and the device name
                // are what tell two targets apart.
                .truncationMode(.middle)
        }
        .menuStyle(.borderlessButton)
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
            if !selection.isEmpty {
                selectionControls(session.filteredEntries)
            }
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
        ConsoleExport.json(session.filteredEntries.map(exportEntry))
    }

    /// One entry in the export's shape — shared with copying a selection as JSON
    /// so both produce the same records.
    private func exportEntry(_ entry: JSEntry) -> ConsoleExportEntry {
        let (type, level): (String, String?) = switch entry.kind {
        case .input: ("input", nil)
        case .result: ("result", nil)
        case .evalError: ("error", nil)
        case .notice: ("notice", nil)
        case let .log(logLevel, _, _, _): ("log", logLevel.rawValue)
        }
        return ConsoleExportEntry(at: entry.at, type: type, level: level, text: jsEntryPlainText(entry.kind))
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
        feed(visible)
            // A drag has to know where every row is, and a row only knows its
            // own frame — they report into `rowFrames` in this space.
            .coordinateSpace(name: jsFeedSpace)
            // Behind the rows, purely to read the mouse: the console's lines are
            // selectable text end to end, so a SwiftUI gesture behind them never
            // gets the click (see `LogSelectionMouse`).
            .background(
                LogSelectionMouse(
                    isActive: tabIsActive,
                    onPress: { y in beginSweep(atY: y, in: visible) },
                    onClick: { y, click in clickRow(atY: y, in: visible, click: click) },
                    onSweep: { y, additive in sweep(toY: y, additive: additive, in: visible) },
                    onSweepEnd: { suppressNextPlainClick = true }
                )
            )
            // A selection over rows the feed no longer has (cleared, filtered
            // out, trimmed) would copy logs nobody can see. Keyed on the count,
            // not the ids: mapping 2000 ids per render is the kind of per-flush
            // allocation this console has been burned by before.
            .onChange(of: visible.count) { _, _ in
                guard !selection.isEmpty else { return }
                selection.retain(in: visible.map(\.id))
            }
    }

    @ViewBuilder
    private func feed(_ visible: [JSEntry]) -> some View {
        // No connection gate on the jump buttons: the buffer outlives the
        // connection, and scrolling those logs is exactly what a disconnected
        // session is for.
        if session.newestFirst {
            LogTailViewV2(entries: visible.reversed(), newestEdge: .top,
                          focusID: session.currentFindID) { jsRow($0, in: visible) }
        } else {
            LogTailViewV2(entries: visible, newestEdge: .bottom,
                          focusID: session.currentFindID) { jsRow($0, in: visible) }
        }
    }

    @ViewBuilder
    private func jsRow(_ entry: JSEntry, in visible: [JSEntry]) -> some View {
        let band = levelBand(entry)
        JSEntryRow(
            entry: entry, session: session,
            isSelected: selection.contains(entry.id),
            onSelect: { click in select(entry, in: visible, click: click) },
            onCopySelection: { copySelection(visible: visible, asJSON: $0) },
            selectionCount: selection.count
        )
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Selection wins over the level band: the reader is looking at what
            // they picked, and two washes stacked read as neither.
            .background(selection.contains(entry.id)
                ? Color.brandAccent.opacity(0.22)
                : (band?.fill ?? .clear))
            .reportingRowFrame(entry.id, in: jsFeedSpace, into: rowFrames)
            .overlay(alignment: .leading) {
                if let band { Rectangle().fill(band.rule).frame(width: 3) }
            }
        Divider().opacity(0.18)
    }

    /// Returns true when the pane took the click, so the row leaves its own
    /// behaviour (opening the first object) alone.
    private func select(_ entry: JSEntry, in visible: [JSEntry], click: LogRowClick) -> Bool {
        switch click {
        case .toggle:
            selection.toggle(entry.id)
            return true
        case .extend:
            selection.extend(to: entry.id, in: visible.map(\.id))
            return true
        case .plain:
            if suppressNextPlainClick {
                suppressNextPlainClick = false
                return true             // the click that ended a sweep
            }
            let had = !selection.isEmpty
            selection.clear()
            // Dropping a selection is itself what the click did; opening an
            // object on the way out would be a second, unasked-for action.
            return had
        }
    }

    /// A ⌘/⇧-click from the mouse monitor, which knows a y position rather than a
    /// row — resolve it through the same frames the sweep uses.
    private func clickRow(atY y: CGFloat, in visible: [JSEntry], click: LogRowClick) {
        let ids = visible.map(\.id)
        guard let id = rowFrames.row(at: y, among: ids),
              let entry = visible.first(where: { $0.id == id }) else { return }
        _ = select(entry, in: visible, click: click)
    }

    /// The button went down: fix the sweep's anchor row, and drop a suppression
    /// left over from a sweep whose closing click never landed on a row (it would
    /// otherwise eat this press's click).
    private func beginSweep(atY y: CGFloat, in visible: [JSEntry]) {
        sweepAnchor = rowFrames.row(at: y, among: visible.map(\.id))
        suppressNextPlainClick = false
    }

    /// The pointer moved while sweeping: the span runs from the anchor row to
    /// whatever row is under the pointer *now*.
    private func sweep(toY y: CGFloat, additive: Bool, in visible: [JSEntry]) {
        let ids = visible.map(\.id)
        guard let anchor = sweepAnchor, let end = rowFrames.row(at: y, among: ids) else { return }
        selection.select(from: anchor, to: end, in: ids, additive: additive)
    }

    /// Copy the picked rows. The text form resolves every object through the
    /// runtime (`jsEntryCompleteText`), because `{…}` is the one part of a
    /// pasted log nobody can act on; the JSON form matches Export.
    private func copySelection(visible: [JSEntry], asJSON: Bool) {
        let picked = Set(selection.ids)
        let entries = visible.filter { picked.contains($0.id) }
        guard !entries.isEmpty else { return }
        if asJSON {
            guard let json = ConsoleExport.json(entries.map(exportEntry)) else { return }
            copyToPasteboard(json)
            state.showToast(Toast(message: "Copied \(entries.count) logs as JSON", ok: true))
            return
        }
        Task {
            var lines: [String] = []
            for entry in entries {
                lines.append(await jsEntryCompleteText(entry, session: session))
            }
            copyToPasteboard(lines.joined(separator: "\n\n"))
            state.showToast(Toast(message: "Copied \(entries.count) logs", ok: true))
        }
    }

    @ViewBuilder
    private func selectionControls(_ visible: [JSEntry]) -> some View {
        Text("\(selection.count) selected")
            .font(.app(.caption))
            .foregroundStyle(.textMuted)
        Menu {
            Button("Copy") { copySelection(visible: visible, asJSON: false) }
            Button("Copy as JSON") { copySelection(visible: visible, asJSON: true) }
            Divider()
            Button("Deselect") { selection.clear() }
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(IconButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Copy the selected logs (⌘C) — ⌘-click to pick rows, ⇧-click or drag for a range")
        // ⌘C only while rows are picked, so it never shadows copying text out of
        // the input field, the filter, or an expanded value.
        Button("") { copySelection(visible: visible, asJSON: false) }
            .keyboardShortcut("c", modifiers: .command)
            .opacity(0)
            .frame(width: 0)
            .accessibilityHidden(true)
    }

    /// The Chrome-style row band (fill + left rule) for error and warning rows;
    /// nil for the levels that sit on the plain console surface.
    private func levelBand(_ entry: JSEntry) -> (fill: Color, rule: Color)? {
        switch entry.kind {
        case let .log(level, _, _, _): level.consoleBand
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
    // Log arguments copy the way they render — a `console.log('hi')` pasted
    // into an issue should read `hi`, not `'hi'`.
    case let .log(_, args, _, _): args.map { $0.inlineSummary(style: .consoleArgument) }.joined(separator: " ")
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
    var consoleLinkUnderline: Bool {
        get { self[ConsoleLinkUnderlineKey.self] }
        set { self[ConsoleLinkUnderlineKey.self] = newValue }
    }
}

/// Syntax-colored `Text` for a value's tokens, with find matches highlighted
/// and http(s) URLs linkified. Bounded to `jsDisplayCharacterLimit` characters.
@MainActor
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
@MainActor
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
/// offsets, and reads detection through `ConsoleLinkSpanMemo` so a row's
/// re-renders don't re-run `NSDataDetector` on unchanged text.
@MainActor
func applyLinkAttributes(_ attr: inout AttributedString, underlined: Bool) {
    let plain = String(attr.characters)
    for span in ConsoleLinkSpanMemo.spans(in: plain) {
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
