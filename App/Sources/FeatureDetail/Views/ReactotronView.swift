import ADBKit
import os
import SwiftUI

/// Whether the Reactotron server accepts clients from the local network (the
/// official desktop app's behavior — needed when the app's Metro bundle was
/// served over Wi-Fi/LAN, because the client dials the bundle's host, not
/// localhost). Defaults to on; Settings ▸ Privacy owns the toggle.
let reactotronAllowLANKey = "reactotronAllowLAN"

/// Missing key means the default: LAN allowed, like the official app.
func reactotronAllowsLAN() -> Bool {
    UserDefaults.standard.object(forKey: reactotronAllowLANKey) == nil
        || UserDefaults.standard.bool(forKey: reactotronAllowLANKey)
}

/// The live Reactotron session — server, adb-reverse tunnels, and the whole
/// timeline/state buffer. Owned by `AppState` (like `jsConsoleSession`) so it
/// survives leaving the feature: the user can keep events streaming in the
/// background and return to an intact timeline. The view is a thin renderer over
/// this; nothing here imports UI beyond `Color` used by the helper value types.
@MainActor
@Observable
final class ReactotronSession {
    /// Saved store snapshots kept per session — each is a full store copy, so
    /// the count is capped and the oldest drops first.
    static let maxSnapshots = 20

    fileprivate var items: [RtItem] = []
    /// Cumulative wire bytes of `items`, maintained alongside it so the byte
    /// budget doesn't re-sum the buffer on every append.
    private var itemsBytes = 0
    /// Timeline events received between flushes. Coalesced on a ~16ms timer so a
    /// chatty client (tens of events/sec) triggers one `items` mutation — and
    /// thus one SwiftUI invalidation — per frame, not one per event. Never
    /// observed, so appending to it doesn't re-render.
    @ObservationIgnored private var pendingItems: [RtItem] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    // Anonymous usage stats (numbers only, no payload contents) reported per
    // session so the timeline caps can be sized against real workloads.
    private var peakItemsBytes = 0
    private var peakItemCount = 0
    private var evictedItemCount = 0
    fileprivate var commands: [RegisteredCommand] = []
    fileprivate var connection: RtConnection = .idle
    fileprivate var connectedApp: String?
    fileprivate var clients: [ClientInfo] = []
    fileprivate var selectedClient: Int?
    fileprivate var subscriptionPaths: [String] = []
    fileprivate var subscriptionValues: [String: JSONValue] = [:]
    fileprivate var snapshots: [Snapshot] = []
    fileprivate var storeState: JSONValue?
    fileprivate var pendingSnapshot = false
    fileprivate var awaitingStateTree = false
    fileprivate var replNames: [String] = []
    fileprivate var replResultText: String?
    /// Per-serial `adb reverse` failures (serial → adb's reason), so a tunnel
    /// that never opened is a visible banner, not a silent "waiting" state.
    fileprivate var tunnelIssues: [String: String] = [:]

    private let client: AdbClient
    /// Back-reference for toasts and save dialogs; set right after init.
    weak var app: AppState?
    private var service: ReactotronService?
    private var consumeTask: Task<Void, Never>?
    /// Every serial a reverse tunnel was opened on this session — what stop()
    /// removes.
    private var reversedSerials: Set<String> = []
    /// The ready-Android serials last seen, so `deviceListChanged` reverses
    /// only serials that (re)appeared — not every device on every flicker.
    private var knownReadySerials: Set<String> = []

    /// True once the server is up — stays true after leaving the view when the
    /// user chose to keep the connection alive.
    var isRunning: Bool { service != nil }

    /// True when at least one app is connected — what makes "keep it running"
    /// worth asking about on the way out.
    var hasLiveConnection: Bool { isRunning && !clients.isEmpty }

    init(client: AdbClient) {
        self.client = client
    }

    fileprivate var displayedItems: [RtItem] {
        guard let selectedClient else { return items }
        return items.filter { $0.connectionId == selectedClient }
    }

    /// The serials worth an `adb reverse`: ready *Android* devices. iOS
    /// Simulators share the Mac's loopback and need no tunnel — and feeding
    /// their UDIDs to adb just produces "device not found" noise.
    var readyAndroidSerials: [String] {
        (app?.devices ?? [])
            .filter { $0.isReady && $0.platform == .android }
            .map(\.serial)
    }

    // MARK: - Lifecycle

    /// Start the server, or — if it's already running because the connection was
    /// kept alive — just re-apply the reverse so a re-entered view reconnects.
    func start(serials: [String]) async {
        if isRunning {
            await applyReverse(serials: serials)
            return
        }
        reset()
        await startServer(serials: serials)
    }

    /// Bring up the socket layer (server + tunnels) without touching buffered
    /// state — shared by a fresh start and the Settings network-scope restart.
    private func startServer(serials: [String]) async {
        let reactotron = ReactotronService(client: client, loopbackOnly: !reactotronAllowsLAN())
        service = reactotron
        guard let stream = try? await reactotron.start() else {
            connection = .failed("Couldn't start the Reactotron server.")
            service = nil
            return
        }
        connection = .listening
        await applyReverse(serials: serials)
        consumeTask = Task { [weak self] in
            for await event in stream {
                if Task.isCancelled { break }
                self?.handle(event)
            }
        }
    }

    func applyReverse(serials: [String]) async {
        guard let service else { return }
        // In the unified log next to the server's connection-drop lines, for
        // field diagnosis of tunnel/connection interactions.
        Logger(subsystem: "com.rohindh.droidective", category: "reactotron-session")
            .notice("applying adb reverse for \(serials.count) device(s)")
        reversedSerials.formUnion(serials)
        knownReadySerials.formUnion(serials)
        recordTunnelResults(await service.reverse(serials: serials))
    }

    /// Called from AppState on every device-list update, so tunnels recover
    /// even while this view is closed (a kept-alive session): replugging a
    /// device silently drops its reverse tunnels, so a serial that (re)appears
    /// gets a fresh `adb reverse`. Only *new* serials are reversed — a device
    /// flickering through states or a simulator booting doesn't re-bind the
    /// tunnels of already-connected devices.
    func deviceListChanged() {
        let current = Set(readyAndroidSerials)
        tunnelIssues = tunnelIssues.filter { current.contains($0.key) }
        guard isRunning else {
            knownReadySerials = current
            return
        }
        let added = current.subtracting(knownReadySerials)
        knownReadySerials = current
        guard !added.isEmpty else { return }
        Task { await applyReverse(serials: Array(added)) }
    }

    /// The Settings LAN toggle flipped: restart the socket layer with the new
    /// scope, keeping the buffered timeline. Connected apps are dropped and
    /// won't reconnect until reloaded — the Reactotron client has no retry.
    func networkScopeChanged() async {
        guard isRunning else { return }
        consumeTask?.cancel()
        consumeTask = nil
        let stopping = service
        service = nil
        await stopping?.stop(serials: Array(reversedSerials))
        reversedSerials.removeAll()
        clients.removeAll()
        selectedClient = nil
        commands.removeAll()
        await startServer(serials: readyAndroidSerials)
    }

    private func recordTunnelResults(_ results: [ReactotronService.ReverseResult]) {
        for result in results {
            tunnelIssues[result.serial] = result.ok ? nil : result.detail
        }
    }

    /// Tear down the server and tunnels and clear all buffered state.
    func stop() async {
        consumeTask?.cancel()
        consumeTask = nil
        let stopping = service
        let serials = Array(reversedSerials)
        service = nil
        await stopping?.stop(serials: serials)
        reset()
    }

