import ADBKit
import Foundation
import MCP

/// Builds one fully-wired `MCP.Server` per MCP session. A single `Server`
/// accepts exactly one `initialize` (SDK #144), so the HTTP layer calls this
/// factory for every new session; all servers share the one store/sender.
public struct McpServerFactory: Sendable {
    public let store: McpCommandStore
    let sender: any McpCommandSender
    let version: String

    public init(store: McpCommandStore, sender: any McpCommandSender, version: String) {
        self.store = store
        self.sender = sender
        self.version = version
    }

    public func makeServer() async -> Server {
        let handlers = McpToolHandlers(store: store, sender: sender)
        let resources = McpResources(store: store)

        let server = Server(
            name: "droidective-reactotron",
            version: version,
            instructions: "Reactotron debugging data from Droidective. Read the "
                + "reactotron://timeline resource (or ask for recent events) first to see "
                + "what the connected React Native app is doing, then use the tools to "
                + "query state or drive the app.",
            capabilities: Server.Capabilities(
                completions: Server.Capabilities.Completions(),
                resources: Server.Capabilities.Resources(subscribe: false, listChanged: false),
                tools: Server.Capabilities.Tools(listChanged: false)
            )
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: McpToolRegistry.all.compactMap(\.tool))
        }
        await server.withMethodHandler(CallTool.self) { params in
            try await handlers.call(name: params.name, arguments: params.arguments)
        }
        await server.withMethodHandler(ListResources.self) { _ in
            ListResources.Result(resources: await resources.list())
        }
        await server.withMethodHandler(ListResourceTemplates.self) { _ in
            ListResourceTemplates.Result(templates: resources.templates())
        }
        await server.withMethodHandler(ReadResource.self) { params in
            try await resources.read(uri: params.uri)
        }
        await server.withMethodHandler(Complete.self) { params in
            guard case let .resource(reference) = params.ref,
                  reference.uri == "reactotron://timeline/{type}",
                  params.argument.name == "type" else {
                return Complete.Result(completion: .init(values: []))
            }
            let values = await resources.completeType(prefix: params.argument.value)
            return Complete.Result(completion: .init(values: values))
        }
        return server
    }
}
