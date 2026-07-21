import Foundation

/// Which first-run prompt (if any) to show on launch, in priority order.
///
/// Pure logic so the onboarding decision tree — role picker → tour →
/// GitHub-star nudge — is unit-tested rather than only exercised by hand.
/// `RootView` reads the flags and drives the UI; this just decides which prompt
/// is due. (Telemetry is on by default with opt-out in Settings ▸ Privacy, so
/// there is no first-run consent prompt.)
enum LaunchPrompt: Equatable {
    /// Brand-new user picks a role; its dismissal chains into the tour.
    case rolePicker
    case tour
    case star

    /// The highest-priority prompt due for the given persisted state, or nil.
    static func next(
        hasChosenRole: Bool,
        hasSeenTour: Bool,
        starResolved: Bool,
        launchCount: Int,
        snoozeCount: Int,
        nextLaunch: Int,
        maxAsks: Int
    ) -> LaunchPrompt? {
        if !hasChosenRole && !hasSeenTour { return .rolePicker }
        if !hasSeenTour { return .tour }
        if starDue(
            resolved: starResolved, launchCount: launchCount,
            snoozeCount: snoozeCount, nextLaunch: nextLaunch, maxAsks: maxAsks
        ) {
            return .star
        }
        return nil
    }

    /// Whether the recurring GitHub-star nudge is due. It stops for good once
    /// the user stars (`resolved`) and only re-appears every `nextLaunch`
    /// milestone up to `maxAsks` times — each "Maybe Later" pushes `nextLaunch`
    /// out and bumps `snoozeCount`.
    static func starDue(
        resolved: Bool, launchCount: Int, snoozeCount: Int, nextLaunch: Int, maxAsks: Int
    ) -> Bool {
        !resolved && snoozeCount < maxAsks && launchCount >= nextLaunch
    }
}
