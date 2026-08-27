//! Metro's debugger endpoints, fetched from Rust rather than the webview.
//!
//! **Metro serves no `Access-Control-Allow-Origin`.** The webview's origin is
//! the app's own, so a `fetch` to `http://localhost:8081/json/list` is
//! cross-origin and the browser refuses it before Metro ever sees it — the
//! console reported "nothing is answering on port 8081" while `curl` to the
//! same URL worked. Rust has no same-origin policy, so the target list comes
//! through here.
//!
//! The debugger **WebSocket** stays in the webview: sockets are not subject
//! to the same-origin policy, and the alternative is a NIO client nobody needs
//! (see `no-urlsession-websocket-offdarwin`).

use crate::error::DaemonError;

/// How long to wait on Metro before calling it absent.
///
/// Short: this is a loopback request to a process that either answers at once
/// or is not running, and the screen polls it.
const TIMEOUT_MS: u64 = 4_000;

fn client() -> Result<reqwest::Client, DaemonError> {
    reqwest::Client::builder()
        // Loopback must never be handed to a proxy — the same reason the daemon
        // client sets this. A machine with HTTP_PROXY set would otherwise send
        // every Metro probe off the box.
        .no_proxy()
        .timeout(std::time::Duration::from_millis(TIMEOUT_MS))
        .build()
        .map_err(|error| DaemonError::Transport(error.to_string()))
}

/// Metro's debugger target list, verbatim.
///
/// Returned as raw JSON rather than typed here: the shape is Metro's, it
/// changes between React Native versions, and `lib/metro.ts` already holds the
/// rules for reading it — the same rules `MetroInspector` uses in the Mac app.
#[tauri::command]
pub async fn metro_targets(port: u16) -> Result<serde_json::Value, DaemonError> {
    let url = format!("http://127.0.0.1:{port}/json/list");
    let response = client()?
        .get(&url)
        .send()
        .await
        .map_err(|error| DaemonError::Transport(error.to_string()))?;
    response
        .json()
        .await
        .map_err(|error| DaemonError::Decode(error.to_string()))
}

/// Whether a Metro dev server is answering on the port.
///
/// `/status` replies `packager-status:running` when it is up. Asked separately
/// from the target list so the screen can tell "Metro is not running" from
/// "Metro is running and no app has connected", which need different advice.
#[tauri::command]
pub async fn metro_running(port: u16) -> Result<bool, DaemonError> {
    let url = format!("http://127.0.0.1:{port}/status");
    let Ok(response) = client()?.get(&url).send().await else {
        return Ok(false);
    };
    let Ok(body) = response.text().await else {
        return Ok(false);
    };
    Ok(body.contains("packager-status:running"))
}
