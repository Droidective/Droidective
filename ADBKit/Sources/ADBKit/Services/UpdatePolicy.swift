import Foundation

/// Pure decisions for the app's update flow, kept out of the Sparkle-facing
/// glue so they're testable without Sparkle. The App layer maps Sparkle's
/// types onto these and acts on the answers:
///
/// - Automatic downloads never reach the update UI — Sparkle stages them
///   silently and the app only learns "ready, relaunch whenever". These
///   decisions cover the *visible* flows: background checks with automatic
///   downloads off, manual checks, and the user clicking "Update now".
/// - "You're up to date" and check errors are surfaced only for
///   user-initiated checks; background checks stay silent.
public enum UpdatePolicy {
    /// Where Sparkle is in an update's lifecycle when it asks what to do.
    public enum Stage: Sendable {
        /// Found in the appcast, nothing downloaded yet.
        case notDownloaded
        /// Already downloaded earlier (e.g. a dismissed update resumed).
        case downloaded
        /// Downloaded and staged — installs on quit no matter what.
        case installing
    }

    /// What to answer when Sparkle reports an update was found.
    public enum FoundReply: Equatable, Sendable {
        /// Reply "install": download/extract proceeds silently, then the
        /// ready-to-relaunch decision applies.
        case startInstall
        /// Reply "dismiss" and remember the version: show the sidebar pill
        /// and (once per version) a notification. Nothing is downloaded.
        case recordAvailable
        /// Keep Sparkle's reply handler: the pill's click answers "install"
        /// later, which relaunches into the staged update.
        case holdForRelaunch
    }

    /// Decision for `showUpdateFound`.
    ///
    /// - `userInitiated`: the check came from the user (manual "Check for
    ///   Updates…" or the pill/notification's "Update now") rather than the
    ///   hourly schedule.
    /// - `userRequestedInstall`: the user explicitly asked to *install*
    ///   ("Update now"), not merely to check.
    /// - `autoDownloadEnabled`: the Settings "download and install
    ///   automatically" toggle. When it's off, even a manual check only
    ///   announces the update — downloading stays an explicit choice.
    /// - `informational` items must never be installed — they only point at
    ///   a URL.
    public static func replyForUpdateFound(
        stage: Stage,
        userInitiated: Bool,
        userRequestedInstall: Bool,
        autoDownloadEnabled: Bool,
        informational: Bool
    ) -> FoundReply {
        if informational { return .recordAvailable }
        switch stage {
        case .installing:
            // Already staged (it installs on quit regardless) — the held
            // reply lets the pill offer an immediate relaunch instead.
            return .holdForRelaunch
        case .notDownloaded, .downloaded:
            if userRequestedInstall { return .startInstall }
            // A background check reaching the visible flow means automatic
            // download was off *or* Sparkle refused to auto-install (major
            // upgrade, failed signing) — never install those silently.
            guard userInitiated else { return .recordAvailable }
            // Plain manual check: with auto-download on, pull it now (the
            // scheduler would have anyway); with it off, announce and let
            // the user click Update.
            return autoDownloadEnabled ? .startInstall : .recordAvailable
        }
    }

    /// What to answer when a download the user started finishes extracting.
    /// An explicit "Update now" carries through to an immediate relaunch; a
    /// plain "Check for Updates" stages it and lets the pill relaunch.
    public static func relaunchImmediately(userRequestedInstall: Bool) -> Bool {
        userRequestedInstall
    }

    /// What to do on launch with the changelog stashed when an install was
    /// staged (the app writes version + notes just before relaunch/quit).
    public enum WhatsNewAction: Equatable, Sendable {
        /// Running the stashed version now — show the What's New sheet, then
        /// clear the stash.
        case show
        /// Still on the old version (install pending until quit) — keep the
        /// stash for the launch that lands in the new version.
        case keep
        /// Running something newer than the stash (updated by other means) —
        /// drop the stale notes without showing them.
        case clear
    }

    public static func whatsNewAction(
        stashedVersion: String?, currentVersion: String
    ) -> WhatsNewAction? {
        guard let stashedVersion else { return nil }
        switch currentVersion.compare(stashedVersion, options: .numeric) {
        case .orderedSame: return .show
        case .orderedAscending: return .keep
        case .orderedDescending: return .clear
        }
    }

    /// Notify (toast / notification history) at most once per discovered
    /// version, however often the hourly re-check keeps finding it. A manual
    /// "Check for Updates…" is answering the user — it always notifies, even
    /// about a version the background check already announced.
    public static func shouldNotify(
        version: String, lastNotified: String?, manualCheck: Bool = false
    ) -> Bool {
        manualCheck || version != lastNotified
    }

    /// The one-time migration of the old "Automatically check for updates"
    /// opt-out into the new download/install toggle (checks now always run).
    /// Returns the value to write for "automatically download & install", or
    /// nil to leave the new toggle at its default.
    public static func migratedAutoDownload(oldAutomaticChecks: Bool?) -> Bool? {
        guard let oldAutomaticChecks, !oldAutomaticChecks else { return nil }
        return false
    }
}
