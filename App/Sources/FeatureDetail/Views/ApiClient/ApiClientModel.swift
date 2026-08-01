import ADBKit
import Foundation
import Observation

/// State and actions behind the API Testing pane.
///
/// All of the HTTP work lives in ADBKit; this holds the editor's state, drives
/// persistence, and keeps the send in a cancellable `Task` so navigating away
/// tears the request down instead of orphaning it.
@Observable
@MainActor
final class ApiClientModel {

    // MARK: Persisted data

    var data = ApiClientData()

    // MARK: Editor state

    var current = SavedRequest()
    /// Collection the open request belongs to, for inherited auth and variables.
    var currentCollectionId: String?
    var response: ApiResponse?
    var prepared: PreparedRequest?
    var assertionResults: [AssertionResult] = []
    var warnings: [String] = []
    var errorText: String?
    var isSending = false

    // MARK: Runner

    var runSummary: RunSummary?
    var runningCollectionId: String?
    var runProgress: [RunResult] = []

    // MARK: Import feedback

    var importReport: String?

    private var engine: FeatureEngine?
    private var store: JSONStore<ApiClientData>?
    private var sendTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func attach(engine: FeatureEngine, store: JSONStore<ApiClientData>) async {
        guard self.store == nil else { return }
        self.engine = engine
        self.store = store
        data = await store.load()
    }

    /// Cancels in-flight work. Called when the pane goes away.
    func teardown() {
        sendTask?.cancel()
        runTask?.cancel()
        sendTask = nil
        runTask = nil
        isSending = false
        runningCollectionId = nil
    }

    func persist() {
        guard let store else { return }
        let snapshot = data
        Task { try? await store.save(snapshot) }
    }

    // MARK: - Scope

    var activeCollection: ApiCollection? {
        guard let currentCollectionId else { return nil }
        return data.collections.first { $0.id == currentCollectionId }
    }

    var scope: VariableScope {
        data.scope(for: activeCollection)
    }

    var inheritedAuth: AuthSpec? {
        guard let auth = activeCollection?.auth, auth.type != .none else { return nil }
        return auth
    }

    var unresolvedVariables: [String] {
        ApiVariables.unresolvedNames(in: current, scope: scope)
    }

    // MARK: - Sending

    var canSend: Bool {
        !current.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    func send() {
        guard let engine, canSend else { return }
        sendTask?.cancel()
        isSending = true
        errorText = nil
        response = nil
        assertionResults = []
        warnings = []

        let request = current
        let scope = scope
        let inherited = inheritedAuth
        let client = engine.httpClient

        sendTask = Task { [weak self] in
            do {
                let outcome = try await client.send(
                    request, scope: scope, inheritedAuth: inherited
                )
                guard let self, !Task.isCancelled else { return }
                response = outcome.response
                prepared = outcome.prepared
                assertionResults = outcome.assertions
                warnings = outcome.warnings
                record(outcome: outcome, for: request)
            } catch is CancellationError {
                guard let self else { return }
                errorText = "Request cancelled."
            } catch {
                guard let self, !Task.isCancelled else { return }
                errorText = error.localizedDescription
                record(failure: error, for: request)
            }
            self?.isSending = false
        }
    }

    func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
    }

    private func record(outcome: ApiSendOutcome, for request: SavedRequest) {
        data.addToHistory(
            ApiHistoryEntry(
                method: request.method,
                url: outcome.prepared.url,
                statusCode: outcome.response.statusCode,
                elapsedMs: outcome.response.elapsedMs,
                responseSize: outcome.response.size,
                request: request
            )
        )
        persist()
    }

    private func record(failure: any Error, for request: SavedRequest) {
        data.addToHistory(
            ApiHistoryEntry(
                method: request.method,
                url: request.url,
                errorText: failure.localizedDescription,
                request: request
            )
        )
        persist()
    }

    // MARK: - Editor actions

    func open(_ request: SavedRequest, in collectionId: String?) {
        cancelSend()
        current = request
        currentCollectionId = collectionId
        response = nil
        prepared = nil
        errorText = nil
        warnings = []
        assertionResults = []
    }

