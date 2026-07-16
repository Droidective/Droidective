#if !APPSTORE
import ADBKit
import Combine
import os
import Sparkle
import SwiftUI

/// UserDefaults key for the beta update channel opt-in (Settings ▸ General ▸
/// Updates). Off by default: everyone stays on stable-only.
let receiveBetaUpdatesKey = "receiveBetaUpdates"

/// A found update, distilled from its appcast item for the sidebar pill, the
/// notifications, and the post-relaunch What's New sheet.
struct UpdateInfo: Equatable, Sendable {
    let version: String
    /// The build number (`sparkle:version`) — what Sparkle actually compares,
    /// and the only identity that's guaranteed to change between releases
    /// (the What's New stash keys off it, not the display version).
    let build: String
    /// The release notes embedded in the appcast item (HTML).
    let notesHTML: String?
    /// An item that must not be installed — it only points at `infoURL`
    /// (Sparkle's fallback when a release is pulled).
    let isInformational: Bool
    let infoURL: URL?

    init(item: SUAppcastItem) {
        version = item.displayVersionString
        build = item.versionString
        notesHTML = item.itemDescription
        isInformational = item.isInformationOnlyUpdate
        infoURL = item.infoURL
    }
}

/// Where the updater is, driving the sidebar pill, Settings ▸ Updates, and
/// About. Background checks that find nothing never leave `.idle` — "you're
/// up to date" is reserved for a check the user asked for.
enum UpdatePhase: Equatable {
    case idle
    /// A manual check is in flight.
    case checking
    /// A manual check found nothing newer.
    case upToDate
    /// An update is known but not downloaded: automatic downloads are off,
    /// or Sparkle won't install this one unattended (major upgrade, failed
    /// signing, information-only).
    case available(UpdateInfo)
    /// Downloading/extracting silently — deliberately no percentages.
    case downloading(UpdateInfo)
    /// Staged: the pill relaunches now; otherwise it installs on quit.
    case readyToRelaunch(UpdateInfo)
    /// Relaunch under way; Sparkle is quitting the app to swap it.
    case installing
}

/// Drives Sparkle with no Sparkle-owned UI at all: this object is both the
/// user driver (update lifecycle callbacks land here and become `phase`) and
/// the updater delegate. The flow mirrors Claude Code's updater:
///
/// - Checks always run (launch + hourly), in both modes.
/// - With "download automatically" on (the default), updates stage silently
///   and surface only as the sidebar's "Relaunch to update" pill; quitting
///   installs them anyway.
/// - With it off, a found update surfaces as the pill + a notification, and
///   downloads only on an explicit "Update now".
/// - Release notes for an installed update are stashed and shown as the
///   What's New sheet on the first launch of the new version.
///
/// Lives in the App layer (never ADBKit) and is compiled out of any Mac App
/// Store build, which updates through the App Store instead. The decisions
/// are `UpdatePolicy` (ADBKit, tested); this file is the Sparkle glue.
@MainActor
final class UpdaterViewModel: NSObject, ObservableObject {
    @Published private(set) var phase: UpdatePhase = .idle
    @Published var canCheckForUpdates = false

    /// Surfaces toasts (which also land in the notification history). Wired
    /// to `AppState.showToast` as soon as the app state exists.
    var notify: ((Toast) -> Void)?

    /// nil until a real EdDSA public key is embedded — without one, starting
    /// the updater fails its launch check, so we hold off entirely.
    private var updater: SPUUpdater?
    /// Sparkle's reply handler, held while the pill offers "Relaunch".
    private var heldReply: ((SPUUserUpdateChoice) -> Void)?
    /// The automatic driver's install-now block, held once an update was
    /// staged silently in the background (see `willInstallUpdateOnQuit`).
    private var immediateInstall: (() -> Void)?
    /// The item the in-flight session is about, for callbacks that don't
    /// carry it (download progress, ready-to-relaunch).
    private var currentInfo: UpdateInfo?
    /// A user-facing "Check for Updates…" is in flight — only then do
    /// "you're up to date" and check errors surface.
    private var manualCheck = false
    /// The user clicked "Update now" — carry that consent through download
    /// straight to the relaunch instead of stopping at the pill.
    private var userRequestedInstall = false

