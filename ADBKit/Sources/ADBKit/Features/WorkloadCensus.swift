import Foundation

/// What the app was actually doing when something went wrong.
///
/// A resource alert used to carry the metric that tripped, its limit, and the
/// name of whatever feature happened to be on screen. That last part is the
/// problem: every tab stays mounted, so `active_feature` names what the user
/// was *looking at*, which on the incidents seen so far was rarely what was
/// doing the work — a Reactotron tab in front while three mirrors streamed
/// behind it reports `reactotron`.
///
/// The counts here are the difference between "high memory while reactotron
/// was active" and "high memory with 3 mirrors, 2 recordings and 14 tabs
/// across 3 windows on an 11-hour session". Only the second can be optimised.
///
/// Counts and durations only — never a serial, a bundle id, or a path.
///
/// Two things a reader will look for and not find: how many screen recordings
/// are running, and how many feeds have a live connection. Neither has an
/// app-wide registry to ask — recording state lives per tab and feed
/// connections live per view — and a field that is always zero reads as "none
/// were running" rather than "nobody counted", which is worse than its
/// absence. They belong here once those registries exist.
public struct WorkloadCensus: Sendable, Equatable {
    /// Live scrcpy sessions: the in-tab mirror, every Mirror Wall tile, every
    /// pop-out window. Each decodes H.264 in-process, so this is the single
    /// biggest predictor of CPU.
    public var mirrorSessions: Int
    /// Open PTY shells, across every terminal tab and split pane.
    public var shells: Int
    /// Devices the app can see (USB, wireless, emulators, simulators).
    public var devices: Int
    /// Workspace windows open. Each holds its own tab set, and every tab in
    /// every one of them stays mounted.
    public var windows: Int
    /// Feature tabs mounted across all windows — the direct measure of how
    /// much view tree each layout pass walks.
    public var tabs: Int
    /// Seconds since launch. A footprint means one thing ten minutes in and
    /// another eleven hours in, and growth percentage alone cannot say which.
    public var sessionSeconds: Int

    public init(
        mirrorSessions: Int = 0,
        shells: Int = 0,
        devices: Int = 0,
        windows: Int = 0,
        tabs: Int = 0,
        sessionSeconds: Int = 0
    ) {
        self.mirrorSessions = mirrorSessions
        self.shells = shells
        self.devices = devices
        self.windows = windows
        self.tabs = tabs
        self.sessionSeconds = sessionSeconds
    }

    /// Flattened for telemetry, under a fixed `work_` namespace.
    ///
    /// Zeroes are kept rather than omitted. "No mirror was running" is a fact
    /// that rules a cause out, and an absent key cannot be distinguished from
    /// an older app version that never sent it.
    public var properties: [String: Int] {
        [
            "work_mirrors": mirrorSessions,
            "work_shells": shells,
            "work_devices": devices,
            "work_windows": windows,
            "work_tabs": tabs,
            "work_session_seconds": sessionSeconds,
        ]
    }

    /// A one-line summary for a Sentry title or a local log, so an incident is
    /// readable without opening the properties. Only the parts that are
    /// actually happening appear — "3 mirrors, 14 tabs, 2 windows".
    public var summary: String {
        var parts: [String] = []
        if mirrorSessions > 0 { parts.append(count(mirrorSessions, "mirror")) }
        if shells > 0 { parts.append(count(shells, "shell")) }
        if tabs > 0 { parts.append(count(tabs, "tab")) }
        if windows > 1 { parts.append(count(windows, "window")) }
        return parts.isEmpty ? "idle" : parts.joined(separator: ", ")
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
