import AppKit
import UserNotifications

/// Posts a macOS notification when an install batch finishes while nobody
/// would see the in-app toast — the main window is closed (background mode)
/// or another app is frontmost. Authorization is requested lazily, the first
/// time an install starts, so the permission prompt appears in context.
@MainActor
enum InstallNotifier {
    private static var authorizationRequested = false

    /// Ask for notification permission once per launch, at the moment it
    /// becomes relevant. A denial is respected silently — the in-app toasts
    /// still cover the foreground case.
    static func requestAuthorizationOnce() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// True when an in-app toast can't be seen: background mode (accessory,
    /// no windows) or another app frontmost.
    private static var isBackgrounded: Bool {
        NSApp.activationPolicy() == .accessory || !NSApp.isActive
    }

    static func postIfBackgrounded(body: String, ok: Bool) {
        guard isBackgrounded else { return }
        let content = UNMutableNotificationContent()
        content.title = ok ? "Install finished" : "Install failed"
        content.body = body.isEmpty ? (ok ? "APK installed." : "The install didn't complete.") : body
        if !ok { content.sound = .default }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
