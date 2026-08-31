mod api;
mod commands;
mod daemon;
mod error;
mod menu;
mod metro;
mod panel;
mod record;
mod shortcuts;
mod tray;

use std::sync::atomic::{AtomicBool, Ordering};

use tauri::{Emitter, Manager, RunEvent, WindowEvent};

use crate::daemon::{DaemonStatus, Supervisor};
use crate::tray::TrayState;

/// The event the UI waits on before it asks the daemon for anything.
const STATUS_EVENT: &str = "daemon://status";

/// Told to the page when the window is hidden rather than closed, so it can do
/// what the Mac's `AppState.enterBackground` does: stop the work that was only
/// running because a window was open.
const BACKGROUND_EVENT: &str = "app://background";

/// Settings ▸ General ▸ "Keep running in the background", mirrored from the
/// page. Defaults to on, as it does on the Mac.
#[derive(Debug)]
pub struct BackgroundMode(AtomicBool);

impl Default for BackgroundMode {
    fn default() -> Self {
        Self(AtomicBool::new(true))
    }
}

impl BackgroundMode {
    fn is_enabled(&self) -> bool {
        self.0.load(Ordering::Relaxed)
    }

    fn set(&self, enabled: bool) {
        self.0.store(enabled, Ordering::Relaxed);
    }
}

/// Hides the window instead of closing it, when there is a tray to get it back
/// from and the user has asked for that.
///
/// The tray check is not belt and braces: a desktop that gave us no tray icon
/// would otherwise hide the window into a process nobody can reach, and
/// "closing the window quits" is the correct behaviour there rather than a
/// degraded one.
fn on_window_event(window: &tauri::Window, event: &WindowEvent) {
    let WindowEvent::CloseRequested { api, .. } = event else {
        return;
    };
    if window.label() != "main" {
        return;
    }
    let app = window.app_handle();
    if !app.state::<BackgroundMode>().is_enabled() || !app.state::<TrayState>().is_present() {
        return;
    }
    api.prevent_close();
    let _ = window.hide();
    let _ = window.emit(BACKGROUND_EVENT, true);
}

/// Builds the app, starts the daemon in the background, and runs the event
/// loop until the window closes.
///
/// # Errors
///
/// Fails only if Tauri itself cannot build the app — a malformed
/// `tauri.conf.json` or a window the platform refuses to create. A daemon that
/// will not start is *not* an error here: the UI comes up and says so.
#[expect(
    clippy::exit,
    reason = "tauri::generate_context! expands to a process::exit on a malformed config"
)]
pub fn run() -> tauri::Result<()> {
    let app = tauri::Builder::default()
        // The window menu, and the only home these commands have: a webview has
        // no menu of its own. Every click is forwarded to the page, which is
        // where the state each command acts on lives.
        .menu(menu::build)
        .on_menu_event(menu::forward)
        .plugin(tauri_plugin_shell::init())
        // Registered for their Rust APIs only. The capability file grants the
        // webview neither, so the clipboard and the file manager are reachable
        // through our own commands and nowhere else.
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        // Same arrangement: an important result that lands while you are in
        // another app posts a native notification through our own command, so
        // the page cannot post one on its own.
        .plugin(tauri_plugin_notification::init())
        // A recorded shortcut fires from wherever you are, which is what makes
        // it worth recording. Registration is driven by the page (`shortcuts`)
        // rather than declared here, because the bindings are the user's.
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .manage(Supervisor::default())
        .manage(BackgroundMode::default())
        .manage(TrayState::default())
        .invoke_handler(handlers())
        .on_window_event(|window, event| {
            on_window_event(window, event);
        })
        .setup(|app| {
            // Before the daemon: the tray is what a hidden window is reached
            // through, and whether one exists decides what the close button
            // does from the first click.
            tray::install(app.handle());
            // Off the setup path: spawning the sidecar and waiting for its
            // port line takes as long as it takes, and blocking here would
            // hold the window back with nothing to show for it.
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                let supervisor = handle.state::<Supervisor>();
                let outcome = supervisor.start(&handle).await;
                let status = match outcome {
                    Ok(port) => DaemonStatus::Ready { port },
                    Err(error) => DaemonStatus::Failed {
                        message: error.to_string(),
                    },
                };
                let _ = handle.emit(STATUS_EVENT, status);
            });
            Ok(())
        })
        .build(tauri::generate_context!())?;

    app.run(|handle, event| {
        // Kill the daemon with us. `--parent-pid` is the backstop for the
        // cases where this never runs (a crash, a SIGKILL).
        if matches!(event, RunEvent::Exit) {
            handle.state::<Supervisor>().shutdown();
        }
    });
    Ok(())
}