    func newRequest() {
        open(SavedRequest(), in: currentCollectionId)
    }

    func loadCurl(_ text: String) -> [String] {
        guard let result = CurlParser.parseWithWarnings(text) else { return [] }
        open(result.request, in: currentCollectionId)
        warnings = result.warnings
        return result.warnings
    }

    var curlPreview: String {
        CodeGenerator.generate(.curl, for: current, scope: scope)
    }

    func code(for target: CodeTarget) -> String {
        CodeGenerator.generate(target, for: withInheritedAuth(current), scope: scope)
    }

    private func withInheritedAuth(_ request: SavedRequest) -> SavedRequest {
        guard request.auth.type == .none, let inheritedAuth else { return request }
        var copy = request
        copy.auth = inheritedAuth
        return copy
    }

    // MARK: - Collections

    func addCollection(named name: String) -> ApiCollection {
        let collection = ApiCollection(name: name)
        data.collections.append(collection)
        currentCollectionId = collection.id
        persist()
        return collection
    }

    func deleteCollection(_ id: String) {
        data.collections.removeAll { $0.id == id }
        if currentCollectionId == id { currentCollectionId = nil }
        persist()
    }

    func renameCollection(_ id: String, to name: String) {
        guard let index = data.collections.firstIndex(where: { $0.id == id }) else { return }
        data.collections[index].name = name
        persist()
    }

    func addFolder(named name: String, toCollection collectionId: String, inFolder parent: String?) {
        mutate(collectionId) { items in
            ApiCollectionTree.appending(.folder(ApiFolder(name: name)), toFolder: parent, in: items)
        }
    }

    /// Saves the open request into a collection, replacing it if already there.
    func saveCurrent(named name: String, toCollection collectionId: String, inFolder folder: String?) {
        var request = current
        request.name = name.trimmingCharacters(in: .whitespaces)
        request.modifiedAt = Date().timeIntervalSince1970
        current = request
        currentCollectionId = collectionId

        mutate(collectionId) { items in
            if let replaced = ApiCollectionTree.replacing(request, in: items) { return replaced }
            return ApiCollectionTree.appending(.request(request), toFolder: folder, in: items)
        }
    }

    func deleteItem(_ id: String, from collectionId: String) {
        mutate(collectionId) { ApiCollectionTree.removing(id, from: $0) }
    }

    func duplicateItem(_ id: String, in collectionId: String) {
        guard let collection = data.collections.first(where: { $0.id == collectionId }),
              let item = ApiCollectionTree.find(id, in: collection.items)
        else { return }
        let copy = ApiCollectionTree.duplicating(item)
        let parent = ApiCollectionTree.path(to: id, in: collection.items)?.isEmpty == false
            ? enclosingFolderId(of: id, in: collection.items)
            : nil
        mutate(collectionId) { ApiCollectionTree.appending(copy, toFolder: parent, in: $0) }
    }

    func move(_ id: String, toFolder folder: String?, in collectionId: String) {
        mutate(collectionId) { ApiCollectionTree.moving(id, toFolder: folder, in: $0) }
    }

    func renameFolder(_ id: String, to name: String, in collectionId: String) {
        mutate(collectionId) { ApiCollectionTree.renamingFolder(id, to: name, in: $0) }
    }

    func setCollectionAuth(_ auth: AuthSpec, for collectionId: String) {
        guard let index = data.collections.firstIndex(where: { $0.id == collectionId }) else { return }
        data.collections[index].auth = auth
        persist()
    }

    private func mutate(_ collectionId: String, _ transform: ([ApiItem]) -> [ApiItem]) {
        guard let index = data.collections.firstIndex(where: { $0.id == collectionId }) else { return }
        data.collections[index].items = transform(data.collections[index].items)
        persist()
    }

    private func enclosingFolderId(of id: String, in items: [ApiItem]) -> String? {
        for item in items {
            guard case .folder(let folder) = item else { continue }
            if folder.items.contains(where: { $0.id == id }) { return folder.id }
            if let deeper = enclosingFolderId(of: id, in: folder.items) { return deeper }
        }
        return nil
    }

    // MARK: - Environments

