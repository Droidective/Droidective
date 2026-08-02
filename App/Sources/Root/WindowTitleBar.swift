import AppKit
import SwiftUI

/// Centers the window title.
///
/// macOS 26 lays a plain window's title out **leading**, tucked against the
/// traffic lights (verified at runtime: no toolbar, `titleVisibility ==
/// .visible`, and it still renders left). The only placement the system
/// centers is a toolbar's principal item, so the window title itself is
/// hidden and the same string is drawn there instead. `window.title` is still
/// set by `.navigationTitle`, which is what names the window in the Window
/// menu and Mission Control.
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
                        .font(.app(.headline))
                        .foregroundStyle(.textMain)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            // Deliberately *not* `.navigationTitle`: on macOS 26 that renders
            // as its own leading item beside the traffic lights, which would
            // sit there duplicating the centered one. Setting `window.title`
            // straight keeps the Window menu and Mission Control naming
            // without drawing anything.
            .background(WindowTitleSetter(title: title))
    }

    /// Keep the toolbar reading as part of the titlebar rather than a second
    /// bar. Called from `RootView`'s window hook.
    @MainActor
    static func configure(_ window: NSWindow) {
        window.toolbarStyle = .unified
    }
}

/// Writes the window title without drawing it. Re-applied on every update, so
/// it also re-hides the system title if SwiftUI puts it back.
private struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.titleVisibility = .hidden
        if window.title != title { window.title = title }
    }
}
