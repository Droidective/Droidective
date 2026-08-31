//! The API Testing boundary.
//!
//! Its own module rather than more of `commands.rs`, which is already the
//! longest file here — and because these seven all share one shape: untyped
//! JSON in, untyped JSON out. That is deliberate (see `DaemonClient::api_call`);
//! what keeps it a boundary rather than an open pipe is that the route is a
//! Rust enum, so the webview picks from a closed set instead of naming a path.

use serde_json::{json, Value};
use tauri::State;

use crate::daemon::client::ApiRoute;
use crate::daemon::Supervisor;
use crate::error::DaemonError;

/// The saved workspace: collections, environments, globals, history.
#[tauri::command]
pub async fn api_workspace(supervisor: State<'_, Supervisor>) -> Result<Value, DaemonError> {
    forward(&supervisor, ApiRoute::Read, empty()).await
}

/// Replaces the whole document.
///
/// The whole document rather than a patch, for the reason the deep links and
/// the custom commands take the whole list: this side holds what it is
/// showing, so a per-item verb would only make the daemon re-derive it.
#[tauri::command]
pub async fn api_write(
    supervisor: State<'_, Supervisor>,
    data: Value,
) -> Result<Value, DaemonError> {
    forward(&supervisor, ApiRoute::Write, json!({ "data": data })).await
}

/// Sends one request and answers with everything it produced.
///
/// Through the daemon rather than the webview's own `fetch`, and not only
/// because of CORS: a browser cannot see a redirect chain, a TLS handshake's
/// timing, or a `Set-Cookie` it was not allowed to read — all of which this
/// screen shows.
#[tauri::command]
pub async fn api_send(
    supervisor: State<'_, Supervisor>,
    request: Value,
) -> Result<Value, DaemonError> {
    forward(&supervisor, ApiRoute::Send, request).await
}

/// Stops an in-flight send.
///
/// A real cancel rather than a client-side "stop showing it": the daemon
/// tears the request down, so a sixty-second timeout someone gave up on does
/// not keep a connection open behind a pane that already moved on.
#[tauri::command]
pub async fn api_cancel(
    supervisor: State<'_, Supervisor>,
    send_id: String,
) -> Result<Value, DaemonError> {
    forward(&supervisor, ApiRoute::Cancel, json!({ "sendId": send_id })).await
}

/// A code snippet for one request, in one of the six targets.
#[tauri::command]
pub async fn api_code(
    supervisor: State<'_, Supervisor>,
    request: Value,
) -> Result<Value, DaemonError> {
    forward(&supervisor, ApiRoute::Code, request).await
}

/// Parses a pasted cURL command line into a request.
#[tauri::command]
pub async fn api_curl(
    supervisor: State<'_, Supervisor>,
    text: String,
) -> Result<Value, DaemonError> {
    forward(&supervisor, ApiRoute::Curl, json!({ "text": text })).await
}

/// Reads a Postman collection, a Postman environment, or a workspace export.
#[tauri::command]
pub async fn api_import(
    supervisor: State<'_, Supervisor>,
    path: String,
) -> Result<Value, DaemonError> {
    forward(&supervisor, ApiRoute::Import, json!({ "path": path })).await
}

/// Builds the JSON for an export, and the name to offer for it.
///
/// The file is written by `export_text`, not here: every export in this app
/// lands in the same folder, and two places deciding where would be how a Show
/// in folder button ends up pointing at the wrong one.
#[tauri::command]
pub async fn api_export(
    supervisor: State<'_, Supervisor>,
    request: Value,
) -> Result<Value, DaemonError> {
    forward(&supervisor, ApiRoute::Export, request).await
}

async fn forward(
    supervisor: &Supervisor,
    route: ApiRoute,
    body: Value,
) -> Result<Value, DaemonError> {
    supervisor.client().await?.api_call(route, &body).await
}

fn empty() -> Value {
    json!({})
}
