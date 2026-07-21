import Testing

/// The launch-prompt decision tree (role → tour → star) is the kind of
/// multi-flag onboarding logic the audit flagged as bug-prone and untested.
@Suite struct LaunchPromptTests {
    /// Defaults represent a fully-onboarded user (nothing due); each test flips
    /// only the inputs it cares about. Thresholds mirror RootView's.
    private func next(
        hasChosenRole: Bool = true, hasSeenTour: Bool = true,
        starResolved: Bool = true,
        launchCount: Int = 0, snoozeCount: Int = 0,
        nextLaunch: Int = 10, maxAsks: Int = 5
    ) -> LaunchPrompt? {
        LaunchPrompt.next(
            hasChosenRole: hasChosenRole, hasSeenTour: hasSeenTour,
            starResolved: starResolved, launchCount: launchCount,
            snoozeCount: snoozeCount, nextLaunch: nextLaunch, maxAsks: maxAsks)
    }

    @Test func brandNewUserGetsRolePicker() {
        #expect(next(hasChosenRole: false, hasSeenTour: false) == .rolePicker)
    }

    @Test func roleChosenButTourUnseenGetsTour() {
        #expect(next(hasChosenRole: true, hasSeenTour: false) == .tour)
    }

    @Test func tourTakesPriorityOverDueStar() {
        #expect(next(hasSeenTour: false, starResolved: false, launchCount: 50) == .tour)
    }

    @Test func starNudgeShownOnlyAtItsThreshold() {
        #expect(next(starResolved: false, launchCount: 9) == nil)
        #expect(next(starResolved: false, launchCount: 10) == .star)
    }

    /// A "Maybe Later" tap pushes `nextLaunch` out, so the nudge waits until the
    /// next milestone instead of reappearing every launch.
    @Test func starReschedulesAfterSnooze() {
        #expect(next(starResolved: false, launchCount: 15, snoozeCount: 1, nextLaunch: 20) == nil)
        #expect(next(starResolved: false, launchCount: 20, snoozeCount: 1, nextLaunch: 20) == .star)
    }

    /// The ask cap stops the nudge for good even if the launch milestone is met.
    @Test func starStopsAfterMaxAsks() {
        #expect(next(starResolved: false, launchCount: 100, snoozeCount: 5, nextLaunch: 60, maxAsks: 5) == nil)
    }

    /// Starring resolves it permanently.
    @Test func starNotShownOnceResolved() {
        #expect(next(starResolved: true, launchCount: 100, snoozeCount: 0, nextLaunch: 10) == nil)
    }

    @Test func fullyOnboardedUserSeesNothing() {
        #expect(next(launchCount: 100) == nil)
    }
}
