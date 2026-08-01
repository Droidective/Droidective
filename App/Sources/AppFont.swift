import AppKit
import CoreText
import SwiftUI

/// UserDefaults key for the app-wide font family (Settings ▸ Appearance).
/// Empty or unset → the system font (San Francisco).
let appFontFamilyDefaultsKey = "appFontFamily"
/// UserDefaults key for the text-size multiplier applied to every `Font.app`
/// token (0 or unset → 1.0). Independent of the ⌘=/⌘- window zoom, which
/// scales the whole layout.
let appFontSizeScaleDefaultsKey = "appFontSizeScale"

/// The user's font preference, resolved fresh per call like `Color.brandAccent`
/// — the scene roots re-key on the stored values so a change rebuilds every
/// view with the new fonts.
enum AppFontPrefs {
    static var family: String? {
        guard let stored = UserDefaults.standard.string(forKey: appFontFamilyDefaultsKey),
              !stored.isEmpty else { return nil }
        return stored
    }

    static var sizeScale: Double {
        let stored = UserDefaults.standard.double(forKey: appFontSizeScaleDefaultsKey)
        return stored > 0 ? stored : 1.0
    }

    /// macOS default point sizes per text style, so a custom family keeps the
    /// familiar hierarchy. `default` covers styles this app never uses (and
    /// future ones) at body size.
    static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline: 13
        case .subheadline: 11
        case .body: 13
        case .callout: 12
        case .footnote: 10
        case .caption: 10
        case .caption2: 10
        default: 13
        }
    }

    /// Headline is the one semantic style with an intrinsic weight.
    static func weight(for style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }
}

/// App-wide font tokens. Every `.font(...)` in the app routes through these so
/// Settings ▸ Appearance can swap the family and scale the size in one place.
extension Font {
    /// Semantic token — `.font(.app(.headline))` instead of `.font(.headline)`.
    static func app(_ style: Font.TextStyle) -> Font {
        let size = AppFontPrefs.pointSize(for: style) * AppFontPrefs.sizeScale
        guard let family = AppFontPrefs.family else {
            return .system(size: size, weight: AppFontPrefs.weight(for: style))
        }
        return .custom(family, size: size, relativeTo: style).weight(AppFontPrefs.weight(for: style))
    }

    /// Semantic token with an explicit design (`.monospaced` call sites). The
    /// design is kept — a family override would break column alignment — but
    /// the size still honors the user's text-size scale.
    static func app(_ style: Font.TextStyle, design: Font.Design) -> Font {
        .system(
            size: AppFontPrefs.pointSize(for: style) * AppFontPrefs.sizeScale,
            weight: AppFontPrefs.weight(for: style),
            design: design
        )
    }

    /// Sized token — `.font(.app(size: 11))` instead of `.font(.system(size: 11))`.
    /// A non-default design keeps the system font (monospaced tables, rounded
    /// badges) while still scaling.
    static func app(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let scaled = size * AppFontPrefs.sizeScale
        if design != .default {
            return .system(size: scaled, weight: weight, design: design)
        }
        guard let family = AppFontPrefs.family else {
            return .system(size: scaled, weight: weight)
        }
        return .custom(family, size: scaled).weight(weight)
    }
}

/// Installed font families, enumerated once and cached — `preload()` warms the
/// cache off the main actor at launch so the Settings picker opens instantly and
/// the font-registry walk never lands on the main thread.
@MainActor
enum FontCatalog {
    /// Fonts that ship with macOS, shortlisted at the top of the picker.
    /// `nonisolated` so the pure `derive` can read it off the main actor.
    private nonisolated static let curated: [String] = [
        "Avenir", "Avenir Next", "Charter", "Futura", "Georgia", "Gill Sans",
        "Helvetica Neue", "Menlo", "Monaco", "Optima", "Palatino", "Seravek",
        "SF Mono", "Times New Roman", "Verdana",
    ]

    /// The three picker lists, derived together from one enumeration.
    struct Lists: Sendable, Equatable {
        var families: [String] = []
        var standard: [String] = []
        var other: [String] = []
    }

    private static var cached: Lists?

    /// Cached lists, or an inline enumeration if something reads them before
    /// `preload()` finishes. That fallback is the pre-fix behavior kept as a
    /// backstop — correct, just slower — rather than a path worth relying on.
    private static var lists: Lists {
        if let cached { return cached }
        let built = derive(from: enumerateRawFamilies())
        cached = built
        return built
    }

    /// Every installed family (hidden system fonts excluded), sorted.
    static var families: [String] { lists.families }
    /// The curated shortlist, limited to families actually installed.
    static var standardFamilies: [String] { lists.standard }
    static var otherFamilies: [String] { lists.other }

    /// Warm the cache without ever touching the main thread.
    ///
    /// `CTFontManagerCopyAvailableFontFamilyNames` is documented thread-safe
    /// where `NSFontManager` is not (and measured ~7x faster besides), so the
    /// walk can move off the main actor. On a machine with a cold font registry
    /// the old main-thread enumeration blocked launch long enough to trip the
    /// 2 s hang detector (DROIDECTIVE-MAC-55).
    static func preload() async {
        guard cached == nil else { return }
        cached = await Task.detached { derive(from: enumerateRawFamilies()) }.value
    }

    /// Raw family names from Core Text. `nonisolated` so `preload` can run it
    /// off the main actor.
    private nonisolated static func enumerateRawFamilies() -> [String] {
        CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
    }

    /// Splits raw family names into the picker's three lists: hidden system
    /// families (dot-prefixed) dropped, the rest collated the way the picker
    /// lists them, and the curated shortlist narrowed to what is installed.
    /// Pure, so the filter, collation, and split are pinned by tests instead of
    /// eyeballed in the picker.
    nonisolated static func derive(from raw: [String]) -> Lists {
        let families = raw
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let installed = Set(families)
        let standard = curated.filter { installed.contains($0) }
        let standardSet = Set(standard)
        return Lists(
            families: families,
            standard: standard,
            other: families.filter { !standardSet.contains($0) }
        )
    }
}
