import ADBKit
import AppKit
import SwiftUI

/// The translucent-window appearance (Settings ▸ Appearance ▸ Window): the
/// stored preference keys, the window-server blur, the Metal grain film, and
/// the alpha-aware background fills every opaque pane routes through. The
/// value math lives in `WindowEffects` (ADBKit, tested); this file is only
/// the SwiftUI/AppKit plumbing.

let windowOpacityDefaultsKey = "windowOpacity"
let windowBlurDefaultsKey = "windowBlurAmount"
let windowGrainDefaultsKey = "windowGrainAmount"

extension EnvironmentValues {
    /// The clamped window opacity, injected once by RootView so every pane
    /// derives its fill alpha from the same value. 1.0 (the default in other
    /// scenes) keeps every fill exactly as before the feature existed.
    @Entry var windowOpacity: Double = 1.0
}

/// Window-server flags plus the behind-window blur radius. Idempotent —
/// called on attach and on every slider change.
@MainActor
func applyWindowTranslucency(_ window: NSWindow, opacity: Double, blurAmount: Double) {
    let translucent = WindowEffects.isTranslucent(opacity)
    window.isOpaque = !translucent
    window.backgroundColor = translucent ? .clear : .windowBackgroundColor
    WindowServerBlur.apply(
        radius: WindowEffects.blurRadius(amount: blurAmount, root: opacity), to: window)
    window.invalidateShadow()
}

/// The adjustable behind-window blur. `NSVisualEffectView` only offers fixed
/// per-material radii, so the radius goes straight to the window server —
/// the same `CGSSetWindowBackgroundBlurRadius` call iTerm2's blur slider has
/// shipped on for years. Both symbols are resolved lazily; on a macOS that
/// drops them the slider quietly does nothing instead of crashing.
private enum WindowServerBlur {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias SetRadius = @convention(c) (UInt32, UInt32, UInt32) -> Int32

    private static let connection: UInt32? = {
        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "CGSDefaultConnectionForThread") else {
            return nil
        }
        return unsafeBitCast(sym, to: Connection.self)()
    }()

    private static let setRadius: SetRadius? = {
        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "CGSSetWindowBackgroundBlurRadius") else {
            return nil
        }
        return unsafeBitCast(sym, to: SetRadius.self)
    }()

    @MainActor
    static func apply(radius: Int, to window: NSWindow) {
        guard let connection, let setRadius, window.windowNumber > 0 else { return }
        _ = setRadius(connection, UInt32(window.windowNumber), UInt32(radius))
    }
}

/// Everything RootView layers onto its content for the translucent window,
/// as ONE chain link: the grain film, the `\.windowOpacity` environment, and
/// the live re-application of window flags + blur radius on slider changes.
/// (Kept out of RootView's `body` chain — its expression already sits near
/// the type-checker's time limit on CI, and four more links pushed it over.)
struct WindowTranslucencyModifier: ViewModifier {
    let state: AppState
    @AppStorage(windowOpacityDefaultsKey) private var windowOpacity = 1.0
    @AppStorage(windowBlurDefaultsKey) private var windowBlur = 0.6
    @AppStorage(windowGrainDefaultsKey) private var windowGrain = 0.0

    func body(content: Content) -> some View {
        content
            // Outside RootView's zoom scaleEffect, so ⌘= never magnifies
            // the specks.
            .overlay {
                GrainOverlay(
                    strength: WindowEffects.grainOpacity(root: windowOpacity, amount: windowGrain))
            }
            .environment(\.windowOpacity, WindowEffects.clamped(windowOpacity))
            .onChange(of: windowOpacity) { _, value in
                if let window = state.mainWindow {
                    applyWindowTranslucency(window, opacity: value, blurAmount: windowBlur)
                }
            }
            .onChange(of: windowBlur) { _, value in
                if let window = state.mainWindow {
                    applyWindowTranslucency(window, opacity: windowOpacity, blurAmount: value)
                }
            }
    }
}

/// The static Metal grain film over the glass. The base fill is
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
