import Foundation
import Testing

@testable import ADBKit

/// The census answers "what was the app doing", which the feature name on an
/// incident could not — every tab stays mounted, so the active feature is
/// whatever the user was looking at rather than whatever was working.
@Suite struct WorkloadCensusTests {
    @Test func anIdleAppSaysSoRatherThanRenderingAnEmptyList() {
        #expect(WorkloadCensus().summary == "idle")
    }

    @Test func theSummaryNamesOnlyWhatIsActuallyRunning() {
        let subject = WorkloadCensus(
            mirrorSessions: 3, shells: 5, devices: 4, windows: 2, tabs: 14)
        #expect(subject.summary == "3 mirrors, 5 shells, 14 tabs, 2 windows")
    }

    /// A single window is the ordinary case and says nothing; two is the fact
    /// that doubles every mounted tab.
    @Test func oneWindowIsNotWorthSaying() {
        let single = WorkloadCensus(windows: 1, tabs: 5)
        #expect(single.summary == "5 tabs")
        let pair = WorkloadCensus(windows: 2, tabs: 5)
        #expect(pair.summary == "5 tabs, 2 windows")
    }

    @Test func singularAndPluralBothRead() {
        #expect(WorkloadCensus(mirrorSessions: 1).summary == "1 mirror")
        #expect(WorkloadCensus(mirrorSessions: 2).summary == "2 mirrors")
        #expect(WorkloadCensus(shells: 1).summary == "1 shell")
    }

    /// Zeroes are sent. "No mirror was running" rules a cause out, and an
    /// absent key is indistinguishable from an older build that never sent it.
    @Test func propertiesKeepTheirZeroes() {
        let properties = WorkloadCensus(tabs: 3).properties
        #expect(properties["work_tabs"] == 3)
        #expect(properties["work_mirrors"] == 0)
        #expect(properties["work_shells"] == 0)
        #expect(properties.count == 6, "every field ships every time")
    }

    @Test func everyFieldReachesItsOwnKey() {
        let subject = WorkloadCensus(
            mirrorSessions: 1, shells: 3, devices: 4,
            windows: 5, tabs: 6, sessionSeconds: 8)
        #expect(subject.properties == [
            "work_mirrors": 1,
            "work_shells": 3,
            "work_devices": 4,
            "work_windows": 5,
            "work_tabs": 6,
            "work_session_seconds": 8,
        ])
    }
}
