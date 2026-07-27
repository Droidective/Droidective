import ADBKit
import SwiftUI

struct ApiClientView: View {
    @Environment(AppState.self) private var state
    @State private var data = ApiClientData()
    @State private var current = SavedRequest()
    @State private var response: ApiResponse?
    @State private var sending = false
    @State private var error: String?
    @State private var selectedTab: RequestTab = .params
    @State private var responseTab: ResponseTab = .body
    @State private var showCurlImport = false
    @State private var curlInput = ""
    @State private var showSaveSheet = false
    @State private var saveName = ""
    @State private var saveCollectionId: String?
    @State private var showNewCollection = false
    @State private var newCollectionName = ""
    @State private var showNewEnvironment = false
    @State private var newEnvName = ""
    @State private var editingEnvironment: ApiEnvironment?
    @State private var showEnvEditor = false
    @State private var sidebarSection: SidebarSection = .collections
    @State private var showExportPicker = false
    @State private var exportCollectionId: String?
    @State private var curlImportError: String?

    private var engine: FeatureEngine { state.env.engine }
    private var store: JSONStore<ApiClientData> { state.env.stores.apiClient }
    private var activeEnv: ApiEnvironment? { data.activeEnvironment }

    @State private var barWidth: CGFloat = 800
    @State private var showSidebar = true

    enum RequestTab: String, CaseIterable { case params, headers, body, auth, curl }
    enum ResponseTab: String, CaseIterable { case body, headers }
    enum SidebarSection: String, CaseIterable { case collections, history, environments }

    private var isNarrow: Bool { barWidth < 700 }
    private var isCompactBar: Bool { barWidth < 600 }

