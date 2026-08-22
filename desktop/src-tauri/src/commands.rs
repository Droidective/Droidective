//! Everything the webview can ask for.
//!
//! This is the whole boundary. The webview has no shell, filesystem, or HTTP
//! permission of its own, so the daemon's token and port never leave this
//! process — which is also what keeps the daemon's `Origin` guard meaningful.

use std::path::PathBuf;
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use tauri::ipc::Channel;
use tauri::{AppHandle, Manager, State};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_opener::OpenerExt;

use crate::daemon::stream::StreamMessage;
use crate::daemon::wire::{
    AppControlRequest, AppInfoResponse, AppPullRequest, AppPullResponse, AppRequest, AppsResponse,
    BugReportRequest, BugReportResponse, CrashListResponse, DeepLink, DeepLinkLaunchRequest,
    DeepLinksResponse, DeepLinksWriteRequest, DevSettingsResponse, DevSettingsWriteRequest, Device,
    DevicePropsResponse, DnsResponse, DnsWriteRequest, EmulatorActionRequest, EmulatorsResponse,
    FeatureSummary, FileInfoRequest, FileInfoResponse, FileOperationRequest, FilePullRequest,
    FilePullResponse, FilesListRequest, FilesListResponse, InstallRequest, InstallResponse,
    LaunchResponse, MemInfoResponse, PairResponse, PermissionWriteRequest, PermissionsResponse,
    RestrictionWriteRequest, RestrictionsResponse, RootStatusResponse, RunRequest, RunResponse,
    SandboxRequest, SandboxResponse, StreamParams, ToolsResponse, WifiResponse, WifiWriteRequest,
    WirelessActionRequest,
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

#[tauri::command]
pub async fn device_props(
    supervisor: State<'_, Supervisor>,
    serial: String,
) -> Result<DevicePropsResponse, DaemonError> {
    supervisor.client().await?.device_props(serial).await
}

/// Whether this device gives a root shell, and why. Gates the File Explorer's
/// Root toggle the way the Mac's `RootService.detect` does.
#[tauri::command]
pub async fn root_status(
    supervisor: State<'_, Supervisor>,
    serial: String,
) -> Result<RootStatusResponse, DaemonError> {
    supervisor.client().await?.root_status(serial).await
}

#[tauri::command]
pub async fn list_files(
    supervisor: State<'_, Supervisor>,
    serial: String,
    path: String,
    as_root: bool,
) -> Result<FilesListResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .list_files(&FilesListRequest {
            serial,
            path,
            as_root,
        })
        .await
}

/// One mutation — `makeDirectory`, `delete`, `copy` or `move`.
///
/// The verb goes over as the daemon's own string and an unknown one is refused
/// there, before it can reach a device shell. Nothing on this path is quoted
/// here on purpose: `FileExplorerService` does that, and a path mangled in
/// transit would be quoted wrong at the far end.
#[tauri::command]
pub async fn file_operation(
    supervisor: State<'_, Supervisor>,
    serial: String,
    op: String,
    path: String,
    destination: Option<String>,
    as_root: bool,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .file_operation(&FileOperationRequest {
            serial,
            op,
            path,
            destination,
            as_root,
        })
        .await
}

#[tauri::command]
pub async fn file_info(
    supervisor: State<'_, Supervisor>,
    serial: String,
    path: String,
    as_root: bool,
) -> Result<FileInfoResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .file_info(&FileInfoRequest {
            serial,
            path,
            as_root,
        })
        .await
}

/// Pulls one device path into `~/Downloads/Droidective`, answering where it
/// landed.
///
/// The destination is decided **here**, not by the caller and not by the
/// daemon: this is the process that knows where this platform's Downloads
/// folder is, and it is the same folder `export_text` writes to, so someone
/// moving between the two apps finds their files in one place. The leaf name
/// comes off a device path — which is device-controlled data ending up in a
/// host path — so it goes through the same check.
#[tauri::command]
pub async fn pull_file(
    app: AppHandle,
    supervisor: State<'_, Supervisor>,
    serial: String,
    path: String,
    as_root: bool,
) -> Result<FilePullResponse, DaemonError> {
    let folder = droidective_folder(&app)?;
    let destination = folder.join(safe_file_name(leaf_name(&path))?);
    supervisor
        .client()
        .await?
        .pull_file(&FilePullRequest {
            serial,
            path,
            destination: destination.to_string_lossy().into_owned(),
            as_root,
        })
        .await
}

