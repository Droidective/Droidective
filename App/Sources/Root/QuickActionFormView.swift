import ADBKit
import AppKit
import SwiftUI

/// The Quick Actions panel's compact form screen: renders a form action's
/// declarative `FieldDef`s (the same definitions `FormActionView` uses in the
/// main window) and submits through `AppState.run`, so Send Text, Reverse
/// Port, Deep Link, Fake Battery… all work in-panel with no per-feature UI.
/// ⏎ in a text field runs; the outcome goes to the panel footer via `onFinish`.
///
/// Send Text additionally gets its snippet library under the field
/// (`QuickSnippetList`), because a saved snippet is the whole reason to reach
/// for Send Text from a global hotkey. ↓/↑ walk the snippets and ⏎ inserts the
/// highlighted one — the panel's own convention, where "arrow keys own
/// navigation; the query caret cedes to them".
struct QuickActionFormView: View {
    @Environment(AppState.self) private var state

    let feature: FeatureDef
    /// The panel's device fan-out: non-nil when "All devices" is in effect
    /// and this feature supports run-on-all; nil defers to the selection.
    let targetsProvider: (FeatureDef) -> [String]?
    /// Reports the outcome back to the panel, which renders it in the footer
    /// (with Reveal/Copy affordances when the result carries them).
    let onFinish: (QuickRunOutcome) -> Void