    /// Stop on app termination, bounded so a hung adb can't freeze quit. The
    /// server socket is closed first inside `stop()`, so even if the reverse
    /// removal is cut short the port is already freed (and a stale tunnel is
    /// harmless — it clears on next launch / device disconnect).
    func stopForQuit() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.stop() }
            group.addTask { try? await Task.sleep(for: .seconds(2)) }
            await group.next()
            group.cancelAll()
        }
    }

    private func reset() {
        flushUsageStats()
        flushTask?.cancel()
        flushTask = nil
        pendingItems.removeAll()
        // The timeline/store graphs can be huge (gigabytes of nested JSON
        // payloads); hand them to a background task instead of freeing them
        // inline, which hangs the main thread for the whole release cascade.
        Self.discardInBackground((items, snapshots, storeState, subscriptionValues))
        items.removeAll()
        itemsBytes = 0
        commands.removeAll()
        subscriptionPaths.removeAll()
        subscriptionValues.removeAll()
        snapshots.removeAll()
        storeState = nil
        pendingSnapshot = false
        awaitingStateTree = false
        replNames.removeAll()
        replResultText = nil
        clients.removeAll()
        selectedClient = nil
        connectedApp = nil
        connection = .idle
        tunnelIssues.removeAll()
        reversedSerials.removeAll()
        knownReadySerials.removeAll()
    }

    // MARK: - Outbound

    /// Deliver a server→client frame to the selected app, or to every connected
    /// app when "All apps" is chosen, so multi-connection targeting stays
    /// consistent across commands, state, and REPL.
    private func sendToTarget(type: String, payload: JSONValue) async {
        if let selectedClient {
            await service?.send(type: type, payload: payload, toConnection: selectedClient)
        } else {
            await service?.broadcast(type: type, payload: payload)
        }
    }

    fileprivate func send(_ command: RegisteredCommand, args: [String: String]) {
        let argObject = Dictionary(
            uniqueKeysWithValues: command.args.map { ($0.name, JSONValue.string(args[$0.name] ?? "")) }
        )
        let payload = JSONValue.object(["command": .string(command.command), "args": .object(argObject)])
        Task {
            await sendToTarget(type: "custom", payload: payload)
            app?.showToast(Toast(message: "Sent “\(command.command)”", ok: true))
        }
    }

    func addSubscription(_ rawPath: String) {
        let path = rawPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, !subscriptionPaths.contains(path) else { return }
        subscriptionPaths.append(path)
        sendSubscriptions()
    }

    func removeSubscription(_ path: String) {
        subscriptionPaths.removeAll { $0 == path }
        subscriptionValues[path] = nil
        sendSubscriptions()
    }

    /// Send the current watch paths — to one connection (a client that just
    /// completed its handshake) or to the usual target selection.
    private func sendSubscriptions(to connectionId: Int? = nil) {
        let payload = JSONValue.object(["paths": .array(subscriptionPaths.map(JSONValue.string))])
        Task {
            if let connectionId {
                await service?.send(type: "state.values.subscribe", payload: payload, toConnection: connectionId)
            } else {
                await sendToTarget(type: "state.values.subscribe", payload: payload)
            }
        }
    }

    func dispatch(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let data = text.data(using: .utf8),
              let action = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            app?.showToast(Toast(message: "Invalid action JSON", ok: false))
            return
        }
        Task {
            await sendToTarget(type: "state.action.dispatch", payload: .object(["action": action]))
            app?.showToast(Toast(message: "Dispatched", ok: true))
        }
    }

    /// Pull the whole store. redux/mst reply to `state.backup.request` with
    /// `state.backup.response`, while a plain `state.values.request` (no path)
    /// returns the whole cleaned state inside a `state.keys.response` (redux) or
    /// `state.values.response` (mst). Ask for both and take whichever arrives; if
    /// neither does within a few seconds, the app has no store plugin wired.
    func loadStateTree() {
        awaitingStateTree = true
        Task {
            await sendToTarget(type: "state.values.request", payload: .object([:]))
            await sendToTarget(type: "state.backup.request", payload: .object([:]))
            try? await Task.sleep(for: .seconds(4))
            guard awaitingStateTree else { return }
            awaitingStateTree = false
            app?.showToast(Toast(
                message: "No state received — wire reactotron-redux or reactotron-mst into your store to browse it here.",
                ok: false
            ))
        }
    }

    func takeSnapshot() {
        pendingSnapshot = true
        Task {
            await sendToTarget(type: "state.backup.request", payload: .object([:]))
            // Mirror loadStateTree: if no store plugin replies, clear the pending
            // flag and report it — otherwise it stays pending forever and the next
            // unrelated backup response is silently captured as the snapshot.
            try? await Task.sleep(for: .seconds(4))
            guard pendingSnapshot else { return }
            pendingSnapshot = false
            app?.showToast(Toast(
                message: "No snapshot received — wire reactotron-redux or reactotron-mst into your store to snapshot it.",
                ok: false
            ))
        }
    }

    fileprivate func restore(_ snapshot: Snapshot) {
        Task {
            await sendToTarget(type: "state.restore.request", payload: .object(["state": snapshot.state]))
            app?.showToast(Toast(message: "Restored snapshot", ok: true))
        }
    }

    func sendReplLs() {
        Task { await sendToTarget(type: "repl.ls", payload: .null) }
    }

    func evalRepl(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespaces)
        Task { await sendToTarget(type: "repl.execute", payload: .string(code)) }
    }

    func reverseNow(serials: [String]) {
        guard !serials.isEmpty else {
            app?.showToast(Toast(message: "No Android device connected to reverse", ok: false))
            return
        }
        Task {
            guard let service else { return }
            reversedSerials.formUnion(serials)
            knownReadySerials.formUnion(serials)
            let results = await service.reverse(serials: serials)
            recordTunnelResults(results)
            let okCount = results.count(where: \.ok)
            if let failure = results.first(where: { !$0.ok }) {
                app?.showToast(Toast(
                    message: "reverse failed on \(failure.serial): "
                        + (failure.detail.isEmpty ? "unknown error" : failure.detail),
                    ok: false
                ))
            } else {
                app?.showToast(Toast(
                    message: "adb reverse tcp:9090 → \(okCount)/\(results.count) device(s) OK",
                    ok: true
                ))
            }
        }
    }

    func clearTimeline() {
        // Drop buffered-but-unflushed events too, or they'd reappear on the next
        // flush right after the user cleared the timeline.
        flushTask?.cancel()
        flushTask = nil
        pendingItems.removeAll()
        let cleared = items
        items = []
        itemsBytes = 0
        Self.discardInBackground(cleared)
    }

    fileprivate func deleteSnapshot(_ snapshot: Snapshot) {
        let previous = snapshots
        snapshots = previous.filter { $0.id != snapshot.id }
        Self.discardInBackground(previous)
    }

    fileprivate func export(_ itemsToExport: [RtItem]) {
        guard let file = app?.askSaveLocation(
            suggestedName: "reactotron_\(ScreenCaptureService.stamp()).json"
        ) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(itemsToExport.map(\.command)).write(to: file)
            app?.showToast(Toast(message: "Exported \(itemsToExport.count) events", ok: true, revealPath: file.path))
        } catch {
            app?.showToast(Toast(message: "Export failed: \(error.localizedDescription)", ok: false))
        }
    }

    // MARK: - Inbound

    private func handle(_ event: ReactotronServer.Event) {
        switch event {
        case .listening:
            if clients.isEmpty { connection = .listening }
        case let .connected(connectionId, intro, frameBytes):
            let parsed = ReactotronEvent(command: intro)
            var name = "App"
            var platform: String?
            if case let .clientIntro(introName, _, introPlatform, _) = parsed {
                name = introName
                platform = introPlatform
            }
            clients.removeAll { $0.id == connectionId }
            clients.append(ClientInfo(id: connectionId, name: name, platform: platform))
            refreshConnectionState()
            // Straight to the new client, not the picker's current target —
            // otherwise an app (re)connecting while another is selected never
            // learns the watch paths.
            if !subscriptionPaths.isEmpty { sendSubscriptions(to: connectionId) }
            enqueue(RtItem(
                event: parsed, command: intro, connectionId: connectionId,
                important: false, frameBytes: frameBytes
            ))
        case let .command(connectionId, command, frameBytes):
            let parsed = ReactotronEvent(command: command)
            switch parsed {
            case .clear:
                // Flush first so events still buffered for this client are
                // included in the clear, then scope to the sending client so one
                // app's clear doesn't wipe another connected app's timeline.
                flushPending()
                let previous = items
                items = previous.filter { $0.connectionId != connectionId }
                itemsBytes = items.reduce(0) { $0 + $1.frameBytes }
                Self.discardInBackground(previous)
                return
            case let .customCommandRegister(id, name, title, description, args):
                registerCommand(RegisteredCommand(id: id, command: name, title: title, description: description, args: args))
            case let .customCommandUnregister(id, _):
                commands.removeAll { $0.id == id }
            case let .stateValuesChange(changes):
                for change in changes where subscriptionPaths.contains(change.path) {
                    subscriptionValues[change.path] = change.value
                }
            case let .stateBackup(snapshotState):
                if let snapshotState {
                    replaceStoreState(snapshotState)
                    awaitingStateTree = false
                    if pendingSnapshot {
                        appendSnapshot(Snapshot(state: snapshotState))
                        pendingSnapshot = false
                    }
                }
                return
            case let .stateKeysResponse(path, keys):
                if isWholeStorePath(path), let keys {
                    replaceStoreState(keys)
                    awaitingStateTree = false
                }
                return
            case let .stateValuesResponse(path, value):
                if isWholeStorePath(path), let value {
                    replaceStoreState(value)
                    awaitingStateTree = false
                }
                return
            case let .replKeys(names):
                replNames = names
                return
            case let .replResult(value):
                replResultText = value?.jsonString ?? "undefined"
                return
            default:
                break
            }
            enqueue(RtItem(
                event: parsed, command: command, connectionId: connectionId,
                important: command.isImportant, frameBytes: frameBytes
            ))
        case let .disconnected(connectionId, reason):
            // Before forgetting the client (its name captions the notice):
            // spell out *why* the stream ended, in the timeline where the user
            // is looking — a silent yellow dot reads as "Droidective broke".
            if let notice = Self.disconnectNotice(
                reason, app: clients.first { $0.id == connectionId }?.name
            ) {
                // Headline in the (one-line) row; the full explanation rides the
                // command payload, which is what the row expands to.
                enqueue(RtItem(
                    event: .unknown(type: "disconnected", payload: .string(notice.headline)),
                    command: ReactotronCommand(type: "disconnected", payload: .string(notice.detail)),
                    connectionId: connectionId, important: true, frameBytes: 0
                ))
            }
            clients.removeAll { $0.id == connectionId }
            if selectedClient == connectionId { selectedClient = nil }
            if clients.isEmpty { commands.removeAll() }
            refreshConnectionState()
        case let .failed(reason, portInUse):
            // The server tears itself down on failure, so drop our handle to it —
            // otherwise `isRunning` stays true and re-entering the view (or the
            // Retry button) would skip the restart and the error could never clear.
            consumeTask?.cancel()
            consumeTask = nil
            service = nil
            clients.removeAll()
            selectedClient = nil
            commands.removeAll()
            connection = portInUse ? .portInUse : .failed(reason)
        }
    }

    private func isWholeStorePath(_ path: String?) -> Bool {
        path == nil || path?.isEmpty == true
    }

    /// The timeline row explaining a client drop; nil for teardown-driven
    /// drops (server stop), which need no explanation. `headline` fits the
    /// one-line row; `detail` is the expanded body.
    private static func disconnectNotice(
        _ reason: ReactotronServer.DisconnectReason?, app: String?
    ) -> (headline: String, detail: String)? {
        let name = app ?? "The app"
        switch reason {
        case .clientClosed(goingAway: true):
            return (
                headline: "\(name) hung up — events outpaced the connection (WS 1001). Expand for the fix.",
                detail: "\(name) produced Reactotron events faster than the connection could "
                    + "send them, so Android's WebSocket closed itself once 16 MB were queued "
                    + "(close code 1001, going-away).\n\nVery large console.log / action payloads "
                    + "are the usual cause — log IDs and summaries instead of whole objects.\n\n"
                    + "Reload the app to reconnect."
            )
        case .clientClosed(goingAway: false):
            let text = "\(name) closed the connection (app reloaded or exited)."
            return (headline: text, detail: text)
        case let .transportError(detail):
            return (headline: "\(name) disconnected: \(detail)",
                    detail: "\(name) disconnected: \(detail)")
        case nil:
            return nil
        }
    }

    private func refreshConnectionState() {
        if clients.isEmpty {
            connection = .listening
            connectedApp = nil
        } else {
            connection = .connected
            connectedApp = clients.count == 1 ? clients[0].name : "\(clients.count) apps"
        }
    }

    private func registerCommand(_ command: RegisteredCommand) {
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            commands[index] = command
        } else {
            commands.append(command)
        }
    }

    /// Buffer a timeline event and schedule a coalesced flush, so a burst of
    /// events becomes one `items` mutation instead of one per event.
    private func enqueue(_ item: RtItem) {
        pendingItems.append(item)
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            self?.flushPending()
        }
    }

    /// Drain the pending buffer into the timeline in a single append. Called by
    /// the flush timer, and eagerly before any read that must see every event
    /// (a client `clear`, teardown).
    private func flushPending() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingItems.isEmpty else { return }
        let batch = pendingItems
        pendingItems.removeAll(keepingCapacity: true)
        appendBatch(batch)
    }

    /// Ring-buffer append bounded by count *and* cumulative frame bytes
    /// (`ReactotronTimeline`), so a client streaming huge payloads can't grow
    /// the retained timeline into gigabytes. Trims oldest-first in batches and
    /// frees the dropped items off the main actor.
    private func appendBatch(_ batch: [RtItem]) {
        items.append(contentsOf: batch)
        for item in batch { itemsBytes += item.frameBytes }
        peakItemsBytes = max(peakItemsBytes, itemsBytes)
        peakItemCount = max(peakItemCount, items.count)
        let drop = ReactotronTimeline.dropCount(
            sizes: items.lazy.map(\.frameBytes), count: items.count, totalBytes: itemsBytes
        )
        guard drop > 0 else { return }
        evictedItemCount += drop
        let dropped = Array(items[..<drop])
        items.removeFirst(drop)
        itemsBytes -= dropped.reduce(0) { $0 + $1.frameBytes }
        Self.discardInBackground(dropped)
    }

    /// Replace the browsed store tree, releasing the old graph off the main actor.
    private func replaceStoreState(_ state: JSONValue) {
        if let old = storeState { Self.discardInBackground(old) }
        storeState = state
    }

    /// Keep at most `maxSnapshots` store snapshots, dropping the oldest.
    private func appendSnapshot(_ snapshot: Snapshot) {
        snapshots.append(snapshot)
        guard snapshots.count > Self.maxSnapshots else { return }
        let dropped = Array(snapshots[..<(snapshots.count - Self.maxSnapshots)])
        snapshots.removeFirst(snapshots.count - Self.maxSnapshots)
        Self.discardInBackground(dropped)
    }

    /// Report how full the timeline got this session — peak bytes/items and how
    /// many items the caps evicted — so `ReactotronTimeline`'s budgets can be
    /// sized against real workloads. Numbers only; no payload contents.
    private func flushUsageStats() {
        if peakItemsBytes > 0 {
            Telemetry.shared.track("reactotron_timeline_usage", [
                "peak_bytes": peakItemsBytes,
                "peak_items": peakItemCount,
                "evicted_items": evictedItemCount,
                "max_bytes": ReactotronTimeline.maxTotalBytes,
                "max_items": ReactotronTimeline.maxItems,
            ])
        }
        peakItemsBytes = 0
        peakItemCount = 0
        evictedItemCount = 0
    }

    /// Free a possibly-huge value graph (nested JSON dictionaries/arrays) off
    /// the main actor: the detached task holds the last reference, so the
    /// release cascade — seconds long for a multi-gigabyte timeline — doesn't
    /// block the UI.
    private nonisolated static func discardInBackground<T: Sendable>(_ garbage: T) {
        Task.detached(priority: .utility) { _ = garbage }
    }
}

