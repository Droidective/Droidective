import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Decompile a local APK and browse it: set up the decompiler (download jadx /
/// apktool + a Java runtime if needed), pick an APK, then explore a file tree
/// with file-name filtering and global code search, viewing each file in the
/// CodeMirror editor (syntax highlighting, line numbers, ⌘F find).
struct DecompileBrowserView: View {
    @Environment(AppState.self) private var state
    @Environment(\.tabFeatureID) private var tabFeatureID
    @Environment(\.colorScheme) private var colorScheme

    /// Work in flight, which a move genuinely interrupts: the decompile and
    /// the code search both belong to a `.task` SwiftUI cancels on unmount.
    @State private var busy = false
    @State private var searching = false
    @State private var dropTargeted = false
    /// Bumped on every file open so a slow read can't overwrite a newer one.
    @State private var fileLoadID = 0
    @State private var findToken = 0

    /// A non-nil injected APK embeds the browser in APK Studio: it decompiles
    /// that APK directly (skipping the picker) and drops its "decompile
    /// another" button — the workspace owns APK selection there, which is why
    /// this one is passed in on every rebuild rather than kept.
    private let injectedAPK: URL?
    private let embedded: Bool

    init(apkURL: URL? = nil) {
        injectedAPK = apkURL
        embedded = apkURL != nil
    }

    /// The tree and the browsing of it, held by the window rather than by this
    /// view: a decompile takes minutes. See `DecompileModel`.
    private var model: DecompileModel {
        state.featureState(DecompileModel.self, for: tabFeatureID) { DecompileModel() }
    }

    private var mode: DecompileService.Mode {
        get { model.mode }
        nonmutating set { model.mode = newValue }
    }
    private var toolReady: Bool {
        get { model.toolReady }
        nonmutating set { model.toolReady = newValue }
    }
    private var checkingTool: Bool {
        get { model.checkingTool }
        nonmutating set { model.checkingTool = newValue }
    }
    private var download: DownloadState { model.download }
    private var apkURL: URL? {
        get { embedded ? injectedAPK : model.apkURL }
        nonmutating set { model.apkURL = newValue }
    }
    private var status: String? {
        get { model.status }
        nonmutating set { model.status = newValue }
    }
    private var root: FileNode? {
        get { model.root }
        nonmutating set { model.root = newValue }
    }
    private var selection: String? {
        get { model.selection }
        nonmutating set { model.selection = newValue }
    }
    private var fileText: String? {
        get { model.fileText }
        nonmutating set { model.fileText = newValue }
    }
    private var fileLanguage: String {
        get { model.fileLanguage }
        nonmutating set { model.fileLanguage = newValue }
    }
    private var targetLine: Int {
        get { model.targetLine }
        nonmutating set { model.targetLine = newValue }
    }
    private var filter: String {
        get { model.filter }
        nonmutating set { model.filter = newValue }
    }
    private var searchScope: SearchScope {
        get { model.searchScope }
        nonmutating set { model.searchScope = newValue }
    }
    private var searchHits: [DecompileService.SearchHit] {
        get { model.searchHits }
        nonmutating set { model.searchHits = newValue }
    }

    private typealias SearchScope = DecompileSearchScope

    private var toolName: String { mode == .jadx ? "jadx" : "apktool" }

    var body: some View {
        Group {
            if checkingTool {
                centered { ProgressView() }
            } else if !toolReady {
                setupGate
            } else if apkURL == nil {
                apkPicker
            } else if let root {
                browser(root)
            } else {
                decompileStatus
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: prepKey) { await prepare() }
        .onChange(of: mode) { _, _ in root = nil; selection = nil; fileText = nil }
    }

    /// Re-key the prepare task on both the APK and the decompiler, so switching
    /// jadx ⇆ apktool (or loading a new APK) re-checks tools and decompiles.
    private var prepKey: String { "\(apkURL?.path ?? "")|\(mode.rawValue)" }

    // MARK: - Setup gate (shown first)

    private var setupGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "curlybraces.square").font(.app(size: 46)).foregroundStyle(.brandAccent)
            Text("Set up the decompiler").font(.app(.title2).weight(.semibold))
            modePicker
            VStack(alignment: .leading, spacing: 8) {
                setupRow(toolName, detail: "Decompiler — downloaded from GitHub releases, kept up to date.")
                setupRow("Java runtime", detail: "Used to run \(toolName). A detected JDK is reused; otherwise Temurin is fetched.")
            }
            .frame(maxWidth: 460)
            if download.active {
                downloadProgress
            } else if let status {
                Text(status).font(.app(.callout)).foregroundStyle(.orange).multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            Button(download.active ? "Downloading…" : "Download \(toolName) & continue") {
                Task { await setUpTools() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(download.active)
            Text("Manage versions anytime in Settings ▸ Tools.").font(.app(.caption)).foregroundStyle(.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func setupRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.circle").foregroundStyle(.brandAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.callout).weight(.medium))
                Text(detail).font(.app(.caption)).foregroundStyle(.textMuted)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var downloadProgress: some View {
        Group {
            if let fraction = download.fraction {
                ProgressView(value: fraction) { Text(download.label ?? "Downloading…") }
            } else {
                ProgressView { Text(download.label ?? "Downloading…") }
            }
        }
        .frame(maxWidth: 360)
    }

    // MARK: - APK picker

    private var apkPicker: some View {
        VStack(spacing: 14) {
            modePicker
            Spacer()
            Image(systemName: "doc.badge.arrow.up").font(.app(size: 46)).foregroundStyle(.brandAccent)
            Text("Drag an APK here to decompile with \(toolName)").font(.app(.title3).weight(.medium))
            Button("Choose APK…") { choose() }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(.bgSurface)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    dropTargeted ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.borderSubtle),
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [7]))
                .padding(20)
        }
        .featureFileDrop(extension: "apk", perform: { apkURL = $0 }, isTargeted: { dropTargeted = $0 })
    }

    private var modePicker: some View {
        Picker("Decompiler", selection: modeBinding) {
            Text("Java (jadx)").tag(DecompileService.Mode.jadx)
            Text("Smali + resources (apktool)").tag(DecompileService.Mode.apktool)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .disabled(download.active || busy)
    }

    // MARK: - Decompiling / failure

    @ViewBuilder private var decompileStatus: some View {
        centered {
            if busy {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(status ?? "Decompiling with \(toolName)…").foregroundStyle(.textMuted)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.app(size: 36)).foregroundStyle(.orange)
                    Text(status ?? "Decompilation failed.")
                        .foregroundStyle(.textMuted).multilineTextAlignment(.center).frame(maxWidth: 480)
                    HStack {
                        Button("Try again") { Task { await runDecompile() } }
                        // Embedded in APK Studio the workspace owns which APK
                        // is loaded, so there is nothing here to pick.
                        if !embedded {
                            Button("Choose another APK") { apkURL = nil }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Browser

    private func browser(_ root: FileNode) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                modePicker.controlSize(.small)
                Text(apkURL?.lastPathComponent ?? "").font(.app(.caption)).foregroundStyle(.textMuted).lineLimit(1)
                Spacer()
                Button { findToken += 1 } label: { Label("Find", systemImage: "magnifyingglass") }
                    .help("Find in file (⌘F)")
                Menu {
                    Button("Open APK in jadx-GUI") { Task { await openInJadxGui() } }
                    Button("Open decompiled files in Finder") { revealOutput() }
                } label: {
                    Label("Open externally", systemImage: "arrow.up.forward.app")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Open the APK in the full jadx GUI, or open the files in Finder to edit them in another tool")
                if !embedded {
                    Button("Decompile another") { apkURL = nil; self.root = nil; selection = nil }
                }
            }
            .padding(8)
            Divider()
            GeometryReader { geo in
                // A narrow split pane starved the code editor behind the old
                // fixed 320pt tree — the tree now cedes width proportionally
                // (floor 230pt, cap 320) so both columns stay usable.
                HStack(spacing: 0) {
                    sidebar(root).frame(width: max(230, min(320, geo.size.width * 0.38)))
                    Divider()
                    editorPane
                }
            }
        }
        .background(.bgRoot)
        .onChange(of: selection) { _, path in loadInEditor(path, line: 0) }
    }

    private func sidebar(_ root: FileNode) -> some View {
        VStack(spacing: 6) {
            Picker("", selection: searchScopeBinding) {
                ForEach(SearchScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField(searchScope == .name ? "Filter files…" : "Search code…", text: filterBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if searchScope == .contents { Task { await runSearch(in: root) } } }
                .onChange(of: searchScope) { _, _ in searchHits = [] }
            Divider()
            if searchScope == .contents {
                searchResults
            } else {
                fileTree(root)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bgSurface)
    }

    @ViewBuilder private func fileTree(_ root: FileNode) -> some View {
        if let filtered = filteredNode(root, filter), let children = filtered.children {
            List {
                OutlineGroup(children, children: \.children) { node in
                    treeRow(node)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            centered { Text("No matching files").font(.app(.callout)).foregroundStyle(.textMuted) }
        }
    }

    @ViewBuilder private var searchResults: some View {
        if searching {
            centered { ProgressView() }
        } else if searchHits.isEmpty {
            centered {
                Text(filter.isEmpty ? "Type and press return to search the code" : "No matches")
                    .font(.app(.callout)).foregroundStyle(.textMuted).multilineTextAlignment(.center)
            }
        } else {
            List(searchHits) { hit in
                Button { loadInEditor(hit.path, line: hit.line) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\((hit.path as NSString).lastPathComponent):\(hit.line)").font(.app(.caption).weight(.medium))
                        Text(hit.text).font(.app(.caption).monospaced()).foregroundStyle(.textMuted).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var editorPane: some View {
        if let fileText {
            CodeEditorView(content: fileText, language: fileLanguage, line: targetLine, findToken: findToken)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Self.editorBackground)
        } else {
            centered { Text("Select a file to view its source.").foregroundStyle(.textMuted) }
        }
    }

    /// Matches the editor's `#282c34` (one-dark) so no window vibrancy shows
    /// through behind the web view.
    private static let editorBackground = Color(red: 0.157, green: 0.173, blue: 0.204)

    // MARK: - Actions

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { apkURL = panel.url }
    }

    private func checkTool() async {
        checkingTool = true
        let tool: ManagedTool = mode == .jadx ? .jadx : .apktool
        let hasTool = await state.env.engine.managedTools.resolve(tool) != nil
        let hasJava = await state.env.engine.toolchain.java() != nil
        toolReady = hasTool && hasJava
        checkingTool = false
    }

    private func setUpTools() async {
        do {
            if await state.env.engine.toolchain.java() == nil {
                try await installTool(.temurinJre, arch: ManagedToolStore.hostArch, label: "Java runtime")
            }
            let tool: ManagedTool = mode == .jadx ? .jadx : .apktool
            if await state.env.engine.managedTools.resolve(tool) == nil {
                try await installTool(tool, arch: "", label: tool.rawValue)
            }
            status = nil
            toolReady = true
            if apkURL != nil { await runDecompile() }
        } catch {
            status = "Setup failed: \(error.localizedDescription)"
        }
        download.finish()
    }

    private func installTool(_ tool: ManagedTool, arch: String, label: String) async throws {
        let progress = download
        progress.begin("Downloading \(label)…")
        let onProgress: @Sendable (Double) -> Void = { value in Task { @MainActor in progress.update(value) } }
        let path = try await state.env.engine.managedTools.install(tool, arch: arch, onProgress: onProgress)
        let version = await state.env.engine.managedTools.installedVersion(tool) ?? ""
        state.showToast(Toast(
            message: "Downloaded \(label) \(version)".trimmingCharacters(in: .whitespaces),
            ok: true, copyText: path, revealPath: path))
    }

    private func prepare() async {
        // A tab that moved brings its answer with it, so don't re-ask: the
        // tools were resolved once already, and re-running jadx because a
        // window changed is the restart this whole mechanism exists to avoid.
        if !toolReady { await checkTool() }
        guard toolReady, apkURL != nil else { return }
        guard root == nil || model.treeKey != prepKey else { return }
        await runDecompile()
    }

    private var modeBinding: Binding<DecompileService.Mode> {
        Binding(get: { mode }, set: { mode = $0 })
    }
    private var searchScopeBinding: Binding<SearchScope> {
        Binding(get: { searchScope }, set: { searchScope = $0 })
    }
    private var filterBinding: Binding<String> {
        Binding(get: { filter }, set: { filter = $0 })
    }

    private func runDecompile() async {
        guard let apkURL else { return }
        busy = true
        status = "Decompiling with \(toolName)…"
        defer { busy = false }
        do {
            let dir = try await state.env.engine.decompile.decompile(
                apkPath: apkURL.path, mode: mode, into: AppPaths.decompiledCacheDir)
            guard !Task.isCancelled else { return }
            // A decompiled APK is tens of thousands of files; walk it off the
            // main actor so the browser doesn't beachball as it appears.
            let tree = await Task.detached { DecompileService.tree(at: dir) }.value
            guard !Task.isCancelled else { return }
            root = tree
            model.treeKey = prepKey
            status = nil
        } catch {
            status = error.localizedDescription
            root = nil
            model.treeKey = nil
        }
    }

    /// Hand off to the full jadx GUI for advanced exploration (the in-app viewer
    /// stays a basic reader). Surfaces the launcher's result as a toast.
    private func openInJadxGui() async {
        guard let apkURL else { return }
        let result = await state.env.engine.decompile.launchJadxGui(apkPath: apkURL.path)
        state.showToast(Toast(message: result.message, ok: result.ok))
    }

    /// Reveal the decompiled output so it can be opened in any external editor.
    private func revealOutput() {
        guard let root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root.path)])
    }

    private func runSearch(in root: FileNode) async {
        let query = filter
        guard !query.isEmpty else { searchHits = []; return }
        searching = true
        let dir = URL(fileURLWithPath: root.path)
        let hits = await Task.detached { DecompileService.search(in: dir, query: query) }.value
        guard !Task.isCancelled else { return }
        searchHits = hits
        searching = false
    }

    /// Open a file in the editor, optionally jumping to (and highlighting) a line.
    /// One tree row with hand-drawn selection — same escape from the
    /// control-accent List highlight as the Apps list. Directories keep their
    /// disclosure triangles; tapping a file selects (and opens) it.
    private func treeRow(_ node: FileNode) -> some View {
        let isSelected = selection == node.path
        let accentText = Color.brandAccent.contrastingForeground(for: colorScheme)
        return Button { selection = node.path } label: {
            Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(isSelected ? accentText : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(Color.clear))
                .padding(.horizontal, 4)
        )
    }

    private func loadInEditor(_ path: String?, line: Int) {
        targetLine = line
        loadFile(path)
    }

    private func loadFile(_ path: String?) {
        guard let path else { fileText = nil; return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            fileText = nil
            return
        }
        let ext = (path as NSString).pathExtension.lowercased()
        fileLanguage = ext == "java" ? "java" : (ext == "xml" ? "xml" : "")
        // Stat the size first — clicking a large binary (a lib/*.so,
        // resources.arsc) must not block the main actor on a full read only to
        // then reject it.
        if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int,
           size > 2_000_000 {
            fileText = "File too large to preview (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))."
            return
        }
        fileLoadID += 1
        let token = fileLoadID
        fileText = nil
        Task {
            let text = await Task.detached { () -> String in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                    return "Couldn't read this file."
                }
                return String(data: data, encoding: .utf8)
                    ?? "Binary file — \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))."
            }.value
            guard token == fileLoadID else { return }
            fileText = text
        }
    }

    private func filteredNode(_ node: FileNode, _ query: String) -> FileNode? {
        guard !query.isEmpty else { return node }
        guard let children = node.children else {
            return node.name.localizedCaseInsensitiveContains(query) ? node : nil
        }
        let kept = children.compactMap { filteredNode($0, query) }
        return kept.isEmpty ? nil : FileNode(name: node.name, path: node.path, children: kept)
    }

}
