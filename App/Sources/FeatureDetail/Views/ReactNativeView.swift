import ADBKit
import SwiftUI

/// React Native hub — dev menu, JS reload, process death, Metro connection
/// (USB reverse + Wi-Fi dev host), saved deep links, and quick links to the
/// logs/perf tools RN work leans on. The individual actions stay available from
/// search and global hotkeys; this just gathers them so the sidebar isn't a
/// wall of RN tools.
struct ReactNativeView: View {
    @Environment(AppState.self) private var state
    @AppStorage("rnDevHost") private var devHost = ""
    @State private var metroPort = "8081"
    /// The single action currently running, keyed by feature id. Only that
    /// button shows the running/disabled state — the shared global
    /// `state.isRunningFeature` would grey out every button on this screen at
    /// once, so we track the running one here instead.
    @State private var runningID: String?

    private let actionColumns = [GridItem(.adaptive(minimum: 220), spacing: 10)]

    var body: some View {
        HubColumn {
            HubSection("Quick actions", subtitle: "One-click commands for the dev build on the selected device.") {
                LazyVGrid(columns: actionColumns, spacing: 10) {
                    RNActionCard(
                        title: "Reload JS", detail: "Reload the JS bundle — like pressing R twice",
                        icon: "arrow.clockwise", prominent: true,
                        help: "Sends R·R (keycode 46) — needs an RN dev build with the app in front",
                        disabled: isDisabled("reload-js"), running: runningID == "reload-js"
                    ) { run("reload-js") }
                    RNActionCard(
                        title: "Dev Menu", detail: "Open the in-app developer menu",
                        icon: "filemenu.and.selection",
                        help: "Sends keycode 82 — needs an RN dev build with the app in front",
                        disabled: isDisabled("open-dev-menu"), running: runningID == "open-dev-menu"
                    ) { run("open-dev-menu") }
                    RNActionCard(
                        title: "Process Death", detail: "Background, then kill the app to test state restore",
                        icon: "xmark.octagon",
                        help: "Backgrounds then kills the selected bundle — or the app in front when none is chosen",
                        disabled: isDisabled("process-death"), running: runningID == "process-death"
                    ) { run("process-death") }
                }
                if state.targetSerials.isEmpty {
                    Text("Connect a device to use these.")
                        .font(.app(.footnote))
                        .foregroundStyle(.textMuted)
                }
            }

            HubSection(
                "Metro bundler",
                subtitle: "Connect the app on the device to the bundler running on this Mac."
            ) {
                metroPathRow(
                    "USB", label: "Forward the Metro port",
                    caption: "adb reverse tunnels the device port to this Mac. Metro serves on 8081 by default."
                ) {
                    TextField("", text: $metroPort, prompt: Text("8081"))
                        .brandField()
                        .labelsHidden()
                        .frame(maxWidth: 120)
                    Button("Forward") {
                        run("reverse-port", ["port": .string(metroPort.trimmingCharacters(in: .whitespaces))])
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDisabled("reverse-port") || metroPort.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Divider()

                metroPathRow(
                    "WI-FI", label: "Set the dev server host",
                    caption: "localhost tunnels the Metro port to this Mac; a remote host is set on the "
                        + "device where Android allows it, otherwise the dev menu opens with directions."
                ) {
                    TextField("", text: $devHost, prompt: Text("192.168.1.10:8081"))
                        .brandField()
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    Button("Set") {
                        run("rn-dev-host", ["host": .string(devHost.trimmingCharacters(in: .whitespaces))])
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDisabled("rn-dev-host") || devHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            DeepLinksSection()

            HubSection("Related tools") {
                VStack(spacing: 0) {
                    relatedRow("logcat", "Logcat", "Live JS & native logs", "scroll")
                    Divider()
                    relatedRow("crash-catcher", "Crash Catcher", "Catches ReactNativeJS crashes", "exclamationmark.triangle")
                    Divider()
                    relatedRow("performance", "Performance Monitor", "Live CPU, RAM & FPS", "chart.line.uptrend.xyaxis")
                }
            }
        }
    }

    /// A button is disabled when no device is connected, or while *its own*
    /// action is in flight — never because a different button is running.
    private func isDisabled(_ id: String) -> Bool {
        state.targetSerials.isEmpty || runningID == id
    }

    /// One Metro transport path: an eyebrow naming the transport, what the
    /// control does, a one-line explanation, then the field + button.
    private func metroPathRow(
        _ transport: String, label: String, caption: String,
        @ViewBuilder controls: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(transport)
                    .font(.app(.caption).weight(.semibold))
                    .foregroundStyle(.brandAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color.brandAccent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                Text(label).font(.app(.subheadline)).foregroundStyle(.textMain)
            }
            Text(caption)
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10, content: controls)
                .padding(.top, 2)
        }
    }

    private func relatedRow(_ id: String, _ title: String, _ detail: String, _ icon: String) -> some View {
        Button {
            if let feature = FeatureRegistry.byID[id] { state.openFeature(feature) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(.textMuted).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.textMain)
                    Text(detail).font(.app(.footnote)).foregroundStyle(.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.app(.caption)).foregroundStyle(.textMuted)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private func run(_ id: String, _ params: [String: FeatureValue] = [:]) {
        guard let feature = FeatureRegistry.byID[id] else { return }
        runningID = id
        Task {
            await state.run(feature: feature, params: params)
            // Clear only if this same action is still the one showing as
            // running — a newer click on another button owns the state now.
            if runningID == id { runningID = nil }
        }
    }
}

/// A quick-action tile — the Home launchpad card language (accent icon, title,
/// wrapping subtitle, brand hover border) inset on `bgRoot` so it reads as
/// pressable inside the section card. `prominent` fills the icon chip for the
/// screen's primary action.
private struct RNActionCard: View {
    let title: String
    let detail: String
    let icon: String
    var prominent = false
    var help = ""
    var disabled = false
    /// This card's own action is in flight — shows a spinner in place of the
    /// icon. Set independently per card so one running action never spins the
    /// others.
    var running = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if running {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: icon)
                            .font(.app(.body).weight(.medium))
                            .foregroundStyle(prominent ? Color.brandAccent.contrastingForeground : .brandAccent)
                    }
                }
                .frame(width: 30, height: 30)
                .background(
                    prominent ? Color.brandAccent : Color.brandAccent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.app(.headline))
                        .foregroundStyle(.textMain)
                    Text(detail)
                        .font(.app(.footnote))
                        .foregroundStyle(.textMuted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .background(.bgRoot.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        hovering && !disabled ? Color.brandAccent : Color.borderSubtle,
                        lineWidth: hovering && !disabled ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .help(help)
    }
}