/// Every crash the device has recorded, newest first.
#[tauri::command]
pub async fn list_crashes(
    supervisor: State<'_, Supervisor>,
    serial: String,
) -> Result<CrashListResponse, DaemonError> {
    supervisor.client().await?.list_crashes(serial).await
}

#[tauri::command]
pub async fn clear_crashes(
    supervisor: State<'_, Supervisor>,
    serial: String,
) -> Result<RunResponse, DaemonError> {
    supervisor.client().await?.clear_crashes(serial).await
}

/// Every Developer Options row, definition and current value together.
#[tauri::command]
pub async fn dev_settings(
    supervisor: State<'_, Supervisor>,
    serial: String,
) -> Result<DevSettingsResponse, DaemonError> {
    supervisor.client().await?.dev_settings(serial).await
}

/// Writes one Developer Options row — `on` for a toggle, `value` for a scale.
#[tauri::command]
pub async fn write_dev_setting(
    supervisor: State<'_, Supervisor>,
    serial: String,
    id: String,
    on: Option<bool>,
    value: Option<f64>,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .write_dev_setting(&DevSettingsWriteRequest {
            serial,
            id,
            on,
            value,
        })
        .await
}

/// The dev-time restrictions, plus whether the root-only half is reachable.
#[tauri::command]
pub async fn restrictions(
    supervisor: State<'_, Supervisor>,
    serial: String,
) -> Result<RestrictionsResponse, DaemonError> {
    supervisor.client().await?.restrictions(serial).await
}

/// Writes one restriction, or remounts the system partition (`key: "remount"`).
#[tauri::command]
pub async fn write_restriction(
    supervisor: State<'_, Supervisor>,
    serial: String,
    key: String,
    on: Option<bool>,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .write_restriction(&RestrictionWriteRequest { serial, key, on })
        .await
}

/// The connection, the saved networks, and whether passwords were readable.
#[tauri::command]
pub async fn wifi(
    supervisor: State<'_, Supervisor>,
    serial: String,
) -> Result<WifiResponse, DaemonError> {
    supervisor.client().await?.wifi(serial).await
}

/// Toggles the radio (`enabled`), or connects (`ssid` + `security`).
#[tauri::command]
pub async fn write_wifi(
    supervisor: State<'_, Supervisor>,
    serial: String,
    enabled: Option<bool>,
    ssid: Option<String>,
    security: Option<String>,
    password: Option<String>,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .write_wifi(&WifiWriteRequest {
            serial,
            enabled,
            ssid,
            security,
            password,
        })
        .await
}

#[tauri::command]
pub async fn private_dns(
    supervisor: State<'_, Supervisor>,
    serial: String,
) -> Result<DnsResponse, DaemonError> {
    supervisor.client().await?.private_dns(serial).await
}

/// Version, SDK levels and install dates for the chosen package.
#[tauri::command]
pub async fn app_info(
    supervisor: State<'_, Supervisor>,
    serial: String,
    package_id: String,
) -> Result<AppInfoResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .app_info(&AppRequest { serial, package_id })
        .await
}

#[tauri::command]
pub async fn permissions(
    supervisor: State<'_, Supervisor>,
    serial: String,
    package_id: String,
) -> Result<PermissionsResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .permissions(&AppRequest { serial, package_id })
        .await
}

#[tauri::command]
pub async fn set_permission(
    supervisor: State<'_, Supervisor>,
    serial: String,
    package_id: String,
    permission: String,
    grant: bool,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .set_permission(&PermissionWriteRequest {
            serial,
            package_id,
            permission,
            grant,
        })
        .await
}

