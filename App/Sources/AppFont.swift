import AppKit
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

/// Installed font families, enumerated once and cached — `preload()` runs at
/// launch so the Settings picker opens instantly instead of walking the font
/// registry on first click.
@MainActor
enum FontCatalog {
    /// Fonts that ship with macOS, shortlisted at the top of the picker.
    private static let curated: [String] = [
        "Avenir", "Avenir Next", "Charter", "Futura", "Georgia", "Gill Sans",
        "Helvetica Neue", "Menlo", "Monaco", "Optima", "Palatino", "Seravek",
        "SF Mono", "Times New Roman", "Verdana",
    ]

    /// Every installed family (hidden system fonts excluded), sorted.
    static let families: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    /// The curated shortlist, limited to families actually installed.
    static let standardFamilies: [String] = {
        let installed = Set(families)
        return curated.filter { installed.contains($0) }
    }()

    static let otherFamilies: [String] = {
        let standard = Set(standardFamilies)
        return families.filter { !standard.contains($0) }
    }()

    /// Touch the cached lists so the enumeration cost is paid at launch.
    static func preload() {
        _ = standardFamilies
        _ = otherFamilies
    }
}
