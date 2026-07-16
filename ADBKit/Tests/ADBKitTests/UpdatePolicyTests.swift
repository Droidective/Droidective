import Foundation
import Testing
@testable import ADBKit

@Suite struct UpdatePolicyTests {
    // MARK: replyForUpdateFound

    @Test func backgroundFindRecordsInsteadOfDownloading() {
        // Auto-download off: the hourly check must not pull bytes, only
        // surface the pill + notification.
        #expect(
            UpdatePolicy.replyForUpdateFound(
                stage: .notDownloaded, userInitiated: false, userRequestedInstall: false,
                autoDownloadEnabled: false, informational: false)
                == .recordAvailable)
    }

    @Test func backgroundFindWithAutoDownloadStaysRecorded() {
        // Auto-download on but the update still reached the visible flow —
        // Sparkle refused to auto-install it (major upgrade / failed
        // signing). Never install those silently.
        #expect(
            UpdatePolicy.replyForUpdateFound(
                stage: .notDownloaded, userInitiated: false, userRequestedInstall: false,
                autoDownloadEnabled: true, informational: false)
                == .recordAvailable)
    }

    @Test func explicitUpdateNowInstallsRegardlessOfToggle() {
        for autoDownload in [true, false] {
            for stage in [UpdatePolicy.Stage.notDownloaded, .downloaded] {
                #expect(
                    UpdatePolicy.replyForUpdateFound(
                        stage: stage, userInitiated: true, userRequestedInstall: true,
                        autoDownloadEnabled: autoDownload, informational: false)
                        == .startInstall)
            }
        }
    }

    @Test func explicitInstallConsentOutranksHowTheCheckStarted() {
        // "Update now" re-enters through a check Sparkle may report as
        // non-user-initiated — the recorded consent still means install.
        #expect(
            UpdatePolicy.replyForUpdateFound(
                stage: .notDownloaded, userInitiated: false, userRequestedInstall: true,
                autoDownloadEnabled: false, informational: false)
                == .startInstall)
    }

    @Test func plainManualCheckDownloadsOnlyWhenAutoDownloadIsOn() {
        // With auto-download on, a manual check pulls the update right away
        // (the scheduler would have anyway)…
        #expect(
            UpdatePolicy.replyForUpdateFound(
                stage: .notDownloaded, userInitiated: true, userRequestedInstall: false,
                autoDownloadEnabled: true, informational: false)
                == .startInstall)
        // …with it off, checking is not consenting to a download — announce
        // and wait for an explicit Update.
        #expect(
            UpdatePolicy.replyForUpdateFound(
                stage: .notDownloaded, userInitiated: true, userRequestedInstall: false,
                autoDownloadEnabled: false, informational: false)
                == .recordAvailable)
    }

    @Test func stagedUpdateHoldsForTheRelaunchPill() {
        // Already installing-on-quit: every path should end at "Relaunch to
        // update", never re-download.
        for userInitiated in [true, false] {
            #expect(
                UpdatePolicy.replyForUpdateFound(
                    stage: .installing, userInitiated: userInitiated,
                    userRequestedInstall: userInitiated, autoDownloadEnabled: true,
                    informational: false)
                    == .holdForRelaunch)
        }
    }

    @Test func informationalUpdatesAreNeverInstalled() {
        // Info-only items (a pulled release's fallback) may only be linked
        // to, even when the user explicitly asked to update — and even one
        // Sparkle reports as already staged must not hold for a relaunch.
        for userInitiated in [true, false] {
            #expect(
                UpdatePolicy.replyForUpdateFound(
                    stage: .notDownloaded, userInitiated: userInitiated,
                    userRequestedInstall: userInitiated, autoDownloadEnabled: true,
                    informational: true)
                    == .recordAvailable)
        }
        #expect(
            UpdatePolicy.replyForUpdateFound(
                stage: .installing, userInitiated: false, userRequestedInstall: false,
                autoDownloadEnabled: true, informational: true)
                == .recordAvailable)
    }

    @Test func earlierDownloadChangesNothingWithoutConsent() {
        // A resumed .downloaded item follows the same rules as a fresh find.
        #expect(
            UpdatePolicy.replyForUpdateFound(
                stage: .downloaded, userInitiated: false, userRequestedInstall: false,
                autoDownloadEnabled: false, informational: false)
                == .recordAvailable)
        #expect(
            UpdatePolicy.replyForUpdateFound(
                stage: .downloaded, userInitiated: true, userRequestedInstall: false,
                autoDownloadEnabled: true, informational: false)
                == .startInstall)
    }

    // MARK: ready-to-relaunch

    @Test func explicitUpdateNowRelaunchesStraightThrough() {
        #expect(UpdatePolicy.relaunchImmediately(userRequestedInstall: true))
    }

    @Test func plainCheckStagesAndWaitsForThePill() {
        #expect(!UpdatePolicy.relaunchImmediately(userRequestedInstall: false))
    }

    // MARK: whatsNewAction

    @Test func nothingStashedMeansNothingToDo() {
        #expect(UpdatePolicy.whatsNewAction(stashedVersion: nil, currentVersion: "3.4.0") == nil)
    }

    @Test func firstLaunchOfTheStashedVersionShows() {
        #expect(
            UpdatePolicy.whatsNewAction(stashedVersion: "3.4.0", currentVersion: "3.4.0") == .show)
    }

    @Test func stashKeptWhileInstallStillPending() {
        // Stashed at staging time, app not relaunched yet: current build is
        // older than the stash — keep it for the launch that lands in 3.4.0.
        #expect(
            UpdatePolicy.whatsNewAction(stashedVersion: "3.4.0", currentVersion: "3.3.1") == .keep)
    }

    @Test func staleStashClearedWhenOvertaken() {
        // User skipped ahead (manual download of 3.5.0) — 3.4.0's notes are
        // stale, drop them silently.
        #expect(
            UpdatePolicy.whatsNewAction(stashedVersion: "3.4.0", currentVersion: "3.5.0") == .clear)
    }

    @Test func versionComparisonIsNumericNotLexicographic() {
        // "3.10.0" > "3.9.0" — a lexicographic compare would invert this.
        #expect(
            UpdatePolicy.whatsNewAction(stashedVersion: "3.9.0", currentVersion: "3.10.0") == .clear)
        #expect(
            UpdatePolicy.whatsNewAction(stashedVersion: "3.10.0", currentVersion: "3.9.0") == .keep)
    }

    @Test func comparesPlainBuildNumbersTheProductionCallerFeedsIt() {
        // The app keys the stash by CFBundleVersion — a bare integer, not a
        // dotted version. "99" < "100" is the row a lexicographic compare
        // would invert.
        #expect(UpdatePolicy.whatsNewAction(stashedVersion: "456", currentVersion: "456") == .show)
        #expect(UpdatePolicy.whatsNewAction(stashedVersion: "456", currentVersion: "455") == .keep)
        #expect(UpdatePolicy.whatsNewAction(stashedVersion: "455", currentVersion: "456") == .clear)
        #expect(UpdatePolicy.whatsNewAction(stashedVersion: "100", currentVersion: "99") == .keep)
    }

    // MARK: shouldNotify

    @Test func notifiesOncePerVersion() {
        #expect(UpdatePolicy.shouldNotify(version: "3.4.0", lastNotified: nil))
        #expect(UpdatePolicy.shouldNotify(version: "3.4.0", lastNotified: "3.3.0"))
        #expect(!UpdatePolicy.shouldNotify(version: "3.4.0", lastNotified: "3.4.0"))
    }

    @Test func manualCheckAlwaysNotifiesEvenAboutAKnownVersion() {
        // "Check for Updates…" is answering the user — the once-per-version
        // gate applies only to the hourly background re-check.
        #expect(
            UpdatePolicy.shouldNotify(version: "3.4.0", lastNotified: "3.4.0", manualCheck: true))
        #expect(
            !UpdatePolicy.shouldNotify(version: "3.4.0", lastNotified: "3.4.0", manualCheck: false))
    }

    // MARK: legacy migration

    @Test func oldCheckOptOutBecomesADownloadOptOut() {
        // A user who had turned off "check automatically" must not wake up
        // to silent installs — the old opt-out maps to the download toggle.
        #expect(UpdatePolicy.migratedAutoDownload(oldAutomaticChecks: false) == false)
    }

    @Test func defaultAndOptedInUsersKeepTheNewDefault() {
        #expect(UpdatePolicy.migratedAutoDownload(oldAutomaticChecks: nil) == nil)
        #expect(UpdatePolicy.migratedAutoDownload(oldAutomaticChecks: true) == nil)
    }
}
