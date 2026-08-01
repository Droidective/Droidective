import ADBKit
import SwiftUI

enum ApiClientSheet: Identifiable {
    case importCurl
    case saveRequest
    case newCollection
    case renameCollection(id: String)
    case newFolder(collectionId: String, parent: String?)
    case renameFolder(collectionId: String, folderId: String)
    case collectionAuth(id: String)
    case newEnvironment
    case environment(id: String)
    case globals
    case runner(collectionId: String)

    var id: String {
        switch self {
        case .importCurl: return "importCurl"
        case .saveRequest: return "saveRequest"
        case .newCollection: return "newCollection"
        case .renameCollection(let id): return "renameCollection-\(id)"
        case .newFolder(let collectionId, let parent):
            return "newFolder-\(collectionId)-\(parent ?? "root")"
        case .renameFolder(_, let folderId): return "renameFolder-\(folderId)"
        case .collectionAuth(let id): return "collectionAuth-\(id)"
        case .newEnvironment: return "newEnvironment"
        case .environment(let id): return "environment-\(id)"
        case .globals: return "globals"
        case .runner(let collectionId): return "runner-\(collectionId)"
        }
    }
}

struct ApiClientSheetView: View {
    let model: ApiClientModel
    let sheet: ApiClientSheet
    @Binding var alertMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch sheet {
        case .importCurl:
            CurlImportSheet(model: model)
        case .saveRequest:
            SaveRequestSheet(model: model)
        case .newCollection:
            NameSheet(title: "New Collection", placeholder: "Name", action: "Create") { name in
                _ = model.addCollection(named: name)
            }
        case .renameCollection(let id):
            NameSheet(
                title: "Rename Collection",
                placeholder: "Name",
                action: "Rename",
                initial: model.data.collections.first { $0.id == id }?.name ?? ""
            ) { name in
                model.renameCollection(id, to: name)
            }
        case .newFolder(let collectionId, let parent):
            NameSheet(title: "New Folder", placeholder: "Name", action: "Create") { name in
                model.addFolder(named: name, toCollection: collectionId, inFolder: parent)
            }
        case .renameFolder(let collectionId, let folderId):
            NameSheet(title: "Rename Folder", placeholder: "Name", action: "Rename") { name in
                model.renameFolder(folderId, to: name, in: collectionId)
            }
        case .collectionAuth(let id):
            CollectionAuthSheet(model: model, collectionId: id)
        case .newEnvironment:
            NameSheet(title: "New Environment", placeholder: "Name", action: "Create") { name in
                _ = model.addEnvironment(named: name)
            }
        case .environment(let id):
            VariablesSheet(
                title: "Edit Environment",
                variables: model.data.environments.first { $0.id == id }?.variables ?? [],
                name: model.data.environments.first { $0.id == id }?.name ?? "",
                onSave: { name, variables in
                    guard var environment = model.data.environments.first(where: { $0.id == id })
                    else { return }
                    environment.name = name
                    environment.variables = variables
                    model.update(environment)
                }
            )
        case .globals:
            VariablesSheet(
                title: "Global Variables",
                variables: model.data.globals,
                name: nil,
                onSave: { _, variables in model.setGlobals(variables) }
            )
        case .runner(let collectionId):
            RunnerSheet(model: model, collectionId: collectionId)
        }
    }
}

// MARK: - cURL import

private struct CurlImportSheet: View {
    let model: ApiClientModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import cURL").font(.app(.title3))
            Text("Paste a command copied from a terminal or from your browser's network tab.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)

            TextEditor(text: $text)
                .font(.app(.body, design: .monospaced))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .border(Color.gray.opacity(0.3))
                .onChange(of: text) { _, _ in failure = nil }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import") { attempt() }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 540, minHeight: 300)
    }

    private func attempt() {
        guard CurlParser.parse(text) != nil else {
            failure = "Couldn't parse that. It needs to start with \"curl\" and contain a URL."
            return
        }
        _ = model.loadCurl(text)
        dismiss()
    }
}

