import ADBKit
import SwiftUI

/// Entry point for the Quick Actions panel — a Raycast-style floating
/// launcher summoned by a global hotkey (or the menu bar) that runs instant/
/// toggle actions and saved custom commands directly against the selected
/// device, no main window needed. View features open the full app instead.
@MainActor
enum QuickActionsPanel {
    static func toggle(state: AppState) {
        let controller = FloatingPanelController.quickActions
        if controller.isVisible {
            controller.close()
            return
        }
        // While backgrounded the device poll is widened, so the list can be
        // stale — refresh once on open.
        state.refreshDevices()
        controller.show { close in
            QuickActionsView(onClose: close)
                .environment(state)
                .tint(.brandAccent)
        }
    }
}

/// The panel's content: type to filter saved custom commands and features,
/// ⏎ runs the highlighted one in place (result shown in the footer, success
/// auto-dismisses), Esc closes. Features that need their own screen open the
/// main window instead.
struct QuickActionsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme

    let onClose: () -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @State private var commands: [CustomCommand] = []
    /// Row id of the action in flight (drives its spinner), nil when idle.
    @State private var runningRowID: String?
    /// Outcome of the last action run from the panel, shown in the footer.
    @State private var lastRun: (message: String, ok: Bool)?
    @FocusState private var fieldFocused: Bool

    private static let digitKeys: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7", "8"]

    private var accentText: Color { Color.brandAccent.contrastingForeground(for: colorScheme) }

    /// One result row: a saved custom command, or a registry feature.
    private enum Row: Identifiable {
        case command(CustomCommand)
        case feature(FeatureDef)

        var id: String {
            switch self {
            case .command(let command): return "command:\(command.id)"
            case .feature(let feature): return "feature:\(feature.id)"
            }
        }

        var title: String {
            switch self {
            case .command(let command): return command.name
            case .feature(let feature): return feature.title
            }
        }

        var subtitle: String? {
            switch self {
            case .command(let command): return command.command
            case .feature(let feature): return feature.subtitle
            }
        }

        var icon: String {
            switch self {
            case .command: return "terminal"
            case .feature(let feature): return feature.icon
            }
        }
    }

    /// Saved commands lead (they're the user's own scripts — the point of this
    /// panel), then features in palette order.
    private var visibleRows: [Row] {
        let features = PaletteSearch.features(
            query: query,
            enabled: state.layout.effectiveEnabledIDs,
            favorites: state.layout.favorites
        )
        let commandRows = PaletteSearch.commands(commands, query: query).map(Row.command)
        return Array((commandRows + features.map(Row.feature)).prefix(8))
    }

    private var highlightedRow: Row? {
        visibleRows.indices.contains(highlighted) ? visibleRows[highlighted] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if !visibleRows.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, index: index, isHighlighted: index == highlighted)
                            .onTapGesture { activate(row) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(index == highlighted ? [.isButton, .isSelected] : .isButton)
                            .accessibilityLabel(row.title)
                    }
                }
                .padding(6)
            } else if !query.isEmpty {
                Divider()
                Text("No matching actions")
                    .font(.callout)
                    .foregroundStyle(.textMuted)
                    .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background { shortcutButtons }
        .onExitCommand { onClose() }
        .task { commands = await state.env.stores.customCommands.load() }
        .onAppear {
            // Focus must land after the panel becomes key — setting it
            // synchronously in onAppear loses the race.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                fieldFocused = true
            }
        }
        .onChange(of: query) { highlighted = 0 }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.title)
                .foregroundStyle(.brandAccent)
            TextField("Run a quick action…", text: $query)
                .textFieldStyle(.plain)
                .font(.title)
                .focused($fieldFocused)
                .onSubmit { if let row = highlightedRow { activate(row) } }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    /// Hidden buttons backing ⌘1–8 row jumps, like the ⌘K palette.
    private var shortcutButtons: some View {
        ZStack {
            ForEach(Array(Self.digitKeys.enumerated()), id: \.offset) { index, key in
                Button("") {
                    if visibleRows.indices.contains(index) { activate(visibleRows[index]) }
                }
                .keyboardShortcut(key, modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: 10) {
            if runningRowID != nil {
                ProgressView().controlSize(.small)
                Text("Running…")
                    .font(.caption)
                    .foregroundStyle(.textMuted)
            } else if let lastRun {
                Image(systemName: lastRun.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(lastRun.ok ? Color.brandAccent : Color.orange)
                Text(lastRun.message)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Label(
                    state.selectedDevice.map(state.deviceTitle) ?? "No device connected",
                    systemImage: state.selectedDevice?.platform == .iosSimulator
                        ? "iphone" : "iphone.gen3"
                )
                .font(.caption)
                .foregroundStyle(.textMuted)
                .lineLimit(1)
            }
            Spacer()
            footerHint("⏎", "Run")
            footerHint("esc", "Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyHint(key)
            Text(label).font(.caption2).foregroundStyle(.textMuted)
        }
    }

    private func rowView(_ row: Row, index: Int, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            if runningRowID == row.id {
                ProgressView().controlSize(.small).frame(width: 22)
            } else {
                Image(systemName: row.icon)
                    .frame(width: 22)
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(accentText) : AnyShapeStyle(.brandAccent))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? accentText.opacity(0.75) : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !runsInPlace(row) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundStyle(isHighlighted ? accentText.opacity(0.75) : .secondary)
                    .help("Opens in Droidective")
            }
            if index < 8 {
                KeyHint("⌘\(index + 1)", prominent: isHighlighted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isHighlighted ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .foregroundStyle(isHighlighted ? accentText : .primary)
        .contentShape(Rectangle())
    }

    private func move(_ offset: Int) {
        let count = visibleRows.count
        guard count > 0 else { return }
        highlighted = (highlighted + offset + count) % count
    }

    /// Whether activating this row runs it here (custom commands, implemented
    /// instant/toggle actions — including Screenshot, whose quick path saves
    /// straight to the capture folder) vs. opening the main window.
    private func runsInPlace(_ row: Row) -> Bool {
        switch row {
        case .command: return true
        case .feature(let feature):
            return (feature.kind == .instantAction || feature.kind == .toggleAction)
                && FeatureEngine.implementedIDs.contains(feature.id)
        }
    }

    private func activate(_ row: Row) {
        guard runningRowID == nil else { return }
        switch row {
        case .command(let command):
            run(command)
        case .feature(let feature) where runsInPlace(row):
            run(feature)
        case .feature(let feature):
            onClose()
            state.activateMainWindow()
            state.requestFeature(feature.id)
        }
    }

    private func run(_ feature: FeatureDef) {
        // `state.run` reports these preconditions only via toast (it doesn't
        // write `lastResults`), so check them here where the panel can say so.
        if feature.needsDevice, state.targetSerials.isEmpty {
            lastRun = ("No device connected.", false)
            return
        }
        if feature.needsBundle, state.selectedBundle == nil {
            lastRun = ("Pick a saved bundle first.", false)
            return
        }
        runningRowID = "feature:\(feature.id)"
        lastRun = nil
        Task {
            let started = Date()
            await state.run(feature: feature, params: [:])
            let fresh = state.lastResults[feature.id].flatMap { entry in
                entry.at >= started ? (entry.result.message, entry.result.ok) : nil
            }
            finish(fresh ?? ("Done", true))
        }
    }

    private func run(_ command: CustomCommand) {
        if command.needsBundle, state.selectedBundle == nil {
            lastRun = ("Pick a saved bundle first.", false)
            return
        }
        let serial = state.targetSerials.first ?? ""
        if command.kind == .adb, serial.isEmpty {
            lastRun = ("No device connected.", false)
            return
        }
        runningRowID = "command:\(command.id)"
        lastRun = nil
        let bundleId = state.selectedBundle?.packageId
        Task {
            let result = await CommandLog.userInitiated {
                await state.env.engine.customCommands.run(
                    command: command, bundleId: bundleId, serial: serial
                )
            }
            // Mirror the Custom Commands screen: failures land in the
            // notifications history too, not just this transient footer.
            state.showToast(Toast(message: result.message, ok: result.ok))
            finish((result.message, result.ok))
        }
    }

    /// Show the outcome in the footer; success auto-dismisses the panel after
    /// a beat, failure keeps it open for another try.
    private func finish(_ result: (message: String, ok: Bool)) {
        runningRowID = nil
        lastRun = result
        guard result.ok else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(1300))
            // A newer run may be in flight (or have failed) — don't close over it.
            if runningRowID == nil, lastRun?.ok == true { onClose() }
        }
    }
}
