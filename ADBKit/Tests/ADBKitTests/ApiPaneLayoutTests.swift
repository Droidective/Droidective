import Foundation
import Testing

@testable import ADBKit

@Suite struct ApiPaneLayoutTests {

    @Test func aStoredSidebarWidthIsHonouredWhenThereIsRoom() {
        #expect(ApiPaneLayout.sidebarWidth(stored: 300, total: 1200) == 300)
    }

    @Test func theSidebarIsClampedToItsRange() {
        #expect(ApiPaneLayout.sidebarWidth(stored: 50, total: 1200) == 200)
        #expect(ApiPaneLayout.sidebarWidth(stored: 9000, total: 3000) == 460)
    }

    @Test func theSidebarNeverTakesMoreThanAThirdOfThePane() {
        #expect(ApiPaneLayout.sidebarWidth(stored: 460, total: 900) == 300)
    }

    @Test func aVeryNarrowPaneStillLeavesTheSidebarUsable() {
        // A third of 300pt is below the floor; the floor wins so the sidebar
        // stays operable rather than collapsing to a sliver.
        #expect(ApiPaneLayout.sidebarWidth(stored: 260, total: 300) == 200)
    }

    @Test func theSplitFractionIsClamped() {
        #expect(ApiPaneLayout.clampedFraction(0.5) == 0.5)
        #expect(ApiPaneLayout.clampedFraction(0.01) == 0.25)
        #expect(ApiPaneLayout.clampedFraction(0.99) == 0.75)
    }

    @Test func theLeadingPaneFollowsTheFraction() {
        #expect(ApiPaneLayout.leadingLength(total: 1000, fraction: 0.5) == 500)
        #expect(ApiPaneLayout.leadingLength(total: 1000, fraction: 0.3) == 300)
    }

    @Test func theAbsoluteFloorOverridesTheFractionOnATightPane() {
        // 25% of 800 is 200, below the 240pt floor.
        #expect(ApiPaneLayout.leadingLength(total: 800, fraction: 0.25) == 240)
        #expect(ApiPaneLayout.leadingLength(total: 800, fraction: 0.75) == 560)
    }

    @Test func bothPanesShrinkEvenlyWhenTheFloorCannotHold() {
        // Under 480pt the floor collapses to half so neither pane is pushed off.
        #expect(ApiPaneLayout.leadingLength(total: 400, fraction: 0.25) == 200)
        #expect(ApiPaneLayout.leadingLength(total: 400, fraction: 0.75) == 200)
    }

    @Test func aZeroWidthPaneDoesNotProduceNaN() {
        #expect(ApiPaneLayout.leadingLength(total: 0, fraction: 0.5) == 0)
        #expect(ApiPaneLayout.fraction(forLeading: 100, total: 0) == 0.5)
        #expect(ApiPaneLayout.pointRange(total: 0) == 0...0)
    }

    @Test func theDragRangeMatchesWhereTheLayoutActuallyStops() {
        let total = 800.0
        let range = ApiPaneLayout.pointRange(total: total)
        #expect(ApiPaneLayout.leadingLength(total: total, fraction: 0) == range.lowerBound)
        #expect(ApiPaneLayout.leadingLength(total: total, fraction: 1) == range.upperBound)
    }

    @Test func theDragRangeNeverInverts() {
        for total in stride(from: 0.0, through: 2000.0, by: 137.0) {
            let range = ApiPaneLayout.pointRange(total: total)
            #expect(range.lowerBound <= range.upperBound)
        }
    }

    @Test func pointsRoundTripBackToAFraction() {
        let total = 1000.0
        let points = ApiPaneLayout.leadingLength(total: total, fraction: 0.4)
        #expect(ApiPaneLayout.fraction(forLeading: points, total: total) == 0.4)
    }

    @Test func aDragBeyondTheEdgeStillStoresAValidFraction() {
        let fraction = ApiPaneLayout.fraction(forLeading: 5000, total: 1000)
        #expect(ApiPaneLayout.fractionRange.contains(fraction))
    }
}
