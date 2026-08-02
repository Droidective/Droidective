import AppKit
import SwiftUI

/// Centers the window title in the titlebar — the same row as the traffic
/// lights, costing no extra height.
///
/// macOS 26 lays a window title out *leading*, tucked against the traffic
/// lights. A toolbar's principal item is the only placement the system
/// centers, so that's what this uses. Three other routes were tried and all
/// fail on macOS 26:
///
/// | Route | Why not |
/// | --- | --- |
/// | `.navigationTitle` | renders its own leading item — position unchanged, and it duplicates anything else drawn, so the title is written to `window.title` directly instead |
/// | `.fullSizeContentView` + a strip drawn in the content | SwiftUI collapses a view that `ignoresSafeArea`s into the titlebar; nothing renders there at all |
/// | `NSTitlebarAccessoryViewController` | the titlebar sizes the accessory itself — ignoring `intrinsicContentSize`, a width constraint, *and* an overridden `setFrameSize` — and clips anything drawn past those bounds, so the label can't reach the window's midpoint |
///
/// Known cosmetic gap: macOS 26 draws its glass capsule behind toolbar items.
/// Hiding it is one line — `sharedBackgroundVisibility(.hidden)` — but that API
/// is macOS 26-only, and release builds come from a `macos-15` CI runner whose
/// SDK doesn't have it, so calling it would break the build that ships. Moving
/// CI to `macos-26` is what unlocks it.
///
/// One `.modifier(...)` link because RootView's `body` chain already sits near
/// the type-checker's time limit on CI (see the convention in CLAUDE.md).
struct CenteredWindowTitle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.app(.subheadline).weight(.semibold))
                        .foregroundStyle(.textMain)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .background(WindowTitleSetter(title: title))
    }

    /// Keep the toolbar reading as part of the titlebar rather than as a second
    /// bar. Called from `RootView`'s window hook.
    @MainActor
    static func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
    }
}

/// Writes `window.title` — the Window menu and Mission Control name — without
/// drawing it. Applied both when the view lands in a window and on every later
/// update, since neither alone covers it: at first mount there is no window
/// yet, and afterwards nothing re-renders while the title is unchanged.
private struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleWriterView {
        let view = TitleWriterView()
        view.title = title
        return view
    }

    func updateNSView(_ nsView: TitleWriterView, context: Context) {
        nsView.title = title
        nsView.apply()
    }
}

private final class TitleWriterView: NSView {
    var title = ""

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    func apply() {
        guard let window else { return }
        window.titleVisibility = .hidden
        if window.title != title { window.title = title }
    }
}
