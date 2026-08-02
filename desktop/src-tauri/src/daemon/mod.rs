//! Owning `droidectived`.
//!
//! The daemon is a sidecar this process spawns, reads a port from, and kills
//! on the way out — not a service. A daemon that outlives its UI is the
//! failure mode the protocol design set out to avoid, so there are two guards:
//! we kill the child on exit, and the child polls `--parent-pid` in case we
//! never get the chance.

pub mod client;
pub mod launch;
pub mod stream;
pub mod wire;

use std::sync::Mutex;
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Manager};
use tauri_plugin_shell::process::{CommandChild, CommandEvent};
use tauri_plugin_shell::ShellExt;
use tokio::sync::RwLock;

use crate::daemon::client::DaemonClient;
use crate::daemon::launch::PortLineScanner;
use crate::daemon::stream::StreamClient;
use crate::error::DaemonError;

/// How long the daemon gets to bind and say so. Generous: a cold start on a
/// loaded machine is slow, and the cost of being wrong is a UI that says the
/// daemon is broken when it was merely slow.
const STARTUP_TIMEOUT: Duration = Duration::from_secs(20);

/// What the UI shows before anything else can happen.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "state", rename_all = "camelCase")]
pub enum DaemonStatus {
    Starting,
    Ready { port: u16 },
    Failed { message: String },
}

struct Running {
    port: u16,
    token: String,
    client: DaemonClient,
    stream: Option<StreamClient>,
}

/// The daemon's lifetime, and the one place that knows its port and token.
#[derive(Default)]
pub struct Supervisor {
    running: RwLock<Option<Running>>,
    status: Mutex<Option<DaemonStatus>>,
    /// Kept only so it can be killed. `CommandChild::kill` consumes it, hence
    /// the `Option`.
    child: Mutex<Option<CommandChild>>,
}

impl Supervisor {
    pub fn status(&self) -> DaemonStatus {
        self.status
            .lock()
            .ok()
            .and_then(|status| status.clone())
            .unwrap_or(DaemonStatus::Starting)
    }

    fn set_status(&self, status: DaemonStatus) {
        if let Ok(mut slot) = self.status.lock() {
            *slot = Some(status);
        }
    }

    /// Spawns the sidecar and waits for its one stdout line.
    pub async fn start(&self, app: &AppHandle) -> Result<u16, DaemonError> {
        self.set_status(DaemonStatus::Starting);
        match self.spawn(app).await {
            Ok(port) => {
                self.set_status(DaemonStatus::Ready { port });
                Ok(port)
            }
            Err(error) => {
                self.set_status(DaemonStatus::Failed {
                    message: error.to_string(),
                });
                Err(error)
            }
        }
    }

    async fn spawn(&self, app: &AppHandle) -> Result<u16, DaemonError> {
        let token_file = token_path(app)?;
        let args = launch::spawn_args(&token_file, std::process::id());

        let (mut events, child) = app
            .shell()
            .sidecar("droidectived")
            .map_err(|error| DaemonError::Launch(error.to_string()))?
            .args(args)
            .spawn()
            .map_err(|error| DaemonError::Launch(error.to_string()))?;

        if let Ok(mut slot) = self.child.lock() {
            *slot = Some(child);
        }

        let port = tokio::time::timeout(STARTUP_TIMEOUT, async {
            let mut scanner = PortLineScanner::default();
            // Kept so a failure to start can be reported with the daemon's own
            // words instead of "it didn't work".
            let mut complaints = String::new();
            while let Some(event) = events.recv().await {
                match event {
                    CommandEvent::Stdout(bytes) => {
                        if let Some(port) = scanner.push(&String::from_utf8_lossy(&bytes)) {
                            return Ok(port);
                        }
                    }
                    CommandEvent::Stderr(bytes) => {
                        complaints.push_str(&String::from_utf8_lossy(&bytes));
                    }
                    CommandEvent::Error(message) => {
                        return Err(DaemonError::Launch(message));
                    }
                    CommandEvent::Terminated(payload) => {
                        return Err(DaemonError::Launch(format!(
                            "it exited with code {:?}. {}",
                            payload.code,
                            complaints.trim()
                        )));
                    }
                    _ => {}
                }
            }
            Err(DaemonError::Launch(
                "its output ended before it reported a port".into(),
            ))
        })
        .await
        .map_err(|_| DaemonError::Launch("it did not report a port in time".into()))??;

        // Nothing reads the daemon's output after startup, but the channel
        // still has to be drained or a chatty daemon eventually blocks on it.
        tokio::spawn(async move { while events.recv().await.is_some() {} });

        // Written before the daemon binds, so it is on disk by the time the
        // port line arrives.
        let token = std::fs::read_to_string(&token_file)
            .map_err(|error| DaemonError::Launch(format!("cannot read its token file: {error}")))?
            .trim()
            .to_string();

        let client = DaemonClient::new(port, token.clone())?;
        *self.running.write().await = Some(Running {
            port,
            token,
            client,
            stream: None,
        });
        Ok(port)
    }

    pub async fn client(&self) -> Result<DaemonClient, DaemonError> {
        let running = self.running.read().await;
        running
            .as_ref()
            .map(|running| running.client.clone())
            .ok_or(DaemonError::NotRunning)
    }

    /// The stream socket, connected on first use and reconnected if it died.
    /// The daemon outlives a dropped socket, so a dead one is worth retrying
    /// rather than treating as the end of the session.
    pub async fn stream(&self) -> Result<StreamClient, DaemonError> {
        if let Some(running) = self.running.read().await.as_ref() {
            if let Some(stream) = &running.stream {
                if !stream.is_closed() {
                    return Ok(stream.clone());
                }
            }
        }

        let mut running = self.running.write().await;
        let running = running.as_mut().ok_or(DaemonError::NotRunning)?;
        // Re-checked under the write lock: two views subscribing at once
        // would otherwise open two sockets and leak one.
        if let Some(stream) = &running.stream {
            if !stream.is_closed() {
                return Ok(stream.clone());
            }
        }
        let stream = StreamClient::connect(running.port, &running.token).await?;
        running.stream = Some(stream.clone());
        Ok(stream)
    }

    /// Kills the daemon. Called on app exit; safe to call twice.
    pub fn shutdown(&self) {
        let child = self.child.lock().ok().and_then(|mut slot| slot.take());
        if let Some(child) = child {
            let _ = child.kill();
        }
    }
}

/// Where the daemon writes its token. Under the app's own data directory, so
/// it inherits that directory's permissions on Windows, where the daemon
/// cannot apply a POSIX mode.
fn token_path(app: &AppHandle) -> Result<String, DaemonError> {
    let directory = app
        .path()
        .app_local_data_dir()
        .map_err(|error| DaemonError::Launch(format!("no data directory: {error}")))?;
    std::fs::create_dir_all(&directory).map_err(|error| {
        DaemonError::Launch(format!("cannot create {}: {error}", directory.display()))
    })?;
    directory
        .join("droidectived.token")
        .to_str()
        .map(str::to_string)
        .ok_or_else(|| DaemonError::Launch("its token path is not valid UTF-8".into()))
}
