import ADBKit
import SwiftUI

/// Define and run command macros with {bundleId} and {serial} placeholders —
/// adb argument vectors, plain terminal command lines, or script files.
struct CustomCommandsView: View {
    @Environment(AppState.self) private var state
    @State private var commands: [CustomCommand] = []
    @State private var editing: CustomCommand?
    @State private var showEditor = false
    @State private var showPresets = false
    @State private var draftName = ""
    @State private var draftCommand = ""
    @State private var draftNeedsBundle = false
    @State private var draftRunsInTerminal = false
    @State private var draftTerminal: CustomCommandTerminal = .droidective
    @State private var pendingDelete: CustomCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom Commands").font(.app(.headline))
                    Text("Define adb actions, terminal commands, or script runs with {bundleId} and {serial} placeholders.")
                        .font(.app(.footnote))
                        .foregroundStyle(.textMuted)
                }
                Spacer()
                Button { showPresets = true } label: {
                    Label("Presets", systemImage: "square.grid.2x2")
                }
                .controlSize(.small)
                Button {
                    editing = nil
                    draftName = ""
                    draftCommand = ""
                    draftNeedsBundle = false
                    draftRunsInTerminal = false
                    draftTerminal = .droidective
                    showEditor = true
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if commands.isEmpty {
                ContentUnavailableView(
                    "No custom commands",
                    systemImage: "terminal",
                    description: Text("Example: adb shell am force-stop {bundleId}")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(commands) { command in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(command.name)
                            Text(command.kind == .adb ? "adb \(command.command)" : "$ \(command.command)")
                                .font(.app(.footnote, design: .monospaced))
                                .foregroundStyle(.textMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            run(command)
                        } label: {
                            Image(systemName: command.runsInTerminal ? "terminal.fill" : "play.fill")
                                .foregroundStyle(.brandAccent)
                        }
                        .buttonStyle(.plain)
                        .help(command.runsInTerminal
                            ? "Run in \(command.terminal.displayName) — live output, prompts"
                            : "Run silently and show the result as a toast")
                        Button {
                            editing = command
                            draftName = command.name
                            // Adb commands are stored as bare arguments (like
                            // the presets); the editor shows the runnable line.
                            draftCommand = command.kind == .adb
                                ? "adb \(command.command)" : command.command
                            draftNeedsBundle = command.needsBundle
                            draftRunsInTerminal = command.runsInTerminal
                            draftTerminal = command.terminal
                            showEditor = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        Button {
                            pendingDelete = command
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(command.name)")
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { commands = await state.env.stores.customCommands.load() }
        .sheet(isPresented: $showEditor) { editor }
        .sheet(isPresented: $showPresets) { presetLibrary }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = pendingDelete {
                    commands.removeAll { $0.id == target.id }
                    persist()
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(editing == nil ? "New Command" : "Edit Command").font(.app(.headline))
                Text("Type the line as you'd run it in a terminal — no separate adb mode.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Name").font(.app(.caption)).foregroundStyle(.textMuted)
                TextField("What it does — e.g. Restart app", text: $draftName)
                    .brandField()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Command").font(.app(.caption)).foregroundStyle(.textMuted)
                HStack(alignment: .top, spacing: 8) {
                    commandEditor
                    Button {
                        chooseScript()
                    } label: {
                        Image(systemName: "doc.badge.gearshape")
                            .contentShape(Rectangle())
                    }
                    .help("Choose a script or executable to run")
                }
                HStack(spacing: 6) {
                    placeholderChip("{bundleId}", help: "Fills in the selected saved bundle's package id")
                    placeholderChip("{serial}", help: "Fills in the selected device's serial")
                }
                // Live routing cue — replaces the old adb/Terminal tabs: the
                // leading token decides where the line runs.
                Label(
                    draftRunsViaAdb
                        ? "Starts with adb — runs through Droidective's adb against the selected device."
                        : "Runs through your login shell — script files, pipes, aliases, and PATH all work.",
                    systemImage: draftRunsViaAdb ? "smartphone" : "terminal"
                )
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Output").font(.app(.caption)).foregroundStyle(.textMuted)
                Picker("Show output", selection: $draftRunsInTerminal) {
                    Text("Silently (toast)").tag(false)
                    Text("In a terminal").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if draftRunsInTerminal {
                    Picker("Terminal", selection: $draftTerminal) {
                        ForEach(CustomCommandTerminal.allCases, id: \.self) { terminal in
                            Text(terminal.displayName).tag(terminal)
                        }
                    }
                    .font(.app(.body))
                }
                Text(draftRunsInTerminal
                    ? "Opens \(draftTerminal.displayName) and runs the command — live output, prompts, ctrl-C."
                    : "Runs in the background; the result arrives as a toast.")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            }

            SwitchRow("Requires a saved bundle", isOn: $draftNeedsBundle)

            HStack {
                Spacer()
                Button("Cancel") { showEditor = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                    showEditor = false
                }
                .buttonStyle(.borderedProminent)
                // ⌘⏎, not plain ⏎ — Return belongs to the multi-line editor.
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!draftValid)
            }
        }
        .padding(20)
        .frame(width: 480)
        // Typing {bundleId} implies the command needs one — flip the switch on
        // (once per appearance of the token; the user can still turn it off).
        .onChange(of: draftCommand) { old, new in
            if !old.contains("{bundleId}"), new.contains("{bundleId}") {
                draftNeedsBundle = true
            }
        }
    }

    /// Multi-line command editor (a TextField swallows pasted newlines).
    /// Each line runs in order — multi-line always routes through the shell.
    private var commandEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draftCommand)
                .font(.app(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            if draftCommand.isEmpty {
                Text("adb shell am force-stop {bundleId}")
                    .font(.app(.body, design: .monospaced))
                    .foregroundStyle(.textMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 64, maxHeight: 120)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    /// A one-click insert for a template placeholder, appended to the command.
    private func placeholderChip(_ token: String, help: String) -> some View {
        Button {
            let needsSpace = !(draftCommand.isEmpty || draftCommand.hasSuffix(" "))
            draftCommand += needsSpace ? " \(token)" : token
        } label: {
            Text(token).font(.app(.caption, design: .monospaced))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
    }

    /// Leading-`adb`-token → adb runner (tokenized argv), anything else —
    /// multi-line included — → login shell. The classifier is
    /// `CustomCommandService.draftParts` (pure, tested in ADBKit — it's the
    /// routing decision the argv-vs-shell handling keys off).
    private static func draftParts(of line: String) -> (kind: CustomCommandKind, command: String) {
        CustomCommandService.draftParts(of: line)
    }

    private var draftRunsViaAdb: Bool { Self.draftParts(of: draftCommand).kind == .adb }

    /// A name plus a command with substance — a bare "adb" saves nothing.
    private var draftValid: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty
            && !Self.draftParts(of: draftCommand).command.isEmpty
    }

    /// Pick a script file and drop its (quoted) path into the command field,
    /// keeping anything already typed after it as arguments.
    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a script or executable to run"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // shellQuote, not ad-hoc doubling: the line runs through the user's
        // login shell, so $, backticks, and parens in a path would otherwise
        // expand or break.
        let quoted = shellQuote(url.path)
        draftCommand = draftCommand.trimmingCharacters(in: .whitespaces).isEmpty
            ? quoted
            : "\(quoted) \(draftCommand)"
    }

    private func save() {
        let parts = Self.draftParts(of: draftCommand)
        if var command = editing, let index = commands.firstIndex(where: { $0.id == command.id }) {
            command.name = draftName
            command.command = parts.command
            command.kind = parts.kind
            command.needsBundle = draftNeedsBundle
            command.runsInTerminal = draftRunsInTerminal
            command.terminal = draftTerminal
            commands[index] = command
        } else {
            commands.append(CustomCommand(
                name: draftName,
                command: parts.command,
                kind: parts.kind,
                needsBundle: draftNeedsBundle,
                createdAt: Date().timeIntervalSince1970 * 1000,
                runsInTerminal: draftRunsInTerminal,
                terminal: draftTerminal
            ))
        }
        persist()
    }

    private func persist() {
        let snapshot = commands
        Task {
            try? await state.env.stores.customCommands.save(snapshot)
        }
    }

    private func run(_ command: CustomCommand) {
        if command.needsBundle && state.selectedBundle == nil {
            state.showToast(Toast(message: "Pick a saved bundle first.", ok: false))
            return
        }
        let serial = state.targetSerials.first ?? ""
        let bundleId = state.selectedBundle?.packageId
        if command.runsInTerminal {
            do {
                let line = try CustomCommandService.terminalLine(
                    command: command, bundleId: bundleId, serial: serial
                )
                state.runCustomCommand(
                    line: line, named: command.name, serial: serial, terminal: command.terminal
                )
            } catch {
                state.showToast(Toast(message: error.localizedDescription, ok: false))
            }
            return
        }
        Task {
            await CommandLog.userInitiated {
                let result = await state.env.engine.customCommands.run(
                    command: command, bundleId: bundleId, serial: serial
                )
                state.showToast(Toast(message: result.message, ok: result.ok))
            }
        }
    }

    // MARK: - Presets

    private var presetLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preset Commands").font(.app(.headline))
                Spacer()
                Button("Done") { showPresets = false }
            }
            Text("Common adb commands. Add one to your list, then run or edit it.")
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(CommandPreset.library) { preset in
                        presetRow(preset)
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 520, height: 460)
    }

    private func presetRow(_ preset: CommandPreset) -> some View {
        let added = commands.contains { $0.name == preset.name }
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                Text("adb \(preset.command)")
                    .font(.app(.footnote, design: .monospaced))
                    .foregroundStyle(.textMuted)
                Text(preset.detail)
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            }
            Spacer(minLength: 8)
            if added {
                Label("Added", systemImage: "checkmark")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            } else {
                Button("Add") { add(preset) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func add(_ preset: CommandPreset) {
        guard !commands.contains(where: { $0.name == preset.name }) else { return }
        commands.append(CustomCommand(
            name: preset.name,
            command: preset.command,
            needsBundle: preset.needsBundle,
            createdAt: Date().timeIntervalSince1970 * 1000
        ))
        persist()
    }
}
