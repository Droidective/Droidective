import Testing

/// `FontCatalog.derive` turns Core Text's raw family names into the three lists
/// Settings ▸ Appearance renders. It moved off the main actor to stop the font
/// walk from stalling launch (DROIDECTIVE-MAC-55), so the filter, collation, and
/// curated split are pinned here rather than eyeballed in the picker.
@Suite struct FontCatalogTests {

    /// Core Text reports hidden system families with a leading dot
    /// (".AppleSystemUIFont"). They must never reach the picker.
    @Test func hiddenSystemFamiliesAreDropped() {
        let lists = FontCatalog.derive(from: [
            ".AppleSystemUIFont", ".LastResort", "Georgia", "Verdana",
        ])
        #expect(lists.families == ["Georgia", "Verdana"])
        #expect(!lists.families.contains { $0.hasPrefix(".") })
        #expect(!lists.other.contains { $0.hasPrefix(".") })
    }

    /// The picker lists families the way a reader scans them, so collation is
    /// case-insensitive. The input matters: a lowercase name must sort *before*
    /// an uppercase one that follows it alphabetically, which is where an ASCII
    /// sort diverges (it puts every capital ahead of every lowercase letter).
    @Test func familiesCollateCaseInsensitively() {
        let lists = FontCatalog.derive(from: ["Zapfino", "arial", "Baskerville"])
        #expect(lists.families == ["arial", "Baskerville", "Zapfino"])
    }

    /// The shortlist keeps its curated order (a hand-picked reading order), not
    /// the alphabetical order the full list uses.
    @Test func curatedShortlistKeepsItsOwnOrderNotAlphabetical() {
        let lists = FontCatalog.derive(from: ["Verdana", "Avenir", "Menlo", "Georgia"])
        #expect(lists.standard == ["Avenir", "Georgia", "Menlo", "Verdana"])
        #expect(lists.families == ["Avenir", "Georgia", "Menlo", "Verdana"])
    }

    /// A curated font the user hasn't got installed must not be offered.
    @Test func curatedFamiliesThatAreNotInstalledAreOmitted() {
        let lists = FontCatalog.derive(from: ["Georgia"])
        #expect(lists.standard == ["Georgia"])
        #expect(!lists.standard.contains("Seravek"))
        #expect(!lists.standard.contains("SF Mono"))
    }

    /// `standard` and `other` partition `families` — every installed family is
    /// offered exactly once, so nothing silently disappears from the picker.
    @Test func standardAndOtherPartitionEveryFamily() {
        let raw = [".Hidden", "Georgia", "Menlo", "Comic Sans MS", "Wingdings", "Avenir"]
        let lists = FontCatalog.derive(from: raw)
        #expect(Set(lists.standard).isDisjoint(with: Set(lists.other)))
        #expect(Set(lists.standard).union(lists.other) == Set(lists.families))
        #expect(lists.standard.count + lists.other.count == lists.families.count)
        #expect(lists.other == ["Comic Sans MS", "Wingdings"])
    }

    /// A machine that reports nothing (or a Core Text cast that fails) yields
    /// empty lists rather than tripping on an unwrap.
    @Test func emptyInputYieldsEmptyLists() {
        #expect(FontCatalog.derive(from: []) == FontCatalog.Lists())
    }

    /// Duplicate family names from Core Text must not duplicate picker rows in
    /// the shortlist.
    @Test func duplicateCuratedNamesAppearOnceInTheShortlist() {
        let lists = FontCatalog.derive(from: ["Georgia", "Georgia", "Menlo"])
        #expect(lists.standard == ["Georgia", "Menlo"])
    }
}