    private static let log = Logger(
        subsystem: "com.rohindh.droidective", category: "updates")

    override init() {
        super.init()
        guard Self.signingKeyConfigured else { return }
        Self.migrateLegacyPrefs()
        let updater = SPUUpdater(
            hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        // Checking is always on — the Settings toggle governs downloading and
        // installing, not knowing. Hourly cadence comes from
        // SUScheduledCheckInterval in Info.plist.
        updater.automaticallyChecksForUpdates = true
        do {
            try updater.start()
        } catch {
            Self.log.error("Sparkle failed to start: \(error.localizedDescription)")
            return
        }
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        // The scheduler only fires once the interval has elapsed — this
        // explicit check covers "check on every launch" for quick relaunches.
        updater.checkForUpdatesInBackground()
    }

    // MARK: - User entry points

    /// Menu / Settings / About "Check for Updates…". With an update already
    /// staged there's nothing to check — remind where the relaunch is.
    func checkForUpdates() {
        if case .readyToRelaunch(let info) = phase {
            notify?(Toast(
                message: "Droidective \(info.version) is ready — relaunch to update.",
                ok: true, level: .info, action: .relaunchToUpdate, important: true))
            return
        }
        manualCheck = true
        updater?.checkForUpdates()
    }

    /// The pill's / notification's "Update now" on an `.available` update:
    /// re-enters the updater user-initiated, and `userRequestedInstall`
    /// carries the consent through download to an immediate relaunch.
    /// Information-only items just open their link.
    func installAvailableUpdate() {
        if case .available(let info) = phase, info.isInformational {
            if let url = info.infoURL { NSWorkspace.shared.open(url) }
            return
        }
        userRequestedInstall = true
        updater?.checkForUpdates()
    }

    /// The pill's "Relaunch to update": installs the staged update and
    /// relaunches right away. Ignoring the pill is fine too — a staged
    /// update installs when the app quits. If a previous relaunch got as far
    /// as asking the app to quit and something cancelled it (a close
    /// confirmation), the retained retry block asks again.
    func relaunchNow() {
        phase = .installing
        // A retained retry means a quit was already requested and declined —
        // ask again rather than re-entering the install.
        if let retryTerminate {
            retryTerminate()
        } else if let immediateInstall {
            immediateInstall()
        } else if let heldReply {
            heldReply(.install)
            self.heldReply = nil
        }
    }

    /// Kept when Sparkle's quit request could still be declined by the app
    /// (dirty-state confirmations); the pill retries through it.
    private var retryTerminate: (() -> Void)?

    // MARK: - Settings bindings

    /// Settings toggles bind to these computed properties, whose truth lives
    /// outside SwiftUI (Sparkle / UserDefaults) — the explicit
    /// `objectWillChange` is what re-renders the observing view, otherwise
    /// the toggle snaps back visually while the underlying value did change.
    var automaticallyDownloadsUpdates: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            updater?.automaticallyDownloadsUpdates = newValue
            // Turning it on with an update already announced: grab it now
            // instead of waiting out the hourly schedule.
            if newValue, case .available = phase {
                updater?.checkForUpdatesInBackground()
            }
        }
    }

    /// Opt-in to the beta update channel (appcast items tagged
    /// `<sparkle:channel>beta</sparkle:channel>`). Stored in UserDefaults and
    /// read by `allowedChannels(for:)` on every appcast load; opting in
    /// triggers a background check right away instead of leaving the user to
    /// wait out the hourly schedule.
    var receivesBetaUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: receiveBetaUpdatesKey) }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: receiveBetaUpdatesKey)
            if newValue { updater?.checkForUpdatesInBackground() }
        }
    }

    // MARK: - What's New stash

    /// Shown by the What's New sheet on the first launch of a version this
    /// updater installed.
    struct WhatsNew: Equatable, Identifiable {
        let version: String
        let notesHTML: String?
        var id: String { version }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Launch check: an install that went through left its version + notes
    /// stashed. `.show` consumes the stash; a stale stash (updated by other
    /// means) is dropped silently; a pending one (staged but the quit never
    /// happened) is kept for the launch that lands in the new version.
    /// Compared by build number — display versions can collide (a same-
    /// version re-release, dev builds), builds can't.
    static func takeWhatsNewForLaunch() -> WhatsNew? {
        let defaults = UserDefaults.standard
        let stashedBuild = defaults.string(forKey: Self.whatsNewBuildKey)
        switch UpdatePolicy.whatsNewAction(stashedVersion: stashedBuild, currentVersion: currentBuild) {
        case .show:
            let notes = defaults.string(forKey: Self.whatsNewNotesKey)
            clearWhatsNewStash()
            return WhatsNew(version: currentVersion, notesHTML: notes)
        case .clear:
            clearWhatsNewStash()
            return nil
        case .keep, nil:
            return nil
        }
    }

    private static let whatsNewBuildKey = "whatsNewPendingBuild"
    private static let whatsNewNotesKey = "whatsNewPendingNotes"
    private static let lastNotifiedVersionKey = "lastNotifiedUpdateVersion"

    /// Written whenever an install is staged or started, so the changelog
    /// survives both relaunch paths (pill click and install-on-quit).
    private func stashWhatsNew(_ info: UpdateInfo) {
        let defaults = UserDefaults.standard
        defaults.set(info.build, forKey: Self.whatsNewBuildKey)
        defaults.set(info.notesHTML, forKey: Self.whatsNewNotesKey)
    }

    private static func clearWhatsNewStash() {
        UserDefaults.standard.removeObject(forKey: whatsNewBuildKey)
        UserDefaults.standard.removeObject(forKey: whatsNewNotesKey)
    }

    // MARK: - Notifications

    /// "Update available" toast: every manual check that lands here gets one;
    /// the hourly background re-check announces each version once.
    private func announceAvailable(_ info: UpdateInfo) {
        guard noteShouldNotify(info) else { return }
        notify?(Toast(
            message: "Droidective \(info.version) is available.",
            ok: true, level: .info, action: .updateNow, important: true))
    }

    /// "Ready — relaunch" toast, same once-per-version rule. The pill is the
    /// durable affordance; this is the moment-it-happened nudge.
    private func announceReady(_ info: UpdateInfo) {
        guard noteShouldNotify(info) else { return }
        notify?(Toast(
            message: "Droidective \(info.version) is ready — relaunch to update.",
            ok: true, level: .info, action: .relaunchToUpdate, important: true))
    }

    private func noteShouldNotify(_ info: UpdateInfo) -> Bool {
        // The toast pipeline is wired when the main window first appears; an
        // update staged before that must not consume its once-per-version
        // slot on a toast nobody can see — the next find announces it.
        guard notify != nil else { return false }
        let defaults = UserDefaults.standard
        guard manualCheck
            || UpdatePolicy.shouldNotify(
                version: info.version,
                lastNotified: defaults.string(forKey: Self.lastNotifiedVersionKey))
        else { return false }
        defaults.set(info.version, forKey: Self.lastNotifiedVersionKey)
        return true
    }

    // MARK: - Setup

    /// True once `generate_keys`' output has replaced the project.yml
    /// placeholder.
    private static var signingKeyConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && key != "REPLACE_WITH_OUTPUT_OF_generate_keys"
    }

    private static let migrationKey = "migratedUpdatePrefsToSilentFlow"

    /// One-time: the old toggle was "check automatically"; the new one is
    /// "download & install automatically" (checks always run). A previous
    /// opt-out keeps its meaning — updates wait for an explicit go-ahead.
    /// The dismissed-update launch reminder is replaced by the sidebar pill.
    private static func migrateLegacyPrefs() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }
        if let checks = defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool, !checks {
            defaults.set(false, forKey: "SUAutomaticallyUpdate")
        }
        defaults.removeObject(forKey: "pendingUpdateVersion")
        defaults.set(true, forKey: migrationKey)
    }
}

