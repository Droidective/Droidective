import ADBKit
import SwiftUI

/// The JS Console's color palette, matched to Chrome DevTools' dark console.
///
/// These are *fixed* colors (not app theme tokens): the log feed is a
/// self-contained dark console like Chrome's, so error/warning bands, value
/// syntax colors, and text stay identical regardless of the app's light/dark
/// theme — the way people picture "the Chrome console". Only the feed area
/// adopts this; the surrounding bars stay on the app theme.
enum JSConsoleTheme {
    /// The console surface (Chrome dark `#282828`).
    static let background = Color(red: 0.157, green: 0.157, blue: 0.157)
    /// Default log text (Chrome `#d4d4d4`).
    static let text = Color(red: 0.831, green: 0.831, blue: 0.839)
    /// Timestamps, notices, muted glyphs (`#8c8c8c`).
    static let muted = Color(red: 0.549, green: 0.549, blue: 0.549)

    /// Error rows — light-red text on a dark-red band with a red left rule.
    static let errorText = Color(red: 1.0, green: 0.502, blue: 0.502)      // #ff8080
    static let errorBackground = Color(red: 0.204, green: 0.067, blue: 0.067) // #341111
    static let errorRule = Color(red: 0.643, green: 0.184, blue: 0.184)    // #a42f2f

    /// Warning rows — amber text on a dark-amber band with an amber left rule.
    static let warningText = Color(red: 0.949, green: 0.753, blue: 0.302)  // #f2c04d
    static let warningBackground = Color(red: 0.196, green: 0.184, blue: 0.059) // #322f0f
    static let warningRule = Color(red: 0.643, green: 0.518, blue: 0.129)  // #a48421

    /// Info accent (icon), otherwise info reads as normal text (Chrome `#79b8ff`).
    static let info = Color(red: 0.475, green: 0.722, blue: 1.0)

    /// ⌘F find highlights — warm yellow, stronger orange for the current match.
    static let findMatch = Color(red: 0.961, green: 0.773, blue: 0.094)    // #f5c518
    static let findCurrent = Color(red: 1.0, green: 0.549, blue: 0.102)    // #ff8c1a

    /// Value/token syntax colors, tuned to read on the dark console surface
    /// (VS Code Dark+ palette — the familiar dark-console value coloring).
    static func token(_ kind: JSTokenKind) -> Color {
        switch kind {
        case .string: Color(red: 0.808, green: 0.569, blue: 0.471)   // #ce9178
        case .number: Color(red: 0.475, green: 0.753, blue: 1.0)     // #79c0ff
        case .boolean: Color(red: 0.337, green: 0.612, blue: 0.839)  // #569cd6
        case .null, .undefined: muted
        case .function: Color(red: 0.863, green: 0.863, blue: 0.667) // #dcdcaa
        case .symbol: Color(red: 0.306, green: 0.788, blue: 0.690)   // #4ec9b0
        case .key: Color(red: 0.612, green: 0.863, blue: 0.996)      // #9cdcfe
        case .className: Color(red: 0.306, green: 0.788, blue: 0.690) // #4ec9b0
        case .punctuation: muted
        case .plain: text
        }
    }
}

extension JSLevel {
    /// Text color for this level's message on the dark console.
    var consoleTextColor: Color {
        switch self {
        case .error: JSConsoleTheme.errorText
        case .warning: JSConsoleTheme.warningText
        case .info: JSConsoleTheme.info
        case .log: JSConsoleTheme.text
        case .debug: JSConsoleTheme.muted
        }
    }

    /// The row background band + left rule Chrome draws for errors and warnings;
    /// nil for the levels that render on the plain console surface.
    var consoleBand: (fill: Color, rule: Color)? {
        switch self {
        case .error: (JSConsoleTheme.errorBackground, JSConsoleTheme.errorRule)
        case .warning: (JSConsoleTheme.warningBackground, JSConsoleTheme.warningRule)
        default: nil
        }
    }

    /// Glyph tint in the row gutter.
    var consoleIconColor: Color {
        switch self {
        case .error: JSConsoleTheme.errorText
        case .warning: JSConsoleTheme.warningText
        case .info: JSConsoleTheme.info
        case .log: JSConsoleTheme.muted
        case .debug: JSConsoleTheme.muted
        }
    }
}