// MARK: - Save request

private struct SaveRequestSheet: View {
    let model: ApiClientModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var collectionId: String?
    @State private var folderId: String?
    @State private var newCollectionName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Request").font(.app(.title3))

            TextField("Name", text: $name).textFieldStyle(.roundedBorder)

            if model.data.collections.isEmpty {
                TextField("New collection name", text: $newCollectionName)
                    .textFieldStyle(.roundedBorder)
                Text("Your first collection will be created to hold this request.")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            } else {
                Picker("Collection", selection: $collectionId) {
                    ForEach(model.data.collections) { collection in
                        Text(collection.name).tag(Optional(collection.id))
                    }
                }
                if !folderChoices.isEmpty {
                    Picker("Folder", selection: $folderId) {
                        Text("Top level").tag(String?.none)
                        ForEach(folderChoices, id: \.id) { choice in
                            Text(choice.name).tag(Optional(choice.id))
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding()
        .frame(minWidth: 420)
        .onAppear {
            name = model.current.name
            collectionId = model.currentCollectionId ?? model.data.collections.first?.id
        }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return model.data.collections.isEmpty
            ? !newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty
            : collectionId != nil
    }

    private var folderChoices: [(id: String, name: String)] {
        guard let collectionId,
              let collection = model.data.collections.first(where: { $0.id == collectionId })
        else { return [] }
        var out: [(id: String, name: String)] = []
        func walk(_ items: [ApiItem], prefix: String) {
            for case .folder(let folder) in items {
                let label = prefix.isEmpty ? folder.name : "\(prefix) / \(folder.name)"
                out.append((id: folder.id, name: label))
                walk(folder.items, prefix: label)
            }
        }
        walk(collection.items, prefix: "")
        return out
    }

    private func save() {
        let target = collectionId ?? model.addCollection(named: newCollectionName).id
        model.saveCurrent(named: name, toCollection: target, inFolder: folderId)
        dismiss()
    }
}

// MARK: - Name prompt

private struct NameSheet: View {
    let title: String
    let placeholder: String
    let action: String
    var initial: String = ""
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.app(.title3))
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action) { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 360)
        .onAppear { text = initial }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}

// MARK: - Variables

private struct VariablesSheet: View {
    let title: String
    @State var variables: [ApiKeyValue]
    @State var name: String?
    let onSave: (String, [ApiKeyValue]) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.app(.title3))

            if name != nil {
                TextField(
                    "Name",
                    text: Binding(get: { name ?? "" }, set: { name = $0 })
                )
                .textFieldStyle(.roundedBorder)
            }

            Text("Reference these anywhere with {{name}}.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)

            ApiKeyValueEditor(
                title: "Variables",
                placeholder: "No variables yet.",
                items: $variables
            )
            .frame(minHeight: 200)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name ?? "", variables)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name != nil && (name ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 380)
    }
}

// MARK: - Collection auth

private struct CollectionAuthSheet: View {
    let model: ApiClientModel
    let collectionId: String

    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthSpec()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collection Auth").font(.app(.title3))
            Text("Applied to every request in this collection that has its auth set to None.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)

            Picker("Type", selection: $auth.type) {
                ForEach(AuthType.allCases, id: \.self) { type in
                    Text(ApiLabels.auth(type)).tag(type)
                }
            }

            Group {
                switch auth.type {
                case .none:
                    Text("Requests use their own auth only.")
                        .font(.app(.caption))
                        .foregroundStyle(.textMuted)
                case .bearer:
                    SecureField("Bearer token", text: $auth.bearerToken)
                        .textFieldStyle(.roundedBorder)
                case .basic:
                    TextField("Username", text: $auth.basicUsername).textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $auth.basicPassword).textFieldStyle(.roundedBorder)
                case .apiKey:
                    TextField("Key name", text: $auth.apiKeyName).textFieldStyle(.roundedBorder)
                    SecureField("Key value", text: $auth.apiKeyValue).textFieldStyle(.roundedBorder)
                    Picker("Add to", selection: $auth.apiKeyLocation) {
                        Text("Header").tag(ApiKeyLocation.header)
                        Text("Query parameter").tag(ApiKeyLocation.query)
                    }
                    .pickerStyle(.segmented)
                case .oauth2:
                    SecureField("Access token", text: $auth.oauth2Token)
                        .textFieldStyle(.roundedBorder)
                    TextField("Header prefix", text: $auth.oauth2HeaderPrefix)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.setCollectionAuth(auth, for: collectionId)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 420)
        .onAppear {
            auth = model.data.collections.first { $0.id == collectionId }?.auth ?? AuthSpec()
        }
    }
}

