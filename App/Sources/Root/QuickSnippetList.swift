import ADBKit
import SwiftUI

/// The Send Text snippet library, panel-sized: the recency-ranked rows sitting
/// under the form's text field, collapsed to the first few with the rest behind
/// "Show N more".
///
/// No search field, unlike the main window's Snippets section: the panel's one
/// text field holds the text being *sent*, so filtering the list by it would
/// hide the snippet you were reaching for as you typed it. The recency ranking
/// is what surfaces the right ones instead — and `Show all` is one click away.
///
/// Rows carry the panel's own highlight (a solid accent fill, `accentText` on
/// top) rather than a list-row wash, so ↓/↑ through the snippets looks like
/// ↓/↑ through every other panel screen.
struct QuickSnippetList: View {
    /// The rows to render — already ranked and, unless expanded, truncated.
    let shown: [SendTextSnippet]
    /// How many the library holds, for the "Show N more" count.
    let total: Int
    /// The keyboard-highlighted row, as an index into `shown`.
    let highlighted: Int?
    let expanded: Bool
    let onInsert: (SendTextSnippet) -> Void
    let onToggleExpanded: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Past this many rows the expanded list scrolls instead of growing the
    /// panel past the screen.
    private static let maximumListHeight: CGFloat = 190

    private var accentText: Color { Color.brandAccent.contrastingForeground(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Snippets")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
            if total == 0 {
                Text("No snippets yet — save the text you send often on the Send Text screen.")
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                rows
                if total > shown.count || expanded {
                    expandButton
                }
            }
        }
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, snippet in
                        row(snippet, isHighlighted: index == highlighted)
                            .id(snippet.id)
                    }
                }
            }
            .frame(maxHeight: Self.maximumListHeight)
            // Keep a keyboard-walked row on screen once the list scrolls.
            .onChange(of: highlighted) { _, index in
                guard let index, shown.indices.contains(index) else { return }
                proxy.scrollTo(shown[index].id)
            }
            // A collapsed list is shorter than the cap, so let it size itself
            // instead of reserving the full height.
            .fixedSize(horizontal: false, vertical: !expanded)
        }
    }

    private func row(_ snippet: SendTextSnippet, isHighlighted: Bool) -> some View {
        Button {
            onInsert(snippet)
        } label: {
            HStack(spacing: 10) {
                Text(snippet.name)
                    .font(.app(.callout))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(snippet.text)
                    .font(.app(.caption, design: .monospaced))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(accentText.opacity(0.75))
                        : AnyShapeStyle(.textMuted))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHighlighted ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(isHighlighted ? accentText : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The placeholders are expanded on insert, so show the raw text here —
        // it is what the snippet *is*, and what a `{clipboard}` will replace.
        .help("Click to insert\n\n\(snippet.text)")
        .accessibilityLabel("Insert snippet \(snippet.name)")
    }

    private var expandButton: some View {
        Button(action: onToggleExpanded) {
            Text(expanded ? "Show less" : "Show \(total - shown.count) more")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
