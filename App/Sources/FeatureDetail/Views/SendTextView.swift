import ADBKit
import AppKit
import SwiftUI

/// Bespoke Send Text screen. Two sections instead of one flat column: the send
/// flow (field → Send → its result, inline where the eyes are) and the snippet
/// library (a single recency-ranked, searchable list). Replaces the old
/// FormActionView special-case, whose recent-tags row duplicated the library
/// and whose result card landed below the snippet list.
struct SendTextView: View {
    @Environment(AppState.self) private var state
    let feature: FeatureDef

    @State private var text = ""
    @State private var presets = Presets()
    /// The Mac's LAN IP — the `{ip}` placeholder value and, for the React
    /// Native role, a pinned quick insert (Metro's "Debug server host" is
    /// `<mac-ip>:8081`).
    @State private var macIP: String?
    @State private var creatingSnippet = false
    @State private var newSnippetName = ""
    @State private var newSnippetText = ""
    @State private var snippetSearch = ""
    @State private var showAllSnippets = false
    @State private var snippetPendingRemoval: SendTextSnippet?
    @FocusState private var textFocused: Bool
    /// Wipe the field after a successful send, for firing a sequence of
    /// inputs without hand-clearing between them. Persisted choice.
    @AppStorage("sendTextClearAfterSend") private var clearAfterSend = false

    /// Library collapse: this many rows before "Show more". Search appears
    /// once the library outgrows a glance.
    private static let collapsedLibraryLimit = 8
    private static let searchThreshold = 10

    var body: some View {
        Group {
            if state.targetSerials.isEmpty {
                NoDeviceView(feature: feature)
            } else {
                HubColumn {
                    sendSection
                    snippetsSection
                }
            }
        }
        .task {
            presets = await state.env.stores.presets.load()
            macIP = HostNetwork.primaryIPv4()
        }
        .task {
            // Put the cursor in the field so the user can type right away. The
            // delay lets the field mount and the window become key first.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            textFocused = true
        }
        .confirmationDialog(
            "Remove “\(snippetPendingRemoval?.name ?? "")”?",
            isPresented: Binding(
                get: { snippetPendingRemoval != nil },
                set: { if !$0 { snippetPendingRemoval = nil } }
            )
        ) {
            Button("Remove Snippet", role: .destructive) {
                if let snippet = snippetPendingRemoval {
                    presets.removeSnippet(named: snippet.name)
                    persistPresets()
                }
                snippetPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { snippetPendingRemoval = nil }
        }
    }

    // MARK: - Send section

    private var sendSection: some View {
        HubSection("Text", subtitle: "Types into whatever field is focused on the device.") {
            VStack(alignment: .leading, spacing: 12) {
                textField

                HStack(spacing: 10) {
                    Button {
                        submit()
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.isRunningFeature || text.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)

                    Text("⏎ to send")
                        .font(.app(.caption))
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: 16)

                    Toggle("Clear after sending", isOn: $clearAfterSend)
                        .toggleStyle(.checkbox)
                        .font(.app(.callout))
                        .help("Empty the field after a successful send")
                }
                .frame(maxWidth: 460)

                resultRow
            }
        }
    }

