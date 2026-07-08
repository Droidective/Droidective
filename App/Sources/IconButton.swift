import SwiftUI

/// The app's icon-button sizing standard. Every icon-only button (toolbars,
/// bars, inline dismiss/clear glyphs) uses one of these tokens instead of ad-hoc
/// `.frame`/`.font`/`.controlSize` values, so glyph sizes and hit areas stay
/// consistent across every feature. Pair with ``IconButtonStyle``.
enum IconButtonSize {
    /// Inline glyphs living inside a text bar or chip — clear-search, remove a
    /// filter, close a find bar.
    case small
    /// The default: toolbar and status-bar action icons.
    case medium
    /// Prominent, standalone actions.
    case large

    /// Square clickable frame (points).
    var side: CGFloat {
        switch self {
        case .small: 22
        case .medium: 28
        case .large: 34
        }
    }

    /// SF Symbol point size (points).
    var glyph: CGFloat {
        switch self {
        case .small: 12
        case .medium: 14
        case .large: 17
        }
    }
}

/// A borderless icon-only button: a consistent glyph size, a square hit area, and
/// a subtle hover/press wash. The single source of truth for icon-button sizing
/// — see ``IconButtonSize``. The glyph color is inherited (so `.brandAccent` /
/// `.textMuted` at the call site still apply); only the geometry is standardized.
///
/// ```swift
/// Button { clear() } label: { Image(systemName: "trash") }
///     .buttonStyle(IconButtonStyle())
/// ```
struct IconButtonStyle: ButtonStyle {
    var size: IconButtonSize = .medium

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size)
    }
}

/// Backs ``IconButtonStyle`` — a small view so the hover state can live in
/// `@State` (a `ButtonStyle` body can't hold state directly).
private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: IconButtonSize
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.app(size: size.glyph, weight: .medium))
            .frame(width: size.side, height: size.side)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.07 : 0)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
