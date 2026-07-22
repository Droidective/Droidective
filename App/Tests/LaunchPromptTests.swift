import Testing

/// The launch-prompt decision tree (role → tour → star) is the kind of
/// multi-flag onboarding logic the audit flagged as bug-prone and untested.
@Suite struct LaunchPromptTests {
    /// Defaults represent a fully-onboarded user (nothing due); each test flips
    /// only the inputs it cares about. Thresholds mirror RootView's.
    private func next(
        hasChosenRole: Bool = true, hasSeenTour: Bool = true,
        starResolved: Bool = true,
        launchCount: Int = 0, askCount: Int = 0,
        nextLaunch: Int = 10, maxAsks: Int = 5
    ) -> LaunchPrompt? {
        LaunchPrompt.next(
            hasChosenRole: hasChosenRole, hasSeenTour: hasSeenTour,
            starResolved: starResolved, launchCount: launchCount,
            askCount: askCount, nextLaunch: nextLaunch, maxAsks: maxAsks)
    }

    @Test func brandNewUserGetsRolePicker() {
        #expect(next(hasChosenRole: false, hasSeenTour: false) == .rolePicker)
    }

    /// The role picker wins even when the star nudge is simultaneously due.
    @Test func rolePickerTakesPriorityOverDueStar() {
        #expect(
            next(hasChosenRole: false, hasSeenTour: false, starResolved: false, launchCount: 100)
                == .rolePicker)
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

    /// A recorded ask pushes `nextLaunch` out, so the nudge waits until the
    /// next milestone instead of reappearing every launch.
    @Test func starReschedulesAfterAnAsk() {
        #expect(next(starResolved: false, launchCount: 15, askCount: 1, nextLaunch: 20) == nil)
        #expect(next(starResolved: false, launchCount: 20, askCount: 1, nextLaunch: 20) == .star)
    }

    /// The ask cap stops the nudge for good even if the launch milestone is met.
    @Test func starStopsAfterMaxAsks() {
        #expect(next(starResolved: false, launchCount: 100, askCount: 5, nextLaunch: 60, maxAsks: 5) == nil)
    }

    /// The last allowed ask (one below the cap) still shows.
    @Test func starShownOnFinalAllowedAsk() {
        #expect(next(starResolved: false, launchCount: 100, askCount: 4, nextLaunch: 60, maxAsks: 5) == .star)
    }

    /// Starring resolves it permanently.
    @Test func starNotShownOnceResolved() {
        #expect(next(starResolved: true, launchCount: 100, askCount: 0, nextLaunch: 10) == nil)
    }

    /// The re-ask milestone anchors to the *current* launch, not the old
    /// milestone, so a re-engaged user with an ancient `nextLaunch` waits a
    /// full gap instead of burning through every stale milestone.
    @Test func nextAskAnchorsToCurrentLaunch() {
        #expect(LaunchPrompt.nextAskLaunch(launchCount: 200, reAskGap: 10) == 210)
    }

    /// The full cadence composed, as RootView records it at presentation:
    /// first ask at launch 10, one every 10 launches, exactly 5 asks, then
    /// it stops for good.
    @Test func nudgeAsksExactlyMaxAsksTimesThenStops() {
        var askCount = 0
        var nextLaunch = 10
        var asks: [Int] = []
        for launch in 1...100 where next(
            starResolved: false, launchCount: launch,
            askCount: askCount, nextLaunch: nextLaunch) == .star {
            asks.append(launch)
            askCount += 1
            nextLaunch = LaunchPrompt.nextAskLaunch(launchCount: launch, reAskGap: 10)
        }
        #expect(asks == [10, 20, 30, 40, 50])
    }

    @Test func fullyOnboardedUserSeesNothing() {
        #expect(next(launchCount: 100) == nil)
    }
}
