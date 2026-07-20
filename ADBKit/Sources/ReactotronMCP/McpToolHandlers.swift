import ADBKit
import Foundation
import MCP

/// The outbound seam to the Reactotron relay. `ReactotronService` conforms;
/// tests substitute a recorder.
public protocol McpCommandSender: Sendable {
    func send(type: String, payload: JSONValue, toConnection id: Int) async
    func broadcast(type: String, payload: JSONValue) async
}

extension ReactotronService: McpCommandSender {}

/// Executes the 10 registry tools against the store and the relay — the
/// Swift port of upstream `tools.ts` handlers. Every result is
/// `safeSerialize`d text; correlation is event-driven (`store.awaitCommand`)
/// instead of upstream's 100 ms buffer polling.
public struct McpToolHandlers: Sendable {
    let store: McpCommandStore
    let sender: any McpCommandSender
    /// Reads local overlay images; tests point it at fixtures. Kept as a
    /// closure so handlers stay testable without touching the disk.
    let readFile: @Sendable (String) throws -> Data

    public init(
        store: McpCommandStore,
        sender: any McpCommandSender,
        readFile: @escaping @Sendable (String) throws -> Data = {
            try Data(contentsOf: URL(fileURLWithPath: $0))
        }
    ) {
        self.store = store
        self.sender = sender
        self.readFile = readFile
    }

    public func call(name: String, arguments: [String: Value]?) async throws -> CallTool.Result {
        guard McpToolRegistry.def(named: name) != nil else {
            throw MCPError.methodNotFound("Unknown tool: \(name)")
        }
        let args = (arguments ?? [:]).jsonObject
        switch name {
        case "dispatch_action": return await dispatchAction(args)
        case "request_state": return await requestState(args)
        case "request_state_keys": return await requestStateKeys(args)
        case "swap_state": return await swapState(args)
        case "send_custom_command": return await sendCustomCommand(args)
        case "list_custom_commands": return await listCustomCommands(args)
        case "show_overlay": return await showOverlay(args)
        case "clear_timeline": return await clearTimeline()
        case "subscribe_state": return await subscribeState(args, subscribe: true)
        case "unsubscribe_state": return await subscribeState(args, subscribe: false)
        default:
            throw MCPError.methodNotFound("Tool \(name) is registered but has no handler")
        }
    }

    // MARK: - Target resolution (upstream `resolveClientId`)

    struct ResolvedTarget {
        let clientId: String
        let connectionId: Int?
    }

    private enum Resolution {
        case resolved(ResolvedTarget)
        case error(String)
    }

    private func resolveTarget(_ args: [String: JSONValue]) async -> Resolution {
        let requested = args["clientId"]?.stringValue
        let clients = await store.connectedClients
        if clients.isEmpty {
            return .error("No apps connected to Reactotron.")
        }
        if clients.count > 1, requested == nil {
            let apps = clients
                .map { "\($0.name ?? "?") (\($0.platform ?? "?")): \($0.clientId)" }
                .joined(separator: ", ")
            return .error("Multiple apps connected. Specify clientId. Available: \(apps)")
        }
        let clientId = requested ?? clients[0].clientId
        let connectionId = clients.first { $0.clientId == clientId }?.connectionId
        return .resolved(ResolvedTarget(clientId: clientId, connectionId: connectionId))
    }

    /// Runs `body` with the resolved target app, or returns the resolve
    /// error result (the shape every targeted tool shares).
    private func withTarget(
        _ args: [String: JSONValue],
        _ body: (ResolvedTarget) async -> CallTool.Result
    ) async -> CallTool.Result {
        switch await resolveTarget(args) {
        case let .error(message): errorResult(message)
        case let .resolved(target): await body(target)
        }
    }

    private func send(type: String, payload: JSONValue, to target: ResolvedTarget) async {
        guard let connectionId = target.connectionId else { return }
        await sender.send(type: type, payload: payload, toConnection: connectionId)
    }

    // MARK: - Result shaping

    private func textResult(_ data: JSONValue, guidance: String? = nil) -> CallTool.Result {
        CallTool.Result(content: [.text(
            text: McpSerialization.safeSerialize(data, guidance: guidance),
            annotations: nil, _meta: nil
        )])
    }

    private func errorResult(_ message: String) -> CallTool.Result {
        textResult(.object(["status": .string("error"), "message": .string(message)]))
    }

    private func redactor() async -> McpRedactor {
        await McpRedactor(config: store.redactionConfig, clients: store.connectedClients)
    }

    // MARK: - Tools

