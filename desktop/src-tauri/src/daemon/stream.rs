//! The multiplexed stream socket.
//!
//! One WebSocket carries every subscription, keyed by a correlation id we
//! allocate here. The ids never come from the webview: the daemon rejects a
//! duplicate id, and letting a page choose them would make that rejection a
//! bug the UI could trigger.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, Mutex};

use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::HeaderValue;
use tokio_tungstenite::tungstenite::Message;

use crate::daemon::wire::{StreamEvent, SubscribeCommand, SubscribeParams};
use crate::error::DaemonError;

/// One event, already routed to its subscription.
#[derive(Debug, Clone)]
pub enum StreamMessage {
    Subscribed,
    /// Raw items; the caller knows its topic's payload type.
    Batch(Vec<serde_json::Value>),
    /// The daemon's bounded buffer discarded `count` items. Never silent —
    /// the UI is expected to render a visible gap.
    Dropped(u64),
    Ended(String),
    Failed(String),
}

/// Where a subscription's messages go.
pub type StreamSink = Arc<dyn Fn(StreamMessage) + Send + Sync>;

struct Shared {
    sinks: Mutex<HashMap<i64, StreamSink>>,
    next_id: AtomicI64,
    closed: AtomicBool,
}

impl Shared {
    /// Takes a snapshot rather than dispatching under the lock: a sink calls
    /// into Tauri, and holding a mutex across that invites a deadlock.
    fn sink(&self, id: i64) -> Option<StreamSink> {
        self.sinks.lock().ok()?.get(&id).cloned()
    }

    fn drain(&self) -> Vec<StreamSink> {
        let Ok(mut sinks) = self.sinks.lock() else {
            return Vec::new();
        };
        sinks.drain().map(|(_, sink)| sink).collect()
    }
}

/// A live connection to `/v1/stream`.
#[derive(Clone)]
pub struct StreamClient {
    shared: Arc<Shared>,
    outgoing: mpsc::UnboundedSender<Message>,
}

impl StreamClient {
    pub async fn connect(port: u16, token: &str) -> Result<Self, DaemonError> {
        let mut request = format!("ws://127.0.0.1:{port}/v1/stream")
            .into_client_request()
            .map_err(|error| DaemonError::Transport(error.to_string()))?;
        // The upgrade request is auth-checked exactly like a POST, so the
        // token has to ride on the handshake itself. `Host` comes from the
        // URL and no `Origin` is sent — the daemon's other two guards.
        let bearer = HeaderValue::from_str(&format!("Bearer {token}"))
            .map_err(|error| DaemonError::Transport(error.to_string()))?;
        request.headers_mut().insert("Authorization", bearer);

        let (socket, _) = tokio_tungstenite::connect_async(request)
            .await
            .map_err(|error| DaemonError::Transport(error.to_string()))?;

        let shared = Arc::new(Shared {
            sinks: Mutex::new(HashMap::new()),
            next_id: AtomicI64::new(1),
            closed: AtomicBool::new(false),
        });
        let (mut writer, mut reader) = socket.split();
        let (outgoing, mut queue) = mpsc::unbounded_channel::<Message>();

        tokio::spawn(async move {
            while let Some(message) = queue.recv().await {
                if writer.send(message).await.is_err() {
                    break;
                }
            }
        });

        let reading = Arc::clone(&shared);
        tokio::spawn(async move {
            while let Some(Ok(message)) = reader.next().await {
                let Message::Text(text) = message else {
                    continue;
                };
                let Ok(event) = serde_json::from_str::<StreamEvent>(&text) else {
                    // An event kind this build does not know is not a reason
                    // to tear down every other subscription on the socket.
                    continue;
                };
                if let Some(sink) = reading.sink(event.id) {
                    sink(classify(&event));
                }
                if event.event == "ended" {
                    if let Ok(mut sinks) = reading.sinks.lock() {
                        sinks.remove(&event.id);
                    }
                }
            }
            // The socket went away. Tell every live subscription rather than
            // leaving the UI showing a feed that silently stopped.
            reading.closed.store(true, Ordering::SeqCst);
            for sink in reading.drain() {
                sink(StreamMessage::Ended("socket_closed".into()));
            }
        });

        Ok(Self { shared, outgoing })
    }

    pub fn is_closed(&self) -> bool {
        self.shared.closed.load(Ordering::SeqCst)
    }

