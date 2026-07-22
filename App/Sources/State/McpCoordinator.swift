import ADBKit
import Foundation
import ReactotronMCP
import SwiftUI

let mcpEnabledKey = "mcpServerEnabled"
let mcpPortKey = "mcpServerPort"
let mcpTokenEnabledKey = "mcpTokenEnabled"
let mcpTokenKey = "mcpToken"
let mcpAllowClientRemoveRulesKey = "mcpAllowClientRemoveRules"
let mcpAllowClientDisableKey = "mcpAllowClientDisable"

/// App-side owner of the Reactotron MCP server: reads the Settings ▸ MCP
/// preferences, keeps the `McpServerController` in sync with them and with
/// the Reactotron relay's lifecycle, and reports a display status.
///
/// Strictly downstream of the relay: it *taps* the session's server (never
/// consumes its UI stream), and the only relay control it exercises is
/// bringing the session up when MCP is enabled while the relay is down —
/// and back down on disable only if MCP started it and no app is connected.
@MainActor @Observable
final class McpCoordinator {
    enum DisplayStatus: Equatable {
        case off
        case starting
        case listening(port: UInt16)
        /// Serving MCP, but the Reactotron relay is stopped — agents see
        /// no connected apps until it's started again.
        case listeningWithoutRelay(port: UInt16)
        case failed(String)
    }

    private(set) var status: DisplayStatus = .off

    @ObservationIgnored private let controller = McpServerController()
    @ObservationIgnored weak var app: AppState?
    /// True when enabling MCP is what started the relay — so disabling MCP
    /// can put it back down without killing a user-started session.
    @ObservationIgnored private var startedRelay = false
    /// Serializes apply/enable/disable so a toggle flurry can't interleave.
    @ObservationIgnored private var applyTask: Task<Void, Never>?

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: mcpEnabledKey)
    }

    /// With MCP on, the relay must survive window close / tab close — the
    /// whole point is agents working while the user isn't looking.
    var keepsRelayAlive: Bool { isEnabled }

    static var configuredPort: UInt16 {
        let stored = UserDefaults.standard.integer(forKey: mcpPortKey)
        guard stored > 0, stored <= 65535 else { return McpConstants.defaultPort }
        return UInt16(stored)
    }

    static var bearerToken: String? {
        guard UserDefaults.standard.bool(forKey: mcpTokenEnabledKey) else { return nil }
        if let existing = UserDefaults.standard.string(forKey: mcpTokenKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: mcpTokenKey)
        return generated
    }

    static var redactionConfig: McpRedactionServerConfig {
        McpRedactionServerConfig(
            allowClientDisable: UserDefaults.standard.bool(forKey: mcpAllowClientDisableKey),
            allowClientRemoveRules: UserDefaults.standard.bool(forKey: mcpAllowClientRemoveRulesKey)
        )
    }

    /// The copy-paste line for Claude Code, reflecting the live settings.
    static var claudeAddCommand: String {
        var command = "claude mcp add --transport http reactotron "
            + "http://127.0.0.1:\(configuredPort)/mcp"
        if let token = bearerToken {
            command += " --header \"Authorization: Bearer \(token)\""
        }
        return command
    }

    /// The `.mcp.json` server entry for Cursor and other HTTP clients.
    static var mcpJsonSnippet: String {
        let headers = bearerToken.map {
            ",\n      \"headers\": { \"Authorization\": \"Bearer \($0)\" }"
        } ?? ""
        return """
        {
          "mcpServers": {
            "reactotron": {
              "type": "http",
              "url": "http://127.0.0.1:\(Self.configuredPort)/mcp"\(headers)
            }
          }
        }
        """
    }

    // MARK: - Lifecycle

    /// Bring the server in line with the persisted settings — called at
    /// launch, on every Settings ▸ MCP change, and from the Retry button.
    /// Restarts the listener, so live agent sessions reconnect.
    func applySettings() {
        let previous = applyTask
        applyTask = Task { [weak self] in
            await previous?.value
            await self?.reconcile()
        }
    }

    /// Redaction permissions changed: push the new config without restarting
    /// the listener (live sessions keep running).
    func redactionSettingsChanged() {
        Task { await controller.setRedactionConfig(Self.redactionConfig) }
    }

    /// The Reactotron relay restarted or stopped (session start/stop/network
    /// scope change). With the relay up, re-attach to the fresh server's tap.
    /// With the relay down, keep serving but drop the stale client records so
    /// agents see `no_apps_connected` instead of ghosts — deliberately NOT
    /// restarting a relay the user just stopped.
    func reactotronServerChanged() {
        guard isEnabled, let app else { return }
        if app.reactotronSession.isRunning {
            applySettings()
        } else {
            startedRelay = false
            let listeningPort: UInt16? = if case let .listening(port) = status {
                port
            } else if case let .listeningWithoutRelay(port) = status {
                port
            } else {
                nil
            }
            if let listeningPort { status = .listeningWithoutRelay(port: listeningPort) }
            Task { await controller.noteRelayStopped() }
        }
    }

    /// Bounded teardown for app quit — closing sessions and the socket is
    /// fast, but never allowed to hold the quit hostage.
    func stopForQuit() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.controller.stop() }
            group.addTask { try? await Task.sleep(for: .seconds(2)) }
            await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Reconcile

    private func reconcile() async {
        guard let app else { return }
        guard isEnabled else {
            await controller.stop()
            if startedRelay, app.reactotronSession.isRunning,
               !app.reactotronSession.hasLiveConnection {
                await app.reactotronSession.stop()
            }
            startedRelay = false
            status = .off
            return
        }

        status = .starting
        if !app.reactotronSession.isRunning {
            await app.reactotronSession.start(serials: app.reactotronSession.readyAndroidSerials)
            if app.reactotronSession.isRunning { startedRelay = true }
        }
        guard let (events, sender) = await app.reactotronSession.mcpAttachment() else {
            await controller.stop()
            status = .failed("The Reactotron server isn't running — open the Reactotron "
                + "feature and start it, then retry.")
            return
        }

        await controller.setRedactionConfig(Self.redactionConfig)
        do {
            try await controller.start(
                events: events,
                sender: sender,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? "dev",
                port: Self.configuredPort,
                bearerToken: Self.bearerToken
            )
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        if case let .listening(port) = await controller.status {
            status = .listening(port: port)
        }
    }
}
