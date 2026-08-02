import ADBKit
import SwiftUI

/// A destructive action waiting on a confirmation. Deleting a collection or a
/// folder takes everything inside it, and clearing history can't be undone —
/// all of these used to happen on a single menu click.
struct ApiDeletion: Identifiable {

    enum Target {
        case collection(String)
        case item(id: String, collectionId: String)
        case environment(String)
        case history
    }

    let id = UUID()
    let target: Target
    let title: String
    let message: String
    let confirmLabel: String

    static func collection(_ collection: ApiCollection) -> ApiDeletion {
        let count = ApiCollectionTree.requestCount(in: collection.items)
        return ApiDeletion(
            target: .collection(collection.id),
            title: "Delete “\(collection.name)”?",
            message: count == 1
                ? "Its 1 request is deleted with it. This can't be undone."
                : "Its \(count) requests are deleted with it. This can't be undone.",
            confirmLabel: "Delete Collection"
        )
    }

    static func request(_ request: SavedRequest, in collectionId: String) -> ApiDeletion {
        ApiDeletion(
            target: .item(id: request.id, collectionId: collectionId),
            title: "Delete “\(request.name)”?",
            message: "This can't be undone.",
            confirmLabel: "Delete Request"
        )
    }

    static func folder(_ folder: ApiFolder, in collectionId: String) -> ApiDeletion {
        let count = ApiCollectionTree.requestCount(in: folder.items)
        return ApiDeletion(
            target: .item(id: folder.id, collectionId: collectionId),
            title: "Delete “\(folder.name)”?",
            message: count == 0
                ? "The folder is empty. This can't be undone."
                : "Its \(count) request\(count == 1 ? "" : "s") are deleted with it. "
                    + "This can't be undone.",
            confirmLabel: "Delete Folder"
        )
    }

    static func environment(_ environment: ApiEnvironment) -> ApiDeletion {
        ApiDeletion(
            target: .environment(environment.id),
            title: "Delete “\(environment.name)”?",
            message: "Requests using its variables will have nothing to resolve them to.",
            confirmLabel: "Delete Environment"
        )
    }

    static func history(count: Int) -> ApiDeletion {
        ApiDeletion(
            target: .history,
            title: "Clear history?",
            message: "\(count) entr\(count == 1 ? "y" : "ies") are removed. This can't be undone.",
            confirmLabel: "Clear History"
        )
    }
}

struct ApiClientSidebar: View {
    let model: ApiClientModel
    @Binding var section: ApiSidebarSection
    @Binding var sheet: ApiClientSheet?
    @Binding var alertMessage: String?

    @State private var query = ""
    /// Persisted so a collection doesn't re-collapse every time the pane is
    /// reopened — the tree is navigation, and navigation should stay put.
    @AppStorage("apiExpandedFolders") private var expandedFolderList = ""
    @State private var pendingDeletion: ApiDeletion?

    private var expandedFolders: Binding<Set<String>> {
        Binding(
            get: { Set(expandedFolderList.components(separatedBy: "\n").filter { !$0.isEmpty }) },
            set: { expandedFolderList = $0.sorted().joined(separator: "\n") }
        )
    }

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
        .confirmationDialog(
            pendingDeletion?.title ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { deletion in
            Button(deletion.confirmLabel, role: .destructive) { perform(deletion) }
            Button("Cancel", role: .cancel) {}
        } message: { deletion in
            Text(deletion.message)
        }
    }