    /// Registers `sink` and asks the daemon to start the topic. Returns the
    /// correlation id, which is also the unsubscribe handle.
    pub fn subscribe(
        &self,
        topic: &'static str,
        params: Option<SubscribeParams>,
        sink: StreamSink,
    ) -> Result<i64, DaemonError> {
        if self.is_closed() {
            return Err(DaemonError::NotRunning);
        }
        let id = self.shared.next_id.fetch_add(1, Ordering::SeqCst);
        self.shared
            .sinks
            .lock()
            .map_err(|_| DaemonError::Transport("stream registry poisoned".into()))?
            .insert(id, sink);
        self.send(&SubscribeCommand::subscribe(id, topic, params))?;
        Ok(id)
    }

    /// Drops the local sink first, then tells the daemon. In that order a
    /// racing batch cannot reach a view that has already gone away.
    pub fn unsubscribe(&self, id: i64) -> Result<(), DaemonError> {
        if let Ok(mut sinks) = self.shared.sinks.lock() {
            sinks.remove(&id);
        }
        if self.is_closed() {
            return Ok(());
        }
        self.send(&SubscribeCommand::unsubscribe(id))
    }

    fn send(&self, command: &SubscribeCommand) -> Result<(), DaemonError> {
        let text = serde_json::to_string(command)
            .map_err(|error| DaemonError::Decode(error.to_string()))?;
        self.outgoing
            .send(Message::text(text))
            .map_err(|_| DaemonError::NotRunning)
    }
}

fn classify(event: &StreamEvent) -> StreamMessage {
    match event.event.as_str() {
        "batch" => StreamMessage::Batch(event.items.clone().unwrap_or_default()),
        "dropped" => StreamMessage::Dropped(event.count.unwrap_or_default()),
        "ended" => StreamMessage::Ended(
            event
                .reason
                .clone()
                .unwrap_or_else(|| "unspecified".to_string()),
        ),
        "failed" => StreamMessage::Failed(
            event
                .message
                .clone()
                .unwrap_or_else(|| "unspecified".to_string()),
        ),
        _ => StreamMessage::Subscribed,
    }
}

#[cfg(test)]
#[expect(
    clippy::panic_in_result_fn,
    reason = "an assertion is how a test reports failure; the Result is for the setup steps"
)]
mod tests {
    use std::error::Error;
    use std::sync::Arc;
    use std::time::Duration;

    use futures_util::{SinkExt, StreamExt};
    use tokio::net::TcpListener;
    use tokio::sync::mpsc;
    use tokio_tungstenite::tungstenite::Message;

    use super::{StreamClient, StreamMessage};
    use crate::daemon::wire::SubscribeParams;

