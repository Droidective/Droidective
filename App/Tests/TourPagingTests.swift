import Testing

/// The tour crash class (DROIDECTIVE-MAC-2H): a Next that double-fired
/// between renders stepped past the last page and `pages[index]` trapped.
/// The steps must clamp at both ends no matter how many times they fire.
@Suite struct TourPagingTests {
    @Test func nextAdvancesWithinBounds() {
        #expect(TourPaging.next(from: 0, count: 6) == 1)
        #expect(TourPaging.next(from: 4, count: 6) == 5)
    }

    /// The crash repro: a second fire landing while already on the last page.
    @Test func nextClampsAtTheLastPage() {
        #expect(TourPaging.next(from: 5, count: 6) == 5)
        #expect(TourPaging.next(from: TourPaging.next(from: 4, count: 6), count: 6) == 5)
    }

    @Test func backRetreatsWithinBounds() {
        #expect(TourPaging.back(from: 5) == 4)
        #expect(TourPaging.back(from: 1) == 0)
    }

    /// The same race backward: a double Back from page 1 must not reach -1.
    @Test func backClampsAtTheFirstPage() {
        #expect(TourPaging.back(from: 0) == 0)
        #expect(TourPaging.back(from: TourPaging.back(from: 1)) == 0)
    }
}
