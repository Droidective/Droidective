mod commands;
mod daemon;
mod error;

use tauri::{Emitter, Manager, RunEvent};

use crate::daemon::{DaemonStatus, Supervisor};

/// The event the UI waits on before it asks the daemon for anything.
const STATUS_EVENT: &str = "daemon://status";

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
        .plugin(tauri_plugin_shell::init())
        // Registered for their Rust APIs only. The capability file grants the
        // webview neither, so the clipboard and the file manager are reachable
        // through our own commands and nowhere else.
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_opener::init())
        .manage(Supervisor::default())
        .invoke_handler(tauri::generate_handler![
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
            commands::watch_performance,
            commands::watch_netspeed,
            commands::stop_watching,
            commands::copy_text,
            commands::reveal_path,
            commands::open_url,
            commands::captures_folder,
            commands::export_text,
        ])
        .setup(|app| {
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
