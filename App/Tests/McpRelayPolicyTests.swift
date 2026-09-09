import Foundation
import Testing

/// Whether an MCP reconcile may start the Reactotron relay. The rule exists to
/// break a restart storm, so the tests are written as the storm's own shape.
@Suite struct McpRelayPolicyTests {
    @Test func enablingMcpStartsARelayThatIsDown() {
        #expect(McpRelayPolicy.startsRelay(trigger: .settings, relayRunning: false))
    }

    @Test func aRunningRelayIsLeftAloneAndOnlyReattached() {
        #expect(!McpRelayPolicy.startsRelay(trigger: .settings, relayRunning: true))
        #expect(!McpRelayPolicy.startsRelay(trigger: .relayChanged, relayRunning: true))
    }

    /// The storm: the relay's own `startServer` raises the relay-changed
    /// callback, and its `NWListener` then fails asynchronously when the port
    /// is taken. A reconcile scheduled by that callback must not answer the
    /// failure by starting the relay again — that start would raise the
    /// callback again, and so on without end.
    @Test func aRelayChangedReconcileNeverStartsTheRelay() {
        #expect(!McpRelayPolicy.startsRelay(trigger: .relayChanged, relayRunning: false))
    }

    /// Freeing the port and pressing Retry (or re-enabling MCP) must still
    /// bring the relay up — the rule bounds the automatic path only.
    @Test func retryAfterAFailedStartMayStartTheRelayAgain() {
        #expect(McpRelayPolicy.startsRelay(trigger: .settings, relayRunning: false))
    }

    // MARK: - Reconciling without a relay

    /// The observed outage: MCP had bound its listener, the relay's start then
    /// failed on a port the previous instance still held, and the reconcile
    /// that followed stopped the server. The relay recovered; MCP did not.
    @Test func aServingMcpOutlivesARelayOutage() {
        #expect(McpRelayPolicy.withoutRelay(mcpListening: true) == .keepServing)
    }

    @Test func aServerThatNeverCameUpReportsTheFailure() {
        #expect(McpRelayPolicy.withoutRelay(mcpListening: false) == .reportFailure)
    }
}
