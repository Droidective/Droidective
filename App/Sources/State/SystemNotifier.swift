import AppKit
import UserNotifications

/// Posts a macOS notification when a task finishes and nobody would see the
/// in-app toast — the main window is closed (background mode) or another app
/// is frontmost. Every important toast routes through here from `showToast`
/// (installs, pulls, file operations, conversions, captures…); install
/// batches post one summary instead of per-APK noise. Clicking a
/// notification reopens the main window (see `AppDelegate.didReceive`).
@MainActor
enum SystemNotifier {
    private static var authorizationRequested = false

    /// Ask for notification permission once per launch, at the moment it
    /// becomes relevant (a long task starting). A denial is respected
    /// silently — the in-app toasts still cover the foreground case.
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

    /// Mirror an important toast as a native notification when backgrounded.
    static func postToastIfBackgrounded(_ toast: Toast) {
        guard isBackgrounded else { return }
        post(title: title(for: toast.level), body: toast.message, sound: toast.level == .error)
    }

    static func postIfBackgrounded(title: String, body: String, sound: Bool = false) {
        guard isBackgrounded else { return }
        post(title: title, body: body, sound: sound)
    }

    private static func title(for level: Toast.Level) -> String {
        switch level {
        case .success: return "Task finished"
        case .info, .warning: return "Droidective"
        case .error: return "Task failed"
        }
    }

    private static func post(title: String, body: String, sound: Bool) {
        // First post of the launch with no prior in-context prompt: ask,
        // then deliver after the grant so this notification isn't lost.
        let needsAuthorization = !authorizationRequested
        authorizationRequested = true
        Task {
            let center = UNUserNotificationCenter.current()
            if needsAuthorization {
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                guard granted else { return }
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound { content.sound = .default }
            try? await center.add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
