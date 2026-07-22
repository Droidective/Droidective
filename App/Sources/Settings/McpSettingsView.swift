import ADBKit
import AppKit
import ReactotronMCP
import SwiftUI

/// Settings ▸ MCP: serve the Reactotron relay's data to AI agents (Claude
/// Code, Cursor) over localhost Streamable HTTP — the same contract as the
/// official Reactotron desktop's MCP server, off by default.
struct McpSettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage(mcpEnabledKey) private var mcpEnabled = false
    @AppStorage(mcpPortKey) private var mcpPort = Int(McpConstants.defaultPort)
    @AppStorage(mcpTokenEnabledKey) private var tokenEnabled = false
    @AppStorage(mcpTokenKey) private var token = ""
    @AppStorage(mcpAllowClientRemoveRulesKey) private var allowClientRemoveRules = false
    @AppStorage(mcpAllowClientDisableKey) private var allowClientDisable = false

    var body: some View {
        Form {
            serverSection
            connectSection
            authSection
            redactionSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Server

    private var serverSection: some View {
        Section("MCP server") {
            Toggle("Serve Reactotron data to AI agents", isOn: $mcpEnabled)
                .onChange(of: mcpEnabled) { state.mcp.applySettings() }
            LabeledContent("Status") {
                statusLabel
            }
            LabeledContent("Port") {
                TextField("", value: $mcpPort, format: .number.grouping(.never))
                    .labelsHidden()
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { state.mcp.applySettings() }
            }
            Text("Enabling starts the Reactotron server (port 9090) and an MCP endpoint "
                + "on 127.0.0.1 that AI agents can query: the event timeline, network "
                + "log, Redux/MST state, and tools to dispatch actions or run custom "
                + "commands. Localhost only — never reachable from the network.")
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch state.mcp.status {
        case .off:
            Text("Off").foregroundStyle(.textMuted)
        case .starting:
            Text("Starting…").foregroundStyle(.textMuted)
        case let .listening(port):
            Label("Listening on 127.0.0.1:\(String(port))", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.app(.callout))
        case let .listeningWithoutRelay(port):
            VStack(alignment: .trailing, spacing: 4) {
                Label("Listening on 127.0.0.1:\(String(port))", systemImage: "circle.fill")
                    .foregroundStyle(.orange)
                    .font(.app(.callout))
                Text("The Reactotron server is stopped — agents see no apps. "
                    + "Open the Reactotron feature to start it.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
                    .multilineTextAlignment(.trailing)
            }
        case let .failed(reason):
            VStack(alignment: .trailing, spacing: 4) {
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.app(.callout))
                Text(reason)
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
                    .multilineTextAlignment(.trailing)
                Button("Retry") { state.mcp.applySettings() }
            }
        }
    }

    // MARK: - Connect

    private var connectSection: some View {
        Section("Connect an agent") {
            LabeledContent("Claude Code") {
                copyButton(McpCoordinator.claudeAddCommand, label: "Copy command")
            }
            LabeledContent("Cursor / .mcp.json") {
                copyButton(McpCoordinator.mcpJsonSnippet, label: "Copy JSON")
            }
            Text("Same setup as the official Reactotron MCP server — agents get the "
                + "identical tools and resources.")
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
        }
    }

    private func copyButton(_ content: String, label: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
            state.showToast(Toast(message: "Copied", ok: true))
        } label: {
            Label(label, systemImage: "doc.on.doc")
        }
    }

    // MARK: - Authentication

    private var authSection: some View {
        Section("Authentication") {
            Toggle("Require a bearer token", isOn: $tokenEnabled)
                .onChange(of: tokenEnabled) {
                    if tokenEnabled, token.isEmpty { token = UUID().uuidString }
                    state.mcp.applySettings()
                }
            if tokenEnabled {
                LabeledContent("Token") {
                    HStack(spacing: 8) {
                        Text(token)
                            .font(.app(.footnote).monospaced())
                            .foregroundStyle(.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220, alignment: .trailing)
                        Button("Regenerate") {
                            token = UUID().uuidString
                            state.mcp.applySettings()
                        }
                    }
                }
            }
            Text("Off (the Reactotron default), any local process can query the "
                + "endpoint. On, requests must send the token — the copy buttons "
                + "above include it automatically.")
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
        }
    }

    // MARK: - Redaction

    private var redactionSection: some View {
        Section("Redaction") {
            LabeledContent("Sensitive values") {
                Label(
                    allowClientDisable ? "Apps may opt out" : "Always redacted",
                    systemImage: allowClientDisable ? "shield" : "shield.fill"
                )
                .foregroundStyle(allowClientDisable ? .orange : .green)
                .font(.app(.callout))
            }
            Toggle("Let apps remove specific rules", isOn: $allowClientRemoveRules)
                .onChange(of: allowClientRemoveRules) { state.mcp.redactionSettingsChanged() }
            Toggle("Let apps disable redaction entirely", isOn: $allowClientDisable)
                .onChange(of: allowClientDisable) { state.mcp.redactionSettingsChanged() }
            Text("Passwords, tokens, cookies, API keys, and key-shaped values are "
                + "redacted before anything reaches an agent (the Reactotron window "
                + "itself is never redacted). Apps can add their own rules via "
                + "mcpRedaction in their Reactotron config; removing or disabling "
                + "rules also needs the matching permission above.")
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
        }
    }
}
