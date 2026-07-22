import Foundation

/// Caps and defaults for the MCP layer. Names deliberately mirror upstream
/// `lib/reactotron-mcp` (`mcp-server.ts` / `serialization.ts`) so an upstream
/// diff maps to a one-line change here — see `UPSTREAM_VERSIONS` for the
/// commit this contract targets.
public enum McpConstants {
    /// Upstream `BUFFER_SIZE`: most commands the MCP ring buffer retains.
    public static let bufferSize = 500

    /// Droidective addition (upstream has no byte cap): most cumulative wire
    /// bytes the buffer retains — a single `image`/`api.response` payload can
    /// be megabytes, and 500 of those would not be a "small ring buffer".
    public static let maxBufferBytes = 32 * 1024 * 1024

    /// Upstream `MAX_RESPONSE_CHARS`: every tool/resource result is compact
    /// JSON truncated to this, with guidance appended for the LLM.
    public static let maxResponseChars = 800_000

    /// Upstream `MAX_PAYLOAD_PREVIEW_CHARS`: timeline `payloadPreview` cap.
    public static let maxPayloadPreviewChars = 200

    /// Upstream `MAX_BODY_PREVIEW_CHARS`: network request/response body cap.
    public static let maxBodyPreviewChars = 500

    /// Upstream default MCP port (`docs/mcp.md`, desktop `config.ts`).
    public static let defaultPort: UInt16 = 4567

    /// Upstream's request/response poll timeout (1500 ms in `tools.ts`) —
    /// how long `dispatch_action`/`request_state` wait for the app's answer.
    public static let commandTimeout: Duration = .milliseconds(1500)

    /// Upstream `show_overlay` image cap (2 MB) and allowed formats.
    public static let maxOverlayImageBytes = 2 * 1024 * 1024
}
