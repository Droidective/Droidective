//! Everything the webview can ask for.
//!
//! This is the whole boundary. The webview has no shell, filesystem, or HTTP
//! permission of its own, so the daemon's token and port never leave this
//! process — which is also what keeps the daemon's `Origin` guard meaningful.

use std::sync::Arc;

use serde::{Deserialize, Serialize};
use tauri::ipc::Channel;
use tauri::{AppHandle, State};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_opener::OpenerExt;

use crate::daemon::stream::StreamMessage;
use crate::daemon::wire::{
    AppControlRequest, AppsResponse, Device, FeatureSummary, RunRequest, RunResponse,
    SubscribeParams,
};
use crate::daemon::{DaemonStatus, Supervisor};
use crate::error::DaemonError;

/// One subscription update, shaped like the daemon's own stream event so the
/// UI's handling of a gap or an end is the same code either side of the IPC.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "event", rename_all = "camelCase")]
pub enum StreamUpdate {
    Subscribed,
    Batch { items: Vec<serde_json::Value> },
    Dropped { count: u64 },
    Ended { reason: String },
    Failed { message: String },
}

impl From<StreamMessage> for StreamUpdate {
    fn from(message: StreamMessage) -> Self {
        match message {
            StreamMessage::Subscribed => Self::Subscribed,
            StreamMessage::Batch(items) => Self::Batch { items },
            StreamMessage::Dropped(count) => Self::Dropped { count },
            StreamMessage::Ended(reason) => Self::Ended { reason },
            StreamMessage::Failed(message) => Self::Failed { message },
        }
    }
}

/// A run request as the UI sends it. Field values arrive as bare JSON scalars,
/// which is what the daemon's `ActionProtocol.Value` decodes.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RunActionArgs {
    pub feature_id: String,
    pub serial: String,
    pub platform: Option<String>,
    pub fields: Option<serde_json::Map<String, serde_json::Value>>,
}

#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands State in by value"
)]
pub fn daemon_status(supervisor: State<'_, Supervisor>) -> DaemonStatus {
    supervisor.status()
}

#[tauri::command]
pub async fn list_devices(supervisor: State<'_, Supervisor>) -> Result<Vec<Device>, DaemonError> {
    supervisor.client().await?.list_devices().await
}

#[tauri::command]
pub async fn list_features(
    supervisor: State<'_, Supervisor>,
) -> Result<Vec<FeatureSummary>, DaemonError> {
    supervisor.client().await?.list_features().await
}

#[tauri::command]
pub async fn run_action(
    supervisor: State<'_, Supervisor>,
    args: RunActionArgs,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .run_action(&RunRequest {
            feature_id: args.feature_id,
            serial: args.serial,
            platform: args.platform,
            fields: args.fields,
        })
        .await
}

#[tauri::command]
pub async fn list_apps(
    supervisor: State<'_, Supervisor>,
    serial: String,
) -> Result<AppsResponse, DaemonError> {
    supervisor.client().await?.list_apps(serial).await
}

#[tauri::command]
pub async fn control_app(
    supervisor: State<'_, Supervisor>,
    serial: String,
    package_id: String,
    action: String,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .control_app(&AppControlRequest {
            serial,
            package_id,
            action,
        })
        .await
}

/// Puts an action's `copyText` on the system clipboard.
///
/// Here rather than `navigator.clipboard` in the webview: that needs a secure
/// context and a user gesture the browser agrees was one, and on `WebKitGTK` it
/// can fail silently — which is the exact defect this replaces. A command
/// either works or returns an error the UI can show.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle in by value"
)]
pub fn copy_text(app: AppHandle, text: String) -> Result<(), DaemonError> {
    app.clipboard()
        .write_text(text)
        .map_err(|error| DaemonError::Host(format!("could not copy to the clipboard: {error}")))
}

/// Shows a file in the system file manager — the affordance behind an action
/// that reports where it saved something.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle in by value"
)]
pub fn reveal_path(app: AppHandle, path: String) -> Result<(), DaemonError> {
    app.opener()
        .reveal_item_in_dir(&path)
        .map_err(|error| DaemonError::Host(format!("could not open {path}: {error}")))
}

/// Subscribes to the device list. Returns the id to pass to `stop_watching`.
#[tauri::command]
pub async fn watch_devices(
    supervisor: State<'_, Supervisor>,
    on_event: Channel<StreamUpdate>,
) -> Result<i64, DaemonError> {
    let stream = supervisor.stream().await?;
    stream.subscribe("devices", None, forward(on_event))
}

#[tauri::command]
pub async fn watch_logcat(
    supervisor: State<'_, Supervisor>,
    serial: String,
    filter: Option<String>,
    on_event: Channel<StreamUpdate>,
) -> Result<i64, DaemonError> {
    let stream = supervisor.stream().await?;
    stream.subscribe(
        "logcat",
        Some(SubscribeParams {
            serial: Some(serial),
            filter,
        }),
        forward(on_event),
    )
}

#[tauri::command]
pub async fn stop_watching(supervisor: State<'_, Supervisor>, id: i64) -> Result<(), DaemonError> {
    // A stream that never came up is not an error to tear down — the view
    // unmounting should not have to know whether its subscription succeeded.
    match supervisor.stream().await {
        Ok(stream) => stream.unsubscribe(id),
        Err(DaemonError::NotRunning) => Ok(()),
        Err(error) => Err(error),
    }
}

/// Bridges a stream subscription onto an IPC channel. A send failure means the
/// webview dropped its end; the subsequent `stop_watching` does the cleanup.
fn forward(channel: Channel<StreamUpdate>) -> crate::daemon::stream::StreamSink {
    Arc::new(move |message| {
        let _ = channel.send(StreamUpdate::from(message));
    })
}