/// Native Reactotron server + live timeline. Droidective listens on :9090 and
/// auto-reverses the device port; the app's `reactotron-react-native` client
/// connects and streams events here. Mirrors `LogcatView`'s shape: the whole
/// server lifecycle hangs off `.task(id:)`, with a capped buffer and
/// follow-to-bottom. A second tab drives the client's custom commands.
struct ReactotronView: View {
    @Environment(AppState.self) private var state
    @Environment(\.tabIsActive) private var tabIsActive

    // View-local UI only — drafts and the active tab/split. Everything that must
    // survive leaving the feature lives on `session`.
    @State private var split = false
    @State private var tab: RtTab = .timeline
    @State private var newPath = ""
    @State private var dispatchText = ""
    @State private var replCode = ""
    @State private var showDisconnectAlert = false
    /// One-time first-open intro (the recorded split/filter demo).
    @AppStorage("hasSeenReactotronIntro") private var hasSeenIntro = false
    @State private var showIntro = false

    private var session: ReactotronSession { state.reactotronSession }

    /// Reverse on every ready Android device, not just the selected one — the
    /// server is host-wide, so any connected device should be able to reach it.
    /// (iOS Simulators need no tunnel; they share the Mac's loopback.)
    private var readySerials: [String] { session.readyAndroidSerials }