    var body: some View {
        GeometryReader { geo in
            let sidebarWidth = max(200, min(300, geo.size.width * 0.22))
            HStack(spacing: 0) {
                if showSidebar && !isNarrow {
                    sidebar
                        .frame(width: sidebarWidth)
                    Divider()
                }
                VStack(spacing: 0) {
                    requestBar
                    Divider()
                    if isNarrow {
                        VStack(spacing: 0) {
                            requestEditor
                                .frame(maxHeight: .infinity)
                            Divider()
                            responseViewer
                                .frame(maxHeight: .infinity)
                        }
                    } else {
                        HStack(spacing: 0) {
                            requestEditor
                                .frame(maxWidth: .infinity)
                            Divider()
                            responseViewer
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .overlay(alignment: .leading) {
                if isNarrow && showSidebar {
                    HStack(spacing: 0) {
                        sidebar
                            .frame(width: min(280, geo.size.width * 0.7))
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
            .animation(.easeInOut(duration: 0.2), value: showSidebar)
        }
        .measuringWidth(into: $barWidth)
        .task { [apiStore = store] in data = await apiStore.load() }
        .sheet(isPresented: $showCurlImport) { curlImportSheet }
        .sheet(isPresented: $showSaveSheet) { saveSheet }
        .sheet(isPresented: $showNewCollection) { newCollectionSheet }
        .sheet(isPresented: $showNewEnvironment) { newEnvironmentSheet }
        .sheet(isPresented: $showEnvEditor) { environmentEditorSheet }
        .onChange(of: showExportPicker) { _, show in
            guard show, let cid = exportCollectionId,
                  let collection = data.collections.first(where: { $0.id == cid }) else {
                showExportPicker = false
                return
            }
            showExportPicker = false
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "\(collection.name).json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let exported = ExportedCollection(name: collection.name, requests: collection.requests)
            if let jsonData = try? JSONEncoder().encode(exported) {
                try? jsonData.write(to: url)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                Picker("", selection: $sidebarSection) {
                    ForEach(SidebarSection.allCases, id: \.self) { s in
                        Text(s.rawValue.capitalized).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)

                Picker("", selection: $sidebarSection) {
                    ForEach(SidebarSection.allCases, id: \.self) { s in
                        Text(s.rawValue.capitalized).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .padding(8)
            }

            Divider()

            switch sidebarSection {
            case .collections: collectionsList
            case .history: historyList
            case .environments: environmentsList
            }
        }
        .background(.bgSurface)
    }

    private var collectionsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Collections").font(.app(.headline))
                Spacer()
                Button { showNewCollection = true } label: {
                    Image(systemName: "plus")
                }.buttonStyle(.borderless)
                Menu {
                    Button("Import Collection…") { importCollection() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if data.collections.isEmpty {
                Text("No collections yet").foregroundStyle(.textMuted)
                    .font(.app(.caption)).padding()
                Spacer()
            } else {
                List {
                    ForEach(data.collections) { collection in
                        Section {
                            ForEach(collection.requests) { req in
                                Button {
                                    current = req
                                    response = nil
                                    error = nil
                                } label: {
                                    HStack(spacing: 6) {
                                        methodBadge(req.method, small: true)
                                        Text(req.name).lineLimit(1).font(.app(.caption))
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Duplicate") { duplicateRequest(req, in: collection.id) }
                                    Button("Delete", role: .destructive) { deleteRequest(req.id, from: collection.id) }
                                }
                            }
                        } header: {
                            HStack {
                                Text(collection.name).font(.app(.subheadline)).bold()
                                Spacer()
                                Button {
                                    exportCollectionId = collection.id
                                    showExportPicker = true
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.app(.caption))
                                }.buttonStyle(.borderless)
                                Button(role: .destructive) {
                                    deleteCollection(collection.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.app(.caption))
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .translucentListBackground()
            }
        }
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History").font(.app(.headline))
                Spacer()
                if !data.history.isEmpty {
                    Button("Clear") {
                        data.clearHistory()
                        persistData()
                    }
                    .font(.app(.caption))
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if data.history.isEmpty {
                Text("No requests yet").foregroundStyle(.textMuted)
                    .font(.app(.caption)).padding()
                Spacer()
            } else {
                List(data.history) { entry in
                    Button {
                        current = entry.request
                        response = nil
                        error = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                methodBadge(entry.method, small: true)
                                if let code = entry.statusCode {
                                    Text("\(code)")
                                        .font(.app(.caption, design: .monospaced))
                                        .foregroundStyle(statusColor(code))
                                }
                            }
                            Text(entry.url).lineLimit(1)
                                .font(.app(.caption, design: .monospaced))
                                .foregroundStyle(.textMuted)
                            Text(Date(timeIntervalSince1970: entry.timestamp), style: .relative)
                                .font(.app(.caption2))
                                .foregroundStyle(.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
                .translucentListBackground()
            }
        }
    }

    private var environmentsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Environments").font(.app(.headline))
                Spacer()
                Button { showNewEnvironment = true } label: {
                    Image(systemName: "plus")
                }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Picker("Active", selection: $data.activeEnvironmentId) {
                Text("None").tag(String?.none)
                ForEach(data.environments) { env in
                    Text(env.name).tag(Optional(env.id))
                }
            }
            .padding(.horizontal, 12)
            .onChange(of: data.activeEnvironmentId) { _, _ in
                persistData()
            }

            if data.environments.isEmpty {
                Text("No environments").foregroundStyle(.textMuted)
                    .font(.app(.caption)).padding()
                Spacer()
            } else {
                List(data.environments) { env in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(env.name).font(.app(.callout))
                            Text("\(env.variables.count) variables")
                                .font(.app(.caption)).foregroundStyle(.textMuted)
                        }
                        Spacer()
                        Button {
                            editingEnvironment = env
                            showEnvEditor = true
                        } label: {
                            Image(systemName: "pencil")
                        }.buttonStyle(.borderless)
                        Button(role: .destructive) {
                            deleteEnvironment(env.id)
                        } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
                .listStyle(.sidebar)
                .translucentListBackground()
            }
        }
    }

    // MARK: - Request bar

    private var requestBar: some View {
        VStack(spacing: isCompactBar ? 6 : 0) {
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

                Picker("", selection: $current.method) {
                    ForEach(HttpMethod.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .frame(width: isCompactBar ? 80 : 100)

                TextField("URL", text: $current.url)
                    .textFieldStyle(.roundedBorder)
                    .font(.app(.body, design: .monospaced))
                    .onSubmit { sendRequest() }
                    .onChange(of: current.url) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.lowercased().hasPrefix("curl ") || trimmed.lowercased().hasPrefix("curl\t") {
                            if let parsed = CurlParser.parse(trimmed) {
                                current = parsed
                            }
                        } else if newValue.contains("\n") || newValue.contains("\r") {
                            current.url = trimmed.components(separatedBy: .newlines).first ?? ""
                        }
                    }

                Button(action: sendRequest) {
                    if sending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(current.url.isEmpty || sending)
                .keyboardShortcut(.return, modifiers: .command)

                if sending {
                    Button("Cancel") { cancelRequest() }
                        .buttonStyle(.bordered)
                }

                if !isCompactBar {
                    Divider().frame(height: 20)
                    toolbarActions
                }
            }

            if isCompactBar {
                HStack(spacing: 8) {
                    toolbarActions
                    Spacer()
                }
            }
        }
        .padding(10)
        .background(.bgSurface)
    }

    private var toolbarActions: some View {
        Group {
            Button { showCurlImport = true } label: {
                Image(systemName: "curlybraces")
            }
            .buttonStyle(.borderless)
            .help("Import cURL")

            Button {
                saveName = current.name
                saveCollectionId = data.collections.first?.id
                showSaveSheet = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Save request (⌘S)")
            .keyboardShortcut("s", modifiers: .command)

            if let env = activeEnv {
                Text(env.name)
                    .font(.app(.caption))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.bgSurface, in: Capsule())
            }
        }
    }

    // MARK: - Request editor

    private var requestEditor: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                Picker("", selection: $selectedTab) {
                    ForEach(RequestTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue.capitalized).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)

                Picker("", selection: $selectedTab) {
                    ForEach(RequestTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue.capitalized).tag(tab)
                    }
                }
                .pickerStyle(.menu)
                .padding(8)
            }

            Divider()

            switch selectedTab {
            case .params: paramsTab
            case .headers: headersTab
            case .body: bodyTab
            case .auth: authTab
            case .curl: curlTab
            }
        }
        .background(.bgSurface.opacity(0.5))
    }

    // MARK: - Params tab

    private var paramsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            keyValueEditor(title: "Query Parameters", items: $current.queryParams)
        }
    }

    // MARK: - Headers tab

    private var headersTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            keyValueEditor(title: "Headers", items: $current.headers)
        }
    }

    // MARK: - Body tab

    private var bodyTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                Picker("Body type", selection: $current.body.type) {
                    ForEach(BodyType.allCases, id: \.self) { t in
                        Text(bodyTypeLabel(t)).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12).padding(.top, 8)

                Picker("Body type", selection: $current.body.type) {
                    ForEach(BodyType.allCases, id: \.self) { t in
                        Text(bodyTypeLabel(t)).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12).padding(.top, 8)
            }

            switch current.body.type {
            case .none:
                Text("This request has no body.")
                    .foregroundStyle(.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .json:
                TextEditor(text: $current.body.jsonText)
                    .font(.app(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
            case .raw:
                HStack {
                    Text("Content-Type:").font(.app(.caption))
                    TextField("text/plain", text: $current.body.rawContentType)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                .padding(.horizontal, 12)
                TextEditor(text: $current.body.rawText)
                    .font(.app(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
            case .formUrlEncoded:
                keyValueEditor(title: "Form Fields", items: $current.body.formFields)
            }
        }
    }

    // MARK: - Auth tab

    private var authTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                Picker("Auth type", selection: $current.auth.type) {
                    ForEach(AuthType.allCases, id: \.self) { t in
                        Text(authTypeLabel(t)).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12).padding(.top, 8)

                Picker("Auth type", selection: $current.auth.type) {
                    ForEach(AuthType.allCases, id: \.self) { t in
                        Text(authTypeLabel(t)).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12).padding(.top, 8)
            }

            Group {
                switch current.auth.type {
                case .none:
                    Text("No authentication.")
                        .foregroundStyle(.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .bearer:
                    LabeledContent("Token") {
                        SecureField("Bearer token", text: $current.auth.bearerToken)
                            .textFieldStyle(.roundedBorder)
                    }
                case .basic:
                    LabeledContent("Username") {
                        TextField("Username", text: $current.auth.basicUsername)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Password") {
                        SecureField("Password", text: $current.auth.basicPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                case .apiKey:
                    LabeledContent("Header name") {
                        TextField("X-API-Key", text: $current.auth.apiKeyName)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Value") {
                        SecureField("API key value", text: $current.auth.apiKeyValue)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()
        }
    }

    // MARK: - cURL tab

    private var curlTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("cURL Preview").font(.app(.headline))
                Spacer()
                Button {
                    let curl = CurlParser.export(current, environment: activeEnv)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(curl, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12).padding(.top, 8)

            ScrollView {
                Text(CurlParser.export(current, environment: activeEnv))
                    .font(.app(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
    }

    // MARK: - Response viewer

    private var responseViewer: some View {
        VStack(spacing: 0) {
            if let response {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text("\(response.statusCode) \(response.statusText)")
                            .font(.app(.headline, design: .monospaced))
                            .foregroundStyle(statusColor(response.statusCode))
                        Text(String(format: "%.0f ms", response.elapsedMs))
                            .font(.app(.caption, design: .monospaced))
                            .foregroundStyle(.textMuted)
                        Text(formatBytes(response.size))
                            .font(.app(.caption, design: .monospaced))
                            .foregroundStyle(.textMuted)
                        Spacer()
                        Picker("", selection: $responseTab) {
                            ForEach(ResponseTab.allCases, id: \.self) { t in
                                Text(t.rawValue.capitalized).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    .padding(8)

                    HStack(spacing: 8) {
                        Text("\(response.statusCode)")
                            .font(.app(.headline, design: .monospaced))
                            .foregroundStyle(statusColor(response.statusCode))
                        Text(String(format: "%.0f ms", response.elapsedMs))
                            .font(.app(.caption, design: .monospaced))
                            .foregroundStyle(.textMuted)
                        Text(formatBytes(response.size))
                            .font(.app(.caption, design: .monospaced))
                            .foregroundStyle(.textMuted)
                        Spacer()
                        Picker("", selection: $responseTab) {
                            ForEach(ResponseTab.allCases, id: \.self) { t in
                                Text(t.rawValue.capitalized).tag(t)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(8)
                }
                Divider()

                switch responseTab {
                case .body: responseBody(response)
                case .headers: responseHeaders(response)
                }
            } else if let error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.red)
                    Text(error)
                        .font(.app(.callout))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sending {
                ProgressView("Sending…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "paperplane")
                        .font(.largeTitle).foregroundStyle(.textMuted)
                    Text("Enter a URL and press Send (⌘⏎)")
                        .foregroundStyle(.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.bgSurface.opacity(0.3))
    }

    private func responseBody(_ resp: ApiResponse) -> some View {
        ScrollView([.horizontal, .vertical]) {
            if let pretty = resp.prettyJSON {
                Text(pretty)
                    .font(.app(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else if let text = resp.bodyString {
                Text(text)
                    .font(.app(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else {
                Text("\(resp.size) bytes (binary)")
                    .foregroundStyle(.textMuted)
                    .padding(8)
            }
        }
    }

    private func responseHeaders(_ resp: ApiResponse) -> some View {
        List(Array(resp.headers.enumerated()), id: \.offset) { _, header in
            HStack {
                Text(header.key)
                    .font(.app(.callout, design: .monospaced))
                    .bold()
                Text(header.value)
                    .font(.app(.callout, design: .monospaced))
                    .foregroundStyle(.textMuted)
                    .textSelection(.enabled)
            }
        }
        .listStyle(.plain)
        .translucentListBackground()
    }

    // MARK: - Key-value editor

    private func keyValueEditor(title: String, items: Binding<[ApiKeyValue]>) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.app(.headline))
                Spacer()
                Button {
                    items.wrappedValue.append(ApiKeyValue(key: "", value: ""))
                } label: {
                    Image(systemName: "plus")
                }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if items.wrappedValue.isEmpty {
                Text("No \(title.lowercased()) yet. Click + to add one.")
                    .foregroundStyle(.textMuted)
                    .font(.app(.caption))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { $item in
                        HStack(spacing: 6) {
                            Toggle("", isOn: $item.enabled).labelsHidden()
                                .toggleStyle(.checkbox)
                            TextField("Key", text: $item.key)
                                .textFieldStyle(.roundedBorder)
                                .font(.app(.caption, design: .monospaced))
                            TextField("Value", text: $item.value)
                                .textFieldStyle(.roundedBorder)
                                .font(.app(.caption, design: .monospaced))
                            Button {
                                items.wrappedValue.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.plain)
                .translucentListBackground()
            }
        }
    }

    // MARK: - Sheets

    private var curlImportSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import cURL").font(.app(.title3))
            Text("Paste a cURL command below.")
                .font(.app(.caption)).foregroundStyle(.textMuted)
            TextEditor(text: $curlInput)
                .font(.app(.body, design: .monospaced))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .border(Color.gray.opacity(0.3))
                .onChange(of: curlInput) { _, _ in curlImportError = nil }
            if let curlImportError {
                Text(curlImportError)
                    .font(.app(.caption))
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    curlImportError = nil
                    showCurlImport = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Import") {
                    if let parsed = CurlParser.parse(curlInput) {
                        current = parsed
                        response = nil
                        error = nil
                        curlInput = ""
                        curlImportError = nil
                        showCurlImport = false
                    } else {
                        curlImportError = "Could not parse — make sure it starts with \"curl\" and includes a URL."
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(curlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 250)
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Request").font(.app(.title3))
            TextField("Name", text: $saveName)
                .textFieldStyle(.roundedBorder)
            Picker("Collection", selection: $saveCollectionId) {
                Text("None").tag(String?.none)
                ForEach(data.collections) { c in
                    Text(c.name).tag(Optional(c.id))
                }
            }
            HStack {
                Button("New Collection…") { showNewCollection = true }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Cancel") { showSaveSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    saveCurrentRequest()
                    showSaveSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 400)
    }

    private var newCollectionSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Collection").font(.app(.title3))
            TextField("Name", text: $newCollectionName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    newCollectionName = ""
                    showNewCollection = false
                }.keyboardShortcut(.cancelAction)
                Button("Create") {
                    let c = ApiCollection(name: newCollectionName)
                    data.collections.append(c)
                    saveCollectionId = c.id
                    persistData()
                    newCollectionName = ""
                    showNewCollection = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 350)
    }

    private var newEnvironmentSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Environment").font(.app(.title3))
            TextField("Name", text: $newEnvName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    newEnvName = ""
                    showNewEnvironment = false
                }.keyboardShortcut(.cancelAction)
                Button("Create") {
                    let env = ApiEnvironment(name: newEnvName)
                    data.environments.append(env)
                    persistData()
                    newEnvName = ""
                    showNewEnvironment = false
                    editingEnvironment = env
                    showEnvEditor = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(newEnvName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 350)
    }

    private var environmentEditorSheet: some View {
        EnvironmentEditorView(
            environment: editingEnvironment ?? ApiEnvironment(),
            onSave: { updated in
                if let idx = data.environments.firstIndex(where: { $0.id == updated.id }) {
                    data.environments[idx] = updated
                    persistData()
                }
                showEnvEditor = false
            },
            onCancel: { showEnvEditor = false }
        )
    }

    // MARK: - Actions

    private func sendRequest() {
        guard !current.url.isEmpty, !sending else { return }
        sending = true
        error = nil
        response = nil
        let req = current
        let env = activeEnv
        let httpClient = engine.httpClient
        let apiStore = store
        Task { @MainActor in
            do {
                let resp = try await httpClient.send(req, environment: env)
                response = resp
                data.addToHistory(ApiHistoryEntry(
                    method: req.method,
                    url: EnvironmentEngine.resolve(req.url, with: env?.variableMap ?? [:]),
                    statusCode: resp.statusCode,
                    request: req
                ))
                try? await apiStore.save(data)
            } catch is CancellationError {
                error = "Request cancelled."
            } catch {
                self.error = error.localizedDescription
            }
            sending = false
        }
    }

    private func cancelRequest() {
        let httpClient = engine.httpClient
        let id = current.id
        Task { await httpClient.cancel(id: id) }
    }

    private func persistData() {
        let snapshot = data
        let apiStore = store
        Task { try? await apiStore.save(snapshot) }
    }

    private func saveCurrentRequest() {
        var req = current
        req.name = saveName.trimmingCharacters(in: .whitespaces)
        req.modifiedAt = Date().timeIntervalSince1970
        if let cid = saveCollectionId,
           let idx = data.collections.firstIndex(where: { $0.id == cid }) {
            if let rIdx = data.collections[idx].requests.firstIndex(where: { $0.id == req.id }) {
                data.collections[idx].requests[rIdx] = req
            } else {
                data.collections[idx].requests.append(req)
            }
        }
        current = req
        persistData()
    }

    private func deleteRequest(_ requestId: String, from collectionId: String) {
        guard let idx = data.collections.firstIndex(where: { $0.id == collectionId }) else { return }
        data.collections[idx].requests.removeAll { $0.id == requestId }
        persistData()
    }

    private func duplicateRequest(_ req: SavedRequest, in collectionId: String) {
        guard let idx = data.collections.firstIndex(where: { $0.id == collectionId }) else { return }
        var dup = req
        dup.id = UUID().uuidString
        dup.name = req.name + " Copy"
        dup.createdAt = Date().timeIntervalSince1970
        dup.modifiedAt = Date().timeIntervalSince1970
        data.collections[idx].requests.append(dup)
        persistData()
    }

    private func deleteCollection(_ id: String) {
        data.collections.removeAll { $0.id == id }
        persistData()
    }

    private func deleteEnvironment(_ id: String) {
        data.environments.removeAll { $0.id == id }
        if data.activeEnvironmentId == id { data.activeEnvironmentId = nil }
        persistData()
    }

    private func importCollection() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let apiStore = store
        Task {
            guard let jsonData = try? Data(contentsOf: url),
                  let exported = try? JSONDecoder().decode(ExportedCollection.self, from: jsonData) else { return }
            let collection = ApiCollection(name: exported.name, requests: exported.requests)
            data.collections.append(collection)
            try? await apiStore.save(data)
        }
    }

    // MARK: - Helpers

    private func methodBadge(_ method: HttpMethod, small: Bool = false) -> some View {
        Text(method.rawValue)
            .font(.app(small ? .caption2 : .caption, design: .monospaced))
            .bold()
            .foregroundStyle(methodColor(method))
    }

    private func methodColor(_ method: HttpMethod) -> Color {
        switch method {
        case .get: .green
        case .post: .orange
        case .put: .blue
        case .patch: .purple
        case .delete: .red
        case .head: .cyan
        case .options: .gray
        }
    }

    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: .green
        case 300..<400: .yellow
        case 400..<500: .orange
        case 500...: .red
        default: .primary
        }
    }

    private func bodyTypeLabel(_ t: BodyType) -> String {
        switch t {
        case .none: "None"
        case .json: "JSON"
        case .formUrlEncoded: "Form"
        case .raw: "Raw"
        }
    }

    private func authTypeLabel(_ t: AuthType) -> String {
        switch t {
        case .none: "None"
        case .bearer: "Bearer"
        case .basic: "Basic"
        case .apiKey: "API Key"
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

// MARK: - Environment editor

private struct EnvironmentEditorView: View {
    @State var environment: ApiEnvironment
    var onSave: (ApiEnvironment) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Environment").font(.app(.title3))
            TextField("Name", text: $environment.name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Variables").font(.app(.headline))
                Spacer()
                Button {
                    environment.variables.append(ApiKeyValue(key: "", value: ""))
                } label: {
                    Image(systemName: "plus")
                }.buttonStyle(.borderless)
            }

            if environment.variables.isEmpty {
                Text("No variables yet.")
                    .foregroundStyle(.secondary)
                    .font(.app(.caption))
            } else {
                List {
                    ForEach($environment.variables) { $v in
                        HStack(spacing: 6) {
                            Toggle("", isOn: $v.enabled).labelsHidden()
                                .toggleStyle(.checkbox)
                            TextField("Key", text: $v.key)
                                .textFieldStyle(.roundedBorder)
                                .font(.app(.caption, design: .monospaced))
                            TextField("Value", text: $v.value)
                                .textFieldStyle(.roundedBorder)
                                .font(.app(.caption, design: .monospaced))
                            Button {
                                environment.variables.removeAll { $0.id == v.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 150)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(environment) }
                    .buttonStyle(.borderedProminent)
                    .disabled(environment.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 350)
    }
}