    private var textField: some View {
        TextField(
            "", text: $text,
            prompt: feature.fields.first { $0.name == "text" }?.placeholder.map(Text.init)
        )
        .brandField()
        .focused($textFocused)
        .onSubmit { submit() }
        .overlay(alignment: .trailing) {
            if !text.isEmpty {
                Button {
                    text = ""
                    textFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.textMuted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .help("Clear the text")
            }
        }
        .frame(maxWidth: 460)
    }

    /// Only a FAILED send stays visible under the button — it carries the
    /// ADBKeyboard install offer and error text worth reading. A success
    /// already announces itself via the toast, so it leaves no residue here.
    @ViewBuilder
    private var resultRow: some View {
        if let entry = state.lastResults[feature.id], !entry.result.ok {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(entry.result.message)
                        .font(.app(.callout))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Text(entry.at, style: .time)
                        .font(.app(.caption))
                        .foregroundStyle(.tertiary)
                }
                if entry.result.needsAdbKeyboard {
                    Button("Install ADBKeyboard") {
                        state.installAdbKeyboard()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
    }

    // MARK: - Snippets section

    private var snippetsSection: some View {
        HubSection(
            "Snippets",
            subtitle: "Click one to insert it — {clipboard} and {ip} fill in with the live value."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    newSnippetButton
                    Spacer(minLength: 12)
                    if presets.sendTextSnippets.count > Self.searchThreshold {
                        SearchField(prompt: "Search snippets", text: $snippetSearch)
                            .frame(maxWidth: 240)
                            .help("Find a snippet by its name or its text")
                    }
                }
                .frame(maxWidth: 520)
                snippetList
            }
        }
    }

    @ViewBuilder
    private var snippetList: some View {
        let query = snippetSearch.trimmingCharacters(in: .whitespaces)
        let ranked = presets.recentSnippets(limit: Int.max).filter { $0.matches(query) }
        let pinnedIP = query.isEmpty && state.selectedRole == .reactNativeDeveloper ? macIP : nil

        if !query.isEmpty, ranked.isEmpty {
            Text("No snippets match “\(query)”.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
        } else if ranked.isEmpty, pinnedIP == nil {
            Text("No snippets yet. Save the text you type often and it's one click from here.")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
        } else {
            let shown = showAllSnippets || !query.isEmpty
                ? ranked
                : Array(ranked.prefix(Self.collapsedLibraryLimit))
            VStack(spacing: 0) {
                if let pinnedIP {
                    macIPRow(pinnedIP)
                    if !shown.isEmpty { Divider() }
                }
                ForEach(shown) { snippet in
                    SnippetRow(snippet: snippet) {
                        insert(snippet)
                    } onRemove: {
                        snippetPendingRemoval = snippet
                    }
                    if snippet.id != shown.last?.id { Divider() }
                }
                if query.isEmpty, ranked.count > Self.collapsedLibraryLimit {
                    Divider()
                    Button {
                        showAllSnippets.toggle()
                    } label: {
                        Text(showAllSnippets
                            ? "Show less"
                            : "Show \(ranked.count - Self.collapsedLibraryLimit) more")
                            .font(.app(.caption))
                            .foregroundStyle(.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.bgRoot, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.borderSubtle))
            .frame(maxWidth: 520, alignment: .leading)
        }
    }

    /// Quick insert for the React Native role — not a saved snippet, so it
    /// pins above the list and can't be removed.
    private func macIPRow(_ ip: String) -> some View {
        Button {
            text = ip
            textFocused = true
        } label: {
            HStack(spacing: 10) {
                Label("Mac IP", systemImage: "network")
                    .font(.app(.callout))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(ip)
                    .font(.app(.caption, design: .monospaced))
                    .foregroundStyle(.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HoverHighlight())
        .help("Insert this Mac's IP address — Metro's Debug server host is \(ip):8081")
    }

    private var newSnippetButton: some View {
        Button {
            newSnippetName = ""
            newSnippetText = text
            creatingSnippet = true
        } label: {
            Label("New Snippet", systemImage: "plus")
                .font(.app(.caption))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Save a snippet — supports {clipboard} and {ip}")
        .popover(isPresented: $creatingSnippet, arrowEdge: .bottom) {
            newSnippetPopover
        }
    }

    /// Prefilled with the typed text — "save what I just sent" stays one click.
    private var newSnippetPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New snippet")
                .font(.app(.headline))
            TextField("Name", text: $newSnippetName, prompt: Text("Name — shown in the list"))
                .textFieldStyle(.roundedBorder)
                .onChange(of: newSnippetName) { _, value in
                    if value.count > SendTextSnippet.nameLimit {
                        newSnippetName = String(value.prefix(SendTextSnippet.nameLimit))
                    }
                }
            TextField("Text", text: $newSnippetText, prompt: Text("Text to insert…"), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { saveNewSnippet() }
            Text("{clipboard} and {ip} fill in with the live value when inserted.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
            HStack {
                Text("\(newSnippetName.count)/\(SendTextSnippet.nameLimit)")
                    .font(.app(.caption2).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { creatingSnippet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveNewSnippet() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSaveNewSnippet)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var canSaveNewSnippet: Bool {
        let name = newSnippetName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !newSnippetText.isEmpty
            && !presets.sendTextSnippets.contains { $0.name == name }
    }

    private func saveNewSnippet() {
        guard canSaveNewSnippet else { return }
        presets.addSnippet(named: newSnippetName, text: newSnippetText)
        persistPresets()
        creatingSnippet = false
    }

    /// Insert a snippet: placeholders expand to their live values and the use
    /// count behind the recency ranking bumps.
    private func insert(_ snippet: SendTextSnippet) {
        text = SnippetPlaceholders.expand(snippet.text, values: placeholderValues())
        presets.recordSnippetUse(named: snippet.name)
        persistPresets()
        textFocused = true
    }

    private func placeholderValues() -> [String: String] {
        var values: [String: String] = [:]
        if let clipboard = NSPasteboard.general.string(forType: .string) {
            values["clipboard"] = clipboard
        }
        if let macIP { values["ip"] = macIP }
        return values
    }

    private func persistPresets() {
        let updated = presets
        Task {
            do {
                try await state.env.stores.presets.save(updated)
            } catch {
                state.showToast(Toast(
                    message: "Couldn't save the snippet: \(error.localizedDescription)", ok: false))
            }
        }
    }

    private func submit() {
        guard !text.isEmpty, !state.isRunningFeature else { return }
        let params: [String: FeatureValue] = ["text": .string(text)]
        Task {
            // Compare timestamps so a stale success (run() early-returns on
            // no-device without touching lastResults) can't clear unsent text.
            let previousResultAt = state.lastResults[feature.id]?.1
            await state.run(feature: feature, params: params)
            if clearAfterSend, let (result, at) = state.lastResults[feature.id],
               result.ok, at != previousResultAt {
                text = ""
            }
        }
    }
}

/// One library row: the name beside a muted preview of the text — click
/// inserts, the hover-revealed trash (or right-click) removes. The trash keeps
/// its layout slot when hidden so hovering never shifts the row.
private struct SnippetRow: View {
    let snippet: SendTextSnippet
    let onInsert: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onInsert) {
                HStack(spacing: 10) {
                    Text(snippet.name)
                        .font(.app(.callout))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(snippet.text)
                        .font(.app(.caption, design: .monospaced))
                        .foregroundStyle(.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to insert\n\n\(snippet.text)")

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Remove this snippet")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(hovering ? Color.textMain.opacity(0.06) : .clear)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove Snippet", role: .destructive, action: onRemove)
        }
    }
}

/// The quiet row-hover wash used across list-like rows.
private struct HoverHighlight: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? Color.textMain.opacity(0.06) : .clear)
            .onHover { hovering = $0 }
    }
}