#[tauri::command]
pub async fn meminfo(
    supervisor: State<'_, Supervisor>,
    serial: String,
    package_id: String,
) -> Result<MemInfoResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .meminfo(&AppRequest { serial, package_id })
        .await
}

#[tauri::command]
pub async fn sandbox_list(
    supervisor: State<'_, Supervisor>,
    serial: String,
    package_id: String,
    path: String,
) -> Result<SandboxResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .sandbox_list(&SandboxRequest {
            serial,
            package_id,
            path,
        })
        .await
}

/// Pulls one sandbox file into `~/Downloads/Droidective`.
///
/// The destination is chosen here for the reason `pull_file`'s is: this is the
/// process that knows where this platform's Downloads folder lives, and the
/// leaf comes off a device path, so it goes through the same name check.
#[tauri::command]
pub async fn sandbox_pull(
    app: AppHandle,
    supervisor: State<'_, Supervisor>,
    serial: String,
    package_id: String,
    path: String,
) -> Result<AppPullResponse, DaemonError> {
    let destination = droidective_folder(&app)?.join(safe_file_name(leaf_name(&path))?);
    supervisor
        .client()
        .await?
        .sandbox_pull(&AppPullRequest {
            serial,
            package_id,
            path: Some(path),
            destination: destination.to_string_lossy().into_owned(),
        })
        .await
}

/// Pulls the package's APK — and its splits, which land beside it.
#[tauri::command]
pub async fn pull_apk(
    app: AppHandle,
    supervisor: State<'_, Supervisor>,
    serial: String,
    package_id: String,
) -> Result<AppPullResponse, DaemonError> {
    // The package id is device-reported and ends up in a host path, so it goes
    // through the same check every other leaf name does.
    let destination = droidective_folder(&app)?.join(safe_file_name(&format!("{package_id}.apk"))?);
    supervisor
        .client()
        .await?
        .pull_apk(&AppPullRequest {
            serial,
            package_id,
            path: None,
            destination: destination.to_string_lossy().into_owned(),
        })
        .await
}

#[tauri::command]
pub async fn write_private_dns(
    supervisor: State<'_, Supervisor>,
    serial: String,
    mode: String,
    hostname: Option<String>,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .write_private_dns(&DnsWriteRequest {
            serial,
            mode,
            hostname,
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

/// Where pulls and exports land — `~/Downloads/Droidective`.
///
/// Answered rather than assumed by the UI: this process is the one that
/// resolves the platform's Downloads folder, and Settings showing a path the
/// files do not actually go to would be worse than showing none.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle in by value"
)]
pub fn captures_folder(app: AppHandle) -> Result<String, DaemonError> {
    Ok(droidective_folder(&app)?.to_string_lossy().into_owned())
}

/// Opens an external URL in the default browser.
///
/// Only `https://` is opened, and the check is here rather than at the call
/// site: this command is the boundary, and a `file://` or a custom scheme
/// reaching the OS opener is the difference between showing a web page and
/// launching something. The About screen's links are the only caller today,
/// but a boundary that trusts its caller is not a boundary.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle in by value"
)]
pub fn open_url(app: AppHandle, url: String) -> Result<(), DaemonError> {
    if !url.starts_with("https://") {
        return Err(DaemonError::Host(format!("refusing to open {url}")));
    }
    app.opener()
        .open_url(url.clone(), None::<&str>)
        .map_err(|error| DaemonError::Host(format!("could not open {url}: {error}")))
}

/// Writes text into `~/Downloads/Droidective/<name>` and returns the path.
///
/// The Mac exports there too, so someone moving between the two finds their
/// files in the same place. A fixed folder rather than a save dialog: it is one
/// fewer plugin, one fewer capability, and the path comes back for the Show in
/// folder button to use.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle in by value"
)]
pub fn export_text(app: AppHandle, name: String, contents: String) -> Result<String, DaemonError> {
    let folder = droidective_folder(&app)?;
    let path = folder.join(safe_file_name(&name)?);
    std::fs::write(&path, contents).map_err(|error| {
        DaemonError::Host(format!("could not write {}: {error}", path.display()))
    })?;
    Ok(path.to_string_lossy().into_owned())
}

