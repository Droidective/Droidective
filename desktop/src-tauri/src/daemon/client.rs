//! The request/response half of the protocol.

use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::daemon::wire::{
    AppControlRequest, AppInfoResponse, AppPullRequest, AppPullResponse, AppRequest,
    AppsListRequest, AppsResponse, CrashListRequest, CrashListResponse, DevSettingsResponse,
    DevSettingsWriteRequest, Device, DevicePropsResponse, DeviceRequest, DevicesResponse,
    DnsResponse, DnsWriteRequest, EmulatorActionRequest, EmulatorsResponse, ErrorEnvelope,
    FeatureSummary, FeaturesResponse, FileInfoRequest, FileInfoResponse, FileOperationRequest,
    FilePullRequest, FilePullResponse, FilesListRequest, FilesListResponse, InstallFormatsResponse,
    InstallRequest, InstallResponse, MemInfoResponse, PermissionWriteRequest, PermissionsResponse,
    RestrictionWriteRequest, RestrictionsResponse, RootStatusResponse, RunRequest, RunResponse,
    SandboxRequest, SandboxResponse, WifiResponse, WifiWriteRequest,
};
use crate::error::DaemonError;

/// A bearer-token HTTP client pinned to one loopback daemon.
#[derive(Clone)]
pub struct DaemonClient {
    base: String,
    token: String,
    http: reqwest::Client,
}

impl DaemonClient {
    pub fn new(port: u16, token: String) -> Result<Self, DaemonError> {
        let http = reqwest::Client::builder()
            // Loopback traffic must never be handed to a proxy. reqwest reads
            // HTTP_PROXY/ALL_PROXY from the environment by default, and on a
            // machine that sets one, every daemon call would leave the box.
            .no_proxy()
            .build()
            .map_err(|error| DaemonError::Transport(error.to_string()))?;
        Ok(Self {
            base: format!("http://127.0.0.1:{port}"),
            token,
            http,
        })
    }

    pub async fn list_devices(&self) -> Result<Vec<Device>, DaemonError> {
        let response: DevicesResponse = self.post("/v1/devices/list", &EMPTY).await?;
        Ok(response.devices)
    }

    pub async fn list_features(&self) -> Result<Vec<FeatureSummary>, DaemonError> {
        let response: FeaturesResponse = self.post("/v1/features/list", &EMPTY).await?;
        Ok(response.features)
    }

    pub async fn run_action(&self, request: &RunRequest) -> Result<RunResponse, DaemonError> {
        self.post("/v1/actions/run", request).await
    }

    pub async fn list_apps(&self, serial: String) -> Result<AppsResponse, DaemonError> {
        self.post("/v1/apps/list", &AppsListRequest { serial })
            .await
    }

    pub async fn device_props(&self, serial: String) -> Result<DevicePropsResponse, DaemonError> {
        self.post("/v1/device/props", &DeviceRequest { serial })
            .await
    }

    pub async fn control_app(
        &self,
        request: &AppControlRequest,
    ) -> Result<RunResponse, DaemonError> {
        self.post("/v1/apps/control", request).await
    }

    pub async fn root_status(&self, serial: String) -> Result<RootStatusResponse, DaemonError> {
        self.post("/v1/device/root", &DeviceRequest { serial })
            .await
    }

    pub async fn list_files(
        &self,
        request: &FilesListRequest,
    ) -> Result<FilesListResponse, DaemonError> {
        self.post("/v1/files/list", request).await
    }

    pub async fn file_operation(
        &self,
        request: &FileOperationRequest,
    ) -> Result<RunResponse, DaemonError> {
        self.post("/v1/files/op", request).await
    }

    pub async fn file_info(
        &self,
        request: &FileInfoRequest,
    ) -> Result<FileInfoResponse, DaemonError> {
        self.post("/v1/files/info", request).await
    }

    pub async fn pull_file(
        &self,
        request: &FilePullRequest,
    ) -> Result<FilePullResponse, DaemonError> {
        self.post("/v1/files/pull", request).await
    }

    pub async fn list_crashes(&self, serial: String) -> Result<CrashListResponse, DaemonError> {
        self.post("/v1/crashes/list", &CrashListRequest { serial })
            .await
    }

