import ADBKit
import Foundation

/// The one type the App layer talks to: owns the MCP command store, the tap
/// consumption task, and the HTTP listener. Downstream-only — the Reactotron
/// relay never waits on anything here, and stopping MCP never touches the
/// relay or the UI timeline.
public actor McpServerController {
    public enum Status: Sendable, Equatable {
        case stopped
        case listening(port: UInt16)
        case failed(String)
    }

    private let store = McpCommandStore()
    private var listener: McpHTTPListener?
    private var tapTask: Task<Void, Never>?
    private var currentStatus: Status = .stopped

    public init() {}

    public var status: Status { currentStatus }

    /// The store, exposed for status UI (connected apps, buffered count) —
    /// reads only.
    public var commandStore: McpCommandStore { store }

    public var redactionConfig: McpRedactionServerConfig {
        get async { await store.redactionConfig }
    }

    public func setRedactionConfig(_ config: McpRedactionServerConfig) async {
        await store.setRedactionConfig(config)
    }

    /// Start serving MCP: subscribe to the relay's event tap and bind the
    /// localhost listener. `events` is `ReactotronService.tap()`; `sender`
    /// is the service itself. Throws (and records `.failed`) if the port is
    /// taken — the relay tap is torn back down so a retry starts clean.
    public func start(
        events: AsyncStream<ReactotronServer.Event>,
        sender: any McpCommandSender,
        version: String,
        port: UInt16 = McpConstants.defaultPort,
        bearerToken: String? = nil
    ) async throws {
        await stopListener()

        tapTask?.cancel()
        let store = store
        tapTask = Task {
            for await event in events {
                guard !Task.isCancelled else { break }
                await store.ingest(event)
            }
        }

        let factory = McpServerFactory(store: store, sender: sender, version: version)
        let listener = McpHTTPListener(
            configuration: McpHTTPListener.Configuration(port: port, bearerToken: bearerToken),
            factory: factory
        )
        do {
            try await listener.start()
        } catch {
            tapTask?.cancel()
            tapTask = nil
            currentStatus = .failed(error.localizedDescription)
            throw error
        }
        self.listener = listener
        let bound = await listener.boundPort ?? port
        currentStatus = .listening(port: bound)
    }

    /// Stop serving. Bounded work (session closes + socket close), so it is
    /// safe inside the app's quit budget.
    public func stop() async {
        tapTask?.cancel()
        tapTask = nil
        await stopListener()
        currentStatus = .stopped
    }

    private func stopListener() async {
        if let listener {
            await listener.stop()
        }
        listener = nil
    }
}
