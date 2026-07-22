/// Composes the app-side style layer appended to the What's New sheet's
/// release notes — later rules win at equal specificity, so this restyles the
/// appcast's baseline without the release pipeline changing. Pure string
/// composition (the view resolves the theme colors/size) so the injected CSS
/// is pinned by AppTests.
enum ReleaseNotesStyler {
    /// `textColor`/`accent` are `#RRGGBB` hexes already resolved for the
    /// sheet's scheme; `baseFontPx` is the app's scaled body size.
    static func styled(
        _ notes: String, textColor: String, accent: String, baseFontPx: Double
    ) -> String {
        return notes + """
        <style>
        html, body { background: transparent; }
        body { padding: 16px 22px 24px; color: \(textColor); font-size: \(baseFontPx)px; line-height: 1.5; }
        /* Lead paragraph reads as a highlighted callout with an accent rail. */
        body > p:first-of-type {
            font-size: 1em;
            margin: 2px 0 1.5em;
            padding: 12px 14px;
            border: 1px solid color-mix(in srgb, currentColor 12%, transparent);
            border-left: 3px solid \(accent);
            border-radius: 10px;
            background: transparent;
        }
        h2, h3 { font-weight: 700; }
        /* Section headers: accent, with a divider above each. */
        h3 {
            color: \(accent);
            font-size: 1em;
            margin: 1.7em 0 .55em;
            padding-top: 1.5em;
            border-top: 1px solid color-mix(in srgb, currentColor 12%, transparent);
        }
        h3:first-of-type { border-top: none; padding-top: 0; margin-top: .2em; }
        li { margin: .38em 0; }
        li::marker { color: \(accent); }
        a { color: \(accent); }
        </style>
        """
    }
}
