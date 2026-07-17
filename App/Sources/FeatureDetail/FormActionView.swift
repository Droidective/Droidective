import ADBKit
import AppKit
import SwiftUI

/// Generic form generated from a feature's `[FieldDef]`. Field values are
/// kept as strings/bools and converted to `FeatureValue` on submit.
struct FormActionView: View {
    @Environment(AppState.self) private var state
    let feature: FeatureDef

    @State private var textValues: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]
    @State private var sliderValues: [String: Double] = [:]
    @State private var presets = Presets()
    /// Send Text: the Mac's LAN IP — the `{ip}` placeholder value, and (for
    /// the React Native role) a quick insert in the snippets menu, since
    /// Metro's "Debug server host" is `<mac-ip>:8081`.
    @State private var macIP: String?
    @State private var creatingSnippet = false
    @State private var newSnippetName = ""
    @State private var newSnippetText = ""
    @State private var snippetSearch = ""
    @State private var showAllSnippets = false
    @State private var confirmingRun = false
    @FocusState private var focusedField: String?
    /// Send Text: wipe the field after a successful send, for firing a sequence
    /// of inputs without hand-clearing between them. Persisted choice.
    @AppStorage("sendTextClearAfterSend") private var clearAfterSend = false

    private var isSendText: Bool { feature.id == "send-text" }

    var body: some View {
        Group {
            if state.targetSerials.isEmpty {
                NoDeviceView(feature: feature)
            } else {
                formContent
            }
        }
        .id(feature.id)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(feature.fields, id: \.name) { field in
                fieldRow(for: field)
            }

            HStack(spacing: 10) {
                Button {
                    if feature.isDestructive {
                        confirmingRun = true
                    } else {
                        submit()
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(state.isRunningFeature)
                .keyboardShortcut(.return, modifiers: .command)

                Text("⌘⏎ to run")
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)

            if isSendText {
                Toggle("Clear the text after sending", isOn: $clearAfterSend)
                    .toggleStyle(.checkbox)
                    .font(.app(.callout))
            }

            LastResultCard(featureID: feature.id)
        }
        .centeredCard()
        .confirmationDialog(
            feature.confirmLabel ?? "\(feature.title) can disrupt the device. Run it?",
            isPresented: $confirmingRun
        ) {
            Button("Run \(feature.title)", role: .destructive) { submit() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { seedDefaults() }
        .task(id: feature.id) {
            // Put the cursor in the first text-like field so the user can type
            // right away. The delay lets the field mount and the window become
            // key first, mirroring the command palette's focus timing; running
            // it as a .task ties it to the view's life so a feature switch
            // cancels it instead of focusing a torn-down field.
            guard let first = firstFocusableField else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            focusedField = first
        }
        .task {
            presets = await state.env.stores.presets.load()
            if isSendText {
                macIP = HostNetwork.primaryIPv4()
            }
        }
    }

    /// The first field that takes typed input, focused on open. Features that
    /// are only sliders / switches / pickers have none and stay unfocused.
    private var firstFocusableField: String? {
        feature.fields.first { field in
            switch field.control {
            case .text, .number, .bundle, .preset: return true
            case .select, .switch, .slider: return false
            }
        }?.name
    }

    /// A labeled row for the flush layout: switches and sliders carry their own
    /// labels; every other control gets a caption label above it.
    @ViewBuilder
    private func fieldRow(for field: FieldDef) -> some View {
        switch field.control {
        case .switch, .slider:
            control(for: field)
        default:
            VStack(alignment: .leading, spacing: 5) {
                Text(field.label)
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                control(for: field)
                    .frame(maxWidth: fieldWidth(for: field.control), alignment: .leading)
            }
        }
    }

    /// Sized to the input: a port or a count doesn't need a full-width field;
    /// free text and hosts get more room.
    private func fieldWidth(for control: FieldControl) -> CGFloat {
        switch control {
        case .number: return 160
        case .preset: return 200
        case .select: return 300
        default: return 380
        }
    }

    /// A preset field: a text field with a recent-values menu at its trailing
    /// edge. The chevron sits just outside the field (not overlaid on it) so a
    /// long typed value never renders underneath the chevron.
    @ViewBuilder
    private func presetField(for field: FieldDef) -> some View {
        let values = presetValues(for: field.presetKey ?? "")
        HStack(spacing: 4) {
            TextField("", text: binding(for: field), prompt: field.placeholder.map(Text.init))
                .brandField()
                .focused($focusedField, equals: field.name)
            if !values.isEmpty {
                Menu {
                    ForEach(values, id: \.self) { value in
                        Button(value) { textValues[field.name] = value }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.textMuted)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Recent values")
            }
        }
    }

    private func presetValues(for key: String) -> [String] {
        switch key {
        case "reversePorts": return presets.reversePorts.map(String.init)
        case "proxies": return presets.proxies
        default: return []
        }
    }

    @ViewBuilder
    private func control(for field: FieldDef) -> some View {
        switch field.control {
        case .text, .number, .bundle:
            if isSendText, field.name == "text" {
                VStack(alignment: .leading, spacing: 8) {
                    plainTextField(for: field)
                    snippetTags(for: field)
                    newSnippetButton(for: field)
                    snippetLibrary(for: field)
                }
            } else {
                plainTextField(for: field)
            }
        case .preset:
            presetField(for: field)
        case .select:
            Picker("", selection: binding(for: field)) {
                ForEach(field.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
        case .switch:
            SwitchRow(field.label, isOn: boolBinding(for: field))
        case .slider:
            let range = (field.min ?? 0)...(field.max ?? 1)
            VStack(alignment: .leading) {
                Text("\(field.label): \(sliderValues[field.name] ?? defaultSlider(field), specifier: "%.2f")")
                Slider(value: sliderBinding(for: field), in: range, step: field.step ?? 1)
            }
        }
    }

    @ViewBuilder
    private func plainTextField(for field: FieldDef) -> some View {
        TextField("", text: binding(for: field), prompt: field.placeholder.map(Text.init))
            .brandField()
            .focused($focusedField, equals: field.name)
            .overlay(alignment: .trailing) {
                if isSendText, field.name == "text", !(textValues[field.name] ?? "").isEmpty {
                    Button {
                        textValues[field.name] = ""
                        focusedField = field.name
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
    }

    // MARK: - Send Text snippets

    /// Tag row: at most 6 recent snippets. Library collapse: this many rows
    /// before "Show more". Search appears once the library outgrows a glance.
    private static let recentTagLimit = 6
    private static let collapsedLibraryLimit = 8
    private static let searchThreshold = 10

    /// The recently used snippets as one-click tags under the field (top 6),
    /// led by the Mac's IP for the React Native role (Metro's "Debug server
    /// host" is `<mac-ip>:8081`).
    @ViewBuilder
    private func snippetTags(for field: FieldDef) -> some View {
        let recents = presets.recentSnippets(limit: Self.recentTagLimit)
        if !recents.isEmpty || (state.selectedRole == .reactNativeDeveloper && macIP != nil) {
            SnippetTagFlow(spacing: 6) {
                if state.selectedRole == .reactNativeDeveloper, let macIP {
                    Button {
                        textValues[field.name] = macIP
                    } label: {
                        Label("Mac IP", systemImage: "network")
                            .font(.app(.caption))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Insert this Mac's IP address — \(macIP)")
                }
                ForEach(recents) { snippet in
                    snippetChip(snippet, field: field)
                }
            }
        }
    }

    /// The one place a snippet gets created. Prefills with the typed text so
    /// "save what I just sent" stays one click.
    private func newSnippetButton(for field: FieldDef) -> some View {
        Button {
            beginCreatingSnippet(for: field)
        } label: {
            Label("New Snippet", systemImage: "plus")
                .font(.app(.caption))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Save a snippet — supports {clipboard} and {ip}")
        .popover(isPresented: $creatingSnippet, arrowEdge: .bottom) {
            newSnippetPopover(for: field)
        }
    }

    /// Everything beyond the recent tags, under the New Snippet button:
    /// alphabetical chips, collapsed behind "Show more" when long, with a
    /// search over every snippet's name and text once the library is big
    /// enough to need one.
    @ViewBuilder
    private func snippetLibrary(for field: FieldDef) -> some View {
        let recentIDs = Set(presets.recentSnippets(limit: Self.recentTagLimit).map(\.id))
        let query = snippetSearch.trimmingCharacters(in: .whitespaces)
        let library = presets.sendTextSnippets
            .filter { query.isEmpty ? !recentIDs.contains($0.id) : $0.matches(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if presets.sendTextSnippets.count > Self.searchThreshold {
            TextField("Search snippets…", text: $snippetSearch)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 200)
                .help("Find a snippet by its name or its text")
        }

        if !query.isEmpty && library.isEmpty {
            Text("No snippets match “\(query)”.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
        } else if !library.isEmpty {
            let shown = showAllSnippets || !query.isEmpty
                ? library
                : Array(library.prefix(Self.collapsedLibraryLimit))
            SnippetTagFlow(spacing: 6) {
                ForEach(shown) { snippet in
                    snippetChip(snippet, field: field)
                }
                if query.isEmpty, library.count > Self.collapsedLibraryLimit {
                    Button {
                        showAllSnippets.toggle()
                    } label: {
                        Text(showAllSnippets
                            ? "Show less"
                            : "Show \(library.count - Self.collapsedLibraryLimit) more")
                            .font(.app(.caption))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(Capsule().strokeBorder(.borderSubtle))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.textMuted)
                }
            }
        }
    }

    /// One snippet as a click-to-insert tag; right-click removes it.
    private func snippetChip(_ snippet: SendTextSnippet, field: FieldDef) -> some View {
        Button {
            insert(snippet, into: field)
        } label: {
            Text(snippet.name)
                .font(.app(.caption))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(snippet.text)\n\nRight-click to remove")
        .contextMenu {
            Button("Remove Snippet", role: .destructive) {
                presets.removeSnippet(named: snippet.name)
                persistPresets()
            }
        }
    }

    private func newSnippetPopover(for field: FieldDef) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New snippet")
                .font(.app(.headline))
            TextField("Name", text: $newSnippetName, prompt: Text("Name — shown on the tag"))
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

    /// Prefill the text with what's already typed — "save what I just sent"
    /// stays one click.
    private func beginCreatingSnippet(for field: FieldDef) {
        newSnippetName = ""
        newSnippetText = textValues[field.name] ?? ""
        creatingSnippet = true
    }

    private func saveNewSnippet() {
        guard canSaveNewSnippet else { return }
        presets.addSnippet(named: newSnippetName, text: newSnippetText)
        persistPresets()
        creatingSnippet = false
    }

    /// Insert a snippet: placeholders expand to their live values and the use
    /// count behind the top-5 tags bumps.
    private func insert(_ snippet: SendTextSnippet, into field: FieldDef) {
        textValues[field.name] = SnippetPlaceholders.expand(snippet.text, values: placeholderValues())
        presets.recordSnippetUse(named: snippet.name)
        persistPresets()
    }

    private func placeholderValues() -> [String: String] {
        var values: [String: String] = [:]
        if let clipboard = NSPasteboard.general.string(forType: .string) { values["clipboard"] = clipboard }
        if let macIP { values["ip"] = macIP }
        return values
    }

    private func persistPresets() {
        let updated = presets
        Task {
            do {
                try await state.env.stores.presets.save(updated)
            } catch {
                state.showToast(Toast(message: "Couldn't save the snippet: \(error.localizedDescription)", ok: false))
            }
        }
    }

    private func seedDefaults() {
        for field in feature.fields {
            switch field.defaultValue {
            case .string(let value) where textValues[field.name] == nil:
                textValues[field.name] = value
            case .bool(let value) where boolValues[field.name] == nil:
                boolValues[field.name] = value
            case .number(let value):
                if field.control == .slider, sliderValues[field.name] == nil {
                    sliderValues[field.name] = value
                } else if textValues[field.name] == nil {
                    // No locale grouping — "1,000" wouldn't round-trip.
                    textValues[field.name] = value == value.rounded()
                        ? String(Int(value))
                        : String(value)
                }
            default:
                break
            }
        }
    }

    private func submit() {
        var params: [String: FeatureValue] = [:]
        for field in feature.fields {
            switch field.control {
            case .switch:
                params[field.name] = .bool(boolValues[field.name] ?? (field.defaultValue?.boolValue ?? false))
            case .slider:
                params[field.name] = .number(sliderValues[field.name] ?? defaultSlider(field))
            case .number:
                let raw = (textValues[field.name] ?? "").trimmingCharacters(in: .whitespaces)
                if raw.isEmpty { break }
                guard let value = Double(raw.replacingOccurrences(of: ",", with: "")) else {
                    state.showToast(Toast(message: "\"\(raw)\" isn't a valid number for \(field.label).", ok: false))
                    return
                }
                params[field.name] = .number(value)
            default:
                if let value = textValues[field.name], !value.isEmpty {
                    params[field.name] = .string(value)
                }
            }
        }
        Task {
            // Compare timestamps so a stale success (run() early-returns on
            // no-device without touching lastResults) can't clear unsent text.
            let previousResultAt = state.lastResults[feature.id]?.1
            await state.run(feature: feature, params: params)
            if isSendText, clearAfterSend,
               let (result, at) = state.lastResults[feature.id],
               result.ok, at != previousResultAt {
                textValues["text"] = ""
            }
        }
    }

    private func defaultSlider(_ field: FieldDef) -> Double {
        field.defaultValue?.numberValue ?? field.min ?? 0
    }

    private func binding(for field: FieldDef) -> Binding<String> {
        Binding(
            get: { textValues[field.name] ?? "" },
            set: { textValues[field.name] = $0 }
        )
    }

    private func boolBinding(for field: FieldDef) -> Binding<Bool> {
        Binding(
            get: { boolValues[field.name] ?? (field.defaultValue?.boolValue ?? false) },
            set: { boolValues[field.name] = $0 }
        )
    }

    private func sliderBinding(for field: FieldDef) -> Binding<Double> {
        Binding(
            get: { sliderValues[field.name] ?? defaultSlider(field) },
            set: { sliderValues[field.name] = $0 }
        )
    }

}

/// Wraps the snippet tags onto new lines when they overflow the field width
/// (same shape as ApkInspectorView's FlowChips).
private struct SnippetTagFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