/// `~/Downloads/Droidective`, created if it is not there yet.
///
/// The one place this app decides where files land, shared by `export_text`
/// and `pull_file` — two answers to that question is how a Show in folder
/// button ends up pointing at the wrong one.
fn droidective_folder(app: &AppHandle) -> Result<PathBuf, DaemonError> {
    let folder = app
        .path()
        .download_dir()
        .map_err(|error| DaemonError::Host(format!("no Downloads folder: {error}")))?
        .join("Droidective");
    std::fs::create_dir_all(&folder).map_err(|error| {
        DaemonError::Host(format!("could not create {}: {error}", folder.display()))
    })?;
    Ok(folder)
}

/// The last path component, for either separator.
///
/// Both, because the input is a *device* path read with `/` — but a device is
/// free to answer with a name containing `\`, which is a separator once this
/// reaches Windows.
fn leaf_name(path: &str) -> &str {
    path.rsplit(['/', '\\']).next().unwrap_or(path)
}

/// A name that may safely be joined onto a folder.
///
/// Everything reaching here is about to become a host path, and some of it is
/// device-controlled: a filename comes from `ls` on a phone this app does not
/// own. `Path::join` is happy to escape its parent given `..`, an absolute
/// path, or — the one that is easy to miss — a Windows drive-relative name like
/// `C:x`, where `join` throws the folder away entirely.
fn safe_file_name(name: &str) -> Result<&str, DaemonError> {
    let refused = name.is_empty()
        || name == "."
        || name == ".."
        || name.contains('/')
        || name.contains('\\')
        || name.contains(':')
        || name.contains('\0');
    if refused {
        return Err(DaemonError::Host(format!("refusing to write {name:?}")));
    }
    Ok(name)
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
        Some(StreamParams {
            serial: Some(serial),
            filter,
            ..StreamParams::default()
        }),
        forward(on_event),
    )
}

/// Greys the menu's terminal commands in or out.
///
/// Called by the Terminal pane as it mounts and unmounts, because it is the
/// only thing that knows whether there is a shell to act on — the same reason
/// the Mac's `terminalCommandsEnabled` reads `AppState.terminals`.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle in by value"
)]
pub fn set_terminal_commands_enabled(app: AppHandle, enabled: bool) {
    crate::menu::set_terminal_commands_enabled(&app, enabled);
}

/// Opens a shell on a pseudo-terminal. Returns the id to pass to
/// `write_terminal`, `resize_terminal` and `stop_watching`.
///
/// `serial` is optional and only exports `ANDROID_SERIAL` into the shell, so
/// every adb command inside it targets that device without `-s` — the way the
/// Mac's terminal scopes a tab. A terminal opens with nothing connected.
#[tauri::command]
pub async fn open_terminal(
    supervisor: State<'_, Supervisor>,
    serial: Option<String>,
    columns: u16,
    rows: u16,
    on_event: Channel<StreamUpdate>,
) -> Result<i64, DaemonError> {
    let stream = supervisor.stream().await?;
    stream.subscribe(
        "pty",
        Some(StreamParams {
            serial,
            columns: Some(columns),
            rows: Some(rows),
            ..StreamParams::default()
        }),
        forward(on_event),
    )
}

/// Keystrokes into a terminal. `data` is base64: terminal input is bytes,
/// including the control codes a JSON string cannot carry.
#[tauri::command]
pub async fn write_terminal(
    supervisor: State<'_, Supervisor>,
    id: i64,
    data: String,
) -> Result<(), DaemonError> {
    supervisor.stream().await?.write(id, data)
}

#[tauri::command]
pub async fn resize_terminal(
    supervisor: State<'_, Supervisor>,
    id: i64,
    columns: u16,
    rows: u16,
) -> Result<(), DaemonError> {
    supervisor.stream().await?.resize(id, columns, rows)
}

