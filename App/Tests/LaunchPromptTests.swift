import Testing

/// The launch-prompt decision tree (role → tour → star) is the kind of
/// multi-flag onboarding logic the audit flagged as bug-prone and untested.
@Suite struct LaunchPromptTests {
    /// Defaults represent a fully-onboarded user (nothing due); each test flips
    /// only the inputs it cares about. Thresholds mirror RootView's.
    private func next(
        hasChosenRole: Bool = true, hasSeenTour: Bool = true,
        starPromptShown: Bool = true,
        launchCount: Int = 0, starAfterLaunches: Int = 10
    ) -> LaunchPrompt? {
        LaunchPrompt.next(
            hasChosenRole: hasChosenRole, hasSeenTour: hasSeenTour,
            starPromptShown: starPromptShown,
            launchCount: launchCount, starAfterLaunches: starAfterLaunches)
    }

    @Test func brandNewUserGetsRolePicker() {
        #expect(next(hasChosenRole: false, hasSeenTour: false) == .rolePicker)
    }

    @Test func roleChosenButTourUnseenGetsTour() {
        #expect(next(hasChosenRole: true, hasSeenTour: false) == .tour)
    }

    @Test func tourTakesPriorityOverDueStar() {
        #expect(next(hasSeenTour: false, starPromptShown: false, launchCount: 50) == .tour)
    }

    @Test func starNudgeShownOnlyAtItsThreshold() {
        #expect(next(starPromptShown: false, launchCount: 9) == nil)
        #expect(next(starPromptShown: false, launchCount: 10) == .star)
    }

    @Test func fullyOnboardedUserSeesNothing() {
        #expect(next(launchCount: 100) == nil)
    }
}
