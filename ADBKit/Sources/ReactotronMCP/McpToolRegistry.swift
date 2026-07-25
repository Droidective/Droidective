// ReactotronMCP serves the Reactotron relay's data, and that relay is
// `Network.framework`-based, so this whole target is Apple-only until the
// listener moves to NIO or raw sockets (a port follow-up). Gated rather than
// stubbed: off-Apple the module simply exposes nothing.
#if canImport(Network)

import Foundation
import MCP

/// One MCP tool: name, description, and its JSON-Schema input — the
/// declarative registry the `FeatureRegistry` way, so `tools/list` and
/// dispatch are driven from one table and an invariant test keeps the
/// handler map 1:1 with it.
public struct McpToolDef: Sendable {
    public let name: String
    public let description: String
    /// JSON Schema as JSON text (decoded to an SDK `Value` on listing; a
    /// registry test decodes every schema so a typo fails `swift test`).
    public let inputSchemaJSON: String

    var inputSchema: Value? {
        try? JSONDecoder().decode(Value.self, from: Data(inputSchemaJSON.utf8))
    }

    var tool: Tool? {
        guard let schema = inputSchema else { return nil }
        return Tool(name: name, description: description, inputSchema: schema)
    }
}

/// The 10-tool contract of upstream `lib/reactotron-mcp/src/tools.ts` —
/// names, descriptions, and schemas ported verbatim (descriptions matter:
/// they are the LLM's only manual). See `UPSTREAM_VERSIONS` for the pinned
/// upstream commit; `scripts/check-reactotron-upstream.sh` diffs against it.
public enum McpToolRegistry {
    static let clientIdProperty =
        #""clientId":{"type":"string","description":"Target app clientId (required when multiple apps connected)."}"#

