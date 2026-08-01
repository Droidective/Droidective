#if canImport(Network)

import Foundation
import MCP
import Testing
@testable import ReactotronMCP

/// Pins the served MCP contract — tool names, their input properties (with
/// required markers), and resource URIs — against a golden signature that
/// matches upstream `lib/reactotron-mcp` at the commit in
/// `scripts/reactotron-upstream.lock`.
///
/// When syncing to a new upstream release: port the change, run this test,
/// and update the golden below from the failure message's "actual" output —
/// the diff between the two IS the contract change, reviewable in the PR.
@Suite struct McpGoldenContractTests {
    /// `tool(prop,prop…)` with `*` marking required properties, sorted.
    static let goldenToolSignature = """
    clear_timeline()
    dispatch_action(actionPayload,actionType*,clientId)
    list_custom_commands(clientId)
    request_state(clientId,path)
    request_state_keys(clientId,path)
    send_custom_command(args,clientId,command*)
    show_overlay(alignItems,clientId,growToWindow,height,justifyContent,marginBottom,marginLeft,marginRight,marginTop,opacity,resizeMode,showDebug,uri*,width)
    subscribe_state(path*)
    swap_state(clientId,state*)
    unsubscribe_state(path*)
    """

    static let goldenResourceURIs = """
    reactotron://apps
    reactotron://asyncstorage
    reactotron://benchmarks
    reactotron://network/log
    reactotron://state/current
    reactotron://state/subscriptions
    reactotron://timeline
    reactotron://timeline/{type}
    """

    @Test func toolContractMatchesTheGoldenSignature() throws {
        var lines: [String] = []
        for def in McpToolRegistry.all.sorted(by: { $0.name < $1.name }) {
            let schema = try #require(def.inputSchema)
            guard case let .object(root) = schema,
                  case let .object(properties)? = root["properties"] else {
                Issue.record("schema for \(def.name) has no properties object")
                continue
            }
            let required: Set<String> = if case let .array(names)? = root["required"] {
                Set(names.compactMap { if case let .string(name) = $0 { name } else { nil } })
            } else {
                []
            }
            let props = properties.keys.sorted()
                .map { required.contains($0) ? "\($0)*" : $0 }
                .joined(separator: ",")
            lines.append("\(def.name)(\(props))")
        }
        let actual = lines.joined(separator: "\n")
        #expect(
            actual == Self.goldenToolSignature,
            "Tool contract drifted. Actual signature:\n\(actual)"
        )
    }

    @Test func resourceContractMatchesTheGoldenURIs() {
        var uris = McpResources.staticResources.map(\.uri)
        uris.append(McpResources.timelineTemplate.uriTemplate)
        let actual = uris.sorted().joined(separator: "\n")
        #expect(
            actual == Self.goldenResourceURIs,
            "Resource contract drifted. Actual URIs:\n\(actual)"
        )
    }
}

#endif