    pub async fn clear_crashes(&self, serial: String) -> Result<RunResponse, DaemonError> {
        self.post("/v1/crashes/clear", &CrashListRequest { serial })
            .await
    }

    pub async fn dev_settings(&self, serial: String) -> Result<DevSettingsResponse, DaemonError> {
        self.post("/v1/devsettings/read", &DeviceRequest { serial })
            .await
    }

    pub async fn write_dev_setting(
        &self,
        request: &DevSettingsWriteRequest,
    ) -> Result<RunResponse, DaemonError> {
        self.post("/v1/devsettings/write", request).await
    }

    pub async fn restrictions(&self, serial: String) -> Result<RestrictionsResponse, DaemonError> {
        self.post("/v1/restrictions/read", &DeviceRequest { serial })
            .await
    }

    pub async fn write_restriction(
        &self,
        request: &RestrictionWriteRequest,
    ) -> Result<RunResponse, DaemonError> {
        self.post("/v1/restrictions/write", request).await
    }

    pub async fn wifi(&self, serial: String) -> Result<WifiResponse, DaemonError> {
        self.post("/v1/wifi/read", &DeviceRequest { serial }).await
    }

    pub async fn write_wifi(&self, request: &WifiWriteRequest) -> Result<RunResponse, DaemonError> {
        self.post("/v1/wifi/write", request).await
    }

    pub async fn private_dns(&self, serial: String) -> Result<DnsResponse, DaemonError> {
        self.post("/v1/dns/read", &DeviceRequest { serial }).await
    }

    pub async fn write_private_dns(
        &self,
        request: &DnsWriteRequest,
    ) -> Result<RunResponse, DaemonError> {
        self.post("/v1/dns/write", request).await
    }

    pub async fn app_info(&self, request: &AppRequest) -> Result<AppInfoResponse, DaemonError> {
        self.post("/v1/app/info", request).await
    }

    pub async fn permissions(
        &self,
        request: &AppRequest,
    ) -> Result<PermissionsResponse, DaemonError> {
        self.post("/v1/app/permissions", request).await
    }

    pub async fn set_permission(
        &self,
        request: &PermissionWriteRequest,
    ) -> Result<RunResponse, DaemonError> {
        self.post("/v1/app/permission", request).await
    }

    pub async fn meminfo(&self, request: &AppRequest) -> Result<MemInfoResponse, DaemonError> {
        self.post("/v1/app/meminfo", request).await
    }

    pub async fn sandbox_list(
        &self,
        request: &SandboxRequest,
    ) -> Result<SandboxResponse, DaemonError> {
        self.post("/v1/app/sandbox/list", request).await
    }

    pub async fn sandbox_pull(
        &self,
        request: &AppPullRequest,
    ) -> Result<AppPullResponse, DaemonError> {
        self.post("/v1/app/sandbox/pull", request).await
    }

    pub async fn emulators(&self) -> Result<EmulatorsResponse, DaemonError> {
        self.post("/v1/emulators/list", &EMPTY).await
    }

    pub async fn emulator_action(
        &self,
        request: &EmulatorActionRequest,
    ) -> Result<RunResponse, DaemonError> {
        self.post("/v1/emulators/action", request).await
    }

    pub async fn install_formats(&self) -> Result<InstallFormatsResponse, DaemonError> {
        self.post("/v1/install/formats", &EMPTY).await
    }

    pub async fn install(&self, request: &InstallRequest) -> Result<InstallResponse, DaemonError> {
        self.post("/v1/install/run", request).await
    }

    pub async fn pull_apk(&self, request: &AppPullRequest) -> Result<AppPullResponse, DaemonError> {
        self.post("/v1/app/apk/pull", request).await
    }

