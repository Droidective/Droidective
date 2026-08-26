import ADBKit
import Foundation

/// The wire shapes for the saved custom commands.
///
/// A DTO rather than `CustomCommand` straight off the wire, for the reason the
/// deep links have one: the stored model carries fields a client has no say in
/// (`createdAt`), and letting a client post the model would make every one of
/// them client-settable by accident.
public enum CustomCommandProtocol {
    public struct Command: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let command: String
        /// "adb" or "shell" — which runner the line goes through.
        public let kind: String
        public let needsBundle: Bool
        /// Where a run shows its output: false is the headless runner with a
        /// toast, true types it into a terminal for live output and prompts.
        public let runsInTerminal: Bool
        /// Which terminal a `runsInTerminal` command opens in.
        public let terminal: String
        public let pinned: Bool
        public let createdAt: Double

        public init(_ model: CustomCommand) {
            id = model.id
            name = model.name
            command = model.command
            kind = model.kind.rawValue
            needsBundle = model.needsBundle
            runsInTerminal = model.runsInTerminal
            terminal = model.terminal.rawValue
            pinned = model.pinned
            createdAt = model.createdAt
        }

        public init(
            id: String, name: String, command: String, kind: String, needsBundle: Bool,
            runsInTerminal: Bool, terminal: String, pinned: Bool, createdAt: Double
        ) {
            self.id = id
            self.name = name
            self.command = command
            self.kind = kind
            self.needsBundle = needsBundle
            self.runsInTerminal = runsInTerminal
            self.terminal = terminal
            self.pinned = pinned
            self.createdAt = createdAt
        }

        /// The stored model.
        ///
        /// An unknown `kind` or `terminal` falls back to the default rather
        /// than rejecting the write: these are enums this build knows and a
        /// newer client may not share, and losing someone's whole command list
        /// over one unfamiliar word is the worse outcome.
        public var model: CustomCommand {
            CustomCommand(
                id: id,
                name: name,
                command: command,
                kind: CustomCommandKind(rawValue: kind) ?? .adb,
                needsBundle: needsBundle,
                createdAt: createdAt,
                runsInTerminal: runsInTerminal,
                terminal: CustomCommandTerminal(rawValue: terminal) ?? .droidective,
                pinned: pinned)
        }
    }

    /// A ready-made command someone can add to their list.
    public struct Preset: Codable, Equatable, Sendable {
        public let name: String
        public let command: String
        public let needsBundle: Bool
        public let detail: String

        public init(_ preset: CommandPreset) {
            name = preset.name
            command = preset.command
            needsBundle = preset.needsBundle
            detail = preset.detail
        }
    }

    /// The saved list, and the presets to start from.
    ///
    /// Both on one route because the presets are a static table ADBKit already
    /// holds: serving them beats porting fourteen entries into the client,
    /// where they would drift from the Mac's one preset at a time.
    public struct ListResponse: Codable, Equatable, Sendable {
        public let commands: [Command]
        public let presets: [Preset]

        public init(commands: [Command], presets: [Preset] = CommandPreset.library.map(Preset.init)) {
            self.commands = commands
            self.presets = presets
        }
    }

    /// The whole list, not an add or a delete.
    ///
    /// The client holds what it is showing, so three verbs would each have to
    /// re-derive it — the same reasoning the deep links write follows.
    public struct WriteRequest: Codable, Equatable, Sendable {
        public let commands: [Command]
        public init(commands: [Command]) { self.commands = commands }
    }

    public struct RunRequest: Codable, Equatable, Sendable {
        public let id: String
        public let serial: String
        /// For a `{bundleId}` template. Absent is fine for one that has none.
        public let bundleId: String?

        public init(id: String, serial: String, bundleId: String? = nil) {
            self.id = id
            self.serial = serial
            self.bundleId = bundleId
        }
    }

    static let badRequest = DaemonProtocol.ErrorBody(
        code: "bad_request", message: "That is not a custom-command request.", detail: nil)

    static let unknownCommand = DaemonProtocol.ErrorBody(
        code: "unknown_command", message: "There is no saved command with that id.", detail: nil)
}

/// The three custom-command routes: read the list, replace it, run one.
enum CustomCommandRoutes {
    static func read(backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        let commands = await backend.customCommands()
        return (
            200,
            DaemonProtocol.encoded(
                CustomCommandProtocol.ListResponse(
                    commands: commands.map(CustomCommandProtocol.Command.init)))
        )
    }

    static func write(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard
            let request = try? JSONDecoder().decode(
                CustomCommandProtocol.WriteRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(CustomCommandProtocol.badRequest)) }
        do {
            try await backend.writeCustomCommands(request.commands.map(\.model))
            return (200, DaemonProtocol.encoded(
                CustomCommandProtocol.ListResponse(commands: request.commands)))
        } catch {
            // The store, not a device: a disk that refuses the write is a
            // daemon-side fault and says so.
            return (500, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "store_failed", message: "Could not save the custom commands.",
                detail: "\(error)")))
        }
    }

    static func run(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard
            let request = try? JSONDecoder().decode(
                CustomCommandProtocol.RunRequest.self, from: body),
            !request.id.isEmpty, !request.serial.isEmpty
        else { return (400, DaemonProtocol.encoded(CustomCommandProtocol.badRequest)) }
        guard
            let result = await backend.runCustomCommand(
                id: request.id, serial: request.serial, bundleId: request.bundleId)
        else { return (404, DaemonProtocol.encoded(CustomCommandProtocol.unknownCommand)) }
        return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(result)))
    }
}
