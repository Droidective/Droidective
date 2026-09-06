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
    /// Held per window by `FeatureStateStore`, not as `@State`, so the request
    /// being edited, its response and the loaded collections survive the view
    /// being rebuilt — which is what moving this tab to another window does.
    private var model: ApiClientModel {
        state.featureState(ApiClientModel.self, for: "api-client") { ApiClientModel() }
    }
    /// A bindable handle for the few controls that need write access; the
    /// projection `@State` gave for free is not available on a computed one.
    private var bindable: Bindable<ApiClientModel> { Bindable(model) }

    @AppStorage("apiSidebarSection") private var sidebarSection: ApiSidebarSection = .collections
    @AppStorage("apiRequestTab") private var requestTab: ApiRequestTab = .params
    @AppStorage("apiSidebarVisible") private var showSidebar = true
    @State private var paneWidth: CGFloat = 900

    /// Both seams persist: the sidebar as a width, the editor/response split as
    /// a fraction of the area left over, so it survives a window resize. The
    /// `live` value carries the in-flight drag and the commit happens once, on
    /// release — the same two-binding shape `RootView` uses for its own seams.
    @AppStorage("apiSidebarWidth") private var sidebarWidth = 260.0
    @State private var liveSidebarWidth: Double?
    @AppStorage("apiSplitFraction") private var splitFraction = 0.5
    @State private var liveSplitFraction: Double?

    @State private var sheet: ApiClientSheet?
    @State private var alertMessage: String?
    @State private var pendingNewRequest = false

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
                    .frame(width: ApiPaneLayout.sidebarWidth(
                        stored: liveSidebarWidth ?? sidebarWidth, total: geometry.size.width
                    ))
                    ResizeHandle(
                        value: $sidebarWidth,
                        live: $liveSidebarWidth,
                        range: ApiPaneLayout.sidebarRange
                    )
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
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: $pendingNewRequest
        ) {
            Button("Discard and Start New", role: .destructive) { model.newRequest() }
            Button("Save First…") { sheet = .saveRequest }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(model.current.name)” has edits that aren't saved to a collection.")
        }
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
            if let failure = model.persistFailure { persistFailureStrip(failure) }
            if !model.warnings.isEmpty { warningStrip }
            splitBody
        }
    }

    @ViewBuilder
    private var splitBody: some View {
        GeometryReader { geometry in
            // Stacked when narrow, so the seam runs the other way and the
            // fraction is of height rather than width.
            let total = isNarrow ? geometry.size.height : geometry.size.width
            let leading = ApiPaneLayout.leadingLength(
                total: total, fraction: liveSplitFraction ?? splitFraction
            )
            let handle = ApiSplitHandle(
                fraction: $splitFraction,
                live: $liveSplitFraction,
                total: total,
                axis: isNarrow ? .vertical : .horizontal
            )

            if isNarrow {
                VStack(spacing: 0) {
                    editor.frame(height: leading)
                    handle
                    responsePane.frame(maxHeight: .infinity)
                }
            } else {
                HStack(spacing: 0) {
                    editor.frame(width: leading)
                    handle
                    responsePane.frame(maxWidth: .infinity)
                }
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
                // Shown at every width: the sidebar is hideable in wide layouts
                // too, and without this button there was no way back once it
                // was hidden.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() }
                } label: {
                    Image(systemName: showSidebar ? "sidebar.left" : "sidebar.leading")
                }
                .buttonStyle(.borderless)
                .help(showSidebar ? "Hide sidebar" : "Show sidebar")

                Picker("", selection: bindable.current.method) {
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
        TextField("Enter a URL or paste a cURL command", text: bindable.current.url)
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

            // `tray.and.arrow.down` reads as Save; the plain download glyph is
            // what the response pane uses for an actual download, and having
            // both mean different things was the confusing part.
            Button { sheet = .saveRequest } label: { Image(systemName: "tray.and.arrow.down") }
                .buttonStyle(.borderless)
                .keyboardShortcut("s", modifiers: .command)
                .help("Save this request (⌘S)")

            Button { newRequest() } label: { Image(systemName: "plus.square") }
                .buttonStyle(.borderless)
                .help("New request")

            environmentPicker

            Menu {
                Button("Import Postman Collection or Environment…") { importFile() }
                Divider()
                // Every collection is reachable here, not only the one the open
                // request happens to belong to — with nothing open these were
                // simply absent.
                collectionMenu("Export Collection…") { exportCollection($0, includeSecrets: false) }
                collectionMenu("Export Collection with Secrets…") {
                    exportCollection($0, includeSecrets: true)
                }
                collectionMenu("Run Collection…") { sheet = .runner(collectionId: $0) }
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

    /// One collection: a plain item. Several: a submenu. None: nothing, since
    /// there is nothing to act on.
    @ViewBuilder
    private func collectionMenu(_ title: String, action: @escaping (String) -> Void) -> some View {
        if model.data.collections.count == 1, let only = model.data.collections.first {
            Button(title) { action(only.id) }
        } else if model.data.collections.count > 1 {
            Menu(title) {
                ForEach(model.data.collections) { collection in
                    Button(collection.name) { action(collection.id) }
                }
            }
        }
    }

    /// New Request threw the editor away without asking; an unsaved request is
    /// often several minutes of typing.
    private func newRequest() {
        if model.hasUnsavedChanges {
            pendingNewRequest = true
        } else {
            model.newRequest()
        }
    }

    private var environmentPicker: some View {
        Picker("", selection: bindable.data.activeEnvironmentId) {
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

    /// A failed save used to be swallowed, so collections and history would
    /// quietly not be there at the next launch.
    private func persistFailureStrip(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.app(.caption2))
            Text(message)
                .font(.app(.caption))
                .textSelection(.enabled)
            Spacer()
            Button("Retry") { model.persist() }
                .buttonStyle(.link)
                .font(.app(.caption))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.12))
    }

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
        guard let url = ApiClientFilePanels.askSave(
            suggestedName: "\(collection.name).postman_collection.json"
        ) else { return }
        if let failure = model.exportCollection(id, to: url, includeSecrets: includeSecrets) {
            alertMessage = failure
        }
    }

    private func exportWorkspace() {
        guard let url = ApiClientFilePanels.askSave(suggestedName: "droidective-api.json")
        else { return }
        if let failure = model.exportWorkspace(to: url, includeSecrets: false) {
            alertMessage = failure
        }
    }
}