// MARK: - Sparkle user driver (all update UI is ours)

extension UpdaterViewModel: SPUUserDriver {
    /// Never reached in practice (SUEnableAutomaticChecks is set in
    /// Info.plist, which suppresses the prompt) — grant checks, no profile.
    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let info = UpdateInfo(item: appcastItem)
        currentInfo = info
        let stage: UpdatePolicy.Stage
        switch state.stage {
        case .notDownloaded: stage = .notDownloaded
        case .downloaded: stage = .downloaded
        case .installing: stage = .installing
        @unknown default: stage = .notDownloaded
        }
        switch UpdatePolicy.replyForUpdateFound(
            stage: stage,
            userInitiated: state.userInitiated,
            userRequestedInstall: userRequestedInstall,
            autoDownloadEnabled: automaticallyDownloadsUpdates,
            informational: info.isInformational
        ) {
        case .startInstall:
            phase = .downloading(info)
            reply(.install)
        case .recordAvailable:
            phase = .available(info)
            announceAvailable(info)
            manualCheck = false
            userRequestedInstall = false
            reply(.dismiss)
        case .holdForRelaunch:
            // Already staged from an earlier session — it installs on quit;
            // the held reply lets the pill relaunch immediately instead.
            stashWhatsNew(info)
            heldReply = reply
            phase = .readyToRelaunch(info)
            announceReady(info)
            manualCheck = false
            userRequestedInstall = false
        }
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let info = currentInfo else {
            reply(.dismiss)
            return
        }
        stashWhatsNew(info)
        if UpdatePolicy.relaunchImmediately(userRequestedInstall: userRequestedInstall) {
            phase = .installing
            reply(.install)
        } else {
            heldReply = reply
            phase = .readyToRelaunch(info)
            announceReady(info)
        }
        manualCheck = false
        userRequestedInstall = false
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        if manualCheck {
            phase = .upToDate
            notify?(Toast(
                message: "You're up to date — Droidective \(Self.currentVersion) is the latest version.",
                ok: true, level: .info, important: false))
        }
        manualCheck = false
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        Self.log.error("Updater error: \(error.localizedDescription)")
        if manualCheck {
            notify?(Toast(message: "Update check failed: \(error.localizedDescription)", ok: false))
        }
        manualCheck = false
        userRequestedInstall = false
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        if let currentInfo { phase = .downloading(currentInfo) }
    }

    // Progress is deliberately not surfaced anywhere — the pill shows an
    // indeterminate state and flips to "Relaunch" when staging completes.
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}

    // Release notes are embedded in the appcast (itemDescription); the
    // linked-notes path never runs for our feed.
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        phase = .installing
        // The app may decline the quit (a confirmation sheet). Keep the
        // retry so the pill can ask again instead of hanging on
        // "Installing…" forever.
        retryTerminate = applicationTerminated ? nil : retryTerminatingApplication
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        // Sessions end here on abort or hand-off. Sticky phases (available /
        // ready-to-relaunch / up-to-date) survive; only in-flight progress
        // resets so a silently aborted background download doesn't leave a
        // stuck "Downloading…" pill.
        retryTerminate = nil
        switch phase {
        case .checking, .downloading:
            phase = .idle
        case .idle, .upToDate, .available, .readyToRelaunch, .installing:
            break
        }
    }
}

