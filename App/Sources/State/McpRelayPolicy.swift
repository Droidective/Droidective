import Foundation

/// Whether an MCP reconcile is allowed to bring the Reactotron relay up itself.
///
/// Pure and separate from `McpCoordinator` because the case it exists for
/// cannot be reached through the coordinator in a test: the relay's
/// `startServer` raises `reactotronServerChanged()` *while* it is starting, so
/// a reconcile that starts the relay is told about its own start. That is
/// harmless while the relay stays up — but an `NWListener` fails
/// asynchronously, so when port 9090 is already taken (another Droidective, or
/// the Reactotron desktop app) the server exists for a few milliseconds and is
/// then gone. The reconcile that callback scheduled therefore finds the relay
/// down, starts it again, is told about *that* start, and so on: a
/// free-running restart storm — hundreds of listener binds and `adb reverse`
/// invocations a second — with the Reactotron pane flickering between
/// "Waiting for your app" and "Port 9090 is taken".
///
/// The rule that breaks it: a notification *about* the relay never changes the
/// relay. It exists to re-attach the tap; only the user's own actions (enabling
/// MCP, launch, Retry) may start a relay that is down.
enum McpRelayPolicy {
    /// What scheduled the reconcile.
    enum Trigger {
        /// Launch, a Settings ▸ MCP change, or a Retry button — the user asked
        /// for MCP to be working, so bringing the relay up is part of that.
        case settings
        /// The relay itself started or stopped and MCP is only re-attaching.
        case relayChanged
    }

    /// Whether this reconcile should start the Reactotron relay.
    ///
    /// - Parameters:
    ///   - trigger: what scheduled the reconcile.
    ///   - relayRunning: whether the relay is up already, in which case there
    ///     is nothing to start and the reconcile just attaches its tap.
    static func startsRelay(trigger: Trigger, relayRunning: Bool) -> Bool {
        switch trigger {
        case .settings: !relayRunning
        case .relayChanged: false
        }
    }
}