    private func perform(_ deletion: ApiDeletion) {
        switch deletion.target {
        case .collection(let id): model.deleteCollection(id)
        case .item(let id, let collectionId): model.deleteItem(id, from: collectionId)
        case .environment(let id): model.deleteEnvironment(id)
        case .history: model.clearHistory()
        }
        pendingDeletion = nil
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

    /// Every item is its own `List` row — folders included — so all rows share
    /// one set of insets. Nesting children inside their parent's row gave a
    /// folder's contents different spacing from the requests above them.
    private var collectionTree: some View {
        List {
            ForEach(model.data.collections) { collection in
                Section {
                    ForEach(
                        ApiCollectionTree.rows(collection.items, expanded: expandedFolders.wrappedValue)
                    ) { row in
                        ApiItemRow(
                            row: row,
                            collection: collection,
                            model: model,
                            sheet: $sheet,
                            expandedFolders: expandedFolders,
                            pendingDeletion: $pendingDeletion
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    collectionHeader(collection)
                }
            }
        }
        // Plain, not `.sidebar`: the sidebar style pads every row, which on a
        // one-line request row reads as a gap rather than breathing room.
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 24)
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
                Button("Collection Variables…") { sheet = .collectionVariables(id: collection.id) }
                Button("Export…") { exportCollection(collection) }
                Divider()
                Button("Run Collection…") { sheet = .runner(collectionId: collection.id) }
                Divider()
                Button("Delete Collection…", role: .destructive) {
                    pendingDeletion = .collection(collection)
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
                    Button("Clear") {
                        pendingDeletion = .history(count: model.data.history.count)
                    }
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
                Button("Delete…", role: .destructive) {
                    pendingDeletion = .environment(environment)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func exportCollection(_ collection: ApiCollection) {
        guard let url = ApiClientFilePanels.askSave(
            suggestedName: "\(collection.name).postman_collection.json"
        ) else { return }
        if let failure = model.exportCollection(collection.id, to: url, includeSecrets: false) {
            alertMessage = failure
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

// MARK: - Tree rows

/// One row of the collection tree. Requests and folders are drawn to the same
/// grid — the disclosure column is always reserved, so a request's method badge
/// lines up with the folder names above it instead of hanging a few points off.
private struct ApiItemRow: View {
    let row: ApiCollectionTree.Row
    let collection: ApiCollection
    let model: ApiClientModel
    @Binding var sheet: ApiClientSheet?
    @Binding var expandedFolders: Set<String>
    @Binding var pendingDeletion: ApiDeletion?

    /// Width of the disclosure triangle column, reserved on every row.
    private static let discloseWidth: CGFloat = 12
    /// Width of the method badge, so names start on one line.
    private static let methodWidth: CGFloat = 38
    private static let indentPerLevel: CGFloat = 12
    /// macOS's compact source-list row. Anything taller reads as a gap
    /// between one-line rows rather than breathing room.
    static let rowHeight: CGFloat = 24

    var body: some View {
        switch row.item {
        case .request(let request): requestRow(request)
        case .folder(let folder): folderRow(folder)
        }
    }

    private var indent: CGFloat { CGFloat(row.depth) * Self.indentPerLevel }

    private func requestRow(_ request: SavedRequest) -> some View {
        Button {
            model.open(request, in: collection.id)
        } label: {
            HStack(spacing: 6) {
                Color.clear.frame(width: Self.discloseWidth, height: 1)
                Text(request.method.rawValue)
                    .font(.app(.caption2, design: .monospaced))
                    .bold()
                    .foregroundStyle(ApiStatusStyle.color(for: request.method))
                    .frame(width: Self.methodWidth, alignment: .leading)
                Text(request.name).font(.app(.caption)).lineLimit(1)
                Spacer(minLength: 4)
                if !request.assertions.isEmpty {
                    Image(systemName: "checkmark.seal")
                        .font(.app(.caption2))
                        .foregroundStyle(.textMuted)
                        .help("\(request.assertions.count) test(s)")
                }
            }
            .padding(.leading, indent)
            .frame(minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { itemMenu(id: request.id, deletion: .request(request, in: collection.id)) }
    }

    private func folderRow(_ folder: ApiFolder) -> some View {
        let isOpen = expandedFolders.contains(folder.id)
        return Button {
            if isOpen {
                expandedFolders.remove(folder.id)
            } else {
                expandedFolders.insert(folder.id)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.app(.caption2))
                    .foregroundStyle(.textMuted)
                    .frame(width: Self.discloseWidth)
                Image(systemName: isOpen ? "folder.fill" : "folder")
                    .font(.app(.caption2))
                    .foregroundStyle(.textMuted)
                Text(folder.name).font(.app(.caption)).bold().lineLimit(1)
                Spacer(minLength: 4)
                Text("\(ApiCollectionTree.requestCount(in: folder.items))")
                    .font(.app(.caption2))
                    .foregroundStyle(.textMuted)
            }
            .padding(.leading, indent)
            .frame(minHeight: Self.rowHeight)
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
            itemMenu(id: folder.id, deletion: .folder(folder, in: collection.id))
        }
    }

    @ViewBuilder
    private func itemMenu(id: String, deletion: ApiDeletion) -> some View {
        Button("Duplicate") { model.duplicateItem(id, in: collection.id) }
        Menu("Move To") {
            Button("Top level") { model.move(id, toFolder: nil, in: collection.id) }
            ForEach(folderChoices(excluding: id), id: \.id) { choice in
                Button(choice.name) { model.move(id, toFolder: choice.id, in: collection.id) }
            }
        }
        Divider()
        Button(deletion.confirmLabel + "…", role: .destructive) { pendingDeletion = deletion }
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
