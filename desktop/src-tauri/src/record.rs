//! Screen recording.
//!
//! Five thin forwards. The session lives in the daemon — this process holds no
//! recording state of its own, which is what lets a screen reopen mid-recording
//! and find out what is already running.

use std::path::Path;

use tauri::{AppHandle, State};

use crate::commands::droidective_folder;
use crate::daemon::wire::{
    ManagedToolRequest, ManagedToolsListResponse, RecordOptions, RecordStartRequest,
    RecordStatusResponse, RecordStoppedResponse,
};
use crate::daemon::Supervisor;
use crate::error::DaemonError;

/// What is being recorded, and whether ffmpeg is here to do it.
#[tauri::command]
pub async fn record_status(
    supervisor: State<'_, Supervisor>,
) -> Result<RecordStatusResponse, DaemonError> {
    supervisor.client().await?.record_status().await
}

#[tauri::command]
pub async fn record_start(
    supervisor: State<'_, Supervisor>,
    serial: String,
    options: RecordOptions,
) -> Result<RecordStatusResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .record_start(&RecordStartRequest { serial, options })
        .await
}

#[tauri::command]
pub async fn record_pause(
    supervisor: State<'_, Supervisor>,
) -> Result<RecordStatusResponse, DaemonError> {
    supervisor.client().await?.record_pause().await
}

/// The options travel again because each span is its own scrcpy session:
/// segments recorded at different sizes cannot be concatenated.
#[tauri::command]
pub async fn record_resume(
    supervisor: State<'_, Supervisor>,
    options: RecordOptions,
) -> Result<RecordStatusResponse, DaemonError> {
    supervisor.client().await?.record_resume(&options).await
}

#[tauri::command]
pub async fn record_stop(
    supervisor: State<'_, Supervisor>,
) -> Result<RecordStoppedResponse, DaemonError> {
    supervisor.client().await?.record_stop().await
}

/// Move a finished recording into the folder every capture lands in.
///
/// The daemon writes it to a temporary directory and nothing is kept until
/// someone says so — the Mac's editor-first flow. This is the "says so", and
/// it moves rather than copies so a discarded-then-saved recording cannot
/// leave two files behind.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle in by value"
)]
pub fn save_recording(app: AppHandle, path: String, name: String) -> Result<String, DaemonError> {
    let source = Path::new(&path);
    if !source.is_file() {
        return Err(DaemonError::Host(format!("no recording at {path}")));
    }
    let folder = droidective_folder(&app)?;
    let destination = folder.join(crate::commands::safe_file_name(&name)?);
    // Rename first: it is atomic and instant on the same volume. A temporary
    // directory can sit on another one, though, which is what the copy is for.
    if std::fs::rename(source, &destination).is_err() {
        std::fs::copy(source, &destination).map_err(|error| {
            DaemonError::Host(format!("could not save {}: {error}", destination.display()))
        })?;
        let _ = std::fs::remove_file(source);
    }
    Ok(destination.to_string_lossy().into_owned())
}

/// Throw a finished recording away.
///
/// Best-effort by design: the file is in a temporary directory the OS will
/// clear anyway, and a failure here is not worth a message over a recording
/// somebody has already said they do not want.
#[tauri::command]
pub fn discard_recording(path: String) {
    let _ = std::fs::remove_file(path);
}

/// Settings ▸ Tools: what this host can download, and what is on disk.
///
/// Here rather than in `commands.rs` because it is the other half of the same
/// story — screen recording is the reason ffmpeg is downloadable at all on
/// Windows and Linux.
#[tauri::command]
pub async fn managed_tool_list(
    supervisor: State<'_, Supervisor>,
) -> Result<ManagedToolsListResponse, DaemonError> {
    supervisor.client().await?.managed_tool_list().await
}

#[tauri::command]
pub async fn managed_tool_install(
    supervisor: State<'_, Supervisor>,
    id: String,
) -> Result<ManagedToolsListResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .managed_tool_install(&ManagedToolRequest { id })
        .await
}

#[tauri::command]
pub async fn managed_tool_remove(
    supervisor: State<'_, Supervisor>,
    id: String,
) -> Result<ManagedToolsListResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .managed_tool_remove(&ManagedToolRequest { id })
        .await
}
