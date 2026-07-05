import ADBKit
import SwiftUI

/// The Quick Actions panel's compact form screen: renders a form action's
/// declarative `FieldDef`s (the same definitions `FormActionView` uses in the
/// main window) and submits through `AppState.run`, so Send Text, Reverse
/// Port, Deep Link, Fake Battery… all work in-panel with no per-feature UI.
/// ⏎ in a text field runs; the outcome goes to the panel footer via `onFinish`.
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
                .keyboardShortcut(.return, modifiers: .command)
                Text("⏎ or ⌘⏎ to run")
                    .font(.caption)
                    .foregroundStyle(.textMuted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { seedDefaults() }
        .task {
            presets = await state.env.stores.presets.load()
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
                    .font(.caption)
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
                    .font(.caption)
                    .foregroundStyle(.textMuted)
                Slider(value: sliderBinding(for: field), in: range, step: field.step ?? 1)
            }
        }
    }

    private func textField(for field: FieldDef) -> some View {
        TextField("", text: binding(for: field), prompt: field.placeholder.map(Text.init))
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: field.name)
            .onSubmit { submit() }
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
        if feature.needsDevice, state.targetSerials.isEmpty {
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
