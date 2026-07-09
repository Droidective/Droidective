import SwiftUI
import Testing

/// `TailGeometry` decides when the v2 log feeds count as touching an edge —
/// which drives both the smart-tail (follow at the newest edge, pause away
/// from it) and the jump buttons' visibility. The tolerance and boundary
/// rules are pure, so they're pinned here rather than eyeballed in a stream.
@Suite struct TailGeometryTests {

    // MARK: Scrollability

    @Test func emptyGeometryIsNotScrollable() {
        let geo = TailGeometry()
        #expect(!geo.isScrollable)
        #expect(geo.atNewestEdge)
        #expect(geo.atOldestEdge)
    }

    @Test func contentShorterThanViewportIsNotScrollable() {
        let geo = TailGeometry(contentLeadingOffset: 0, contentHeight: 300, viewportHeight: 600)
        #expect(!geo.isScrollable)
    }

    @Test func contentTallerThanViewportIsScrollable() {
        let geo = TailGeometry(contentLeadingOffset: 0, contentHeight: 2000, viewportHeight: 600)
        #expect(geo.isScrollable)
        #expect(geo.scrollRange == 1400)
    }

    @Test func exactFitLeavesNoScrollRange() {
        let geo = TailGeometry(contentLeadingOffset: 0, contentHeight: 600, viewportHeight: 600)
        #expect(!geo.isScrollable)
        #expect(geo.scrollRange == 0)
    }

    // MARK: Newest edge (tail-follow) detection

    @Test func parkedAtOffsetZeroIsAtNewestEdge() {
        let geo = TailGeometry(contentLeadingOffset: 0, contentHeight: 2000, viewportHeight: 600)
        #expect(geo.atNewestEdge)
        #expect(!geo.atOldestEdge)
    }

    @Test func withinToleranceStillCountsAsNewestEdge() {
        let geo = TailGeometry(
            contentLeadingOffset: TailGeometry.edgeTolerance,
            contentHeight: 2000, viewportHeight: 600
        )
        #expect(geo.atNewestEdge)
    }

    @Test func pastToleranceLeavesTheNewestEdge() {
        let geo = TailGeometry(
            contentLeadingOffset: TailGeometry.edgeTolerance + 1,
            contentHeight: 2000, viewportHeight: 600
        )
        #expect(!geo.atNewestEdge)
        #expect(!geo.atOldestEdge)
    }

    /// The layout flip inverts the offset's sign; only magnitude matters.
    @Test func negativeOffsetsReadTheSameAsPositive() {
        let geo = TailGeometry(contentLeadingOffset: -500, contentHeight: 2000, viewportHeight: 600)
        #expect(geo.distanceFromNewest == 500)
        #expect(!geo.atNewestEdge)
    }

    // MARK: Oldest edge detection

    @Test func fullScrollRangeIsAtOldestEdge() {
        let geo = TailGeometry(contentLeadingOffset: -1400, contentHeight: 2000, viewportHeight: 600)
        #expect(geo.atOldestEdge)
        #expect(!geo.atNewestEdge)
    }

    @Test func withinToleranceOfScrollRangeCountsAsOldestEdge() {
        let geo = TailGeometry(
            contentLeadingOffset: -(1400 - TailGeometry.edgeTolerance),
            contentHeight: 2000, viewportHeight: 600
        )
        #expect(geo.atOldestEdge)
    }

    @Test func rubberBandOverscrollStillCountsAsOldestEdge() {
        let geo = TailGeometry(contentLeadingOffset: -1450, contentHeight: 2000, viewportHeight: 600)
        #expect(geo.atOldestEdge)
    }

    @Test func midScrollTouchesNeitherEdge() {
        let geo = TailGeometry(contentLeadingOffset: -700, contentHeight: 2000, viewportHeight: 600)
        #expect(!geo.atNewestEdge)
        #expect(!geo.atOldestEdge)
    }

    // MARK: Spatial mapping

    @Test func bottomFeedMapsNewestToBottom() {
        let parked = TailGeometry(contentLeadingOffset: 0, contentHeight: 2000, viewportHeight: 600)
        let edges = parked.edges(newestEdge: .bottom)
        #expect(edges.atBottom)
        #expect(!edges.atTop)
        #expect(edges.isScrollable)
    }

    @Test func bottomFeedMapsOldestToTop() {
        let scrolledAway = TailGeometry(
            contentLeadingOffset: -1400, contentHeight: 2000, viewportHeight: 600
        )
        let edges = scrolledAway.edges(newestEdge: .bottom)
        #expect(edges.atTop)
        #expect(!edges.atBottom)
    }

    @Test func topFeedMapsNewestToTop() {
        let parked = TailGeometry(contentLeadingOffset: 0, contentHeight: 2000, viewportHeight: 600)
        let edges = parked.edges(newestEdge: .top)
        #expect(edges.atTop)
        #expect(!edges.atBottom)
    }

    @Test func topFeedMapsOldestToBottom() {
        let scrolledAway = TailGeometry(
            contentLeadingOffset: 1400, contentHeight: 2000, viewportHeight: 600
        )
        let edges = scrolledAway.edges(newestEdge: .top)
        #expect(edges.atBottom)
        #expect(!edges.atTop)
    }

    @Test func unscrollableContentReportsBothEdges() {
        let geo = TailGeometry(contentLeadingOffset: 0, contentHeight: 300, viewportHeight: 600)
        let edges = geo.edges(newestEdge: .bottom)
        #expect(edges.atTop)
        #expect(edges.atBottom)
        #expect(!edges.isScrollable)
    }
}
