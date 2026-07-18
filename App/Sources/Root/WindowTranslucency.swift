import ADBKit
import AppKit
import SwiftUI

/// The translucent-window appearance (Settings ▸ Appearance ▸ Window): the
/// stored preference keys, the behind-window blur backdrop, the Metal grain
/// film, and the alpha-aware background fills every opaque pane routes
/// through. The alpha math itself lives in `WindowEffects` (ADBKit, tested);
/// this file is only the SwiftUI/AppKit plumbing.

let windowOpacityDefaultsKey = "windowOpacity"
let windowBlurDefaultsKey = "windowBlurEnabled"
let windowGrainDefaultsKey = "windowGrainEnabled"

extension EnvironmentValues {
    /// The clamped window opacity, injected once by RootView so every pane
    /// derives its fill alpha from the same value. 1.0 (the default in other
    /// scenes) keeps every fill exactly as before the feature existed.
    @Entry var windowOpacity: Double = 1.0
}

/// Window-server flags for see-through rendering. Idempotent — safe to call
/// on attach and on every slider change.
@MainActor
func applyWindowTranslucency(_ window: NSWindow, opacity: Double) {
    let translucent = WindowEffects.isTranslucent(opacity)
    window.isOpaque = !translucent
    window.backgroundColor = translucent ? .clear : .windowBackgroundColor
    window.invalidateShadow()
}

/// The behind-window blur: an `NSVisualEffectView` that frosts whatever is
/// under the window. Hidden (not removed) when blur is off or the window is
/// opaque, so toggling never restructures the hierarchy.
struct WindowBackdropView: NSViewRepresentable {
    let active: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.isHidden = !active
    }
}

/// The static Metal grain film over the frosted window. The base fill is
/// all-but-invisible so a device that can't run the shader shows nothing
/// instead of a solid flash; the shader replaces each pixel with a frozen
/// speck at the strength `WindowEffects.grainOpacity` hands over.
struct GrainOverlay: View {
    let strength: Double

    var body: some View {
        if strength > 0 {
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .colorEffect(ShaderLibrary.grain(.float(Float(strength))))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Alpha-aware fills

extension View {
    /// The master pane fill: `bgRoot` at the window opacity (opaque at 1.0).
    func translucentRootBackground() -> some View {
        modifier(TranslucentFill(style: .root))
    }

    /// Chrome bars (sidebar, device bar, rails, status strips): `bgSurface`
    /// a step more opaque than the root so their content keeps contrast.
    func translucentSurfaceBackground() -> some View {
        modifier(TranslucentFill(style: .surface))
    }

    /// Feeds that sat on the system `.background` material (logcat, iOS
    /// logs, Reactotron): the material vanishes when translucent so the
    /// root fill shows through, and returns untouched when opaque.
    func translucentFeedBackground() -> some View {
        modifier(TranslucentFill(style: .feed))
    }

    /// `List`s that sat on the default opaque scroll material (files, apps,
    /// crashes): the material hides when translucent, stock otherwise.
    func translucentListBackground() -> some View {
        modifier(TranslucentListBackground())
    }
}

private struct TranslucentListBackground: ViewModifier {
    @Environment(\.windowOpacity) private var opacity

    func body(content: Content) -> some View {
        content.scrollContentBackground(WindowEffects.isTranslucent(opacity) ? .hidden : .automatic)
    }
}

private struct TranslucentFill: ViewModifier {
    enum Style { case root, surface, feed }

    let style: Style
    @Environment(\.windowOpacity) private var opacity

    func body(content: Content) -> some View {
        switch style {
        case .root:
            content.background(Color.bgRoot.opacity(WindowEffects.clamped(opacity)))
        case .surface:
            content.background(Color.bgSurface.opacity(WindowEffects.surfaceAlpha(root: opacity)))
        case .feed:
            content.background(.background.opacity(WindowEffects.isTranslucent(opacity) ? 0 : 1))
        }
    }
}