    private func dispatchAction(_ args: [String: JSONValue]) async -> CallTool.Result {
        await withTarget(args) { target in
        let action = JSONValue.object([
            "type": args["actionType"] ?? .null,
            "payload": args["actionPayload"] ?? .null,
        ])
        let marker = await store.lastMessageId
        await send(type: "state.action.dispatch", payload: .object(["action": action]), to: target)

        let confirmation = await store.awaitCommand(
            ofType: "state.action.complete", clientId: target.clientId, afterMessageId: marker)
        var redactor = await redactor()
        let redactedAction = redactor.redact(action, clientId: target.clientId)
        if confirmation != nil {
            return textResult(.object([
                "status": .string("dispatched"), "action": redactedAction, "confirmed": .bool(true),
            ]))
        }
        return textResult(.object([
            "status": .string("dispatched"), "action": redactedAction, "confirmed": .bool(false),
            "note": .string("Action was sent but no confirmation received. "
                + "The app may not have the Redux plugin configured."),
        ]))
        }
    }

    private func requestState(_ args: [String: JSONValue]) async -> CallTool.Result {
        await withTarget(args) { target in
        let path = args["path"]?.stringValue ?? ""
        let marker = await store.lastMessageId
        await send(type: "state.values.request", payload: .object(["path": .string(path)]), to: target)

        guard let response = await store.awaitCommand(
            ofType: "state.values.response", clientId: target.clientId, afterMessageId: marker
        ) else {
            return textResult(.object([
                "status": .string("no_response"),
                "message": .string("The app did not respond to the state request. It likely "
                    + "doesn't have a state management plugin (Redux or MST) configured in Reactotron."),
            ]))
        }
        let stateValue = response.command.payload?["value"] ?? response.command.payload ?? .null
        var redactor = await redactor()
        let redacted = redactor.redactState(stateValue, clientId: target.clientId, statePath: path)
        return textResult(
            .object(["status": .string("success"), "state": redacted]),
            guidance: "State response is too large. Use request_state with a more specific path "
                + "(e.g. 'user.profile') to narrow the response. Use request_state_keys to "
                + "explore the state shape."
        )
        }
    }

    private func requestStateKeys(_ args: [String: JSONValue]) async -> CallTool.Result {
        await withTarget(args) { target in
        let path = args["path"]?.stringValue ?? ""
        let marker = await store.lastMessageId
        await send(type: "state.keys.request", payload: .object(["path": .string(path)]), to: target)

        guard let response = await store.awaitCommand(
            ofType: "state.keys.response", clientId: target.clientId, afterMessageId: marker
        ) else {
            return textResult(.object([
                "status": .string("no_response"),
                "message": .string("The app did not respond to the keys request. It likely "
                    + "doesn't have a state management plugin (Redux or MST) configured in Reactotron."),
            ]))
        }
        return textResult(.object([
            "status": .string("success"),
            "path": response.command.payload?["path"] ?? .string(path),
            "keys": response.command.payload?["keys"] ?? .array([]),
            "valid": response.command.payload?["valid"] ?? .bool(true),
        ]))
        }
    }

    private func swapState(_ args: [String: JSONValue]) async -> CallTool.Result {
        await withTarget(args) { target in
        await send(
            type: "state.restore.request",
            payload: .object(["state": args["state"] ?? .object([:])]),
            to: target
        )
        return textResult(.object([
            "status": .string("swapped"), "message": .string("State replacement sent to app."),
        ]))
        }
    }

    private func sendCustomCommand(_ args: [String: JSONValue]) async -> CallTool.Result {
        await withTarget(args) { target in
        let command = args["command"] ?? .null
        await send(
            type: "custom",
            payload: .object(["command": command, "args": args["args"] ?? .null]),
            to: target
        )
        return textResult(.object(["status": .string("sent"), "command": command]))
        }
    }

    private func listCustomCommands(_ args: [String: JSONValue]) async -> CallTool.Result {
        await withTarget(args) { target in
        let commands = await store.customCommands(clientId: target.clientId).map { payload in
            JSONValue.object([
                "id": payload["id"] ?? .null,
                "command": payload["command"] ?? .null,
                "title": payload["title"] ?? .null,
                "description": payload["description"] ?? .null,
            ])
        }
        if commands.isEmpty {
            return textResult(.object([
                "status": .string("none"),
                "message": .string("No custom commands registered by the app."),
            ]))
        }
        return textResult(.object(["status": .string("success"), "commands": .array(commands)]))
        }
    }

