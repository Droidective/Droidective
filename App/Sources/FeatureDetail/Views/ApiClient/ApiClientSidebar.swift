import ADBKit
import SwiftUI

struct ApiClientSidebar: View {
    let model: ApiClientModel
    @Binding var section: ApiSidebarSection
    @Binding var sheet: ApiClientSheet?
    @Binding var alertMessage: String?

    @State private var query = ""
    @State private var expandedFolders: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                sectionPicker(.segmented)
                sectionPicker(.menu)
            }
            Divider()
            switch section {
            case .collections: collections
            case .history: history
            case .environments: environments
            }
        }
        .background(.bgSurface)
    }

    private func sectionPicker(_ style: some PickerStyle) -> some View {
        Picker("", selection: $section) {
            ForEach(ApiSidebarSection.allCases) { value in
                Text(value.label).tag(value)
            }
        }
        .labelsHidden()
        .pickerStyle(style)
        .padding(8)
    }

    // MARK: - Collections

    private var collections: some View {
        VStack(spacing: 0) {
            header("Collections") {
                Button { sheet = .newCollection } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New collection")
            }

            TextField("Search requests", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.app(.caption))
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            if model.data.collections.isEmpty {
                emptyState(
                    "No collections yet",
                    detail: "Create one, or import a Postman collection."
                )
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResults
            } else {
                collectionTree
            }
        }
    }

    private var searchResults: some View {
        let hits = model.data.collections.flatMap { collection in
            ApiCollectionTree.search(query, in: collection.items).map { (collection, $0) }
        }
        return Group {
            if hits.isEmpty {
                emptyState("No matches", detail: nil)
            } else {
                List {
                    ForEach(hits, id: \.1.request.id) { collection, hit in
                        Button {
                            model.open(hit.request, in: collection.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                requestLabel(hit.request)
                                Text(([collection.name] + hit.path).joined(separator: " / "))
                                    .font(.app(.caption2))
                                    .foregroundStyle(.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.sidebar)
                .translucentListBackground()
            }
        }
    }

    private var collectionTree: some View {
        List {
            ForEach(model.data.collections) { collection in
                Section {
                    ApiItemList(
                        items: collection.items,
                        collection: collection,
                        model: model,
                        sheet: $sheet,
                        expandedFolders: $expandedFolders,
                        depth: 0
                    )
                } header: {
                    collectionHeader(collection)
                }
            }
        }
        .listStyle(.sidebar)
        .translucentListBackground()
    }

    private func collectionHeader(_ collection: ApiCollection) -> some View {
        HStack(spacing: 4) {
            Text(collection.name)
                .font(.app(.subheadline))
                .bold()
                .lineLimit(1)
            if collection.auth.type != .none {
                Image(systemName: "lock.fill")
                    .font(.app(.caption2))
                    .foregroundStyle(.textMuted)
                    .help("This collection sets auth for its requests")
            }
            Spacer()
            Text("\(ApiCollectionTree.requestCount(in: collection.items))")
                .font(.app(.caption2))
                .foregroundStyle(.textMuted)
            Menu {
                Button("New Folder…") { sheet = .newFolder(collectionId: collection.id, parent: nil) }
                Button("Rename…") { sheet = .renameCollection(id: collection.id) }
                Button("Collection Auth…") { sheet = .collectionAuth(id: collection.id) }
                Divider()
                Button("Run Collection…") { sheet = .runner(collectionId: collection.id) }
                Divider()
                Button("Delete Collection", role: .destructive) {
                    model.deleteCollection(collection.id)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: - History

    private var history: some View {
        VStack(spacing: 0) {
            header("History") {
                if !model.data.history.isEmpty {
                    Button("Clear") { model.clearHistory() }
                        .buttonStyle(.borderless)
                        .font(.app(.caption))
                }
            }
            if model.data.history.isEmpty {
                emptyState("No requests yet", detail: "Sent requests land here.")
            } else {
                List(model.data.history) { entry in
                    Button {
                        model.open(entry.request, in: nil)
                    } label: {
                        historyRow(entry)
                    }
                    .buttonStyle(.plain)
                    .help("Credentials aren't kept in history — re-enter them after loading.")
                }
                .listStyle(.sidebar)
                .translucentListBackground()
            }
        }
    }

    private func historyRow(_ entry: ApiHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                methodBadge(entry.method)
                if let code = entry.statusCode {
                    Text("\(code)")
                        .font(.app(.caption2, design: .monospaced))
                        .foregroundStyle(ApiStatusStyle.color(for: code))
                } else if entry.errorText != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.app(.caption2))
                        .foregroundStyle(.red)
                }
                Spacer()
                if let elapsed = entry.elapsedMs {
                    Text(String(format: "%.0f ms", elapsed))
                        .font(.app(.caption2, design: .monospaced))
                        .foregroundStyle(.textMuted)
                }
            }
            Text(entry.url)
                .font(.app(.caption, design: .monospaced))
                .foregroundStyle(.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(Date(timeIntervalSince1970: entry.timestamp), style: .relative)
                .font(.app(.caption2))
                .foregroundStyle(.textMuted)
        }
    }

    // MARK: - Environments

    private var environments: some View {
        VStack(spacing: 0) {
            header("Environments") {
                Button { sheet = .newEnvironment } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New environment")
            }

            Button {
                sheet = .globals
            } label: {
                HStack {
                    Image(systemName: "globe")
                    Text("Global variables")
                    Spacer()
                    Text("\(model.data.globals.count)")
                        .foregroundStyle(.textMuted)
                }
                .font(.app(.caption))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if model.data.environments.isEmpty {
                emptyState("No environments", detail: "Group per-stage values like {{baseUrl}}.")
            } else {
                List(model.data.environments) { environment in
                    environmentRow(environment)
                }
                .listStyle(.sidebar)
                .translucentListBackground()
            }
        }
    }

    private func environmentRow(_ environment: ApiEnvironment) -> some View {
        HStack {
            Button {
                model.data.activeEnvironmentId = environment.id
                model.persist()
            } label: {
                HStack(spacing: 6) {
                    Image(
                        systemName: model.data.activeEnvironmentId == environment.id
                            ? "largecircle.fill.circle" : "circle"
                    )
                    .font(.app(.caption2))
                    .foregroundStyle(
                        model.data.activeEnvironmentId == environment.id ? Color.accentColor : .textMuted
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(environment.name).font(.app(.callout)).lineLimit(1)
                        Text("\(environment.variables.count) variables")
                            .font(.app(.caption2))
                            .foregroundStyle(.textMuted)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button("Edit…") { sheet = .environment(id: environment.id) }
                Button("Export…") { exportEnvironment(environment) }
                Divider()
                Button("Delete", role: .destructive) { model.deleteEnvironment(environment.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func exportEnvironment(_ environment: ApiEnvironment) {
        guard let url = ApiClientFilePanels.askSave(
            suggestedName: "\(environment.name).postman_environment.json"
        ) else { return }
        if let failure = model.exportEnvironment(environment.id, to: url) {
            alertMessage = failure
        }
    }

    // MARK: - Shared pieces

    private func header(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(title).font(.app(.headline))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func emptyState(_ title: String, detail: String?) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.app(.caption)).foregroundStyle(.textMuted)
            if let detail {
                Text(detail)
                    .font(.app(.caption2))
                    .foregroundStyle(.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requestLabel(_ request: SavedRequest) -> some View {
        HStack(spacing: 6) {
            methodBadge(request.method)
            Text(request.name).font(.app(.caption)).lineLimit(1)
        }
    }

    private func methodBadge(_ method: HttpMethod) -> some View {
        Text(method.rawValue)
            .font(.app(.caption2, design: .monospaced))
            .bold()
            .foregroundStyle(ApiStatusStyle.color(for: method))
            .frame(width: 44, alignment: .leading)
    }
}

// MARK: - Recursive tree rows

/// Folders nest arbitrarily deep, so the rows recurse. Split out of the sidebar
/// to keep each `body` small enough for the type checker.
private struct ApiItemList: View {
    let items: [ApiItem]
    let collection: ApiCollection
    let model: ApiClientModel
    @Binding var sheet: ApiClientSheet?
    @Binding var expandedFolders: Set<String>
    let depth: Int

    var body: some View {
        ForEach(items) { item in
            switch item {
            case .request(let request):
                requestRow(request)
            case .folder(let folder):
                folderRow(folder)
            }
        }
    }

    private func requestRow(_ request: SavedRequest) -> some View {
        Button {
            model.open(request, in: collection.id)
        } label: {
            HStack(spacing: 6) {
                Text(request.method.rawValue)
                    .font(.app(.caption2, design: .monospaced))
                    .bold()
                    .foregroundStyle(ApiStatusStyle.color(for: request.method))
                    .frame(width: 44, alignment: .leading)
                Text(request.name).font(.app(.caption)).lineLimit(1)
                Spacer()
                if !request.assertions.isEmpty {
                    Image(systemName: "checkmark.seal")
                        .font(.app(.caption2))
                        .foregroundStyle(.textMuted)
                        .help("\(request.assertions.count) test(s)")
                }
            }
            .padding(.leading, CGFloat(depth) * 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { itemMenu(id: request.id, isFolder: false) }
    }

    private func folderRow(_ folder: ApiFolder) -> some View {
        let isOpen = expandedFolders.contains(folder.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOpen {
                    expandedFolders.remove(folder.id)
                } else {
                    expandedFolders.insert(folder.id)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.app(.caption2))
                        .foregroundStyle(.textMuted)
                        .frame(width: 10)
                    Image(systemName: "folder")
                        .font(.app(.caption2))
                        .foregroundStyle(.textMuted)
                    Text(folder.name).font(.app(.caption)).bold().lineLimit(1)
                    Spacer()
                    Text("\(ApiCollectionTree.requestCount(in: folder.items))")
                        .font(.app(.caption2))
                        .foregroundStyle(.textMuted)
                }
                .padding(.leading, CGFloat(depth) * 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("New Folder Inside…") {
                    sheet = .newFolder(collectionId: collection.id, parent: folder.id)
                }
                Button("Rename…") {
                    sheet = .renameFolder(collectionId: collection.id, folderId: folder.id)
                }
                Divider()
                itemMenu(id: folder.id, isFolder: true)
            }

            if isOpen {
                ApiItemList(
                    items: folder.items,
                    collection: collection,
                    model: model,
                    sheet: $sheet,
                    expandedFolders: $expandedFolders,
                    depth: depth + 1
                )
            }
        }
    }

    @ViewBuilder
    private func itemMenu(id: String, isFolder: Bool) -> some View {
        Button("Duplicate") { model.duplicateItem(id, in: collection.id) }
        Menu("Move To") {
            Button("Top level") { model.move(id, toFolder: nil, in: collection.id) }
            ForEach(folderChoices(excluding: id), id: \.id) { choice in
                Button(choice.name) { model.move(id, toFolder: choice.id, in: collection.id) }
            }
        }
        Divider()
        Button(isFolder ? "Delete Folder" : "Delete", role: .destructive) {
            model.deleteItem(id, from: collection.id)
        }
    }

    /// Every folder in the collection except the moving item and its own
    /// subtree — the tree refuses those moves, so they aren't offered.
    private func folderChoices(excluding id: String) -> [(id: String, name: String)] {
        var out: [(id: String, name: String)] = []
        func walk(_ items: [ApiItem], prefix: String) {
            for case .folder(let folder) in items where folder.id != id {
                let label = prefix.isEmpty ? folder.name : "\(prefix) / \(folder.name)"
                out.append((id: folder.id, name: label))
                walk(folder.items, prefix: label)
            }
        }
        walk(collection.items, prefix: "")
        return out
    }
}

// MARK: - Shared styling

enum ApiStatusStyle {
    static func color(for method: HttpMethod) -> Color {
        switch method {
        case .get: return .green
        case .post: return .orange
        case .put: return .blue
        case .patch: return .purple
        case .delete: return .red
        case .head: return .cyan
        case .options: return .gray
        }
    }

    static func color(for statusCode: Int) -> Color {
        switch statusCode {
        case 200..<300: return .green
        case 300..<400: return .yellow
        case 400..<500: return .orange
        case 500...: return .red
        default: return .primary
        }
    }
}