    func addEnvironment(named name: String) -> ApiEnvironment {
        let environment = ApiEnvironment(name: name)
        data.environments.append(environment)
        persist()
        return environment
    }

    func update(_ environment: ApiEnvironment) {
        guard let index = data.environments.firstIndex(where: { $0.id == environment.id }) else { return }
        data.environments[index] = environment
        persist()
    }

    func deleteEnvironment(_ id: String) {
        data.environments.removeAll { $0.id == id }
        if data.activeEnvironmentId == id { data.activeEnvironmentId = nil }
        persist()
    }

    func setGlobals(_ globals: [ApiKeyValue]) {
        data.globals = globals
        persist()
    }

    func clearHistory() {
        data.clearHistory()
        persist()
    }

    // MARK: - Import and export

    /// Reads a Postman collection, a Postman environment, or a Droidective
    /// workspace export. Returns a message for the UI in both directions.
    func importFile(at url: URL) -> String {
        do {
            let payload = try Data(contentsOf: url)
            let result = try PostmanFormat.importFile(payload)
            guard !result.isEmpty else { return "Nothing in that file could be imported." }

            for collection in result.collections {
                var copy = collection
                copy.id = UUID().uuidString
                copy.items = ApiCollectionTree.reidentifying(copy.items)
                data.collections.append(copy)
            }
            for environment in result.environments {
                var copy = environment
                copy.id = UUID().uuidString
                data.environments.append(copy)
            }
            persist()

            var message = result.summary
            if !result.warnings.isEmpty {
                message += "\n\n" + result.warnings.map { "• \($0)" }.joined(separator: "\n")
            }
            return message
        } catch let error as PostmanFormatError {
            return error.errorDescription ?? "That file couldn't be imported."
        } catch {
            return "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func exportCollection(_ id: String, to url: URL, includeSecrets: Bool) -> String? {
        guard let collection = data.collections.first(where: { $0.id == id }) else {
            return "That collection no longer exists."
        }
        return write(url) {
            try PostmanFormat.exportCollection(collection, includeSecrets: includeSecrets)
        }
    }

    func exportEnvironment(_ id: String, to url: URL) -> String? {
        guard let environment = data.environments.first(where: { $0.id == id }) else {
            return "That environment no longer exists."
        }
        return write(url) { try PostmanFormat.exportEnvironment(environment) }
    }

    func exportWorkspace(to url: URL, includeSecrets: Bool) -> String? {
        let snapshot = data
        return write(url) {
            try PostmanFormat.exportWorkspace(snapshot, includeSecrets: includeSecrets)
        }
    }

    /// Returns nil on success, an error message otherwise — a silent `try?`
    /// here would look like a successful export that wrote nothing.
    private func write(_ url: URL, _ build: () throws -> Data) -> String? {
        do {
            try build().write(to: url, options: .atomic)
            return nil
        } catch {
            return "Couldn't write \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func saveResponseBody(to url: URL) -> String? {
        guard let response else { return "There's no response to save." }
        do {
            try response.body.write(to: url, options: .atomic)
            return nil
        } catch {
            return "Couldn't write \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - Runner

    func run(collectionId: String, options: RunOptions) {
        guard let engine, let collection = data.collections.first(where: { $0.id == collectionId })
        else { return }
        runTask?.cancel()
        runSummary = nil
        runProgress = []
        runningCollectionId = collectionId

        let runner = ApiRunner(client: engine.httpClient)
        let items = collection.items
        let auth = collection.auth.type == .none ? nil : collection.auth
        let scope = data.scope(for: collection)

        runTask = Task { [weak self] in
            let summary = await runner.run(
                items,
                collectionAuth: auth,
                scope: scope,
                options: options,
                onProgress: { [weak self] result in
                    Task { @MainActor in self?.runProgress.append(result) }
                }
            )
            guard let self, !Task.isCancelled else { return }
            runSummary = summary
            runningCollectionId = nil
        }
    }

    func cancelRun() {
        runTask?.cancel()
        runTask = nil
        runningCollectionId = nil
    }

    var isRunning: Bool { runningCollectionId != nil }
}
