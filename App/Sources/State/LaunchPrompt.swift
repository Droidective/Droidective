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
        starPromptShown: Bool,
        launchCount: Int,
        starAfterLaunches: Int
    ) -> LaunchPrompt? {
        if !hasChosenRole && !hasSeenTour { return .rolePicker }
        if !hasSeenTour { return .tour }
        if starDue(starPromptShown: starPromptShown, launchCount: launchCount, afterLaunches: starAfterLaunches) {
            return .star
        }
        return nil
    }

    /// Whether the one-time GitHub-star nudge is due.
    static func starDue(starPromptShown: Bool, launchCount: Int, afterLaunches: Int) -> Bool {
        !starPromptShown && launchCount >= afterLaunches
    }
}
