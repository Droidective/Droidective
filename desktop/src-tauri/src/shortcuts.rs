//! OS-registered shortcuts.
//!
//! The Mac registers every feature's shortcut with the system, so it fires from
//! whatever app you happen to be in — which is the point of recording one. This
//! app could only manage window shortcuts until now, and the recorder said so.
//!
//! The page owns the bindings, so it sends the accelerators and this registers
//! what the platform will take. Two things make that more than a loop:
//!
//! - **A refusal is normal.** Another app may already hold Ctrl+Alt+L, and the
//!   platform simply says no. Registering the rest and reporting which ones took
//!   is better than failing the batch, and the page needs the answer anyway:
//!   the combinations that did *not* register are exactly the ones its own
//!   window-level handler must keep answering.
//! - **The answer has to be in the platform's spelling.** A press arrives as a
//!   `Shortcut`, and the string it produces is the parser's canonical form
//!   rather than whatever was sent in. So each registration reports the pair,
//!   and the page keys its table on the canonical half.

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, Wry};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutEvent, ShortcutState};

/// The event the webview listens on, carrying the canonical accelerator.
pub const SHORTCUT_EVENT: &str = "shortcut://pressed";

/// One accelerator that registered, in both spellings.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Registered {
    /// What the page asked for.
    pub requested: String,
    /// What a press will arrive as.
    pub canonical: String,
}

/// Replaces every registration with this set, answering with the ones that took.
pub fn set(app: &AppHandle<Wry>, accelerators: &[String]) -> Vec<Registered> {
    let manager = app.global_shortcut();
    // Wholesale, because this is the page's complete set: a shortcut cleared in
    // Settings has to stop firing, and there is no diff worth keeping to work
    // out which one that was.
    let _ = manager.unregister_all();

    let mut registered = Vec::new();
    for requested in accelerators {
        let Ok(shortcut) = requested.parse::<Shortcut>() else {
            continue;
        };
        if manager.on_shortcut(shortcut, on_pressed).is_ok() {
            registered.push(Registered {
                requested: requested.clone(),
                canonical: shortcut.into_string(),
            });
        }
    }
    registered
}

/// Forwards a press to the page — which is where every one of these acts, and
/// which is alive whether or not the window is on screen.
fn on_pressed(app: &AppHandle<Wry>, shortcut: &Shortcut, event: ShortcutEvent) {
    // Both edges arrive. Acting on the release too would run everything twice.
    if event.state != ShortcutState::Pressed {
        return;
    }
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.emit(SHORTCUT_EVENT, shortcut.into_string());
    }
}
