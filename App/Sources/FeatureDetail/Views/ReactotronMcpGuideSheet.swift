import ADBKit
import AppKit
import ReactotronMCP
import SwiftUI

/// The in-feature onboarding for MCP: turn the server on, connect an agent,
/// try a prompt — all from the Reactotron screen (Settings ▸ MCP stays the
/// place for port/token/redaction options). Opened from the header's
/// "AI Agents" button.
struct McpAgentGuideSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage(mcpEnabledKey) private var mcpEnabled = false
    @State private var agent: Agent = .claudeCode

    enum Agent: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case cursor = "Cursor"
        case vsCode = "VS Code"
        case other = "Any MCP client"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                stepOne
                stepTwo
                stepThree
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 12) {
                SettingsLink {
                    Text("Settings ▸ MCP")
                }
                .help("Port, bearer token, and redaction rules")
                Text("Localhost only. Passwords, tokens, and keys are redacted "
                    + "before anything reaches an agent.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 620)
    }

    // MARK: - Step 1: turn it on

    private var stepOne: some View {
        Section("Step 1 — Turn on the MCP server") {
            Toggle("Serve Reactotron data to AI agents", isOn: $mcpEnabled)
                .onChange(of: mcpEnabled) { state.mcp.applySettings() }
            LabeledContent("Status") { statusLabel }
            Text("Agents get this timeline, the network log, and Redux/MST state — "
                + "plus tools to dispatch actions and run the app's custom commands. "
                + "Keeps running while the window is closed.")
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch state.mcp.status {
        case .off:
            Text(mcpEnabled ? "Starting…" : "Off")
                .foregroundStyle(.textMuted)
        case .starting:
            Text("Starting…").foregroundStyle(.textMuted)
        case let .listening(port):
            Label("Serving on 127.0.0.1:\(String(port))", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.app(.callout))
        case let .listeningWithoutRelay(port):
            Label("Serving on 127.0.0.1:\(String(port)) — Reactotron server stopped",
                  systemImage: "circle.fill")
                .foregroundStyle(.orange)
                .font(.app(.callout))
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

    // MARK: - Step 2: connect the agent

    private var stepTwo: some View {
        Section("Step 2 — Connect your agent") {
            Picker("Agent", selection: $agent) {
                ForEach(Agent.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(instructions)
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)

            snippetBox(snippet)
        }
    }

    private var livePort: UInt16 {
        if case let .listening(port) = state.mcp.status { return port }
        if case let .listeningWithoutRelay(port) = state.mcp.status { return port }
        return McpCoordinator.configuredPort
    }

    private var endpointURL: String { "http://127.0.0.1:\(livePort)/mcp" }

    private var instructions: String {
        switch agent {
        case .claudeCode:
            "Run this in your React Native project's terminal, then ask Claude "
                + "about your app (add --scope project to share it via .mcp.json)."
        case .cursor:
            "Save this as .mcp.json in your project root, or paste the server "
                + "into Cursor Settings ▸ MCP. Cursor picks it up on reload."
        case .vsCode:
            "Save this as .vscode/mcp.json in your project. Copilot Chat's "
                + "agent mode lists the reactotron tools once the server starts."
        case .other:
            "Any client that speaks MCP's Streamable HTTP transport can "
                + "connect to the endpoint below"
                + (McpCoordinator.bearerToken != nil
                    ? " — send the Authorization header from Settings ▸ MCP."
                    : ".")
        }
    }

    private var snippet: String {
        switch agent {
        case .claudeCode:
            return McpCoordinator.claudeAddCommand
        case .cursor:
            return McpCoordinator.mcpJsonSnippet
        case .vsCode:
            let headers = McpCoordinator.bearerToken.map {
                ",\n      \"headers\": { \"Authorization\": \"Bearer \($0)\" }"
            } ?? ""
            return """
            {
              "servers": {
                "reactotron": {
                  "type": "http",
                  "url": "\(endpointURL)"\(headers)
                }
              }
            }
            """
        case .other:
            return endpointURL
        }
    }

    private func snippetBox(_ content: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ScrollView(.horizontal) {
                Text(content)
                    .font(.app(.footnote).monospaced())
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content, forType: .string)
                state.showToast(Toast(message: "Copied", ok: true))
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Step 3: try it

    private static let samplePrompts = [
        "What's happening in my app right now?",
        "Show me the failed network requests and what caused them.",
        "Read the redux state under user and tell me what's wrong with it.",
    ]

    private var stepThree: some View {
        Section("Step 3 — Try it") {
            ForEach(Self.samplePrompts, id: \.self) { prompt in
                HStack(spacing: 8) {
                    Text("“\(prompt)”")
                        .font(.app(.callout))
                        .foregroundStyle(.textMuted)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prompt, forType: .string)
                        state.showToast(Toast(message: "Copied", ok: true))
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy prompt")
                }
            }
        }
    }

}