    @State private var textValues: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]
    @State private var sliderValues: [String: Double] = [:]
    @State private var presets = Presets()
    @State private var running = false
    @FocusState private var focusedField: String?
    /// The snippet row ↓/↑ has walked to, as an index into `shownSnippets`.
    /// nil means the caret is back in the field, where ⏎ runs the action.
    @State private var highlightedSnippet: Int?
    @State private var showAllSnippets = false
    /// The Mac's LAN IP — the `{ip}` placeholder's value, read the way the
    /// main window's Send Text screen reads it.
    @State private var macIP: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(feature.fields, id: \.name) { field in
                fieldRow(for: field)
            }
            HStack(spacing: 10) {
                Button {
                    submit()
                } label: {
                    Label(running ? "Running…" : "Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)
                // ⌘⏎ always runs, whether or not a snippet is highlighted.
                .keyboardShortcut(.return, modifiers: .command)
                Text(highlightedSnippet == nil ? "⏎ or ⌘⏎ to run" : "⏎ inserts · ⌘⏎ runs")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            }
            if offersSnippets {
                Divider()
                QuickSnippetList(
                    shown: shownSnippets,
                    total: snippets.count,
                    highlighted: highlightedSnippet,
                    expanded: showAllSnippets,
                    onInsert: { insert($0) },
                    onToggleExpanded: {
                        showAllSnippets.toggle()
                        highlightedSnippet = nil
                    }
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { seedDefaults() }
        .task {
            if offersSnippets { macIP = HostNetwork.primaryIPv4() }
            let loaded = await state.env.stores.presets.load()
            guard !Task.isCancelled else { return }
            presets = loaded
            // Land the cursor in the first typed-input field once the screen
            // has mounted, mirroring the palette's focus timing.
            guard let first = firstFocusableField else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            focusedField = first
        }
    }

    private var firstFocusableField: String? {
        feature.fields.first { field in
            switch field.control {
            case .text, .number, .bundle, .preset: return true
            case .select, .switch, .slider: return false
            }
        }?.name
    }

    @ViewBuilder
    private func fieldRow(for field: FieldDef) -> some View {
        switch field.control {
        case .switch, .slider:
            control(for: field)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label)
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                control(for: field)
            }
        }
    }

    @ViewBuilder
    private func control(for field: FieldDef) -> some View {
        switch field.control {
        case .text, .number, .bundle:
            textField(for: field)
        case .preset:
            HStack(spacing: 4) {
                textField(for: field)
                let values = presetValues(for: field.presetKey ?? "")
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
        case .select:
            Picker("", selection: binding(for: field)) {
                ForEach(field.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        case .switch:
            Toggle(field.label, isOn: boolBinding(for: field))
                .toggleStyle(.switch)
                .controlSize(.small)
        case .slider:
            let range = (field.min ?? 0)...(field.max ?? 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(field.label): \(sliderValues[field.name] ?? defaultSlider(field), specifier: "%.2f")")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                Slider(value: sliderBinding(for: field), in: range, step: field.step ?? 1)
            }
        }
    }

    private func textField(for field: FieldDef) -> some View {
        TextField("", text: binding(for: field), prompt: field.placeholder.map(Text.init))
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: field.name)
            .onSubmit { submitOrInsert() }
            // On the focused view, so the arrows reach the snippet list rather
            // than moving the caret. `.ignored` hands the key back, which is
            // what leaves a form with no snippets behaving exactly as before.
            .onKeyPress(.downArrow) { moveSnippetHighlight(1) }
            .onKeyPress(.upArrow) { moveSnippetHighlight(-1) }
    }

    // MARK: - Snippets

    /// Snippets belong to Send Text — the main window's `SendTextView` owns the
    /// library — so the panel names that feature rather than adding a registry
    /// flag for a single case.
    private static let snippetFeatureID = "send-text"
    private static let snippetFieldName = "text"
    /// Rows before "Show N more". Small enough that the panel does not become
    /// a list screen with a text field on top of it.
    private static let collapsedSnippetLimit = 5

    private var offersSnippets: Bool { feature.id == Self.snippetFeatureID }

    private var snippets: [SendTextSnippet] {
        offersSnippets ? presets.recentSnippets(limit: .max) : []
    }

    private var shownSnippets: [SendTextSnippet] {
        showAllSnippets ? snippets : Array(snippets.prefix(Self.collapsedSnippetLimit))
    }

    /// ⏎ takes the highlighted snippet when the arrows have walked into the
    /// list, and runs the action otherwise.
    private func submitOrInsert() {
        if let index = highlightedSnippet, shownSnippets.indices.contains(index) {
            insert(shownSnippets[index])
        } else {
            submit()
        }
    }

    /// Walk the snippet rows. ↓ from the field steps into the list, ↑ off the
    /// top hands the caret back to it, and ↓ off the bottom rests on the last
    /// row. A form with no snippets ignores both, so the caret keeps them.
    private func moveSnippetHighlight(_ direction: Int) -> KeyPress.Result {
        let rows = shownSnippets
        guard !rows.isEmpty else { return .ignored }
        guard let current = highlightedSnippet else {
            guard direction > 0 else { return .ignored }
            highlightedSnippet = 0
            return .handled
        }
        let next = current + direction
        highlightedSnippet = next < 0 ? nil : min(next, rows.count - 1)
        return .handled
    }

    /// Insert a snippet into the text field: placeholders expand to their live
    /// values and the use count behind the recency ranking bumps — the same
    /// two things the main window's list does, so the ranking is shared.
    private func insert(_ snippet: SendTextSnippet) {
        textValues[Self.snippetFieldName] = SnippetPlaceholders.expand(
            snippet.text, values: placeholderValues())
        presets.recordSnippetUse(named: snippet.name)
        persistPresets()
        highlightedSnippet = nil
        focusedField = Self.snippetFieldName
    }

    private func placeholderValues() -> [String: String] {
        var values: [String: String] = [:]
        if let clipboard = NSPasteboard.general.string(forType: .string) {
            values["clipboard"] = clipboard
        }
        if let macIP { values["ip"] = macIP }
        return values
    }

    /// Reported the way the main window's Send Text screen reports it — same
    /// failure, same store, so it lands in the notification history either
    /// way rather than being swallowed here.
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

    private func presetValues(for key: String) -> [String] {
        switch key {
        case "reversePorts": return presets.reversePorts.map(String.init)
        case "proxies": return presets.proxies
        default: return []
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
        guard !running else { return }
        // The panel resolves targets explicitly; [] means no device is ready.
        if feature.needsDevice, targetsProvider(feature)?.isEmpty == true {
            onFinish(QuickRunOutcome(message: "No device connected.", ok: false))
            return
        }
        if feature.needsBundle, state.selectedBundle == nil {
            onFinish(QuickRunOutcome(message: "Pick a saved bundle first.", ok: false))
            return
        }
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
                    onFinish(QuickRunOutcome(
                        message: "\"\(raw)\" isn't a valid number for \(field.label).", ok: false
                    ))
                    return
                }
                params[field.name] = .number(value)
            default:
                if let value = textValues[field.name], !value.isEmpty {
                    params[field.name] = .string(value)
                }
            }
        }
        running = true
        Task {
            let started = Date()
            await state.run(feature: feature, params: params, on: targetsProvider(feature))
            running = false
            let fresh = state.lastResults[feature.id].flatMap { entry in
                entry.at >= started ? QuickRunOutcome(result: entry.result) : nil
            }
            onFinish(fresh ?? QuickRunOutcome(message: "Done", ok: true))
        }
    }

    private func defaultSlider(_ field: FieldDef) -> Double {
        field.defaultValue?.numberValue ?? field.min ?? 0
    }

    private func binding(for field: FieldDef) -> Binding<String> {
        Binding(
            get: { textValues[field.name] ?? "" },
            // Typing puts ⏎ back on Run: the highlight is a place the arrows
            // took you, and editing the text means you have left it.
            set: { textValues[field.name] = $0; highlightedSnippet = nil }
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
