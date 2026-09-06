import ADBKit
import SwiftUI

/// Whether the mirror has already shown its one-time "you can drop files here"
/// hint. Nobody guesses a drop target; nobody wants to be told twice.
let mirrorDropHintSeenKey = "mirrorDropHintSeen"

/// The progress chips a mirror shows for its own device.
///
/// Deliberately *inside* the mirror rather than a toast: the pop-out window
/// has neither a toast overlay nor a progress strip (both live in RootView),
/// and a Mirror Wall drop is several transfers at once, which one toast can
/// only ever describe the last of. The toast still fires underneath as the
/// record — this is the local, per-device feedback.
struct TransferChipsView: View {
    @Environment(AppState.self) private var state
    let serial: String
    /// Shows the one-time drop hint once the mirror is actually streaming.
    var showsHint: Bool = false
    var compact: Bool = false

    @AppStorage(mirrorDropHintSeenKey) private var hintSeen = false
    @State private var hintVisible = false

    private var transfers: [TransferJob] { state.transferJobs(onSerial: serial) }
    private var installs: [InstallJob] { state.installJobs(onSerial: serial) }

    private var hasContent: Bool {
        !transfers.isEmpty || !installs.isEmpty || hintVisible
    }

    var body: some View {
        // Nothing to show means nothing in the tree: an empty padded stack
        // over the video is an invisible region sitting on the device's own
        // top-left corner, and the mirror is something people tap.
        Group {
            if hasContent {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(transfers) { job in transferChip(job) }
                    ForEach(installs) { job in installChip(job) }
                    if hintVisible, transfers.isEmpty, installs.isEmpty { hintChip }
                }
                .padding(compact ? 8 : 12)
            }
        }
        .animation(.easeOut(duration: 0.18), value: transfers.map(\.id))
        .animation(.easeOut(duration: 0.18), value: installs.map(\.id))
        .task(id: showsHint) { await revealHintOnce() }
    }

    // MARK: - Chips

    private func transferChip(_ job: TransferJob) -> some View {
        chip(
            symbol: symbol(for: job),
            tint: tint(for: job),
            text: job.stage,
            fraction: job.fraction
        ) {
            if job.isRunning {
                chipButton("xmark", help: "Stop copying") { state.cancelTransfer(job.id) }
            }
        }
    }

    private func installChip(_ job: InstallJob) -> some View {
        chip(
            symbol: job.isRunning ? "arrow.down.app" : installSymbol(job),
            tint: installTint(job),
            text: installText(job),
            fraction: nil
        ) {
            // Only the failures an uninstall actually fixes offer it: wiping
            // an app buys nothing against a full disk or a wrong ABI.
            if AppState.offersReplaceRecovery(job) {
                Button("Uninstall & Install") { state.retryInstallByReplacing(job) }
                    .buttonStyle(.plain)
                    .font(.app(.caption).weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            }
        }
    }

    private var hintChip: some View {
        chip(
            symbol: "arrow.down.circle", tint: .white.opacity(0.8),
            text: "Drop files here to install or copy", fraction: nil
        ) { EmptyView() }
    }

    private func chip(
        symbol: String, tint: Color, text: String, fraction: Double?,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.app(.caption).weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.app(.caption))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            if let fraction {
                Text(Self.percent(fraction))
                    .font(.app(.caption).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                progressBar(fraction)
            }
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .frame(maxWidth: compact ? 260 : 380, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func progressBar(_ fraction: Double) -> some View {
        Capsule()
            .fill(.white.opacity(0.18))
            .frame(width: 54, height: 3)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.brandAccent)
                    .frame(width: 54 * max(0, min(1, fraction)), height: 3)
            }
    }

    private func chipButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(.caption2).weight(.bold))
                .foregroundStyle(.white.opacity(0.75))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Appearance per state

    private func symbol(for job: TransferJob) -> String {
        switch job.status {
        case .running: "arrow.down.doc"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func tint(for job: TransferJob) -> Color {
        switch job.status {
        case .running: .white.opacity(0.85)
        case .succeeded: .brandAccent
        case .failed: .orange
        }
    }

    private func installSymbol(_ job: InstallJob) -> String {
        switch job.status {
        case .running: "arrow.down.app"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func installTint(_ job: InstallJob) -> Color {
        switch job.status {
        case .running: .white.opacity(0.85)
        case .succeeded: .brandAccent
        case .failed: .orange
        }
    }

    private func installText(_ job: InstallJob) -> String {
        switch job.status {
        case .running: job.stage ?? "Installing \(job.packageName)…"
        case .succeeded: "Installed \(job.packageName)"
        case let .failed(message): message
        }
    }

    private static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, min(1, fraction)) * 100).rounded()))%"
    }

    /// Show the hint once, briefly, the first time a mirror actually streams —
    /// and never again on any device.
    private func revealHintOnce() async {
        guard showsHint, !hintSeen else { return }
        hintSeen = true
        withAnimation(.easeOut(duration: 0.2)) { hintVisible = true }
        try? await Task.sleep(for: .seconds(6))
        withAnimation(.easeIn(duration: 0.3)) { hintVisible = false }
    }
}
