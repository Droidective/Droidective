#if !APPSTORE
import SwiftUI

/// The sidebar's bottom-left update affordance (Claude-Code style): appears
/// only while an update is available, silently downloading, or staged.
/// Clicking "Update available" starts the install; clicking "Relaunch to
/// update" swaps to the new version right away. No percentages anywhere —
/// downloading is a quiet indeterminate state.
struct UpdatePillView: View {
    @ObservedObject private var updater = SparkleUpdater.shared

    var body: some View {
        Group {
            switch updater.phase {
            case .available(let info):
                pill(
                    icon: "arrow.down.circle.fill",
                    title: info.isInformational ? "Update info" : "Update available",
                    subtitle: "Droidective \(info.version)",
                    help: info.isInformational
                        ? "Open the release page for Droidective \(info.version)"
                        : "Download and install Droidective \(info.version)"
                ) { updater.installAvailableUpdate() }
            case .downloading:
                pill(
                    icon: nil,
                    title: "Downloading update…",
                    subtitle: "Installs when you relaunch",
                    help: nil, action: nil
                )
            case .readyToRelaunch(let info):
                pill(
                    icon: "sparkles",
                    title: "Relaunch to update",
                    subtitle: "Droidective \(info.version)",
                    help: "Install Droidective \(info.version) and relaunch — quitting installs it too"
                ) { updater.relaunchNow() }
            case .installing:
                // Clickable: if the quit gets declined (a close confirmation
                // was cancelled), clicking asks the app to quit again.
                pill(
                    icon: nil,
                    title: "Installing update…",
                    subtitle: "Relaunches in a moment",
                    help: "Waiting to relaunch — click to try again"
                ) { updater.relaunchNow() }
            case .idle, .checking, .upToDate:
                EmptyView()
            }
        }
        .animation(.spring(duration: 0.35), value: pillVisible)
    }

    /// Drives the entrance/exit animation without animating between the
    /// pill's internal states (available → downloading → ready swap in
    /// place; only appear/disappear slides).
    private var pillVisible: Bool {
        switch updater.phase {
        case .available, .downloading, .readyToRelaunch, .installing: return true
        case .idle, .checking, .upToDate: return false
        }
    }

    private func pill(
        icon: String?,
        title: String,
        subtitle: String,
        help: String?,
        action: (() -> Void)?
    ) -> some View {
        PillRow(icon: icon, title: title, subtitle: subtitle, help: help, action: action)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// The menu bar's pending-update rows — the pill's stand-in while the main
/// window is closed (background mode). Renders nothing when there's nothing
/// to act on.
struct UpdateMenuItems: View {
    @ObservedObject private var updater = SparkleUpdater.shared

    var body: some View {
        switch updater.phase {
        case .available(let info):
            Button(
                info.isInformational
                    ? "Update Info: Droidective \(info.version)…"
                    : "Update to Droidective \(info.version)"
            ) { updater.installAvailableUpdate() }
            Divider()
        case .downloading(let info):
            Text("Downloading Droidective \(info.version)…")
            Divider()
        case .readyToRelaunch(let info):
            Button("Relaunch to Update (\(info.version))") { updater.relaunchNow() }
            Divider()
        case .idle, .checking, .upToDate, .installing:
            EmptyView()
        }
    }
}

/// One pill row; a separate view so hover state stays local.
private struct PillRow: View {
    let icon: String?
    let title: String
    let subtitle: String
    let help: String?
    let action: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .help(help ?? "")
                .onHover { hovering = $0 }
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.brandAccent.opacity(0.16))
                    .frame(width: 26, height: 26)
                if let icon {
                    Image(systemName: icon)
                        .font(.app(.callout))
                        .foregroundStyle(.brandAccent)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.app(.body).weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            }
            Spacer(minLength: 0)
            if action != nil {
                Image(systemName: "arrow.right")
                    .font(.app(.footnote).weight(.semibold))
                    .foregroundStyle(hovering ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.textMuted))
                    .offset(x: hovering ? 2 : 0)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.brandAccent.opacity(hovering ? 0.14 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.brandAccent.opacity(hovering ? 0.4 : 0.22))
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
#endif
