import SwiftUI

/// The jump-to-top / jump-to-bottom buttons every log feed shares. Each button
/// hides while the viewport already touches its edge, and both hide when the
/// feed is disabled (no device / not connected) or too short to scroll.
struct LogJumpControls: View {
    let edges: LogScrollEdges
    /// False hides both buttons regardless of geometry — the caller's
    /// "not connected / nothing streaming" state.
    let enabled: Bool
    /// Which end new lines land on — phrases the two help texts.
    let newestEdge: VerticalEdge
    let onJumpToTop: () -> Void
    let onJumpToBottom: () -> Void

    private var showTop: Bool { enabled && edges.isScrollable && !edges.atTop }
    private var showBottom: Bool { enabled && edges.isScrollable && !edges.atBottom }

    var body: some View {
        VStack(spacing: 0) {
            if showTop {
                jumpButton(
                    icon: "arrow.up",
                    help: newestEdge == .top ? "Jump to the newest logs" : "Jump to the oldest logs",
                    action: onJumpToTop
                )
            }
            Spacer(minLength: 0)
            if showBottom {
                jumpButton(
                    icon: "arrow.down",
                    help: newestEdge == .bottom ? "Jump to the newest logs" : "Jump to the oldest logs",
                    action: onJumpToBottom
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(.snappy(duration: 0.2), value: showTop)
        .animation(.snappy(duration: 0.2), value: showBottom)
    }

    private func jumpButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.app(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.tint, in: Circle())
                .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}