    /// One request path, so every route shares one error contract.
    ///
    /// `Host` comes from the URL and no `Origin` is ever sent, which is what
    /// gets us past the daemon's rebinding guards — a webview talking to
    /// 127.0.0.1 directly would fail both.
    async fn post<Body: Serialize + ?Sized, Reply: DeserializeOwned>(
        &self,
        path: &str,
        body: &Body,
    ) -> Result<Reply, DaemonError> {
        let response = self
            .http
            .post(format!("{}{path}", self.base))
            .bearer_auth(&self.token)
            .json(body)
            .send()
            .await
            .map_err(|error| DaemonError::Transport(error.to_string()))?;

        let status = response.status();
        let bytes = response
            .bytes()
            .await
            .map_err(|error| DaemonError::Transport(error.to_string()))?;

        if !status.is_success() {
            // A non-zero adb exit is *not* one of these: the daemon answers
            // 200 with `ok:false` for that, and flattening the two would lose
            // the distinction `AdbClient` exists to preserve.
            return Err(match serde_json::from_slice::<ErrorEnvelope>(&bytes) {
                Ok(envelope) => DaemonError::Refused {
                    code: envelope.error.code,
                    message: envelope.error.message,
                    detail: envelope.error.detail,
                },
                Err(_) => DaemonError::Transport(format!("HTTP {}", status.as_u16())),
            });
        }

        serde_json::from_slice(&bytes).map_err(|error| DaemonError::Decode(error.to_string()))
    }
}

/// The no-argument routes still take a JSON body; an empty object is the
/// smallest thing the daemon's decoder accepts.
static EMPTY: &str = "{}";

#[cfg(test)]
#[expect(
    clippy::panic_in_result_fn,
    reason = "an assertion is how a test reports failure; the Result is for the setup steps"
)]
mod tests {
    use std::error::Error;

    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;
    use tokio::task::JoinHandle;

    use super::DaemonClient;
    use crate::daemon::wire::{
        FileInfoRequest, FileOperationRequest, FilesListRequest, RunRequest,
    };
    use crate::error::DaemonError;

    /// What the fake daemon saw. Asserting on the request is the point: the
    /// headers here are what the real daemon's guards check.
    struct Captured {
        request_line: String,
        headers: Vec<(String, String)>,
        body: String,
    }

    impl Captured {
        fn header(&self, name: &str) -> Option<&str> {
            self.headers
                .iter()
                .find(|(key, _)| key.eq_ignore_ascii_case(name))
                .map(|(_, value)| value.as_str())
        }
    }

