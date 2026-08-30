//! The tray icon — the Mac's menu-bar extra.
//!
//! `MenuBarView` on the Mac is a `SwiftUI` view over `AppState`: it names the
//! selected device, offers Quick Actions, Screenshot and Mirror Screen, then
//! the features the user chose (or their pinned ones), then Open and Quit. Not
//! one of those lines can be decided in this process — the device, the
//! registry, the user's choices and their wording all live in the webview.
//!
//! So the page sends the menu and this renders it, exactly as `menu.rs`
//! forwards clicks rather than handling them. The difference from `menu.rs` is
//! that this menu is *rebuilt*: the Mac's is a view and re-evaluates whenever
//! the device changes, and a tray that still names an unplugged phone would be
//! worse than no tray.
//!
//! **Why the tray is not optional.** Background mode hides the window; without
//! somewhere to click, the app is then running with no way back to it. So the
//! app records whether the tray was actually created (`TrayState`), and a
//! desktop that would not give it one keeps the old behaviour of quitting when
//! the window closes. That failure is real rather than theoretical: the Linux
//! tray is `libayatana-appindicator`, which the `.deb` now depends on, plus a
//! shell that shows indicators at all.

use serde::Deserialize;
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::menu::{Menu, MenuItemBuilder, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, Wry};

/// The event the webview listens on, carrying the clicked item's id. One
/// event, one dispatch table — the same arrangement as `menu.rs`.
pub const TRAY_EVENT: &str = "tray://command";

/// The tray's id, so its menu can be replaced after it is built.
const TRAY_ID: &str = "main";

/// One row the page asked for. An empty `id` is a separator, and a row with
/// `enabled: false` is a label — the device name at the top of the Mac's menu
/// is exactly that.
#[derive(Debug, Clone, Deserialize)]
pub struct TrayEntry {
    pub id: String,
    pub label: String,
    pub enabled: bool,
}

/// Whether a tray icon exists. Read by the window's close handler, which must
/// not hide a window nobody could bring back.
#[derive(Debug, Default)]
pub struct TrayState {
    present: AtomicBool,
}

impl TrayState {
    pub fn is_present(&self) -> bool {
        self.present.load(Ordering::Relaxed)
    }

    fn note_present(&self) {
        self.present.store(true, Ordering::Relaxed);
    }
}

/// Creates the tray icon, with an empty menu until the page sends one.
///
/// A failure here is not an error the app should die of: a desktop with no
/// system tray is a perfectly working desktop, and the only consequence is that
/// closing the window quits instead of hiding.
pub fn install(app: &AppHandle<Wry>) {
    let Some(icon) = app.default_window_icon().cloned() else {
        return;
    };
    let Ok(menu) = Menu::new(app) else {
        return;
    };
    let built = TrayIconBuilder::with_id(TRAY_ID)
        .icon(icon)
        .tooltip("Droidective")
        // The Mac's menu-bar icon opens its menu on a plain click.
        .show_menu_on_left_click(true)
        .menu(&menu)
        .on_menu_event(|app, event| {
            forward(app, event.id.0.as_str());
        })
        .build(app);
    if built.is_ok() {
        app.state::<TrayState>().note_present();
    }
}

/// Replaces the tray's menu with what the page is showing now.
///
/// # Errors
///
/// Fails only if the platform refuses to build the menu.
pub fn set_menu(app: &AppHandle<Wry>, entries: &[TrayEntry]) -> tauri::Result<()> {
    let Some(tray) = app.tray_by_id(TRAY_ID) else {
        return Ok(());
    };
    let menu = Menu::new(app)?;
    for entry in entries {
        if entry.id.is_empty() {
            menu.append(&PredefinedMenuItem::separator(app)?)?;
            continue;
        }
        menu.append(
            &MenuItemBuilder::with_id(entry.id.as_str(), entry.label.as_str())
                .enabled(entry.enabled)
                .build(app)?,
        )?;
    }
    tray.set_menu(Some(menu))
}

/// Forwards a click to the webview — which is alive even with the window
/// hidden, and is where every one of these commands acts.
fn forward(app: &AppHandle<Wry>, id: &str) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.emit(TRAY_EVENT, id);
    }
}
