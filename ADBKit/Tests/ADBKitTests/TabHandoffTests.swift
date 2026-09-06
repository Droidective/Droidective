import Foundation
import Testing
@testable import ADBKit

/// Moving a tab out of its window: what leaves, and what travels with it.
@Suite struct TabHandoffTests {
    private let sourceID = WorkspaceID("source")
    private let newID = WorkspaceID("destination")

    private func source(
        serial: String? = "PIXEL8",
        bundleId: String? = "com.example.app"
    ) -> WindowState {
        WindowState(
            id: sourceID,
            serial: serial,
            bundleId: bundleId,
            tabGroups: [TabGroupState(tabs: ["home", "logcat", "terminal"], activeTab: "logcat")],
            focusedGroup: 0,
            terminalResumeDirs: ["/Users/dev/project", "/tmp"],
            mirrorWallSerials: ["PIXEL8", "GALAXY"]
        )
    }

    // MARK: - Inherited context

    @Test func seedInheritsTheSourcesDeviceAndBundle() {
        let seed = TabHandoff.seed(featureID: "logcat", from: source(), newID: newID)
        #expect(seed.serial == "PIXEL8")
        #expect(seed.bundleId == "com.example.app")
    }

    @Test func seedUsesTheNewWorkspaceIDNotTheSources() {
        let seed = TabHandoff.seed(featureID: "logcat", from: source(), newID: newID)
        #expect(seed.id == newID)
    }

    @Test func seedWithoutASourceDeviceCarriesNoDevice() {
        let seed = TabHandoff.seed(
            featureID: "logcat", from: source(serial: nil, bundleId: nil), newID: newID)
        #expect(seed.serial == nil)
        #expect(seed.bundleId == nil)
    }

    // MARK: - Exactly one tab

    @Test func seedOpensOnlyTheMovedTab() {
        let seed = TabHandoff.seed(featureID: "logcat", from: source(), newID: newID)
        #expect(seed.tabGroups == [TabGroupState(tabs: ["logcat"], activeTab: "logcat")])
        #expect(seed.focusedGroup == 0)
    }

    @Test func seedDoesNotCarryTheSourcesOtherTabs() {
        let seed = TabHandoff.seed(featureID: "logcat", from: source(), newID: newID)
        let tabs = seed.tabGroups?.flatMap(\.tabs) ?? []
        #expect(!tabs.contains("home"))
        #expect(!tabs.contains("terminal"))
    }

    // MARK: - Carried state is filtered to the feature that owns it

    @Test func terminalCarriesItsWorkingDirectories() {
        let carry = TabHandoff.Carry(terminalResumeDirs: ["/Users/dev/project"])
        let seed = TabHandoff.seed(
            featureID: "terminal", from: source(), newID: newID, carrying: carry)
        #expect(seed.terminalResumeDirs == ["/Users/dev/project"])
        #expect(seed.mirrorWallSerials == nil)
    }

    @Test func mirrorWallCarriesItsDevices() {
        let carry = TabHandoff.Carry(mirrorWallSerials: ["A", "B"])
        let seed = TabHandoff.seed(
            featureID: "mirror-wall", from: source(), newID: newID, carrying: carry)
        #expect(seed.mirrorWallSerials == ["A", "B"])
        #expect(seed.terminalResumeDirs == nil)
    }

    /// The whole point of filtering: a torn-off Logcat must not resurrect the
    /// source's terminal directories in a window with no Terminal tab, nor its
    /// wall devices in a window with no wall.
    @Test func anyOtherFeatureCarriesNeither() {
        let carry = TabHandoff.Carry(
            terminalResumeDirs: ["/tmp"], mirrorWallSerials: ["A"])
        let seed = TabHandoff.seed(
            featureID: "logcat", from: source(), newID: newID, carrying: carry)
        #expect(seed.terminalResumeDirs == nil)
        #expect(seed.mirrorWallSerials == nil)
    }

    /// The source's own persisted values are never read for the carry — they
    /// describe the *source's* live state, and by the time a handoff happens
    /// the terminal has been re-snapshotted. Passing no carry means none.
    @Test func withoutACarryNothingTravelsEvenIfTheSourceHasIt() {
        let seed = TabHandoff.seed(featureID: "terminal", from: source(), newID: newID)
        #expect(seed.terminalResumeDirs == nil)
        let wall = TabHandoff.seed(featureID: "mirror-wall", from: source(), newID: newID)
        #expect(wall.mirrorWallSerials == nil)
    }

    // MARK: - Round trip

    /// The seed is a `WindowState` precisely so the receiving window restores
    /// through the same path a relaunch uses — so it has to survive the store's
    /// encoding unchanged.
    @Test func seedRoundTripsThroughJSON() throws {
        let carry = TabHandoff.Carry(terminalResumeDirs: ["/Users/dev"])
        let seed = TabHandoff.seed(
            featureID: "terminal", from: source(), newID: newID, carrying: carry)
        let data = try JSONEncoder().encode(seed)
        let decoded = try JSONDecoder().decode(WindowState.self, from: data)
        #expect(decoded == seed)
    }

    @Test func aTornOffWindowRoundTripsThroughTheLayout() throws {
        var layout = LayoutState()
        let seed = TabHandoff.seed(featureID: "logcat", from: source(), newID: newID)
        layout.upsertWindow(seed)
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        #expect(decoded.windows?.contains(seed) == true)
    }
}
