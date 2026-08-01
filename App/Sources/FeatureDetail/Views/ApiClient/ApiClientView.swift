import ADBKit
import AppKit
import SwiftUI

enum ApiRequestTab: String, CaseIterable, Identifiable {
    case params
    case headers
    case body
    case auth
    case tests
    case settings
    case code

    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}

enum ApiSidebarSection: String, CaseIterable, Identifiable {
    case collections
    case history
    case environments

    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}

struct ApiClientView: View {
    @Environment(AppState.self) private var state
    @State private var model = ApiClientModel()

    @State private var sidebarSection: ApiSidebarSection = .collections
    @State private var requestTab: ApiRequestTab = .params
    @State private var showSidebar = true
    @State private var paneWidth: CGFloat = 900

    @State private var sheet: ApiClientSheet?
    @State private var alertMessage: String?

    private var isNarrow: Bool { paneWidth < 760 }
    private var isCompact: Bool { paneWidth < 620 }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if showSidebar, !isNarrow {
                    ApiClientSidebar(
                        model: model,
                        section: $sidebarSection,
                        sheet: $sheet,
                        alertMessage: $alertMessage
                    )
                    .frame(width: max(220, min(320, geometry.size.width * 0.24)))
                    Divider()
                }
                mainColumn
            }
            .overlay(alignment: .leading) { narrowSidebarOverlay(geometry) }
            .animation(.easeInOut(duration: 0.2), value: showSidebar)
        }
        .measuringWidth(into: $paneWidth)
        .task { await model.attach(engine: state.env.engine, store: state.env.stores.apiClient) }
        .onDisappear { model.teardown() }
        .sheet(item: $sheet) { active in
            ApiClientSheetView(model: model, sheet: active, alertMessage: $alertMessage)
        }
        .alert(
            "API Testing",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            ),
            actions: { Button("OK") { alertMessage = nil } },
            message: { Text(alertMessage ?? "") }
        )
    }

    @ViewBuilder
    private func narrowSidebarOverlay(_ geometry: GeometryProxy) -> some View {
        if isNarrow, showSidebar {
            HStack(spacing: 0) {
                ApiClientSidebar(
                    model: model,
                    section: $sidebarSection,
                    sheet: $sheet,
                    alertMessage: $alertMessage
                )
                .frame(width: min(300, geometry.size.width * 0.75))
                .background(.bgRoot)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 2)
                .transition(.move(edge: .leading))

                Color.black.opacity(0.15)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showSidebar = false }
                    }
            }
        }
    }

    // MARK: - Main column

    private var mainColumn: some View {
        VStack(spacing: 0) {
            requestBar
            Divider()
            if !model.warnings.isEmpty { warningStrip }
            splitBody
        }
    }

    @ViewBuilder
    private var splitBody: some View {
        if isNarrow {
            VStack(spacing: 0) {
                editor
                Divider()
                responsePane
            }
        } else {
            HStack(spacing: 0) {
                editor.frame(maxWidth: .infinity)
                Divider()
                responsePane.frame(maxWidth: .infinity)
            }
        }
    }

    private var editor: some View {
        ApiRequestEditor(model: model, tab: $requestTab, compact: isCompact)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var responsePane: some View {
        ApiResponsePane(model: model, alertMessage: $alertMessage, compact: isCompact)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Request bar

    private var requestBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if isNarrow {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.borderless)
                    .help("Toggle sidebar")
                }

                Picker("", selection: $model.current.method) {
                    ForEach(HttpMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: isCompact ? 84 : 104)
                .help("HTTP method")

                urlField

                sendButton

                if model.isSending {
                    Button("Cancel") { model.cancelSend() }
                        .buttonStyle(.bordered)
                }

                if !isCompact {
                    Divider().frame(height: 20)
                    toolbarActions
                }
            }

            if isCompact {
                HStack(spacing: 8) {
                    toolbarActions
                    Spacer()
                }
            }

            if !model.unresolvedVariables.isEmpty { unresolvedStrip }
        }
        .padding(10)
        .background(.bgSurface)
    }

    private var urlField: some View {
        TextField("Enter a URL or paste a cURL command", text: $model.current.url)
            .textFieldStyle(.roundedBorder)
            .font(.app(.body, design: .monospaced))
            .onSubmit { model.send() }
            .onChange(of: model.current.url) { _, newValue in absorbPastedCurl(newValue) }
    }

    private var sendButton: some View {
        Button {
            model.send()
        } label: {
            if model.isSending {
                ProgressView().controlSize(.small)
            } else {
                Text("Send").frame(minWidth: 34)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canSend)
        .keyboardShortcut(.return, modifiers: .command)
        .help("Send the request (⌘⏎)")
    }

    /// Pasting a whole cURL command into the URL field imports it, which is how
    /// most requests start life. Typed text is left alone.
    private func absorbPastedCurl(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 5, trimmed.lowercased().hasPrefix("curl") else { return }
        let warnings = model.loadCurl(trimmed)
        if !warnings.isEmpty { requestTab = .params }
    }

    private var toolbarActions: some View {
        Group {
            Button { sheet = .importCurl } label: { Image(systemName: "curlybraces") }
                .buttonStyle(.borderless)
                .help("Import a cURL command")

            Button { sheet = .saveRequest } label: { Image(systemName: "square.and.arrow.down") }
                .buttonStyle(.borderless)
                .keyboardShortcut("s", modifiers: .command)
                .help("Save this request (⌘S)")

            Button { model.newRequest() } label: { Image(systemName: "plus.square") }
                .buttonStyle(.borderless)
                .help("New request")

            environmentPicker

            Menu {
                Button("Import Postman Collection or Environment…") { importFile() }
                if let id = model.currentCollectionId {
                    Button("Export Collection…") { exportCollection(id, includeSecrets: false) }
                    Button("Export Collection with Secrets…") {
                        exportCollection(id, includeSecrets: true)
                    }
                    Divider()
                    Button("Run Collection…") { sheet = .runner(collectionId: id) }
                }
                Divider()
                Button("Export Everything…") { exportWorkspace() }
                Button("Edit Global Variables…") { sheet = .globals }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Import, export, and run")
        }
    }

    private var environmentPicker: some View {
        Picker("", selection: $model.data.activeEnvironmentId) {
            Text("No environment").tag(String?.none)
            ForEach(model.data.environments) { environment in
                Text(environment.name).tag(Optional(environment.id))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 160)
        .onChange(of: model.data.activeEnvironmentId) { _, _ in model.persist() }
        .help("Active environment")
    }

    // MARK: - Strips

    private var warningStrip: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.app(.caption2))
                    Text(warning)
                        .font(.app(.caption))
                        .foregroundStyle(.textMuted)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }

    private var unresolvedStrip: some View {
        let names = model.unresolvedVariables.map { "{{\($0)}}" }.joined(separator: ", ")
        return HStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange)
            Text("No value for \(names)")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
            Spacer()
            Button("Edit Environment") {
                if let id = model.data.activeEnvironmentId {
                    sheet = .environment(id: id)
                } else {
                    sheet = .globals
                }
            }
            .buttonStyle(.link)
            .font(.app(.caption))
        }
    }

    // MARK: - File actions

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        NSApp?.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        alertMessage = model.importFile(at: url)
    }

    private func exportCollection(_ id: String, includeSecrets: Bool) {
        guard let collection = model.data.collections.first(where: { $0.id == id }) else { return }
        guard let url = state.askSaveLocation(suggestedName: "\(collection.name).postman_collection.json")
        else { return }
        if let failure = model.exportCollection(id, to: url, includeSecrets: includeSecrets) {
            alertMessage = failure
        }
    }

    private func exportWorkspace() {
        guard let url = state.askSaveLocation(suggestedName: "droidective-api.json") else { return }
        if let failure = model.exportWorkspace(to: url, includeSecrets: false) {
            alertMessage = failure
        }
    }
}