// MARK: - Sparkle updater delegate

extension UpdaterViewModel: SPUUpdaterDelegate {
    /// Sparkle includes appcast items whose `<sparkle:channel>` is in this
    /// set; untagged (stable) items are always included. Turning beta off
    /// later never downgrades — the installed build simply waits for the
    /// next stable release with a higher build number.
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: receiveBetaUpdatesKey) ? ["beta"] : []
    }

    /// The automatic driver downloaded and staged an update without touching
    /// the user driver. Returning true keeps the session alive with an
    /// install-now block — the pill's "Relaunch to update". Quitting without
    /// clicking still installs the staged update.
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Sparkle drives the updater on the main run loop; this callback
        // arrives on the main thread, and the block is only ever stored and
        // invoked on the main actor from here on.
        nonisolated(unsafe) let installHandler = immediateInstallHandler
        MainActor.assumeIsolated {
            let info = UpdateInfo(item: item)
            stashWhatsNew(info)
            currentInfo = info
            immediateInstall = installHandler
            phase = .readyToRelaunch(info)
            announceReady(info)
        }
        return true
    }
}

/// App-wide updater. A single Sparkle updater must own update scheduling, so
/// the menu, About view, Settings, and the sidebar pill all share this one
/// instance.
enum SparkleUpdater {
    @MainActor static let shared = UpdaterViewModel()
}

/// The "Check for Updates…" menu command, greyed out while a check or an
/// update session is in flight.
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
#endif
