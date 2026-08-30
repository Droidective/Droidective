//! The Quick Actions panel's window.
//!
//! The Mac's is an `NSPanel` that never activates the app — it can be summoned
//! over whatever you are working in, take a keystroke, run something and go
//! away without your current app losing focus. Neither Windows nor Linux has
//! that: a window that takes keyboard input is a window with focus. So this is
//! an ordinary always-on-top window that is small, undecorated and out of the
//! taskbar, and it hands focus back by hiding itself the moment it is done.
//! That is the closest honest equivalent, and it is named here rather than
//! quietly diverging.
//!
//! Created on first use rather than at launch: a second webview costs real
//! memory, and someone who never presses the hotkey should never pay it.

use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder, Wry};

/// The window label. The page reads it to decide which app to render — one
/// bundle, two entry points.
pub const PANEL_LABEL: &str = "quick";

const WIDTH: f64 = 560.0;
const HEIGHT: f64 = 460.0;

/// Shows the panel, or hides it if it is already up. The hotkey's whole job.
///
/// # Errors
///
/// Fails only if the platform refuses to create the window.
pub fn toggle(app: &AppHandle<Wry>) -> tauri::Result<()> {
    if let Some(window) = app.get_webview_window(PANEL_LABEL) {
        if window.is_visible().unwrap_or(false) {
            window.hide()?;
            return Ok(());
        }
        window.show()?;
        window.set_focus()?;
        return Ok(());
    }
    // The query string is how the page knows which of the two apps to render;
    // see `main.tsx`. The label alone would work, but only asynchronously.
    let url = WebviewUrl::App("index.html?window=quick".into());
    let window = WebviewWindowBuilder::new(app, PANEL_LABEL, url)
        .title("Quick Actions")
        .inner_size(WIDTH, HEIGHT)
        .resizable(false)
        .decorations(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .center()
        .focused(true)
        .build()?;
    window.set_focus()?;
    Ok(())
}

/// Hides it — Esc at the root, and a successful run when Settings asks.
pub fn hide(app: &AppHandle<Wry>) {
    if let Some(window) = app.get_webview_window(PANEL_LABEL) {
        let _ = window.hide();
    }
}
