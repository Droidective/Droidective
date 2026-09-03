import AppKit
import UserNotifications

/// Mirrors the app's own notifications into Notification Center. Everything
/// that reaches the in-app notification bar is posted here too — installs,
/// pulls, file operations, conversions, captures, crashes, updates — so an
/// event is never visible only in a toast that disappears after five
/// seconds. Foreground included: a 5s overlay in the corner of one window is
/// missable whether or not that window is frontmost, and Notification Center
/// is the only record that survives it. Whoever wants less says so in System
/// Settings ▸ Notifications ▸ Droidective, which is where a Mac user looks.
///
/// Clicking one lands on the matching row in the in-app notification bar (see
/// `AppDelegate.didReceive` → `AppCore.revealNotifications`). Install batches
/// still post one summary instead of one notification per APK.
@MainActor
enum SystemNotifier {
    /// `userInfo` key carrying the `AppNotification.id` a notification came
    /// from, so a click can open the bar on that row. `nonisolated` because
    /// the delegate reads it off the response before hopping to the main
    /// actor — the value crossing is an immutable String.
    nonisolated static let entryKey = "droidective.notification"

    private static var authorizationRequested = false

    /// Ask for notification permission once per launch, at the moment it
    /// becomes relevant (a long task starting). A denial is respected
    /// silently — the in-app toasts still cover the foreground case.
    /// Must stay on the async API: a completion closure formed here is
    /// MainActor-isolated, UserNotifications invokes it on a background
    /// queue, and the isolation check traps (DROIDECTIVE-MAC-3E).
    static func requestAuthorizationOnce() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    /// True when an in-app toast can't be seen at all: background mode
    /// (accessory, no windows) or another app frontmost. Only the install
    /// batch summary uses this — it has no in-app counterpart to compete
    /// with, so posting it while the user is watching the install progress
    /// would be telling them what is already on screen.
    private static var isBackgrounded: Bool {
        NSApp.activationPolicy() == .accessory || !NSApp.isActive
    }

    /// Mirror a toast that reached the notification bar. `entry` is the
    /// `AppNotification.id` it was filed under, so a click can open the bar
    /// on that row.
    static func postToast(_ toast: Toast, entry: UUID) {
        post(
            title: title(for: toast.level), body: toast.message,
            sound: toast.level == .error, entry: entry
        )
    }

    static func postIfBackgrounded(title: String, body: String, sound: Bool = false) {
        guard isBackgrounded else { return }
        post(title: title, body: body, sound: sound, entry: nil)
    }

    /// The app's name leads, because a notification is identified by its icon
    /// and first line — "Task failed" alone says nothing about which app
    /// failed once it's sitting in Notification Center with fifty others.
    private static func title(for level: Toast.Level) -> String {
        switch level {
        case .success: return "Droidective"
        case .info: return "Droidective"
        case .warning: return "Droidective — warning"
        case .error: return "Droidective — failed"
        }
    }

    private static func post(title: String, body: String, sound: Bool, entry: UUID?) {
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
            if let entry { content.userInfo = [entryKey: entry.uuidString] }
            // The bar entry's id doubles as the request identifier, so the
            // same event re-posted replaces its notification instead of
            // stacking a second copy.
            try? await center.add(UNNotificationRequest(
                identifier: entry?.uuidString ?? UUID().uuidString,
                content: content, trigger: nil
            ))
        }
    }
}