/// Live performance samples, one a second, until `stop_watching`.
#[tauri::command]
pub async fn watch_performance(
    supervisor: State<'_, Supervisor>,
    serial: String,
    package_id: Option<String>,
    processes: bool,
    on_event: Channel<StreamUpdate>,
) -> Result<i64, DaemonError> {
    let stream = supervisor.stream().await?;
    stream.subscribe(
        "performance",
        Some(StreamParams {
            serial: Some(serial),
            package_id,
            processes: Some(processes),
            ..StreamParams::default()
        }),
        forward(on_event),
    )
}

/// Picks a package and installs it onto the given devices.
///
/// The picker runs **here**, not in the webview: a webview drag hands over a
/// `File` with no path, and the daemon needs a real one. It is also why the
/// dialog plugin is registered for its Rust API only — the page cannot open a
/// dialog on its own.
///
/// Answers `None` when the picker was dismissed, which is a choice rather than
/// a failure and must not surface as an error.
#[tauri::command]
pub async fn pick_and_install(
    app: AppHandle,
    supervisor: State<'_, Supervisor>,
    serials: Vec<String>,
) -> Result<Option<InstallResponse>, DaemonError> {
    let client = supervisor.client().await?;
    let extensions = client.install_formats().await?.extensions;
    let filters: Vec<&str> = extensions.iter().map(String::as_str).collect();

    let picked = app
        .dialog()
        .file()
        .add_filter("App package", &filters)
        .blocking_pick_file();
    let Some(picked) = picked else {
        return Ok(None);
    };

    let path = picked
        .into_path()
        .map_err(|error| DaemonError::Host(format!("could not read that file: {error}")))?;
    let response = client
        .install(&InstallRequest {
            serials,
            path: path.to_string_lossy().into_owned(),
        })
        .await?;
    Ok(Some(response))
}

/// Every AVD on this machine, and whether the emulator binary is here at all.
#[tauri::command]
pub async fn emulators(
    supervisor: State<'_, Supervisor>,
) -> Result<EmulatorsResponse, DaemonError> {
    supervisor.client().await?.emulators().await
}

/// Launch, cold-boot, wipe, relaunch or stop one AVD.
#[tauri::command]
pub async fn emulator_action(
    supervisor: State<'_, Supervisor>,
    avd: Option<String>,
    serial: Option<String>,
    action: String,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .emulator_action(&EmulatorActionRequest {
            avd,
            serial,
            action,
        })
        .await
}

/// Android 11+ pairing. The reply carries the endpoint the device then
/// advertised, so the sheet can connect without asking for a port the phone
/// never showed.
#[tauri::command]
pub async fn pair_wireless(
    supervisor: State<'_, Supervisor>,
    endpoint: String,
    code: String,
) -> Result<PairResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .pair_wireless(&WirelessActionRequest {
            action: "pair".to_owned(),
            endpoint: Some(endpoint),
            code: Some(code),
            serial: None,
        })
        .await
}

/// `adb connect`. A bare host takes adb's own default port, which the daemon
/// applies — this side never invents one.
#[tauri::command]
pub async fn connect_wireless(
    supervisor: State<'_, Supervisor>,
    endpoint: String,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .wireless_action(&WirelessActionRequest {
            action: "connect".to_owned(),
            endpoint: Some(endpoint),
            code: None,
            serial: None,
        })
        .await
}

/// `adb disconnect`. No serial means every wireless device.
#[tauri::command]
pub async fn disconnect_wireless(
    supervisor: State<'_, Supervisor>,
    serial: Option<String>,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .wireless_action(&WirelessActionRequest {
            action: "disconnect".to_owned(),
            endpoint: None,
            code: None,
            serial,
        })
        .await
}

/// `adb tcpip 5555` on a USB device, then connect to its Wi-Fi address.
#[tauri::command]
pub async fn enable_tcpip(
    supervisor: State<'_, Supervisor>,
    serial: String,
) -> Result<RunResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .wireless_action(&WirelessActionRequest {
            action: "tcpip".to_owned(),
            endpoint: None,
            code: None,
            serial: Some(serial),
        })
        .await
}

