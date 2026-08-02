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
                .foregroundStyle(isSelected ? Color.black : Color.textMain)
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

    static var chipHeight: CGFloat { 22 }
    static var rowHeight: CGFloat { 22 }

    /// Rendered width of a chip. Measured with the same font the chip draws in
    /// (`Font.app(.callout)` resolves to the system font at the user's text
    /// scale) so the fit decision matches what lands on screen.
    static func width(of text: String) -> CGFloat {
        let font = NSFont.systemFont(
            ofSize: AppFontPrefs.pointSize(for: .callout) * AppFontPrefs.sizeScale
        )
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(measured) + 20
    }
}