    /// A one-shot HTTP/1.1 server on a loopback port. Small enough to be
    /// obviously correct, and it means the client is tested over a real
    /// socket rather than against a mock of itself.
    async fn fake_daemon(
        status: u16,
        body: &'static str,
    ) -> Result<(u16, JoinHandle<Result<Captured, std::io::Error>>), Box<dyn Error>> {
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let port = listener.local_addr()?.port();
        let handle = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await?;
            let mut raw = Vec::new();
            let mut chunk = [0_u8; 1024];
            // Read headers, then exactly as many body bytes as declared.
            let (head_end, content_length) = loop {
                let read = socket.read(&mut chunk).await?;
                if read == 0 {
                    break (raw.len(), 0);
                }
                raw.extend_from_slice(&chunk[..read]);
                if let Some(end) = find_double_crlf(&raw) {
                    let head = String::from_utf8_lossy(&raw[..end]).to_string();
                    let length = head
                        .lines()
                        .find_map(|line| {
                            let (key, value) = line.split_once(':')?;
                            key.eq_ignore_ascii_case("content-length")
                                .then(|| value.trim().parse::<usize>().ok())?
                        })
                        .unwrap_or(0);
                    break (end + 4, length);
                }
            };
            while raw.len() < head_end + content_length {
                let read = socket.read(&mut chunk).await?;
                if read == 0 {
                    break;
                }
                raw.extend_from_slice(&chunk[..read]);
            }

            let head = String::from_utf8_lossy(&raw[..head_end.saturating_sub(4)]).to_string();
            let mut lines = head.lines();
            let request_line = lines.next().unwrap_or_default().to_string();
            let headers = lines
                .filter_map(|line| {
                    let (key, value) = line.split_once(':')?;
                    Some((key.trim().to_string(), value.trim().to_string()))
                })
                .collect();
            let body_text = String::from_utf8_lossy(&raw[head_end.min(raw.len())..]).to_string();

            let reason = if status == 200 { "OK" } else { "Error" };
            let response = format!(
                "HTTP/1.1 {status} {reason}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            socket.write_all(response.as_bytes()).await?;
            socket.flush().await?;
            Ok(Captured {
                request_line,
                headers,
                body: body_text,
            })
        });
        Ok((port, handle))
    }

    fn find_double_crlf(bytes: &[u8]) -> Option<usize> {
        bytes.windows(4).position(|window| window == b"\r\n\r\n")
    }

    #[tokio::test]
    async fn a_request_carries_the_bearer_token_a_loopback_host_and_no_origin(
    ) -> Result<(), Box<dyn Error>> {
        let (port, server) = fake_daemon(200, r#"{"devices":[]}"#).await?;
        let client = DaemonClient::new(port, "secret-token".into())?;
        client.list_devices().await?;

        let captured = server.await??;
        assert_eq!(captured.request_line, "POST /v1/devices/list HTTP/1.1");
        assert_eq!(
            captured.header("authorization"),
            Some("Bearer secret-token")
        );
        assert_eq!(
            captured.header("host"),
            Some(format!("127.0.0.1:{port}").as_str())
        );
        // The daemon refuses a foreign Origin, and a webview would send one.
        // Rust sending none is exactly why the token stays out of the webview.
        assert_eq!(captured.header("origin"), None);
        Ok(())
    }

    #[tokio::test]
    async fn decodes_a_device_list() -> Result<(), Box<dyn Error>> {
        let payload = r#"{"devices":[{"serial":"emulator-5554","state":"device","model":"sdk_gphone64_arm64","product":null,"transportId":"3","label":"Pixel 7 (5554)","isWireless":false,"platform":"android"}]}"#;
        let (port, server) = fake_daemon(200, payload).await?;
        let client = DaemonClient::new(port, "t".into())?;

        let devices = client.list_devices().await?;
        server.await??;

        assert_eq!(devices.len(), 1);
        let device = devices.first().ok_or("one device")?;
        assert_eq!(device.serial, "emulator-5554");
        assert_eq!(device.label, "Pixel 7 (5554)");
        assert_eq!(device.platform, "android");
        assert!(!device.is_wireless);
        Ok(())
    }

    #[tokio::test]
    async fn a_failed_action_is_a_200_not_an_error() -> Result<(), Box<dyn Error>> {
        // The protocol's sharpest edge: adb saying no is an answer, not a
        // transport fault, and it must not surface as a rejected promise.
        let payload = r#"{"ok":false,"message":"Device offline","copyText":null,"revealPath":null,"needsAdbKeyboard":false}"#;
        let (port, server) = fake_daemon(200, payload).await?;
        let client = DaemonClient::new(port, "t".into())?;

        let response = client
            .run_action(&RunRequest {
                feature_id: "dark-mode".into(),
                serial: "emulator-5554".into(),
                platform: Some("android".into()),
                fields: None,
            })
            .await?;

        let captured = server.await??;
        assert_eq!(captured.request_line, "POST /v1/actions/run HTTP/1.1");
        assert!(captured.body.contains(r#""featureId":"dark-mode""#));
        assert!(!response.ok);
        assert_eq!(response.message, "Device offline");
        Ok(())
    }

    #[tokio::test]
    async fn a_file_operation_sends_the_daemons_own_field_names() -> Result<(), Box<dyn Error>> {
        // These structs are a hand-written mirror of Swift types no compiler
        // checks them against, and `asRoot` is the one whose loss is silent:
        // a dropped root flag browses the wrong filesystem without an error.
        let payload = r#"{"ok":true,"message":"Deleted","copyText":null,"revealPath":null,"needsAdbKeyboard":false}"#;
        let (port, server) = fake_daemon(200, payload).await?;
        let client = DaemonClient::new(port, "t".into())?;

        let response = client
            .file_operation(&FileOperationRequest {
                serial: "emulator-5554".into(),
                op: "delete".into(),
                path: "/sdcard/a b".into(),
                destination: None,
                as_root: true,
            })
            .await?;

        let captured = server.await??;
        assert_eq!(captured.request_line, "POST /v1/files/op HTTP/1.1");
        assert!(
            captured.body.contains(r#""asRoot":true"#),
            "{}",
            captured.body
        );
        assert!(
            captured.body.contains(r#""op":"delete""#),
            "{}",
            captured.body
        );
        // Omitted rather than sent as null: the daemon reads a missing
        // destination as "this verb does not take one".
        assert!(!captured.body.contains("destination"), "{}", captured.body);
        assert!(response.ok);
        Ok(())
    }

    #[tokio::test]
    async fn a_listing_decodes_its_entries() -> Result<(), Box<dyn Error>> {
        let payload = r#"{"path":"/sdcard","entries":[{"name":"DCIM","isDir":true,"size":4096,"perms":"drwxrwx---"}]}"#;
        let (port, server) = fake_daemon(200, payload).await?;
        let client = DaemonClient::new(port, "t".into())?;

        let response = client
            .list_files(&FilesListRequest {
                serial: "emulator-5554".into(),
                path: "/sdcard".into(),
                as_root: false,
            })
            .await?;

        server.await??;
        assert_eq!(response.path, "/sdcard");
        let entry = response.entries.first().ok_or("one entry")?;
        assert_eq!(entry.name, "DCIM");
        assert!(entry.is_dir);
        assert_eq!(entry.perms, "drwxrwx---");
        Ok(())
    }

    #[tokio::test]
    async fn a_path_the_device_cannot_stat_decodes_as_no_info() -> Result<(), Box<dyn Error>> {
        let (port, server) = fake_daemon(200, r#"{"info":null}"#).await?;
        let client = DaemonClient::new(port, "t".into())?;

        let response = client
            .file_info(&FileInfoRequest {
                serial: "emulator-5554".into(),
                path: "/sdcard/gone".into(),
                as_root: false,
            })
            .await?;

        server.await??;
        assert!(response.info.is_none());
        Ok(())
    }

    #[tokio::test]
    async fn an_error_body_keeps_the_daemons_own_code() -> Result<(), Box<dyn Error>> {
        let payload = r#"{"error":{"code":"unknown_feature","message":"No such feature, or it has no runner."}}"#;
        let (port, server) = fake_daemon(404, payload).await?;
        let client = DaemonClient::new(port, "t".into())?;

        let failure = client.list_features().await.err().ok_or("should fail")?;
        server.await??;

        match failure {
            DaemonError::Refused { code, message, .. } => {
                assert_eq!(code, "unknown_feature");
                assert_eq!(message, "No such feature, or it has no runner.");
            }
            other => return Err(format!("expected a refusal, got {other:?}").into()),
        }
        Ok(())
    }

    #[tokio::test]
    async fn a_non_json_failure_still_reports_its_status() -> Result<(), Box<dyn Error>> {
        let (port, server) = fake_daemon(502, "bad gateway").await?;
        let client = DaemonClient::new(port, "t".into())?;

        let failure = client.list_devices().await.err().ok_or("should fail")?;
        server.await??;

        match failure {
            DaemonError::Transport(message) => assert!(message.contains("502"), "{message}"),
            other => return Err(format!("expected a transport error, got {other:?}").into()),
        }
        Ok(())
    }

    #[tokio::test]
    async fn a_reply_this_build_cannot_read_is_a_decode_error_not_a_crash(
    ) -> Result<(), Box<dyn Error>> {
        let (port, server) = fake_daemon(200, r#"{"unexpected":true}"#).await?;
        let client = DaemonClient::new(port, "t".into())?;

        let failure = client.list_devices().await.err().ok_or("should fail")?;
        server.await??;

        assert!(matches!(failure, DaemonError::Decode(_)), "{failure:?}");
        Ok(())
    }

    #[tokio::test]
    async fn a_daemon_that_is_not_there_is_a_transport_error() -> Result<(), Box<dyn Error>> {
        // Bind and drop, so the port is almost certainly closed.
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let port = listener.local_addr()?.port();
        drop(listener);

        let client = DaemonClient::new(port, "t".into())?;
        let failure = client.list_devices().await.err().ok_or("should fail")?;
        assert!(matches!(failure, DaemonError::Transport(_)), "{failure:?}");
        Ok(())
    }
}
