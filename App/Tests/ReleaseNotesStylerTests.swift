import Testing

/// The What's New sheet's injected CSS is plain string interpolation — exactly
/// where a silently-wrong color/size lives — so pin the composed output.
@Suite struct ReleaseNotesStylerTests {
    @Test func injectsResolvedColorsAndFontSize() {
        let out = ReleaseNotesStyler.styled(
            "<p>Hi</p>", textColor: "#ABCDEF", accent: "#123456", baseFontPx: 15.0)
        #expect(out.contains("color: #ABCDEF"))
        #expect(out.contains("border-left: 3px solid #123456"))
        #expect(out.contains("font-size: 15.0px"))
    }

    /// The notes come first, untouched, with a single appended style block —
    /// later rules win at equal specificity, which is the whole mechanism.
    @Test func preservesNotesAndAppendsOneStyleBlock() {
        let notes = "<h3>Fixes</h3><ul><li>One</li></ul>"
        let out = ReleaseNotesStyler.styled(
            notes, textColor: "#111111", accent: "#222222", baseFontPx: 13.0)
        #expect(out.hasPrefix(notes))
        #expect(out.components(separatedBy: "<style>").count == 2)
        #expect(out.components(separatedBy: "</style>").count == 2)
    }

    /// The accent reaches all three surfaces it unifies: section headers,
    /// list markers, and links.
    @Test func accentAppliesToHeadersMarkersAndLinks() {
        let out = ReleaseNotesStyler.styled(
            "x", textColor: "#111111", accent: "#ABC123", baseFontPx: 13.0)
        #expect(out.contains("h3 {\n    color: #ABC123"))
        #expect(out.contains("li::marker { color: #ABC123; }"))
        #expect(out.contains("a { color: #ABC123; }"))
    }

    /// The lead-in callout and the first-section exemption stay addressed at
    /// the selectors the shipped appcast notes actually use.
    @Test func leadAndSectionRulesPresent() {
        let out = ReleaseNotesStyler.styled(
            "x", textColor: "#111111", accent: "#222222", baseFontPx: 13.0)
        #expect(out.contains("body > p:first-of-type"))
        #expect(out.contains("h3:first-of-type { border-top: none;"))
    }
}