// MARK: - Runner

private struct RunnerSheet: View {
    let model: ApiClientModel
    let collectionId: String

    @Environment(\.dismiss) private var dismiss
    @State private var iterations = 1
    @State private var delayMs = 0
    @State private var stopOnFailure = false

    private var collection: ApiCollection? {
        model.data.collections.first { $0.id == collectionId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run \(collection?.name ?? "Collection")").font(.app(.title3))
            Text(
                "\(ApiCollectionTree.requestCount(in: collection?.items ?? [])) requests, "
                    + "sent in order with the active environment."
            )
            .font(.app(.caption))
            .foregroundStyle(.textMuted)

            HStack(spacing: 12) {
                LabeledContent("Iterations") {
                    TextField("1", value: $iterations, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
                LabeledContent("Delay (ms)") {
                    TextField("0", value: $delayMs, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                Toggle("Stop on first failure", isOn: $stopOnFailure)
            }

            Divider()

            resultsList

            HStack {
                if let summary = model.runSummary {
                    Text(summary.headline)
                        .font(.app(.caption))
                        .foregroundStyle(summary.failedCount == 0 ? .green : .orange)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if model.isRunning {
                    Button("Stop") { model.cancelRun() }.buttonStyle(.bordered)
                } else {
                    Button("Run") {
                        model.run(
                            collectionId: collectionId,
                            options: RunOptions(
                                iterations: iterations,
                                delayMs: delayMs,
                                stopOnFailure: stopOnFailure
                            )
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ApiCollectionTree.requestCount(in: collection?.items ?? []) == 0)
                }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
    }

    @ViewBuilder
    private var resultsList: some View {
        let rows = model.runSummary?.results ?? model.runProgress
        if rows.isEmpty {
            VStack(spacing: 6) {
                if model.isRunning {
                    ProgressView()
                } else {
                    Image(systemName: "play.circle").font(.largeTitle).foregroundStyle(.textMuted)
                    Text("Run to see each request's result and its tests.")
                        .font(.app(.caption))
                        .foregroundStyle(.textMuted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(rows) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(row.passed ? .green : .red)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(row.method.rawValue)
                                .font(.app(.caption2, design: .monospaced))
                                .foregroundStyle(ApiStatusStyle.color(for: row.method))
                            Text(row.name).font(.app(.caption))
                            if !row.path.isEmpty {
                                Text(row.path.joined(separator: " / "))
                                    .font(.app(.caption2))
                                    .foregroundStyle(.textMuted)
                            }
                        }
                        if let error = row.errorText {
                            Text(error).font(.app(.caption2)).foregroundStyle(.red).lineLimit(2)
                        } else if let failed = row.assertions.first(where: { !$0.passed }) {
                            Text("\(failed.label) — got \(failed.detail)")
                                .font(.app(.caption2))
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if let code = row.statusCode {
                        Text("\(code)")
                            .font(.app(.caption, design: .monospaced))
                            .foregroundStyle(ApiStatusStyle.color(for: code))
                    }
                    if let elapsed = row.elapsedMs {
                        Text(String(format: "%.0f ms", elapsed))
                            .font(.app(.caption2, design: .monospaced))
                            .foregroundStyle(.textMuted)
                    }
                }
            }
            .listStyle(.plain)
            .translucentListBackground()
        }
    }
}
