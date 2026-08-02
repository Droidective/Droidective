//! The request/response half of the protocol.

use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::daemon::wire::{
    AppControlRequest, AppsListRequest, AppsResponse, Device, DevicesResponse, ErrorEnvelope,
    FeatureSummary, FeaturesResponse, RunRequest, RunResponse,
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

    pub async fn control_app(
        &self,
        request: &AppControlRequest,
    ) -> Result<RunResponse, DaemonError> {
        self.post("/v1/apps/control", request).await
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
    use crate::daemon::wire::RunRequest;
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