/// One app's saved deep links.
#[tauri::command]
pub async fn deep_links(
    supervisor: State<'_, Supervisor>,
    package_id: String,
) -> Result<DeepLinksResponse, DaemonError> {
    supervisor.client().await?.deep_links(package_id).await
}

/// Replaces one app's list, and answers with what was stored.
#[tauri::command]
pub async fn write_deep_links(
    supervisor: State<'_, Supervisor>,
    package_id: String,
    links: Vec<DeepLink>,
) -> Result<DeepLinksResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .write_deep_links(&DeepLinksWriteRequest { package_id, links })
        .await
}

/// Launches one url on every targeted device, answering per device.
#[tauri::command]
pub async fn launch_deep_link(
    supervisor: State<'_, Supervisor>,
    serials: Vec<String>,
    url: String,
) -> Result<LaunchResponse, DaemonError> {
    supervisor
        .client()
        .await?
        .launch_deep_link(&DeepLinkLaunchRequest { serials, url })
        .await
}

/// Builds the bug-report zip into the same folder every other download lands
/// in, and answers where it went.
#[tauri::command]
pub async fn create_bug_report(
    app: AppHandle,
    supervisor: State<'_, Supervisor>,
    serial: String,
    package_id: Option<String>,
) -> Result<BugReportResponse, DaemonError> {
    let folder = droidective_folder(&app)?;
    supervisor
        .client()
        .await?
        .create_bug_report(&BugReportRequest {
            serial,
            package_id,
            destination: folder.to_string_lossy().into_owned(),
        })
        .await
}

/// Which external tools are on this machine — the Doctor, and the device bar's
/// adb warning.
#[tauri::command]
pub async fn detect_tools(supervisor: State<'_, Supervisor>) -> Result<ToolsResponse, DaemonError> {
    supervisor.client().await?.detect_tools().await
}

/// Live `/proc/net/dev` throughput, one sample a second, until `stop_watching`.
#[tauri::command]
pub async fn watch_netspeed(
    supervisor: State<'_, Supervisor>,
    serial: String,
    on_event: Channel<StreamUpdate>,
) -> Result<i64, DaemonError> {
    let stream = supervisor.stream().await?;
    stream.subscribe(
        "netspeed",
        Some(StreamParams {
            serial: Some(serial),
            ..StreamParams::default()
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

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::{leaf_name, safe_file_name};

    #[test]
    fn a_leaf_is_taken_off_either_separator() {
        assert_eq!(leaf_name("/sdcard/DCIM/photo.jpg"), "photo.jpg");
        // A device may answer with a backslash in a name; on Windows that is a
        // separator by the time it reaches `join`.
        assert_eq!(leaf_name(r"/sdcard/weird\name"), "name");
        assert_eq!(leaf_name("photo.jpg"), "photo.jpg");
        assert_eq!(leaf_name("/sdcard/"), "");
    }

    #[test]
    fn an_ordinary_name_is_allowed_through_unchanged() {
        assert_eq!(
            safe_file_name("getprop_emulator-5554.txt").ok(),
            Some("getprop_emulator-5554.txt")
        );
        // `..` inside a name is only a name; it is `..` *as* the name that walks.
        assert_eq!(
            safe_file_name("backup..2026.txt").ok(),
            Some("backup..2026.txt")
        );
    }

    #[test]
    fn nothing_that_can_leave_the_folder_gets_through() {
        for name in ["", ".", "..", "a/b", r"a\b", "/etc/passwd", "sub/../../x"] {
            assert!(safe_file_name(name).is_err(), "{name:?} should be refused");
        }
    }

    #[test]
    fn a_windows_drive_relative_name_is_refused() {
        // The one that does not look dangerous: `join` does not append a
        // drive-relative path, it *replaces* what it was joined onto.
        assert!(safe_file_name("C:evil.txt").is_err());
        assert_eq!(
            Path::new("/tmp/Droidective").join("C:evil.txt"),
            Path::new(if cfg!(windows) {
                "C:evil.txt"
            } else {
                "/tmp/Droidective/C:evil.txt"
            }),
            "the refusal is what stands between this and writing outside the folder",
        );
    }
}