/// Every command the webview may call.
///
/// Its own function so `run` stays readable: the list is a declaration rather
/// than logic, and inline it pushed the builder past the line limit — which is
/// a real signal about `run`, and a useless one about a list of names — which
/// is also why the length lint is turned off for it rather than the list being
/// broken up: `generate_handler!` takes one list, and splitting it would mean
/// splitting the macro.
#[expect(
    clippy::too_many_lines,
    reason = "a declaration of every command, not logic; one macro takes one list"
)]
fn handlers() -> impl Fn(tauri::ipc::Invoke<tauri::Wry>) -> bool + Send + Sync + 'static {
    tauri::generate_handler![
        commands::daemon_status,
        commands::list_devices,
        commands::list_features,
        commands::run_action,
        commands::list_apps,
        commands::control_app,
        commands::device_props,
        commands::root_status,
        commands::list_files,
        commands::file_operation,
        commands::file_info,
        commands::pull_file,
        commands::list_crashes,
        commands::clear_crashes,
        commands::dev_settings,
        commands::write_dev_setting,
        commands::restrictions,
        commands::write_restriction,
        commands::wifi,
        commands::write_wifi,
        commands::private_dns,
        commands::write_private_dns,
        commands::app_info,
        commands::permissions,
        commands::set_permission,
        commands::meminfo,
        commands::sandbox_list,
        commands::sandbox_pull,
        commands::pull_apk,
        commands::watch_devices,
        commands::watch_logcat,
        commands::logcat_pid,
        commands::watch_performance,
        commands::watch_netspeed,
        commands::foreground_app,
        commands::watch_reactotron,
        commands::reactotron_reverse,
        commands::reactotron_unreverse,
        commands::install_path,
        commands::pick_file,
        commands::pick_folder,
        commands::apk_toolchain,
        commands::decompile_apk,
        metro::metro_targets,
        metro::metro_running,
        commands::decompiled_file,
        commands::search_decompiled,
        commands::rebuild_decompiled,
        commands::managed_tools,
        commands::install_tool,
        commands::inspect_apk,
        commands::sign_apk,
        commands::convert_aab,
        commands::custom_commands,
        commands::write_custom_commands,
        commands::run_custom_command,
        commands::watch_mirror,
        commands::write_mirror,
        commands::open_terminal,
        commands::write_terminal,
        commands::resize_terminal,
        commands::set_terminal_commands_enabled,
        commands::emulators,
        commands::emulator_action,
        commands::pair_wireless,
        commands::connect_wireless,
        commands::disconnect_wireless,
        commands::enable_tcpip,
        commands::deep_links,
        commands::write_deep_links,
        commands::launch_deep_link,
        commands::create_bug_report,
        commands::detect_tools,
        commands::pick_and_install,
        commands::stop_watching,
        commands::copy_text,
        commands::reveal_path,
        commands::post_notification,
        commands::set_tray_menu,
        commands::set_background_mode,
        commands::background_available,
        commands::show_main_window,
        commands::quit_app,
        commands::set_global_shortcuts,
        commands::toggle_quick_panel,
        commands::hide_quick_panel,
        commands::open_url,
        commands::captures_folder,
        commands::export_text,
        api::api_workspace,
        api::api_write,
        api::api_send,
        api::api_cancel,
        api::api_code,
        api::api_curl,
        api::api_import,
        api::api_export,
        record::record_status,
        record::record_start,
        record::record_pause,
        record::record_resume,
        record::record_stop,
        record::save_recording,
        record::discard_recording,
        record::managed_tool_list,
        record::managed_tool_install,
        record::managed_tool_remove,
    ]
}