    private func showOverlay(_ args: [String: JSONValue]) async -> CallTool.Result {
        await withTarget(args) { target in
        var payload: [String: JSONValue] = [:]
        for (key, value) in args where key != "clientId" && !value.isNull {
            payload[key] = value
        }
        if args["uri"]?.isNull == true { payload["uri"] = .null }

        // Local file → data: URI (PNG/JPEG/GIF, 2 MB cap), like upstream.
        if let uri = payload["uri"]?.stringValue,
           !uri.hasPrefix("data:"), !uri.hasPrefix("http") {
            let filePath = uri.hasPrefix("file://") ? String(uri.dropFirst("file://".count)) : uri
            let ext = (filePath as NSString).pathExtension.lowercased()
            let mimeByExtension = [
                "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
            ]
            guard let mime = mimeByExtension[ext] else {
                return errorResult("Unsupported image format: .\(ext). Use PNG, JPEG, or GIF.")
            }
            guard let data = try? readFile(filePath) else {
                return errorResult("Could not read file: \(filePath)")
            }
            if data.count > McpConstants.maxOverlayImageBytes {
                let megabytes = String(format: "%.1f", Double(data.count) / 1024 / 1024)
                return errorResult("Image too large (\(megabytes)MB). Maximum is 2MB. "
                    + "Resize or compress the image first.")
            }
            payload["uri"] = .string("data:\(mime);base64,\(data.base64EncodedString())")
            if payload["width"] == nil || payload["height"] == nil,
               let size = McpImageProbe.size(of: data, extension: ext) {
                if payload["width"] == nil { payload["width"] = .number(Double(size.width)) }
                if payload["height"] == nil { payload["height"] = .number(Double(size.height)) }
            }
        }

        // Defaults matching the desktop app's overlay behavior.
        payload["opacity"] = payload["opacity"] ?? .number(0.5)
        payload["marginTop"] = payload["marginTop"] ?? .number(0)
        payload["marginRight"] = payload["marginRight"] ?? .number(0)
        payload["marginBottom"] = payload["marginBottom"] ?? .number(0)
        payload["marginLeft"] = payload["marginLeft"] ?? .number(0)
        payload["growToWindow"] = payload["growToWindow"] ?? .bool(false)
        payload["justifyContent"] = payload["justifyContent"] ?? .string("center")
        payload["alignItems"] = payload["alignItems"] ?? .string("center")

        let uriLength = payload["uri"]?.stringValue?.count ?? 0
        await send(type: "overlay", payload: .object(payload), to: target)

        var echoed = payload
        echoed["uri"] = uriLength > 0 ? .string("(\(uriLength) chars)") : .null
        return textResult(.object(["status": .string("sent"), "overlay": .object(echoed)]))
        }
    }

    private func clearTimeline() async -> CallTool.Result {
        let count = await store.bufferedCount
        await store.clear()
        return textResult(.object([
            "status": .string("cleared"), "eventsRemoved": .number(Double(count)),
        ]))
    }

    private func subscribeState(_ args: [String: JSONValue], subscribe: Bool) async -> CallTool.Result {
        guard let path = args["path"]?.stringValue, !path.isEmpty else {
            return errorResult("path is required")
        }
        var paths = await store.subscriptions
        if subscribe {
            if !paths.contains(path) { paths.append(path) }
        } else {
            paths.removeAll { $0 == path }
        }
        await store.setSubscriptions(paths)
        // Like upstream's stateValuesSubscribe: the full path list goes to
        // every client.
        await sender.broadcast(
            type: "state.values.subscribe",
            payload: .object(["paths": .array(paths.map(JSONValue.string))])
        )
        return textResult(.object([
            "status": .string(subscribe ? "subscribed" : "unsubscribed"),
            "path": .string(path),
            "activeSubscriptions": .array(paths.map(JSONValue.string)),
        ]))
    }
}

/// Width/height extraction from PNG/JPEG/GIF headers — a pure port of
/// upstream `getImageSize` so `show_overlay` can fill missing dimensions.
enum McpImageProbe {
    static func size(of data: Data, extension ext: String) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data)
        switch ext {
        case "png":
            // Width at offset 16, height at offset 20 (big-endian uint32).
            guard bytes.count > 24 else { return nil }
            return (Int(bigEndian32(bytes, at: 16)), Int(bigEndian32(bytes, at: 20)))
        case "jpg", "jpeg":
            guard bytes.count > 2, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
            var offset = 2
            while offset < bytes.count - 8 {
                guard bytes[offset] == 0xFF else { break }
                let marker = bytes[offset + 1]
                if marker == 0xC0 || marker == 0xC2 {
                    let height = Int(bigEndian16(bytes, at: offset + 5))
                    let width = Int(bigEndian16(bytes, at: offset + 7))
                    return (width, height)
                }
                offset += 2 + Int(bigEndian16(bytes, at: offset + 2))
            }
            return nil
        case "gif":
            // Width at offset 6, height at offset 8 (little-endian uint16).
            guard bytes.count > 10 else { return nil }
            return (
                Int(bytes[6]) | (Int(bytes[7]) << 8),
                Int(bytes[8]) | (Int(bytes[9]) << 8)
            )
        default:
            return nil
        }
    }

    private static func bigEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    private static func bigEndian16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }
}
