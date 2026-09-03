import AppKit
import SwiftUI

/// The notifications history: a persistent right column listing the important
/// notifications (errors, warnings, key wins). Toggled by the bell in the
/// device bar.
struct NotificationPanelView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.notifications.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.notifications) { note in
                                NotificationRow(note: note, focused: state.focusedNotification == note.id)
                                    .id(note.id)
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    // A clicked macOS notification names its row; scroll to it
                    // and let the row flash. Cleared once handled so it can't
                    // re-flash on a later render, and so a reopened panel
                    // doesn't jump to a row nobody asked about.
                    .task(id: state.focusedNotification) {
                        guard let focused = state.focusedNotification else { return }
                        withAnimation { proxy.scrollTo(focused, anchor: .center) }
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled, state.focusedNotification == focused else { return }
                        state.focusedNotification = nil
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bgSurface)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Notifications")
                .font(.app(.headline))
            Spacer()
            if state.notifications.count > 1 {
                Button("Clear all") { state.clearNotifications() }
                    .buttonStyle(.plain)
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                    .help("Clear all notifications")
            }
            CloseButton(help: "Close notifications") { state.toggleNotifications() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.app(size: 30))
                .foregroundStyle(.textMuted)
            Text("No notifications")
                .font(.app(.callout))
                .foregroundStyle(.textMain)
            Text("Errors, warnings, and key results show up here.")
                .font(.app(.footnote))
                .foregroundStyle(.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NotificationRow: View {
    @Environment(AppState.self) private var state
    let note: AppNotification
    /// This is the row a macOS notification click asked for — tinted so the
    /// eye lands on it after the panel scrolls.
    let focused: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ToastStyle.icon(note.level))
                .foregroundStyle(ToastStyle.color(note.level))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(note.message)
                    .font(.app(.callout))
                    .foregroundStyle(.textMain)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(note.date, format: .relative(presentation: .named))
                        .font(.app(.caption))
                        .foregroundStyle(.textMuted)
                    if let revealPath = note.revealPath {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: revealPath)]
                            )
                        } label: {
                            Label("Reveal", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else if let copyText = note.copyText {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(copyText, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if let action = note.action {
                        Button(action.buttonTitle) {
                            state.performNotificationAction(action)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 0)
            if hovering {
                CloseButton(help: "Dismiss") { state.dismissNotification(note.id) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground)
        .animation(.easeOut(duration: 0.25), value: focused)
        .onHover { hovering = $0 }
    }

    /// Focus outranks hover — the flash is a one-off answer to a click that
    /// came from outside the app, and the cursor is usually sitting on the
    /// row by then anyway.
    private var rowBackground: AnyShapeStyle {
        if focused { return AnyShapeStyle(.brandAccent.opacity(0.22)) }
        if hovering { return AnyShapeStyle(.brandAccent.opacity(0.08)) }
        return AnyShapeStyle(.clear)
    }
}

/// The bell that toggles the notifications panel, with an unread badge. Lives
/// at the top-right of the device bar so toasts drop from underneath it.
struct NotificationBell: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            state.toggleNotifications()
        } label: {
            Image(systemName: state.showNotifications ? "bell.fill" : "bell")
                .overlay(alignment: .topTrailing) {
                    if state.unreadNotifications > 0 && !state.showNotifications {
                        Text(state.unreadNotifications > 99 ? "99+" : "\(state.unreadNotifications)")
                            .font(.app(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 9)
                            .padding(.vertical, 1)
                            .background(.red, in: Capsule())
                            .offset(x: 6, y: -5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle())
        .foregroundStyle(state.showNotifications ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.textMuted))
        .help(state.showNotifications ? "Hide notifications" : "Show notifications")
    }
}
