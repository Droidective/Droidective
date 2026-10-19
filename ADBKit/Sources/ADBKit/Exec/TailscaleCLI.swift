import Foundation

/// Where the Tailscale command line lives, and which kind it is.
///
/// Two kinds, because they are started differently. A `tailscale` on the PATH
/// — the standalone Mac app's "Install CLI", Homebrew, a Linux package, the
/// Windows installer — runs as itself. The Mac App Store build ships no CLI at
/// all: its bundle executable acts as one only when `TAILSCALE_BE_CLI=1` is in
/// its environment. `ProcessRunning` has no environment parameter, and
/// `SystemProcessRunner` *replaces* the environment when given one, so that
/// variable goes in through `/usr/bin/env`, which keeps the rest intact and
/// keeps the call an ordinary argument vector a test can assert.
public struct TailscaleCLI: Sendable, Equatable {
    public enum Flavor: String, Sendable, Codable {
        /// A `tailscale` binary that runs as the CLI on its own.
        case standalone
        /// The Mac app's bundle executable, run with `TAILSCALE_BE_CLI=1`.
        case appBundle
    }

    public let path: String
    public let flavor: Flavor

    public init(path: String, flavor: Flavor) {
        self.path = path
        self.flavor = flavor
    }

    /// The Mac app's bundle executable, the App Store build's only CLI.
    public static let macAppBundlePath = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

    /// The process to spawn for `tailscale <arguments>`.
    public func invocation(_ arguments: [String]) -> (executable: String, arguments: [String]) {
        switch flavor {
        case .standalone:
            return (path, arguments)
        case .appBundle:
            return ("/usr/bin/env", ["TAILSCALE_BE_CLI=1", path] + arguments)
        }
    }
}
