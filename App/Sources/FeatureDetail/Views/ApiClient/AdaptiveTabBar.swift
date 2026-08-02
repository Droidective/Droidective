import ADBKit
import AppKit
import SwiftUI

/// A segmented-looking tab row that degrades one tab at a time.
///
/// `ViewThatFits` over a segmented and a menu picker was all-or-nothing: seven
/// request tabs never fit a half-width pane, so the row collapsed to a single
/// centred dropdown even with room for five of them. This keeps every tab that
/// fits and hands only the remainder to a "More" menu — and because the widths
/// are measured rather than guessed, no tab is ever drawn clipped.
struct AdaptiveTabBar<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    let label: (Tab) -> String
    @Binding var selection: Tab
    /// `.leading` for a row of its own, `.trailing` when the bar shares a row
    /// with something else and should sit against the edge.
    var alignment: HorizontalAlignment = .leading

    @Environment(\.colorScheme) private var colorScheme

    private static var spacing: CGFloat { 2 }
    private static var overflowWidth: CGFloat { 34 }

    var body: some View {
        // A fixed height keeps the row from resizing as tabs move in and out of
        // the menu, which would nudge the content below it on every keystroke.
        GeometryReader { geometry in
            let widths = tabs.map { Self.width(of: label($0)) }
            let layout = TabOverflow.layout(
                widths: widths.map(Double.init),
                available: Double(geometry.size.width),
                spacing: Double(Self.spacing),
                overflowWidth: Double(Self.overflowWidth),
                selected: tabs.firstIndex(of: selection)
            )
            HStack(spacing: Self.spacing) {
                if alignment == .trailing { Spacer(minLength: 0) }
                ForEach(layout.visible, id: \.self) { index in
                    chip(tabs[index], width: widths[index])
                }
                if !layout.overflow.isEmpty {
                    overflowMenu(layout.overflow)
                }
                if alignment == .leading { Spacer(minLength: 0) }
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: Self.rowHeight)
    }

    private func chip(_ tab: Tab, width: CGFloat) -> some View {
        let isSelected = tab == selection
        return Button {
            selection = tab
        } label: {
            Text(label(tab))
                .font(.app(.callout))
                // The accent is user-chosen; a hardcoded black label goes
                // unreadable the moment someone picks a dark one.
                .foregroundStyle(
                    isSelected
                        ? Color.brandAccent.contrastingForeground(for: colorScheme)
                        : Color.textMain
                )
                .lineLimit(1)
                .frame(width: width, height: Self.chipHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.brandAccent : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label(tab))
    }

    private func overflowMenu(_ indices: [Int]) -> some View {
        Menu {
            ForEach(indices, id: \.self) { index in
                Button {
                    selection = tabs[index]
                } label: {
                    // A checkmark would be dead weight: the selected tab is
                    // pulled out of the menu and drawn in the row.
                    Text(label(tabs[index]))
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: Self.overflowWidth, height: Self.chipHeight)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More tabs")
    }

    // MARK: - Measurement

    static var chipHeight: CGFloat { TabLabelMetrics.chipHeight }
    static var rowHeight: CGFloat { TabLabelMetrics.chipHeight }

    static func width(of text: String) -> CGFloat { TabLabelMetrics.width(of: text) }
}

/// Chip sizing, kept out of the generic view so the memo can be a stored static.
@MainActor
enum TabLabelMetrics {

    static let chipHeight: CGFloat = 22
    /// Horizontal padding inside a chip, on top of the measured text.
    private static let horizontalPadding: CGFloat = 20

    private struct Key: Hashable {
        let text: String
        let family: String?
        let size: CGFloat
    }

    private static var cache: [Key: CGFloat] = [:]

    /// Rendered width of a chip.
    ///
    /// Measured in the font the chip actually draws in, family included:
    /// `Font.app(.callout)` honours Settings ▸ Appearance ▸ Font, so measuring
    /// the system font would under-measure a wider family and clip the last
    /// chip — the one thing this control exists to prevent.
    ///
    /// Memoised because this runs for every tab on every layout pass, and a
    /// pane-divider drag issues a great many of those.
    static func width(of text: String) -> CGFloat {
        let size = AppFontPrefs.pointSize(for: .callout) * AppFontPrefs.sizeScale
        let family = AppFontPrefs.family
        let key = Key(text: text, family: family, size: size)
        if let cached = cache[key] { return cached }

        let measured = (text as NSString)
            .size(withAttributes: [.font: font(family: family, size: size)])
            .width
        let width = ceil(measured) + horizontalPadding
        // A pane only ever shows a handful of distinct labels; the cap is just
        // so a pathological run of label changes can't grow this unbounded.
        if cache.count > 256 { cache.removeAll() }
        cache[key] = width
        return width
    }

    private static func font(family: String?, size: CGFloat) -> NSFont {
        guard let family else { return .systemFont(ofSize: size) }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
    }
}