    /// The app name the Restart button should target: the selected client's,
    /// else the lone connected client's. Nil (several clients, none selected —
    /// or none connected) leaves detection to the foreground-app fallback.
    private var restartClientName: String? {
        if let id = session.selectedClient { return session.clients.first { $0.id == id }?.name }
        return session.clients.count == 1 ? session.clients[0].name : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topTabs
            Divider()
            if session.connection.isError {
                serverErrorBanner
                Divider()
            }
            if !session.tunnelIssues.isEmpty {
                tunnelWarningBanner
                Divider()
            }
            content
        }
        // The session is owned by AppState, so it persists across feature
        // switches. `start` is idempotent — if the connection was kept alive it
        // just re-applies the reverse and the existing timeline stays intact.
        // Devices appearing later are handled by AppState → deviceListChanged,
        // which also covers the view being closed (kept-alive sessions).
        .task { await session.start(serials: readySerials) }
        // A device dropping off is announced with an alert instead of the old
        // full-pane overlay, which painted over the still-visible timeline.
        .onChange(of: state.targetSerials.isEmpty) { wasEmpty, isEmpty in
            if isEmpty, !wasEmpty, tabIsActive { showDisconnectAlert = true }
        }
        .alert("Device disconnected", isPresented: $showDisconnectAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Reactotron keeps listening on :9090 and the timeline stays as it is. "
                + "Reconnect a device or start an emulator to keep receiving events.")
        }
        // First open only: what makes this screen different (split timeline,
        // per-pane filters), as a recorded demo. Any dismissal marks it seen.
        .onAppear {
            if !hasSeenIntro { showIntro = true }
        }
        .sheet(isPresented: $showIntro, onDismiss: { hasSeenIntro = true }) {
            ReactotronIntroSheet()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .timeline:
            // Single pane: the global controls ride the pane's own toolbar so
            // the timeline isn't topped by two stacked strips. The dedicated
            // strip appears only in split mode, where the pane toolbars are
            // per-pane and the globals need a home of their own.
            if split {
                timelineControls
                Divider()
            }
            timelineBody
        case .commands:
            commandsPane
        case .state:
            statePane
        case .repl:
            replPane
        }
    }

    // MARK: - Tabs

    private var topTabs: some View {
        HStack(spacing: 8) {
            // Connection state as a dot plus the connected app's name — the
            // detailed "Listening on :9090…" guidance lives in the timeline's
            // empty state, so a dedicated status bar would just repeat it.
            HStack(spacing: 5) {
                Circle()
                    .fill(session.connection.color)
                    .frame(width: 7, height: 7)
                if let app = session.connectedApp {
                    Text(app)
                        .font(.app(.caption).weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .help(session.connection.text(app: session.connectedApp))

            Picker("View", selection: $tab) {
                Text("Timeline").tag(RtTab.timeline)
                Text(session.commands.isEmpty ? "Commands" : "Commands (\(session.commands.count))").tag(RtTab.commands)
                Text("State").tag(RtTab.state)
                Text("REPL").tag(RtTab.repl)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            Spacer()

            if session.clients.count > 1 {
                Picker("App", selection: Binding(
                    get: { session.selectedClient },
                    set: { session.selectedClient = $0 }
                )) {
                    Text("All apps").tag(Int?.none)
                    ForEach(session.clients) { client in
                        Text(client.label).tag(Int?.some(client.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            RestartAppMenu(clientName: restartClientName)
                .controlSize(.small)
                .help("Force-stop and relaunch the connected app so it reconnects")
            Button {
                session.reverseNow(serials: readySerials)
            } label: {
                Label("Reverse :9090", systemImage: "arrow.uturn.backward.circle")
            }
            .controlSize(.small)
            .help("Run adb reverse tcp:9090 tcp:9090 on connected devices")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// The server failing (port taken, socket error) used to be a red dot with a
    /// hover tooltip — invisible unless you knew to hover. Spell the reason out
    /// and offer the restart inline; it shows on every tab, even mid-timeline.
    private var serverErrorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.app(size: 12))
                .foregroundStyle(.red)
            Text(session.connection.text(app: nil))
                .font(.app(.caption))
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Retry") {
                Task { await session.start(serials: readySerials) }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.red.opacity(0.08))
    }

    /// `adb reverse` failed on some device — without the tunnel, apps that
    /// dial localhost (USB) can never reach the server, and the old behavior
    /// (silently staying on "waiting for your app") read as Droidective broken.
    private var tunnelWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.app(size: 12))
                .foregroundStyle(.orange)
            Text(tunnelWarningText)
                .font(.app(.caption))
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Retry") { session.reverseNow(serials: readySerials) }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.08))
    }

    private var tunnelWarningText: String {
        let issues = session.tunnelIssues
            .sorted { $0.key < $1.key }
            .map { "\($0.key) (\($0.value.isEmpty ? "unknown error" : $0.value))" }
            .joined(separator: ", ")
        return "adb reverse tcp:9090 failed on \(issues) — apps on this device can't reach the server over USB."
    }

    // MARK: - Toolbar (timeline)

    /// Pane-independent controls: split toggle plus the global export/clear. Each
    /// pane carries its own filter/search/order so a split view can watch two
    /// slices at once (e.g. Network on the left, State on the right).
    private var timelineControls: some View {
        HStack(spacing: 12) {
            Spacer()

            Text("\(session.displayedItems.count) events")
                .font(.app(.caption))
                .foregroundStyle(.tertiary)

            Button {
                split.toggle()
            } label: {
                Image(systemName: split ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .foregroundStyle(split ? Color.brandAccent : Color.secondary)
            }
            .help(split ? "Back to a single pane" : "Split into two panes")

            Button {
                session.clearTimeline()
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear the timeline")
            .disabled(session.items.isEmpty)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var timelineBody: some View {
        if split {
            HStack(spacing: 0) {
                pane(showOnboarding: true)
                Divider()
                pane(showOnboarding: false)
            }
        } else {
            pane(showOnboarding: true, trailing: AnyView(paneGlobalControls))
        }
    }

    /// The strip's controls restyled for the pane toolbar (single-pane mode).
    private var paneGlobalControls: some View {
        HStack(spacing: 10) {
            Text("\(session.displayedItems.count) events")
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
            Button {
                split.toggle()
            } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .buttonStyle(IconButtonStyle())
            .help("Split into two panes")
            Button {
                session.clearTimeline()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(IconButtonStyle())
            .help("Clear the timeline")
            .disabled(session.items.isEmpty)
        }
    }

    private func pane(showOnboarding: Bool, trailing: AnyView? = nil) -> some View {
        TimelinePane(
            items: session.displayedItems,
            targetEmpty: state.targetSerials.isEmpty,
            connection: session.connection,
            showOnboarding: showOnboarding,
            trailing: trailing,
            onExport: { session.export($0) },
            onRetry: { Task { await session.start(serials: readySerials) } }
        )
    }

    // MARK: - Custom commands

    @ViewBuilder
    private var commandsPane: some View {
        if session.commands.isEmpty {
            ContentUnavailableView(
                "No custom commands", systemImage: "terminal",
                description: Text("Register commands in your app with `Reactotron.onCustomCommand(...)` — they appear here as buttons you can trigger on the device.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(session.commands) { command in
                        CommandCard(command: command) { cmd, args in session.send(cmd, args: args) }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - State (subscriptions + dispatch)

    @ViewBuilder
    private var statePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                stateTreeSection
                subscriptionsSection
                dispatchSection
                snapshotsSection
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Needs the `reactotron-redux` or `reactotron-mst` plugin wired into your store.")
                }
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stateTreeSection: some View {
        StateCard(
            icon: "list.bullet.indent", tint: .rtKey,
            title: "State tree",
            subtitle: "Pull the whole store and drill into any branch."
        ) {
            if let count = session.storeState?.objectValue?.count { CountChip(count: count, suffix: "keys") }
            if let storeState = session.storeState {
                CopyButton(label: "Copy JSON") { storeState.prettyJSON }
            }
            Button { session.loadStateTree() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .controlSize(.small)
        } content: {
            if let storeState = session.storeState {
                JSONTreeView(root: storeState)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardInset()
            } else if session.awaitingStateTree {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Requesting store state…").font(.app(size: 11)).foregroundStyle(.textMuted)
                    Spacer()
                }
                .cardInset()
            } else {
                EmptyHint(
                    icon: "tree", message: "Load the current store to browse it as a tree.",
                    actionTitle: "Load store state"
                ) { session.loadStateTree() }
            }
        }
    }

    private var subscriptionsSection: some View {
        StateCard(
            icon: "dot.radiowaves.up.forward", tint: .rtName,
            title: "Subscriptions",
            subtitle: "Watch specific paths and see them update live."
        ) {
            if !session.subscriptionPaths.isEmpty {
                CountChip(count: session.subscriptionPaths.count, suffix: "watching")
            }
        } content: {
            HStack(spacing: 8) {
                TextField("Path to watch, e.g. user.name", text: $newPath)
                    .brandField()
                    .onSubmit { addSubscription() }
                Button("Add") { addSubscription() }
                    .controlSize(.small)
                    .disabled(newPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if session.subscriptionPaths.isEmpty {
                EmptyHint(icon: "eye", message: "Add a dot-path above to watch it change in real time.")
            } else {
                VStack(spacing: 6) {
                    ForEach(session.subscriptionPaths, id: \.self) { path in subscriptionRow(path) }
                }
            }
        }
    }

    private func addSubscription() {
        session.addSubscription(newPath)
        newPath = ""
    }

    private func subscriptionRow(_ path: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(path)
                    .font(.app(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.rtKey)
                if let value = session.subscriptionValues[path] {
                    // A collapsible, colored tree instead of a raw JSON string —
                    // the same reader the State browser uses.
                    JSONTreeView(root: value, showSearch: false)
                } else {
                    Text("waiting for a change…")
                        .font(.app(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let value = session.subscriptionValues[path] {
                CopyButton(label: "Copy JSON") { value.prettyJSON }
            }
            Button { session.removeSubscription(path) } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Stop watching this path")
        }
        .cardInset()
    }

    private var dispatchSection: some View {
        StateCard(
            icon: "paperplane", tint: .rtBadge,
            title: "Dispatch action",
            subtitle: "Send a Redux action straight to the running app."
        ) {
            EmptyView()
        } content: {
            TextField(#"{ "type": "INCREMENT" }"#, text: $dispatchText, axis: .vertical)
                .brandField()
                .font(.app(size: 12, design: .monospaced))
                .lineLimit(2...6)
            HStack {
                Spacer()
                Button { session.dispatch(dispatchText) } label: { Label("Dispatch", systemImage: "paperplane.fill") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(dispatchText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var snapshotsSection: some View {
        StateCard(
            icon: "camera", tint: .rtNumber,
            title: "Snapshots",
            subtitle: "Freeze the store now, restore it later to reproduce a bug."
        ) {
            if !session.snapshots.isEmpty { CountChip(count: session.snapshots.count, suffix: "saved") }
            Button { session.takeSnapshot() } label: { Label("Take Snapshot", systemImage: "camera.fill") }
                .controlSize(.small)
        } content: {
            if session.snapshots.isEmpty {
                EmptyHint(icon: "camera", message: "Take a snapshot to capture the store as it is right now.")
            } else {
                VStack(spacing: 6) {
                    ForEach(session.snapshots) { snapshot in
                        SnapshotRow(
                            time: Self.timeFormatter.string(from: snapshot.takenAt),
                            state: snapshot.state,
                            onRestore: { session.restore(snapshot) },
                            onDelete: { session.deleteSnapshot(snapshot) }
                        )
                    }
                }
            }
        }
    }


    // MARK: - REPL

    @ViewBuilder
    private var replPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("REPL").font(.app(size: 13, weight: .semibold))
                    Spacer()
                    Button { session.sendReplLs() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(IconButtonStyle())
                        .help("Refresh available values")
                }
                Text("Evaluate JS against values your app registered with `Reactotron.repl(name, value)`.")
                    .font(.app(.caption)).foregroundStyle(.textMuted)
                if !session.replNames.isEmpty {
                    Text("Available: \(session.replNames.joined(separator: ", "))")
                        .font(.app(size: 11, design: .monospaced))
                        .foregroundStyle(.textMuted)
                }
                TextField("e.g. store.getState()", text: $replCode, axis: .vertical)
                    .brandField()
                    .lineLimit(2...5)
                HStack {
                    Spacer()
                    Button("Evaluate") { session.evalRepl(replCode) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(replCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let replResultText = session.replResultText {
                    Text("Result").font(.app(size: 12, weight: .semibold))
                    Text(replResultText)
                        .font(.app(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { session.sendReplLs() }
    }
}

// MARK: - Connection state

private enum RtTab {
    case timeline
    case commands
    case state
    case repl
}

private enum RtConnection: Equatable {
    case idle
    case listening
    case connected
    case portInUse
    case failed(String)

    /// Server-dead states — the ones worth a visible banner, not just a dot.
    var isError: Bool {
        switch self {
        case .portInUse, .failed: true
        case .idle, .listening, .connected: false
        }
    }

    var color: Color {
        switch self {
        case .idle: .textMuted
        case .listening: .orange
        case .connected: .green
        case .portInUse, .failed: .red
        }
    }

    func text(app: String?) -> String {
        switch self {
        case .idle: "Starting the server on :9090…"
        case .listening: "Listening on :9090 — waiting for your app to connect"
        case .connected: "Connected" + (app.map { " — \($0)" } ?? "")
        case .portInUse: "Port 9090 is in use — close the app that owns it (usually the Reactotron desktop app), then retry"
        case let .failed(reason): "Server error: \(reason)"
        }
    }
}

// MARK: - Timeline item

private struct RtItem: Identifiable, Sendable {
    let id = UUID()
    let event: ReactotronEvent
    let command: ReactotronCommand
    let connectionId: Int
    let important: Bool
    /// Wire size of the frame this item was decoded from — drives the
    /// timeline's byte budget.
    let frameBytes: Int
    let receivedAt = Date()
    /// Badge + primary text, lowercased once at creation, so search matching is
    /// an allocation-free `contains` instead of rebuilding `event.presentation`
    /// and re-lowercasing on every filter pass.
    let searchText: String

    init(event: ReactotronEvent, command: ReactotronCommand, connectionId: Int, important: Bool, frameBytes: Int) {
        self.event = event
        self.command = command
        self.connectionId = connectionId
        self.important = important
        self.frameBytes = frameBytes
        let presentation = event.presentation
        // Bounded so a giant log message (a console.log of a huge string) can't
        // store a multi-megabyte lowercased copy per row — search matches the
        // header text, and the full payload lives in the expandable row.
        searchText = "\(presentation.badge) \(presentation.primary)".prefix(2000).lowercased()
    }
}

private struct RegisteredCommand: Identifiable {
    let id: Int
    let command: String
    let title: String?
    let description: String?
    let args: [ReactotronCommandArg]
}

private struct Snapshot: Identifiable, Sendable {
    let id = UUID()
    let state: JSONValue
    let takenAt = Date()
}

/// One connected Reactotron client, keyed by the server's connection id. Powers
/// the app picker so several devices/apps can stream at once and the user can
/// switch which one the timeline and control tabs target.
private struct ClientInfo: Identifiable {
    let id: Int
    let name: String
    let platform: String?

    var label: String {
        guard let platform, !platform.isEmpty else { return name }
        return "\(name) · \(platform)"
    }
}

/// The timeline's filterable event kinds — the same set, grouping, and display
/// names as the Reactotron desktop app's timeline filter dialog. Events the
/// dialog doesn't cover (REPL, custom commands, state responses) are always
/// shown.
private enum RtEventKind: String, CaseIterable, Identifiable {
    case log, image, display
    case connection, benchmark, api
    case asyncStorage
    case action, saga, subscription

    var id: String { rawValue }

    var label: String {
        switch self {
        case .log: "Log"
        case .image: "Image"
        case .display: "Custom Display"
        case .connection: "Connection"
        case .benchmark: "Benchmark"
        case .api: "API"
        case .asyncStorage: "Mutations"
        case .action: "Action"
        case .saga: "Saga"
        case .subscription: "Subscription Changed"
        }
    }

    /// The filter popover's sections, mirroring Reactotron's dialog.
    static let groups: [(name: String, kinds: [RtEventKind])] = [
        ("Informational", [.log, .image, .display]),
        ("General", [.connection, .benchmark, .api]),
        ("Async Storage", [.asyncStorage]),
        ("State & Sagas", [.action, .saga, .subscription]),
    ]
}

// MARK: - Timeline pane

/// One scrollable timeline column with its own filter, search and sort order, fed
/// from the shared event buffer. Used once on its own or twice side-by-side (the
/// VSCode-style split), so each pane can watch a different slice at the same time.
private struct TimelinePane: View {
    let items: [RtItem]
    let targetEmpty: Bool
    let connection: RtConnection
    let showOnboarding: Bool
    /// Extra trailing toolbar content — the global timeline controls when the
    /// pane is the only one on screen (no dedicated strip above it).
    let trailing: AnyView?
    let onExport: ([RtItem]) -> Void
    let onRetry: () -> Void

    @State private var search = ""
    /// Event kinds toggled off in the filter popover — empty means everything
    /// shows, matching Reactotron's hide-what-you-untick model.
    @State private var hiddenKinds: Set<RtEventKind> = []
    /// API-only refinements, set from the filter popover and cleared when the
    /// API kind is hidden: HTTP method and status class (2xx…5xx/Failed).
    @State private var methodFilter: String?
    @State private var statusFilter: HTTPStatusClass?
    @State private var showFilterSheet = false

    var body: some View {
        // Filter once per render — the count badge, export button, and timeline
        // all read the same result instead of each recomputing the filter.
        let visible = filteredItems
        return VStack(spacing: 0) {
            paneToolbar(visible: visible)
            Divider()
            // Newest first: the fixed timeline order (matches the Reactotron
            // app). Lazily reversed — materializing a 2000-item copy per
            // render was measurable during streaming bursts.
            timeline(ordered: visible.reversed())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Whether any popover filter narrows the timeline (drives the filled
    /// filter icon and the count badge).
    private var isFiltering: Bool {
        !hiddenKinds.isEmpty || methodFilter != nil || statusFilter != nil
    }

    private func paneToolbar(visible: [RtItem]) -> some View {
        HStack(spacing: 10) {
            Button {
                showFilterSheet = true
            } label: {
                Image(systemName: isFiltering
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(IconButtonStyle())
            .help("Filter the timeline by event type")
            .sheet(isPresented: $showFilterSheet) { filterSheet }

            SearchField(prompt: "Search…", text: $search)
                .frame(maxWidth: 200)

            Spacer()

            if !search.isEmpty || isFiltering {
                Text("\(visible.count)")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            }

            Button {
                onExport(visible)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(IconButtonStyle())
            .help("Export this pane's filtered timeline to JSON")
            .disabled(visible.isEmpty)

            if let trailing {
                trailing
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// The HTTP methods present in the buffer's API events, for the method
    /// picker — only what the app actually sent, not a canned list.
    private var seenMethods: [String] {
        Array(Set(items.compactMap { $0.event.apiMethod })).sorted()
    }

    private var filteredItems: [RtItem] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            if let kind = item.event.kind, hiddenKinds.contains(kind) { return false }
            if let methodFilter, item.event.apiMethod != methodFilter { return false }
            if let statusFilter,
               item.event.apiStatus.flatMap({ HTTPStatusClass(status: $0) }) != statusFilter {
                return false
            }
            // item.searchText is lowercased at creation, so this is a plain,
            // allocation-free substring check.
            if !query.isEmpty, !item.searchText.contains(query) { return false }
            return true
        }
    }

    /// The Reactotron-style filter dialog, presented as a modal sheet like the
    /// desktop app's "Timeline Filter": every event kind as a checkbox in the
    /// same groups, the API method/status refinements nested under the API
    /// toggle, and Check all / Uncheck all shortcuts.
    private var filterSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timeline Filter")
                    .font(.app(.title3).bold())
                Text("Checked event types appear in the timeline.")
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
            }
            ForEach(RtEventKind.groups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.name)
                        .font(.app(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 16) {
                        ForEach(group.kinds) { kind in
                            Toggle(kind.label, isOn: shows(kind))
                                .toggleStyle(.checkbox)
                        }
                    }
                    if group.kinds.contains(.api), !hiddenKinds.contains(.api) {
                        // Indented + captioned so the pickers read as API
                        // refinements, not filters for the whole group.
                        HStack(spacing: 8) {
                            Text("API only")
                                .font(.app(size: 10))
                                .foregroundStyle(.tertiary)
                            networkFilters
                        }
                        .padding(.leading, 18)
                    }
                }
            }
            Divider()
            HStack(spacing: 10) {
                Button("Check all") { hiddenKinds = [] }
                    .disabled(hiddenKinds.isEmpty)
                Button("Uncheck all") {
                    hiddenKinds = Set(RtEventKind.allCases)
                    methodFilter = nil
                    statusFilter = nil
                }
                .disabled(hiddenKinds.count == RtEventKind.allCases.count)
                Spacer()
                Button("Done") { showFilterSheet = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430, alignment: .leading)
        .onExitCommand { showFilterSheet = false }
    }

    /// Whether `kind` is currently shown; hiding API also clears its
    /// method/status refinements so they can't filter invisibly.
    private func shows(_ kind: RtEventKind) -> Binding<Bool> {
        Binding(
            get: { !hiddenKinds.contains(kind) },
            set: { shown in
                if shown {
                    hiddenKinds.remove(kind)
                } else {
                    hiddenKinds.insert(kind)
                    if kind == .api {
                        methodFilter = nil
                        statusFilter = nil
                    }
                }
            }
        )
    }

    private var networkFilters: some View {
        HStack(spacing: 6) {
            Picker("Method", selection: $methodFilter) {
                Text("Method").tag(String?.none)
                ForEach(seenMethods, id: \.self) { method in
                    Text(method).tag(Optional(method))
                }
            }
            .labelsHidden()
            .fixedSize()
            .help("Show only requests with this HTTP method")

            Picker("Status", selection: $statusFilter) {
                Text("Status").tag(HTTPStatusClass?.none)
                ForEach(HTTPStatusClass.allCases) { statusClass in
                    Text(statusClass.label).tag(Optional(statusClass))
                }
            }
            .labelsHidden()
            .fixedSize()
            .help("Show only responses in this status class")
        }
    }

    private func timeline(ordered: ReversedCollection<[RtItem]>) -> some View {
        // Newest events land at the top — LogTailViewV2 follows that edge, pauses
        // when the user scrolls off, and overlays the jump-to-top/bottom buttons.
        LogTailViewV2(entries: ordered, newestEdge: .top) { item in
            RtRow(item: item)
            Divider()
        }
        .background(.background)
        .overlay { emptyOverlay }
    }

    /// Empty-state overlays appear only over an *empty* timeline — a device
    /// dropping off mid-session must not paint over live events (the view
    /// raises an alert for that instead).
    @ViewBuilder
    private var emptyOverlay: some View {
        if items.isEmpty, connection.isError, showOnboarding {
            // A dead server trumps the other empty states — nothing can connect
            // until it's restarted, so lead with the error and the fix.
            ReactotronOnboarding(connection: connection, onRetry: onRetry)
        } else if items.isEmpty, targetEmpty {
            ContentUnavailableView(
                "No device connected", systemImage: "iphone.slash",
                description: Text("Connect a device or start an emulator to receive Reactotron events.")
            )
        } else if items.isEmpty, showOnboarding {
            ReactotronOnboarding(connection: connection, onRetry: onRetry)
        }
    }
}

// MARK: - Row

private struct RtRow: View {
    let item: RtItem
    @State private var expanded = false
    @State private var apiTab: ApiTab = .response
    @State private var hovering = false
    @State private var copiedLine = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var object: JSONValue? { item.command.payload }
    private var canExpand: Bool { object != nil }

    var body: some View {
        let presentation = item.event.presentation
        return VStack(alignment: .leading, spacing: 0) {
            header(presentation)
            if expanded {
                expandedBody()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.important ? Color.orange.opacity(0.06) : Color.clear)
        .overlay(alignment: .leading) {
            if item.important { Rectangle().fill(.orange).frame(width: 3) }
        }
        .contextMenu {
            if let object {
                Button("Copy object") { copyToPasteboard(object.prettyJSON) }
            }
            Button("Copy line") { copyToPasteboard(presentation.copyText) }
        }
    }

    /// The chevron cluster and the row's blank trailing space toggle
    /// expansion; the action/log text itself stays OUT of the tap target so
    /// it's selectable — a whole-row gesture swallowed drag-to-select, making
    /// action and debug names uncopyable.
    private func header(_ presentation: RtPresentation) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.app(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .opacity(canExpand ? 1 : 0)
                Text(Self.timeFormatter.string(from: item.receivedAt))
                    .font(.app(size: 11, design: .monospaced))
                    .foregroundStyle(.textMuted)
                Text(presentation.badge)
                    .font(.app(size: 10, weight: .bold))
                    .foregroundStyle(presentation.badgeColor)
                    .fixedSize()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { if canExpand { expanded.toggle() } }

            if !presentation.primary.isEmpty {
                Text(presentation.primary)
                    .font(.app(size: 12, weight: .medium))
                    .foregroundStyle(presentation.primaryColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Rectangle()
                .fill(.clear)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
                .onTapGesture { if canExpand { expanded.toggle() } }

            if hovering || copiedLine {
                Button {
                    copyToPasteboard(presentation.copyText)
                    copiedLine = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copiedLine = false }
                } label: {
                    Image(systemName: copiedLine ? "checkmark" : "doc.on.doc")
                        .font(.app(size: 11))
                        .foregroundStyle(copiedLine ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy this line (right-click for the full object)")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private func expandedBody() -> some View {
        switch item.event {
        case let .apiResponse(method, url, status, duration, request, response):
            apiBody(method: method, url: url, status: status, duration: duration, request: request, response: response)
        case let .stateAction(_, action, ms):
            actionBody(action: action, ms: ms)
        case let .log(_, _, stack):
            logBody(stack: stack)
        case let .image(uri, _, caption, width, height):
            imageBody(uri: uri, caption: caption, width: width, height: height)
        case let .display(_, value, _, image):
            displayBody(value: value, image: image)
        default:
            if let object { treeSection(title: nil, object: object) }
        }
    }

    private func imageBody(uri: String, caption: String?, width: Double?, height: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let caption, !caption.isEmpty {
                Text(caption).font(.app(size: 12)).foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            RtImageThumbnail(uri: uri)
            if let width, let height {
                metaRow("Size", "\(Int(width)) × \(Int(height))", color: .rtNumber)
            }
        }
    }

    private func displayBody(value: JSONValue?, image: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image, !image.isEmpty { RtImageThumbnail(uri: image) }
            if let value, !value.isNull { treeSection(title: nil, object: value) }
        }
    }

    // MARK: type-specific bodies

    private func actionBody(action: JSONValue?, ms: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let ms { metaRow("duration", "\(formatMs(ms)) ms", color: .rtNumber) }
            treeSection(title: "ACTION", object: action ?? object ?? .object([:]))
        }
    }

    private func apiBody(
        method: String, url: String, status: Int, duration: Double, request: JSONValue?, response: JSONValue?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(url)
                .font(.app(size: 11, design: .monospaced))
                .foregroundStyle(.rtKey)
                .textSelection(.enabled)
                .lineLimit(3)
            VStack(alignment: .leading, spacing: 3) {
                metaRow("Status", "\(status)", color: statusColor(status))
                metaRow("Method", method.uppercased(), color: .rtNumber)
                metaRow("Duration", "\(formatMs(duration)) ms", color: .rtNumber)
            }
            HStack {
                Spacer()
                CopyButton(label: "Copy as cURL", icon: "terminal") {
                    ReactotronCurl.command(method: method, url: url, request: request)
                }
            }
            Picker("", selection: $apiTab) {
                ForEach(ApiTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            treeSection(title: nil, object: apiObject(request: request, response: response))
        }
    }

    private func apiObject(request: JSONValue?, response: JSONValue?) -> JSONValue {
        switch apiTab {
        case .response: return parseBody(response?["body"]) ?? response?["body"] ?? response ?? .null
        case .request: return request ?? .null
        case .responseHeaders: return response?["headers"] ?? .object([:])
        case .requestHeaders: return request?["headers"] ?? .object([:])
        }
    }

    private func logBody(stack: [ReactotronStackFrame]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = object?["message"] {
                switch message {
                case .object, .array:
                    treeSection(title: nil, object: message)
                default:
                    Text(String((message.stringValue ?? message.jsonString).prefix(20_000)))
                        .font(.app(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !stack.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(stack.enumerated()), id: \.offset) { _, frame in
                        Text("\(frame.functionName.isEmpty ? "?" : frame.functionName)  \(frame.fileName):\(frame.lineNumber.map(String.init) ?? "?")")
                            .font(.app(size: 10, design: .monospaced))
                            .foregroundStyle(.textMuted)
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    // MARK: building blocks

    private func metaRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.app(size: 11))
                .foregroundStyle(.textMuted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.app(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
        }
    }

    private func treeSection(title: String?, object: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let title {
                    Text(title).font(.app(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
                Spacer()
                CopyButton { object.prettyJSON }
            }
            JSONTreeView(root: object)
        }
        .padding(8)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 6))
    }

    private func parseBody(_ value: JSONValue?) -> JSONValue? {
        guard case let .string(text) = value,
              let data = text.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return parsed
    }

    private func formatMs(_ ms: Double) -> String {
        ms < 10 ? String(format: "%.2f", ms) : String(Int(ms.rounded()))
    }

    private func statusColor(_ status: Int) -> Color {
        switch status {
        case 200..<300: .green
        case 400..<500: .orange
        case 500...: .red
        default: .rtNumber
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private enum ApiTab: String, CaseIterable, Identifiable {
    case response, request, responseHeaders, requestHeaders
    var id: String { rawValue }
    var label: String {
        switch self {
        case .response: "Response"
        case .request: "Request"
        case .responseHeaders: "Resp Headers"
        case .requestHeaders: "Req Headers"
        }
    }
}

// MARK: - Image overlay

/// Inline thumbnail for `image`/`display` events. Handles base64 `data:` URIs
/// (e.g. `Reactotron.display({ image })`) and remote `http(s)` URLs
/// (`Reactotron.image({ uri })`); clicking opens a full-size lightbox.
private struct RtImageThumbnail: View {
    let uri: String
    @State private var showFull = false

    var body: some View {
        thumbnail
            .sheet(isPresented: $showFull) { RtImageOverlay(uri: uri) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = rtDecodeImage(uri) {
            framed(Image(nsImage: image))
        } else if let url = rtRemoteURL(uri) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image): framed(image)
                case .failure: fallback
                default: ProgressView().controlSize(.small).frame(width: 80, height: 60)
                }
            }
        } else {
            fallback
        }
    }

    private func framed(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 320, maxHeight: 240, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture { showFull = true }
            .help("Click to view full size")
    }

    private var fallback: some View {
        Text(uri.isEmpty ? "No image" : "Can't render image\n\(String(uri.prefix(140)))")
            .font(.app(size: 10, design: .monospaced))
            .foregroundStyle(.textMuted)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Full-size image lightbox shown as a sheet over the timeline.
private struct RtImageOverlay: View {
    let uri: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.app(.title2))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            }
            .padding(10)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 480, idealWidth: 760, minHeight: 360, idealHeight: 600)
    }

    @ViewBuilder
    private var content: some View {
        if let image = rtDecodeImage(uri) {
            Image(nsImage: image).resizable().scaledToFit()
        } else if let url = rtRemoteURL(uri) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else if phase.error != nil {
                    Text("Couldn't load image").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
        } else {
            Text("Can't render this image").foregroundStyle(.secondary)
        }
    }
}

/// Decode a base64 `data:` URI into an image; nil for any other form.
private func rtDecodeImage(_ uri: String) -> NSImage? {
    guard uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") else { return nil }
    let encoded = String(uri[uri.index(after: comma)...])
    guard let data = Data(base64Encoded: encoded) else { return nil }
    return NSImage(data: data)
}

private func rtRemoteURL(_ uri: String) -> URL? {
    guard uri.hasPrefix("http://") || uri.hasPrefix("https://") else { return nil }
    return URL(string: uri)
}

// MARK: - JSON tree (collapsible, searchable, lazy)

/// Renders a `JSONValue` as a collapsible tree. Everything starts collapsed and
/// only expanded/visible nodes are flattened into the `LazyVStack`, so even a
/// very large object is cheap to display until the user drills in.
/// A saved store snapshot: a compact header (time, Restore, Delete) that reveals
/// the full state as a collapsible, searchable tree when expanded — instead of a
/// one-line raw-JSON preview.
private struct SnapshotRow: View {
    let time: String
    let state: JSONValue
    let onRestore: () -> Void
    let onDelete: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.app(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(time)
                            .font(.app(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.rtNumber)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Hide the snapshot" : "Show the snapshot")
                Spacer(minLength: 8)
                CopyButton(label: "Copy JSON") { state.prettyJSON }
                Button("Restore", action: onRestore).controlSize(.small)
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Delete this snapshot")
            }
            if expanded {
                JSONTreeView(root: state)
            }
        }
        .cardInset()
    }
}

private struct JSONTreeView: View {
    let root: JSONValue
    /// Show the built-in key/value search field (hidden when embedded in a list
    /// where a search box per row would be clutter).
    var showSearch: Bool = true
    @State private var expanded: Set<String> = []
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showSearch {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.app(size: 9))
                        .foregroundStyle(.tertiary)
                    TextField("Search keys & values…", text: $search)
                        .textFieldStyle(.plain)
                        .font(.app(size: 11, design: .monospaced))
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            LazyVStack(alignment: .leading, spacing: 1) {
                let nodes = rows
                ForEach(nodes) { node in
                    rowView(node)
                }
                if nodes.isEmpty {
                    Text(search.isEmpty ? "(empty)" : "No matches")
                        .font(.app(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var rows: [JSONNode] {
        search.isEmpty ? collapsedRows() : matchRows(search.lowercased())
    }

    private func collapsedRows() -> [JSONNode] {
        var out: [JSONNode] = []
        func walk(_ node: JSONNode) {
            out.append(node)
            guard node.isContainer, expanded.contains(node.path) else { return }
            for child in node.children { walk(child) }
        }
        for child in JSONNode(path: "", key: "", value: root, depth: -1).children { walk(child) }
        return out
    }

    private func matchRows(_ query: String) -> [JSONNode] {
        var out: [JSONNode] = []
        var visited = 0
        func walk(_ node: JSONNode) {
            if out.count >= 800 || visited >= 40_000 { return }
            visited += 1
            if node.matches(query) { out.append(JSONNode(path: node.path, key: node.key, value: node.value, depth: 0)) }
            for child in node.children { walk(child) }
        }
        for child in JSONNode(path: "", key: "", value: root, depth: -1).children { walk(child) }
        return out
    }

    @ViewBuilder
    private func rowView(_ node: JSONNode) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if search.isEmpty {
                Color.clear.frame(width: CGFloat(max(0, node.depth)) * 12, height: 1)
            }
            if node.isContainer, search.isEmpty {
                Image(systemName: expanded.contains(node.path) ? "chevron.down" : "chevron.right")
                    .font(.app(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14, height: 1)
            }
            if !node.key.isEmpty {
                Text(node.key)
                    .font(.app(size: 11, design: .monospaced))
                    .foregroundStyle(.rtKey)
                Text(":")
                    .font(.app(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(node.valuePreview)
                .font(.app(size: 11, design: .monospaced))
                .foregroundStyle(node.valueColor)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        // Rows were 13pt slivers — give container rows a real click target.
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isContainer, search.isEmpty { toggle(node.path) }
        }
        .contextMenu {
            Button("Copy value") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.value.prettyJSON, forType: .string)
            }
        }
    }

    private func toggle(_ path: String) {
        if expanded.contains(path) { expanded.remove(path) } else { expanded.insert(path) }
    }
}

private struct JSONNode: Identifiable {
    let path: String
    let key: String
    let value: JSONValue
    let depth: Int
    var id: String { path }

    var isContainer: Bool {
        switch value {
        case .object, .array: return true
        default: return false
        }
    }

    var children: [JSONNode] {
        switch value {
        case let .object(dict):
            // Identity is positional (parent path + ordinal), never the key
            // text, so a key containing "/" or "[0]" can't collide with another
            // node and toggle the wrong branch.
            return dict.sorted { $0.key < $1.key }.enumerated().map { offset, entry in
                JSONNode(path: "\(path).\(offset)", key: entry.key, value: entry.value, depth: depth + 1)
            }
        case let .array(items):
            return items.enumerated().map {
                JSONNode(path: "\(path).\($0.offset)", key: "[\($0.offset)]", value: $0.element, depth: depth + 1)
            }
        default:
            return []
        }
    }

    func matches(_ query: String) -> Bool {
        if key.lowercased().contains(query) { return true }
        switch value {
        case let .string(text): return text.lowercased().contains(query)
        case let .number(number): return "\(number)".contains(query)
        case let .bool(flag): return "\(flag)".contains(query)
        default: return false
        }
    }

    var valuePreview: String {
        switch value {
        case let .object(dict): return "{ \(dict.count) }"
        case let .array(items): return "[ \(items.count) ]"
        case let .string(text): return "\"\(text)\""
        case let .number(number):
            return number.truncatingRemainder(dividingBy: 1) == 0 && abs(number) < 9e15
                ? String(Int(number)) : String(number)
        case let .bool(flag): return flag ? "true" : "false"
        case .null: return "null"
        }
    }

    var valueColor: Color {
        switch value {
        case .string: return .primary
        case .number: return .rtNumber
        case .bool: return .rtNumber
        case .null: return .rtSpecial
        case .object, .array: return .secondary
        }
    }
}

// MARK: - Command card

private struct CommandCard: View {
    let command: RegisteredCommand
    let onSend: (RegisteredCommand, [String: String]) -> Void
    @State private var args: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title ?? command.command)
                        .font(.app(size: 13, weight: .semibold))
                    if command.title != nil {
                        Text(command.command)
                            .font(.app(size: 11, design: .monospaced))
                            .foregroundStyle(.textMuted)
                    }
                    if let description = command.description {
                        Text(description)
                            .font(.app(.caption))
                            .foregroundStyle(.textMuted)
                    }
                }
                Spacer()
                Button("Send") { onSend(command, args) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            ForEach(command.args, id: \.name) { arg in
                TextField(arg.name, text: Binding(
                    get: { args[arg.name] ?? "" },
                    set: { args[arg.name] = $0 }
                ))
                .brandField()
            }
        }
        .padding(12)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

// MARK: - Onboarding

private struct ReactotronOnboarding: View {
    let connection: RtConnection
    let onRetry: () -> Void
    @AppStorage(reactotronAllowLANKey) private var allowLAN = true

    private static let snippet = """
    // App entry (e.g. index.js)
    import Reactotron from 'reactotron-react-native'

    Reactotron.configure()
      .useReactNative()
      .connect()
    """

    @ViewBuilder
    var body: some View {
        if connection.isError {
            errorBody
        } else {
            waitingBody
        }
    }

    /// The server couldn't start (or died) — the "add the client" walkthrough
    /// would mislead here, so state the actual error and offer the restart.
    private var errorBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.app(size: 40))
                .foregroundStyle(.red)
            Text(connection == .portInUse ? "Port 9090 is taken" : "Reactotron server error")
                .font(.app(.title3).weight(.semibold))
            Text(connection.text(app: nil))
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 460)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var waitingBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.app(size: 40))
                .foregroundStyle(.textMuted)
            Text("Waiting for your app")
                .font(.app(.title3).weight(.semibold))
            Text("Droidective is the Reactotron server — it listens on :9090 and already ran `adb reverse tcp:9090 tcp:9090`. Add the client to your app and reload:")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Text(Self.snippet)
                .font(.app(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 6))
            Text("Needs `reactotron-react-native` installed in the app and a dev build.")
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
            if !allowLAN {
                // The one setup this scope can't serve: a device that loaded
                // its bundle over Wi-Fi dials the Mac's LAN IP, not localhost.
                Text("Running Metro over Wi-Fi? Enable “Accept Reactotron connections from your network” in Settings ▸ Privacy.")
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            alreadyRunningHint
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// A connected client only registers when it (re)launches, so an app that was
    /// already open before the server came up won't appear until it restarts.
    private var alreadyRunningHint: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.rtName.opacity(0.16)).frame(width: 30, height: 30)
                Image(systemName: "lightbulb.fill")
                    .font(.app(size: 13))
                    .foregroundStyle(.rtName)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Already running your app?")
                    .font(.app(size: 12, weight: .semibold))
                Text("Restart it so it reconnects.")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            }
            Spacer(minLength: 12)
            RestartAppMenu()
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 460)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.borderSubtle))
    }
}

/// One-time intro shown the first time Reactotron opens: the recorded demo of
/// the split timeline with a different filter per pane — the two things that
/// set this screen apart from the other log feeds. Marks itself seen on any
/// dismissal; the recording is the same `tour-reactotron` clip the tour
/// infrastructure bundles, with the drawn demo as fallback.
private struct ReactotronIntroSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            TourClipView(clipName: "tour-reactotron") { ReactotronTourDemo() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Reactotron, built in")
                .font(.app(.title2).bold())
            Text("Droidective is the Reactotron server — your app's actions, API calls, and logs "
                + "stream into this timeline live. Split it and give each pane its own filter: "
                + "API traffic on one side, logs on the other.")
                .font(.app(.body))
                .multilineTextAlignment(.center)
                .foregroundStyle(.textMuted)
                .frame(maxWidth: 540)
                .fixedSize(horizontal: false, vertical: true)
            Button("Got it") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 680, height: 600)
    }
}

/// Restarts (force-stop → relaunch) the app being debugged so it reconnects to
/// the Reactotron server. Detects the app automatically — the connected
/// client's reported name matched against installed packages, else the
/// foreground app — and only opens the searchable picker when detection or
/// the relaunch fails.
private struct RestartAppMenu: View {
    /// The connected Reactotron client's app name, when one is connected —
    /// the strongest detection signal (it names the exact app to restart).
    var clientName: String?

    @Environment(AppState.self) private var state
    @State private var restarting = false
    @State private var showPicker = false

    private var serial: String? {
        state.selectedSerial ?? state.devices.first(where: \.isReady)?.serial
    }

    var body: some View {
        Button {
            Task { await smartRestart() }
        } label: {
            Label("Restart app", systemImage: "arrow.clockwise.circle")
        }
        .disabled(serial == nil || restarting)
        .sheet(isPresented: $showPicker) {
            RestartAppPickerSheet(serial: serial) { package in
                Task {
                    if !(await restart(package)) {
                        state.showToast(Toast(message: "Couldn't restart \(package)", ok: false))
                    }
                }
            }
        }
    }

    /// Restart the detected app; fall back to the picker when nothing (or the
    /// wrong thing) is detected, or the relaunch fails. With no client
    /// connected there is nothing trustworthy to detect — the foreground app
    /// could be anything — so ask straight away.
    private func smartRestart() async {
        guard serial != nil else { return }
        guard clientName != nil else {
            showPicker = true
            return
        }
        restarting = true
        defer { restarting = false }
        if let detected = await detectPackage(), await restart(detected) { return }
        showPicker = true
    }

    /// The app to restart: the connected client's name matched against the
    /// installed third-party packages, else the foreground app (only when it's
    /// a third-party app — never the launcher). Nil means ask the user.
    private func detectPackage() async -> String? {
        guard let serial else { return nil }
        return await CommandLog.userInitiated {
            let control = AppControlService(client: state.env.client)
            let installed = (try? await control.listInstalledPackages(serial: serial)) ?? []
            if let clientName,
               let matched = AppNameMatcher.match(appName: clientName, in: installed) {
                return matched
            }
            if let foreground = try? await state.env.engine.inspection.getForegroundPackage(serial: serial),
               installed.contains(foreground) {
                return foreground
            }
            return nil
        }
    }

    private func restart(_ package: String) async -> Bool {
        guard let serial else { return false }
        let service = AppControlService(client: state.env.client)
        let result = await CommandLog.userInitiated {
            _ = try? await service.control(serial: serial, packageId: package, action: .stop)
            return try? await service.control(serial: serial, packageId: package, action: .open)
        }
        guard result?.ok == true else { return false }
        state.showToast(Toast(message: "Restarting \(package)…", ok: true))
        return true
    }
}

// MARK: - State tab building blocks

/// A labeled card: a type-colored icon + title + subtitle, an optional trailing
/// control cluster, and content below. The four State-tab sections share it so
/// each reads as one unit and the icon color identifies it at a glance (teal =
/// tree, gold = subscriptions, coral = dispatch, orange = snapshots), echoing the
/// timeline badge palette.
private struct StateCard<Trailing: View, Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(tint.opacity(0.16))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.app(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(size: 13, weight: .semibold))
                    Text(subtitle).font(.app(size: 11)).foregroundStyle(.textMuted)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) { trailing() }
            }
            content()
        }
        .padding(14)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderSubtle))
    }
}

/// Small pill showing a count (e.g. "3 keys") in a card header.
private struct CountChip: View {
    let count: Int
    let suffix: String

    var body: some View {
        Text("\(count) \(suffix)")
            .font(.app(size: 10, weight: .medium))
            .foregroundStyle(.textMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.bgRoot, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.borderSubtle))
    }
}

/// An empty-state row that invites the next action instead of just stating
/// emptiness — optionally with an inline button.
private struct EmptyHint: View {
    let icon: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.app(size: 14))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.app(size: 11))
                .foregroundStyle(.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.bgRoot, in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    /// Inset surface for rows/trees inside a `StateCard` — one step deeper than
    /// the card so nested content reads as recessed.
    func cardInset() -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgRoot, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderSubtle.opacity(0.6)))
    }
}

// MARK: - Reactotron palette

private extension ShapeStyle where Self == Color {
    static var rtBadge: Color { Color(red: 0.91, green: 0.46, blue: 0.36) }   // coral — type badges
    static var rtName: Color { Color(red: 0.95, green: 0.78, blue: 0.42) }    // gold — action / primary name
    static var rtKey: Color { Color(red: 0.46, green: 0.76, blue: 0.86) }     // teal — JSON keys
    static var rtNumber: Color { Color(red: 0.93, green: 0.60, blue: 0.40) }  // orange — numbers
    static var rtSpecial: Color { Color(red: 0.90, green: 0.52, blue: 0.48) } // null / undefined / functions
}

// MARK: - Copy button with feedback

private struct CopyButton: View {
    var label = "Copy"
    var icon = "doc.on.doc"
    let provider: () -> String
    @State private var copied = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(provider(), forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: copied ? "checkmark" : icon)
                Text(copied ? "Copied" : label)
            }
            .font(.app(size: 11, weight: .medium))
            .foregroundStyle(copied ? Color.green.contrastingForeground(for: colorScheme) : Color.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(copied ? Color.green : Color.secondary.opacity(0.18), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: copied)
    }
}

// MARK: - Event presentation

private struct RtPresentation {
    let badge: String
    let badgeColor: Color
    let primary: String
    let primaryColor: Color

    var copyText: String { "\(badge) \(primary)".trimmingCharacters(in: .whitespaces) }
}

/// Path (+ trimmed query) of an API URL for the compact list row; the full URL
/// is shown when the row is expanded.
private func rtShortPath(_ url: String) -> String {
    guard let components = URLComponents(string: url), components.host != nil else { return url }
    let path = components.path.isEmpty ? "/" : components.path
    if let query = components.query, !query.isEmpty {
        return path + "?" + String(query.prefix(60))
    }
    return path
}

private extension ReactotronEvent {
    /// The filterable kind matching Reactotron's filter dialog; nil for events
    /// the dialog doesn't cover, which are always shown. Sagas arrive as
    /// `.unknown` (the parser has no typed case), and the session's synthetic
    /// disconnect notice rides the Connection toggle with `clientIntro`.
    var kind: RtEventKind? {
        switch self {
        case .log: .log
        case .image: .image
        case .display: .display
        case .clientIntro: .connection
        case .benchmark: .benchmark
        case .apiResponse: .api
        case .asyncStorage: .asyncStorage
        case .stateAction: .action
        case .stateValuesChange: .subscription
        case let .unknown(type, _) where type == "saga.task.complete": .saga
        case let .unknown(type, _) where type == "disconnected": .connection
        default: nil
        }
    }

    var presentation: RtPresentation {
        switch self {
        case let .clientIntro(name, environment, _, _):
            return RtPresentation(
                badge: "CONNECT", badgeColor: .green,
                primary: [name, environment].compactMap { $0 }.joined(separator: " · "), primaryColor: .primary
            )
        case let .log(level, message, _):
            return RtPresentation(badge: level.badge, badgeColor: level.tint, primary: message, primaryColor: .primary)
        case let .display(name, _, preview, _):
            return RtPresentation(
                badge: "DISPLAY", badgeColor: .rtBadge,
                primary: [name, preview].compactMap { $0 }.joined(separator: " — "), primaryColor: .rtName
            )
        case let .image(_, _, caption, _, _):
            return RtPresentation(badge: "IMAGE", badgeColor: .rtBadge, primary: caption ?? "", primaryColor: .primary)
        case let .apiResponse(method, url, _, _, _, _):
            return RtPresentation(
                badge: "API", badgeColor: .rtBadge,
                primary: "\(method.uppercased()) \(rtShortPath(url))", primaryColor: .primary
            )
        case let .benchmark(title, _):
            return RtPresentation(badge: "BENCHMARK", badgeColor: .rtBadge, primary: title, primaryColor: .rtName)
        case .clear:
            return RtPresentation(badge: "CLEAR", badgeColor: .secondary, primary: "", primaryColor: .secondary)
        case let .asyncStorage(action, _):
            return RtPresentation(badge: "STORAGE", badgeColor: .rtBadge, primary: action, primaryColor: .rtName)
        case let .stateAction(name, _, _):
            return RtPresentation(badge: "ACTION", badgeColor: .rtBadge, primary: name, primaryColor: .rtName)
        case let .stateValuesChange(changes):
            return RtPresentation(
                badge: "STATE", badgeColor: .rtBadge,
                primary: changes.first?.path ?? "\(changes.count) changes", primaryColor: .rtName
            )
        case let .customCommandRegister(_, command, _, _, _):
            return RtPresentation(badge: "COMMAND", badgeColor: .rtBadge, primary: command, primaryColor: .rtName)
        case let .customCommandUnregister(_, command):
            return RtPresentation(badge: "COMMAND", badgeColor: .secondary, primary: "removed \(command)", primaryColor: .secondary)
        case let .stateValuesResponse(path, _):
            return RtPresentation(badge: "STATE", badgeColor: .rtBadge, primary: path ?? "store", primaryColor: .rtName)
        case let .stateKeysResponse(path, _):
            return RtPresentation(badge: "STATE", badgeColor: .rtBadge, primary: path ?? "store", primaryColor: .rtName)
        case .stateBackup:
            return RtPresentation(badge: "SNAPSHOT", badgeColor: .rtBadge, primary: "", primaryColor: .primary)
        case let .replKeys(names):
            return RtPresentation(badge: "REPL", badgeColor: .rtBadge, primary: names.joined(separator: ", "), primaryColor: .primary)
        case .replResult:
            return RtPresentation(badge: "REPL", badgeColor: .rtBadge, primary: "result", primaryColor: .primary)
        case let .unknown(type, payload):
            // The session's synthetic drop notice — not a wire event; it gets
            // warning styling and an untruncated headline.
            if type == "disconnected" {
                return RtPresentation(
                    badge: "DISCONNECTED", badgeColor: .orange,
                    primary: payload?.stringValue ?? "", primaryColor: .primary
                )
            }
            return RtPresentation(
                badge: type.uppercased(), badgeColor: .secondary,
                primary: payload?.stringValue.map { String($0.prefix(140)) } ?? "", primaryColor: .secondary
            )
        }
    }
}

private extension ReactotronLogLevel {
    var badge: String { rawValue.uppercased() }

    var tint: Color {
        switch self {
        case .debug: .secondary
        case .warn: .orange
        case .error: .red
        }
    }
}
