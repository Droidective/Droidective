import Testing
@testable import ADBKit

@Suite struct PanelTargetingTests {
    // MARK: - singleTarget

    @Test func singleTargetPrefersTheLivePickOverEverything() {
        let target = PanelTargeting.singleTarget(
            picked: "A", selected: "B", ready: ["A", "B", "C"]
        )
        #expect(target == "A")
    }

    @Test func singleTargetDropsAPickWhoseDeviceDisconnectedAndFallsToSelection() {
        // "A" was picked but is no longer ready — fall back to the selection.
        let target = PanelTargeting.singleTarget(
            picked: "A", selected: "B", ready: ["B", "C"]
        )
        #expect(target == "B")
    }

    @Test func singleTargetFallsToFirstReadyWhenNeitherPickNorSelectionIsReady() {
        let target = PanelTargeting.singleTarget(
            picked: "gone", selected: "also-gone", ready: ["C", "D"]
        )
        #expect(target == "C")
    }

    @Test func singleTargetUsesSelectionWhenThereIsNoPick() {
        let target = PanelTargeting.singleTarget(
            picked: nil, selected: "B", ready: ["A", "B"]
        )
        #expect(target == "B")
    }

    @Test func singleTargetIsNilWhenNothingIsReady() {
        #expect(PanelTargeting.singleTarget(picked: "A", selected: "B", ready: []) == nil)
    }

    // MARK: - approvedTargets

    @Test func approvedTargetsIsApprovedIntersectReadyInApprovedOrder() {
        let live = PanelTargeting.approvedTargets(
            approved: ["A", "B", "C"], ready: ["C", "A", "B"]
        )
        // Approved order, not ready order.
        #expect(live == ["A", "B", "C"])
    }

    @Test func approvedTargetsExcludesADeviceAttachedAfterTheApproval() {
        // "D" is ready now but wasn't in the approval — it must never join it.
        let live = PanelTargeting.approvedTargets(
            approved: ["A", "B"], ready: ["A", "B", "D"]
        )
        #expect(live == ["A", "B"])
    }

    @Test func approvedTargetsDropsDisconnectedApprovedDevices() {
        let live = PanelTargeting.approvedTargets(
            approved: ["A", "B", "C"], ready: ["A", "C"]
        )
        #expect(live == ["A", "C"])
    }

    @Test func approvedTargetsIsNilWhenNoApprovalExists() {
        #expect(PanelTargeting.approvedTargets(approved: nil, ready: ["A"]) == nil)
    }

    @Test func approvedTargetsIsNilWhenNothingApprovedIsStillReady() {
        #expect(PanelTargeting.approvedTargets(approved: ["A", "B"], ready: ["C"]) == nil)
    }

    // MARK: - fanOut

    @Test func fanOutReturnsEveryLiveApprovedDeviceWhenMoreThanOne() {
        let targets = PanelTargeting.fanOut(
            picked: nil, selected: "A", approved: ["A", "B", "C"], ready: ["A", "B", "C"]
        )
        #expect(targets == ["A", "B", "C"])
    }

    @Test func fanOutCollapsesToSingleWhenApprovalShrankToOneLiveDevice() {
        // Approved A+B, but B disconnected — one live approved device is not a
        // fan-out; fall to the single-target rule (the live pick here).
        let targets = PanelTargeting.fanOut(
            picked: "A", selected: "B", approved: ["A", "B"], ready: ["A"]
        )
        #expect(targets == ["A"])
    }

    @Test func fanOutIsSingleTargetWhenThereIsNoApproval() {
        let targets = PanelTargeting.fanOut(
            picked: "A", selected: "B", approved: nil, ready: ["A", "B"]
        )
        #expect(targets == ["A"])
    }

    @Test func fanOutIsEmptyWhenNothingIsReady() {
        let targets = PanelTargeting.fanOut(
            picked: "A", selected: "B", approved: ["A", "B"], ready: []
        )
        #expect(targets.isEmpty)
    }

    // MARK: - runTargets

    @Test func runTargetsIsNilForAFeatureThatNeedsNoDeviceEvenWithDevicesReady() {
        let targets = PanelTargeting.runTargets(
            needsDevice: false, picked: "A", selected: "B",
            approved: ["A", "B"], ready: ["A", "B"]
        )
        #expect(targets == nil)
    }

    @Test func runTargetsFansOutForADeviceFeature() {
        let targets = PanelTargeting.runTargets(
            needsDevice: true, picked: nil, selected: "A",
            approved: ["A", "B"], ready: ["A", "B"]
        )
        #expect(targets == ["A", "B"])
    }

    @Test func runTargetsIsASingleElementForADeviceFeatureWithNoApproval() {
        let targets = PanelTargeting.runTargets(
            needsDevice: true, picked: "B", selected: "A",
            approved: nil, ready: ["A", "B"]
        )
        #expect(targets == ["B"])
    }

    @Test func runTargetsIsEmptyForADeviceFeatureWithNothingReady() {
        let targets = PanelTargeting.runTargets(
            needsDevice: true, picked: "A", selected: "B",
            approved: nil, ready: []
        )
        #expect(targets == [])
    }
}
