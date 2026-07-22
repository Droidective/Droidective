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
        askCount: Int,
        nextLaunch: Int,
        maxAsks: Int
    ) -> LaunchPrompt? {
        if !hasChosenRole && !hasSeenTour { return .rolePicker }
        if !hasSeenTour { return .tour }
        if starDue(
            resolved: starResolved, launchCount: launchCount,
            askCount: askCount, nextLaunch: nextLaunch, maxAsks: maxAsks
        ) {
            return .star
        }
        return nil
    }

    /// Whether the recurring GitHub-star nudge is due. It stops for good once
    /// the user stars (`resolved`) or after `maxAsks` asks, and otherwise waits
    /// for the `nextLaunch` milestone. Each ask is recorded at *presentation*
    /// (bump `askCount`, push `nextLaunch` out via `nextAskLaunch`), so a quit
    /// with the sheet still open can't replay the ask every launch.
    static func starDue(
        resolved: Bool, launchCount: Int, askCount: Int, nextLaunch: Int, maxAsks: Int
    ) -> Bool {
        !resolved && askCount < maxAsks && launchCount >= nextLaunch
    }

    /// The milestone the next ask is due at, anchored to the *current* launch —
    /// not the old milestone — so a re-engaged user with an ancient `nextLaunch`
    /// waits a full gap instead of burning through every stale milestone.
    static func nextAskLaunch(launchCount: Int, reAskGap: Int) -> Int {
        launchCount + reAskGap
    }
}