    /// A fake `/v1/stream`: accepts one client, records the handshake's
    /// Authorization header and the first command, then replays `script`.
    #[expect(
        clippy::result_large_err,
        reason = "the Err type belongs to tungstenite's handshake callback, not to us"
    )]
    async fn fake_stream(
        script: Vec<String>,
    ) -> Result<
        (
            u16,
            tokio::task::JoinHandle<(Option<String>, Option<String>)>,
        ),
        Box<dyn Error>,
    > {
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let port = listener.local_addr()?.port();
        let handle = tokio::spawn(async move {
            let Ok((socket, _)) = listener.accept().await else {
                return (None, None);
            };
            let mut authorization = None;
            let upgraded = tokio_tungstenite::accept_hdr_async(socket, |request: &_, response| {
                let request: &tokio_tungstenite::tungstenite::handshake::server::Request = request;
                authorization = request
                    .headers()
                    .get("Authorization")
                    .and_then(|value| value.to_str().ok())
                    .map(str::to_string);
                Ok(response)
            })
            .await;
            let Ok(mut socket) = upgraded else {
                return (authorization, None);
            };
            let command = match socket.next().await {
                Some(Ok(Message::Text(text))) => Some(text.to_string()),
                _ => None,
            };
            for frame in script {
                if socket.send(Message::text(frame)).await.is_err() {
                    break;
                }
            }
            let _ = socket.close(None).await;
            (authorization, command)
        });
        Ok((port, handle))
    }

    /// Collects sink calls.
    ///
    /// An async channel, not `std::sync::mpsc`: a blocking `recv_timeout` on
    /// the test thread starves the reader task on the current-thread runtime
    /// `#[tokio::test]` gives us, so every one of these tests would hang.
    fn recorder() -> (super::StreamSink, mpsc::UnboundedReceiver<StreamMessage>) {
        let (sender, receiver) = mpsc::unbounded_channel();
        let sink: super::StreamSink = Arc::new(move |message| {
            let _ = sender.send(message);
        });
        (sink, receiver)
    }

    async fn next_message(
        events: &mut mpsc::UnboundedReceiver<StreamMessage>,
    ) -> Result<StreamMessage, Box<dyn Error>> {
        tokio::time::timeout(Duration::from_secs(5), events.recv())
            .await?
            .ok_or_else(|| "the sink was dropped before sending anything".into())
    }

    #[tokio::test]
    async fn the_handshake_carries_the_token_and_the_subscription_reaches_the_daemon(
    ) -> Result<(), Box<dyn Error>> {
        let (port, server) = fake_stream(vec![r#"{"id":1,"event":"subscribed"}"#.into()]).await?;
        let client = StreamClient::connect(port, "secret-token").await?;
        let (sink, mut events) = recorder();

        let id = client.subscribe(
            "logcat",
            Some(SubscribeParams {
                serial: Some("emulator-5554".into()),
                ..SubscribeParams::default()
            }),
            sink,
        )?;
        assert_eq!(id, 1, "ids are allocated here, starting at 1");

        let (authorization, command) = server.await?;
        assert_eq!(authorization.as_deref(), Some("Bearer secret-token"));
        let command = command.ok_or("the daemon should have received a command")?;
        assert!(command.contains(r#""op":"subscribe""#), "{command}");
        assert!(command.contains(r#""topic":"logcat""#), "{command}");
        assert!(command.contains(r#""serial":"emulator-5554""#), "{command}");

        let first = next_message(&mut events).await?;
        assert!(matches!(first, StreamMessage::Subscribed), "{first:?}");
        Ok(())
    }

    #[tokio::test]
    async fn a_batch_and_a_gap_both_reach_the_subscriber() -> Result<(), Box<dyn Error>> {
        let (port, server) = fake_stream(vec![
            r#"{"id":1,"event":"batch","items":[{"tag":"A"},{"tag":"B"}]}"#.into(),
            r#"{"id":1,"event":"dropped","count":17}"#.into(),
            r#"{"id":1,"event":"ended","reason":"device_disconnected"}"#.into(),
        ])
        .await?;
        let client = StreamClient::connect(port, "t").await?;
        let (sink, mut events) = recorder();
        client.subscribe("logcat", None, sink)?;
        server.await?;

        match next_message(&mut events).await? {
            StreamMessage::Batch(items) => assert_eq!(items.len(), 2),
            other => return Err(format!("expected a batch, got {other:?}").into()),
        }
        match next_message(&mut events).await? {
            StreamMessage::Dropped(count) => assert_eq!(count, 17),
            other => return Err(format!("expected a gap, got {other:?}").into()),
        }
        match next_message(&mut events).await? {
            StreamMessage::Ended(reason) => assert_eq!(reason, "device_disconnected"),
            other => return Err(format!("expected an end, got {other:?}").into()),
        }
        Ok(())
    }

    #[tokio::test]
    async fn a_frame_for_an_unknown_id_does_not_disturb_a_live_subscription(
    ) -> Result<(), Box<dyn Error>> {
        let (port, server) = fake_stream(vec![
            r#"{"id":99,"event":"batch","items":[{"stray":true}]}"#.into(),
            r#"{"id":1,"event":"batch","items":[{"mine":true}]}"#.into(),
        ])
        .await?;
        let client = StreamClient::connect(port, "t").await?;
        let (sink, mut events) = recorder();
        client.subscribe("devices", None, sink)?;
        server.await?;

        match next_message(&mut events).await? {
            StreamMessage::Batch(items) => {
                assert_eq!(items.len(), 1);
                assert!(items.first().is_some_and(|item| item["mine"] == true));
            }
            other => return Err(format!("expected my batch, got {other:?}").into()),
        }
        Ok(())
    }

    #[tokio::test]
    async fn a_dead_socket_ends_every_live_subscription() -> Result<(), Box<dyn Error>> {
        // Nothing scripted: the server accepts, then hangs up.
        let (port, server) = fake_stream(Vec::new()).await?;
        let client = StreamClient::connect(port, "t").await?;
        let (sink, mut events) = recorder();
        client.subscribe("logcat", None, sink)?;
        server.await?;

        let message = next_message(&mut events).await?;
        match message {
            StreamMessage::Ended(reason) => assert_eq!(reason, "socket_closed"),
            other => return Err(format!("expected a close, got {other:?}").into()),
        }
        // And the client knows, so the supervisor reconnects instead of
        // handing out subscriptions on a socket that is gone.
        assert!(client.is_closed());
        Ok(())
    }
}
