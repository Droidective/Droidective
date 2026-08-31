//! The translucent window's native half: the platform's own blur behind the
//! page.
//!
//! The page paints itself at the chosen opacity — that part is portable and
//! lives in `lib/window-effects.ts`. What is *behind* the window can only be
//! blurred by the compositor, and the three platforms do not agree on how:
//!
//! - **Windows** has Acrylic (10 and 11) and Mica (11 only). Both are
//!   on-or-off; neither takes a radius.
//! - **macOS** has `NSVisualEffectView` materials, also without a radius.
//! - **Linux** has nothing an application can ask for. Whether a transparent
//!   window is blurred is the compositor's decision — a `KWin` rule, a GNOME
//!   extension — and there is no portable call that changes it.
//!
//! That is why the desktop's Blur is a switch where the Mac's is a slider. The
//! divergence is forced by the platforms rather than chosen, and it is named
//! here, in Settings, and in `docs/desktop-parity.md`.

use tauri::utils::config::WindowEffectsConfig;
use tauri::utils::WindowEffect;
use tauri::{AppHandle, Manager, Wry};

use crate::error::DaemonError;

/// Turn the platform's window blur on or off for one window.
///
/// Failing to apply it is not an error worth stopping for: the window is still
/// perfectly usable, just not frosted. It is reported so Settings can say the
/// platform refused rather than leaving a switch that looks on and does
/// nothing.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle and String in by value"
)]
pub fn set_window_blur(
    app: AppHandle<Wry>,
    label: String,
    enabled: bool,
) -> Result<bool, DaemonError> {
    let window = app
        .get_webview_window(&label)
        .ok_or_else(|| DaemonError::Host(format!("No window named {label}.")))?;

    let effects = if enabled { blur_effects() } else { None };
    window
        .set_effects(effects)
        .map_err(|error| DaemonError::Host(format!("The window refused the effect: {error}")))?;
    Ok(enabled && supported())
}

/// Whether this platform has a window blur to ask for at all.
#[tauri::command]
pub fn window_blur_supported() -> bool {
    supported()
}

const fn supported() -> bool {
    cfg!(any(target_os = "windows", target_os = "macos"))
}

/// The effect stack for "blur on", per platform.
///
/// Acrylic rather than Mica on Windows: Mica tints with the desktop's dominant
/// colour rather than blurring it, and it is Windows 11 only, so on 10 the
/// switch would silently do nothing. Acrylic works on both and is the effect
/// people mean when they say a window is frosted.
fn blur_effects() -> Option<WindowEffectsConfig> {
    if !supported() {
        return None;
    }
    let effect = if cfg!(target_os = "windows") {
        WindowEffect::Acrylic
    } else {
        WindowEffect::UnderWindowBackground
    };
    Some(WindowEffectsConfig {
        effects: vec![effect],
        state: None,
        radius: None,
        color: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The switch has to be able to say "this platform cannot" — a control
    /// that looks on and does nothing is worse than one that is disabled.
    #[test]
    fn a_platform_with_no_effect_produces_none() {
        assert_eq!(blur_effects().is_some(), supported());
    }

    #[test]
    fn support_matches_the_platform() {
        assert_eq!(
            window_blur_supported(),
            cfg!(any(target_os = "windows", target_os = "macos"))
        );
    }

    /// Acrylic on Windows, a vibrancy material elsewhere. Named because
    /// picking Mica here would make the switch inert on Windows 10.
    #[test]
    fn the_effect_is_the_one_that_actually_blurs() {
        let Some(config) = blur_effects() else { return };
        let expected = if cfg!(target_os = "windows") {
            WindowEffect::Acrylic
        } else {
            WindowEffect::UnderWindowBackground
        };
        assert_eq!(config.effects, vec![expected]);
    }
}
