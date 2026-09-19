import ADBKit
import Foundation

/// Wire shapes for the saved Send Text snippets.
///
/// The store is the Mac's own `presets.json`, under the shared support dir, so
/// a developer running both apps has one set of snippets rather than two — the
/// arrangement the deep links and the custom commands already use.
///
/// Unlike those two, the write is a **verb** rather than a whole list. The
/// rules that make a snippet — the trimmed, length-clamped name, the
/// uniqueness check, the use-count bump that ranks the quick-insert row — are
/// `Presets`' own methods, and a client re-deriving them would drift from the
/// Mac the first time one changed.
public enum PresetProtocol {
    public struct SnippetsResponse: Codable, Equatable, Sendable {
        public let snippets: [SendTextSnippet]
        public init(snippets: [SendTextSnippet]) { self.snippets = snippets }
    }

    public enum Operation: String, Codable, Sendable {
        case add
        case remove
        /// Bumps the use count and freshness that rank the quick-insert row.
        case use
    }

    public struct WriteRequest: Codable, Equatable, Sendable {
        public let op: Operation
        public let name: String
        /// Only read by `add`.
        public let text: String?

        public init(op: Operation, name: String, text: String? = nil) {
            self.op = op
            self.name = name
            self.text = text
        }
    }

    /// A snippet's text with its live values filled in.
    ///
    /// The clipboard comes *from* the client because the daemon has none — it
    /// is a headless process, and the clipboard belongs to whoever has a
    /// window. `{ip}` is the host's own address, which the daemon does have.
    public struct ExpandRequest: Codable, Equatable, Sendable {
        public let text: String
        public let clipboard: String?

        public init(text: String, clipboard: String? = nil) {
            self.text = text
            self.clipboard = clipboard
        }
    }

    public struct ExpandResponse: Codable, Equatable, Sendable {
        public let text: String
        /// What this host's address resolved to, for the "Host IP" row.
        public let hostIp: String?

        public init(text: String, hostIp: String?) {
            self.text = text
            self.hostIp = hostIp
        }
    }

    public static let duplicateName = DaemonProtocol.ErrorBody(
        code: "snippet_rejected",
        message: "A snippet needs a name and some text, and the name must be new.")
}

enum PresetRoutes {
    static func snippets(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        (200, DaemonProtocol.encoded(PresetProtocol.SnippetsResponse(
            snippets: await backend.snippets())))
    }

    static func write(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(PresetProtocol.WriteRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        let updated = await backend.writeSnippet(request)
        guard let updated else {
            // `addSnippet` answers false for an empty name, empty text or a
            // name already taken. A 409 rather than a silent no-op: the screen
            // has a field to point at.
            return (409, DaemonProtocol.encoded(PresetProtocol.duplicateName))
        }
        return (200, DaemonProtocol.encoded(PresetProtocol.SnippetsResponse(snippets: updated)))
    }

    static func expand(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(PresetProtocol.ExpandRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        let (text, hostIp) = await backend.expandSnippet(request)
        return (200, DaemonProtocol.encoded(
            PresetProtocol.ExpandResponse(text: text, hostIp: hostIp)))
    }
}