    public static let all: [McpToolDef] = [
        McpToolDef(
            name: "dispatch_action",
            description: "Dispatch a Redux action to the connected app. "
                + "Requires the Reactotron Redux plugin to be configured in the app. "
                + "Example: { type: 'user/setName', payload: { name: 'Alice' } }",
            inputSchemaJSON: """
            {"type":"object","properties":{
              "actionType":{"type":"string","description":"Action type, e.g. 'counter/increment' or 'RESET'"},
              "actionPayload":{"description":"Optional action payload, e.g. { name: 'Alice' }"},
              \(clientIdProperty)},
             "required":["actionType"]}
            """
        ),
        McpToolDef(
            name: "request_state",
            description: "Request a fresh state snapshot from the connected app. "
                + "Requires Redux or MST plugin configured in the app. "
                + "IMPORTANT: Always specify a path to avoid oversized responses. "
                + "The full state tree can be millions of characters. "
                + "Use request_state_keys first to explore the state shape, then request specific slices. "
                + "Example path: 'user.profile' to get just that slice.",
            inputSchemaJSON: """
            {"type":"object","properties":{
              "path":{"type":"string","description":"Dot-separated state path, e.g. 'user.profile'. STRONGLY RECOMMENDED — omitting this returns the full state tree which may be too large."},
              \(clientIdProperty)}}
            """
        ),
        McpToolDef(
            name: "request_state_keys",
            description: "List the keys at a state path without fetching values. "
                + "Use this to explore the state tree structure before requesting specific slices with request_state. "
                + "Returns an array of key names at the given path. "
                + "Example: path='' returns root keys, path='user' returns keys under user.",
            inputSchemaJSON: """
            {"type":"object","properties":{
              "path":{"type":"string","description":"Dot-separated state path. Omit or pass empty string for root keys."},
              \(clientIdProperty)}}
            """
        ),
        McpToolDef(
            name: "swap_state",
            description: "Replace the entire app state tree. WARNING: this is destructive and cannot be undone. "
                + "Requires the Reactotron state plugin (Redux or MST). "
                + "Use request_state first to get the current state, modify it, then swap.",
            inputSchemaJSON: """
            {"type":"object","properties":{
              "state":{"type":"object","description":"The complete replacement state tree as a JSON object."},
              \(clientIdProperty)},
             "required":["state"]}
            """
        ),
        McpToolDef(
            name: "send_custom_command",
            description: "Send a named custom command to the app. "
                + "The app must have registered a handler for this command name. "
                + "Use list_custom_commands first to see what commands are available. "
                + "Example: command='showDebugOverlay', args={ enabled: true }",
            inputSchemaJSON: """
            {"type":"object","properties":{
              "command":{"type":"string","description":"The custom command name, e.g. 'ping' or 'showDebugOverlay'"},
              "args":{"description":"Optional arguments to pass to the command handler"},
              \(clientIdProperty)},
             "required":["command"]}
            """
        ),
        McpToolDef(
            name: "list_custom_commands",
            description: "List all custom commands registered by the connected app. "
                + "These are commands the app has set up handlers for. "
                + "Use this before send_custom_command to see what's available.",
            inputSchemaJSON: """
            {"type":"object","properties":{\(clientIdProperty)}}
            """
        ),
        McpToolDef(
            name: "show_overlay",
            description: "Show an image overlay on top of the running app. "
                + "Useful for comparing a design mockup against the actual UI. "
                + "The app must have the overlay plugin enabled (it is by default in React Native). "
                + "Pass uri=null or opacity=0 to hide the overlay.",
            inputSchemaJSON: """
            {"type":"object","properties":{
              "uri":{"type":["string","null"],"description":"Image to display. Accepts a local file path (/path/to/image.png), file:// URI, http/https URL, or data: URI. Local files are automatically converted to base64. Pass null to clear the overlay."},
              "opacity":{"type":"number","description":"Overlay opacity from 0 to 1 (default: 0.5)"},
              "growToWindow":{"type":"boolean","description":"Scale image to fill the entire window (default: false)"},
              "resizeMode":{"type":"string","enum":["cover","contain","stretch","center"],"description":"How to resize the image when growToWindow is true (default: cover)"},
              "width":{"type":"number","description":"Image width in pixels (ignored if growToWindow is true)"},
              "height":{"type":"number","description":"Image height in pixels (ignored if growToWindow is true)"},
              "marginTop":{"type":"number","description":"Top margin offset in pixels"},
              "marginBottom":{"type":"number","description":"Bottom margin offset in pixels"},
              "marginLeft":{"type":"number","description":"Left margin offset in pixels"},
              "marginRight":{"type":"number","description":"Right margin offset in pixels"},
              "justifyContent":{"type":"string","enum":["flex-start","flex-end","center","space-between","space-around","space-evenly"],"description":"Vertical alignment of the overlay image (default: center)"},
              "alignItems":{"type":"string","enum":["flex-start","flex-end","center","stretch","baseline"],"description":"Horizontal alignment of the overlay image (default: center)"},
              "showDebug":{"type":"boolean","description":"Show debug info overlay with current overlay settings (useful for positioning)"},
              \(clientIdProperty)},
             "required":["uri"]}
            """
        ),
        McpToolDef(
            name: "clear_timeline",
            description: "Clear the MCP event buffer. This only affects what you see via MCP resources — "
                + "the Reactotron timeline in the app is not affected. "
                + "Useful to discard old events and focus on what happens next.",
            inputSchemaJSON: #"{"type":"object","properties":{}}"#
        ),
        McpToolDef(
            name: "subscribe_state",
            description: "Subscribe to a state path. The app will send state.values.change events "
                + "whenever the value at this path changes. "
                + "Read the state/subscriptions resource to see changes. "
                + "Requires Redux or MST plugin. Example path: 'user.profile.name'",
            inputSchemaJSON: """
            {"type":"object","properties":{
              "path":{"type":"string","description":"Dot-separated state path to subscribe to, e.g. 'user.profile' or 'cart.items'"}},
             "required":["path"]}
            """
        ),
        McpToolDef(
            name: "unsubscribe_state",
            description: "Unsubscribe from a state path. Stops receiving change events for this path.",
            inputSchemaJSON: """
            {"type":"object","properties":{
              "path":{"type":"string","description":"State path to unsubscribe from"}},
             "required":["path"]}
            """
        ),
    ]

    public static func def(named name: String) -> McpToolDef? {
        all.first { $0.name == name }
    }
}

#endif
