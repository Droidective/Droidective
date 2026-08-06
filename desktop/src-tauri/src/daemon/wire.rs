//! The daemon's JSON shapes, mirrored.
//!
//! These deliberately mirror `droidectived/Sources/DaemonCore/` field for
//! field rather than reshaping anything on the way through: the UI's types are
//! generated from these, so a divergence here would be a divergence the whole
//! way up. `docs/droidectived-protocol.md` is the written contract.

use serde::{Deserialize, Serialize};

/// `ADBKit.Device`, which the daemon encodes as itself.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Device {
    pub serial: String,
    /// adb's own state string: "device", "offline", "unauthorized", …
    pub state: String,
    pub model: Option<String>,
    pub product: Option<String>,
    #[serde(rename = "transportId")]
    pub transport_id: Option<String>,
    pub label: String,
    #[serde(rename = "isWireless")]
    pub is_wireless: bool,
    /// "android" or "ios-simulator". A string rather than an enum: it is
    /// passed straight back in a run request, so parsing it here would only
    /// create a way to lose a platform the daemon knows about and we do not.
    pub platform: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DevicesResponse {
    pub devices: Vec<Device>,
}

/// Both halves of a choice: the value a runner wants, and the label a person
/// can read.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldOption {
    pub value: String,
    pub label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureField {
    pub name: String,
    pub label: String,
    /// "text", "number", "select", "preset", "slider", or "switch".
    pub control: String,
    pub options: Vec<FieldOption>,
    pub placeholder: Option<String>,
    pub optional: bool,
    pub description: Option<String>,
    #[serde(rename = "defaultValue")]
    pub default_value: Option<serde_json::Value>,
    pub min: Option<f64>,
    pub max: Option<f64>,
    pub step: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[expect(
    clippy::struct_excessive_bools,
    reason = "a mirror of the daemon's wire shape; folding its flags into enums here would be the drift this file exists to prevent"
)]
pub struct FeatureSummary {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub keywords: Vec<String>,
    /// The `FeatureCategory` case name — "input", "deviceState", …
    pub category: String,
    /// The `FeatureKind` case name — "instantAction", "formAction",
    /// "toggleAction", "view", or "system".
    pub kind: String,
    pub implemented: bool,
    #[serde(rename = "needsDevice")]
    pub needs_device: bool,
    #[serde(rename = "needsBundle")]
    pub needs_bundle: bool,
    #[serde(rename = "isDestructive")]
    pub is_destructive: bool,
    /// True when a hub screen owns this feature. Hubs are full-app views this
    /// UI does not have yet, so absorbed members are shown standalone here —
    /// but the flag has to survive the wire for that to stay a decision.
    #[serde(rename = "isAbsorbedByHub")]
    pub is_absorbed_by_hub: bool,
    pub fields: Vec<FeatureField>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FeaturesResponse {
    pub features: Vec<FeatureSummary>,
}

#[derive(Debug, Clone, Serialize)]
pub struct RunRequest {
    #[serde(rename = "featureId")]
    pub feature_id: String,
    pub serial: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub platform: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fields: Option<serde_json::Map<String, serde_json::Value>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunResponse {
    pub ok: bool,
    pub message: String,
    #[serde(rename = "copyText")]
    pub copy_text: Option<String>,
    #[serde(rename = "revealPath")]
    pub reveal_path: Option<String>,
    #[serde(rename = "needsAdbKeyboard")]
    pub needs_adb_keyboard: bool,
}

/// One installed app, as `/v1/apps/list` sends it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSummary {
    #[serde(rename = "packageId")]
    pub package_id: String,
    /// Derived from the package id by the daemon, so this client does not
    /// reimplement the rule and then drift from it.
    #[serde(rename = "displayName")]
    pub display_name: String,
    #[serde(rename = "versionName")]
    pub version_name: Option<String>,
    #[serde(rename = "isSystem")]
    pub is_system: bool,
}

/// A verb the daemon accepts, with its own destructive flag.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppActionDescriptor {
    pub id: String,
    #[serde(rename = "isDestructive")]
    pub is_destructive: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppsResponse {
    pub apps: Vec<AppSummary>,
    /// Sent with the list, so the UI offers exactly the verbs the daemon runs.
    pub actions: Vec<AppActionDescriptor>,
}

#[derive(Debug, Clone, Serialize)]
pub struct AppsListRequest {
    pub serial: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DeviceRequest {
    pub serial: String,
}

/// Everything `getprop` printed. Passed through as a map rather than reshaped:
/// which property matters is the reader's question, not this layer's.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DevicePropsResponse {
    pub properties: std::collections::HashMap<String, String>,
}

/// One signal behind the root verdict — a row in the UI, not just a boolean.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RootSignal {
    pub name: String,
    pub detail: String,
    #[serde(rename = "indicatesRoot")]
    pub indicates_root: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RootStatusResponse {
    /// `su -c id` really answered uid 0 — what root-gated browsing needs.
    #[serde(rename = "hasRootShell")]
    pub has_root_shell: bool,
    #[serde(rename = "likelyRooted")]
    pub likely_rooted: bool,
    pub summary: String,
    pub signals: Vec<RootSignal>,
}

// MARK: - the device's filesystem

#[derive(Debug, Clone, Serialize)]
pub struct FilesListRequest {
    pub serial: String,
    pub path: String,
    #[serde(rename = "asRoot")]
    pub as_root: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct FileEntry {
    pub name: String,
    #[serde(rename = "isDir")]
    pub is_dir: bool,
    pub size: i64,
    /// The `ls -la` mode column — "drwxrwx---".
    pub perms: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct FilesListResponse {
    /// Echoed by the daemon, so a client that navigated on can spot a late
    /// reply.
    pub path: String,
    pub entries: Vec<FileEntry>,
}

/// A mutation. `op` is a string for the same reason an app verb is: the daemon
/// owns the list and refuses an unknown one, so mirroring it as an enum here
/// would only add a place to fall behind.
#[derive(Debug, Clone, Serialize)]
pub struct FileOperationRequest {
    pub serial: String,
    pub op: String,
    pub path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub destination: Option<String>,
    #[serde(rename = "asRoot")]
    pub as_root: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct FileInfoRequest {
    pub serial: String,
    pub path: String,
    #[serde(rename = "asRoot")]
    pub as_root: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct FileDetails {
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(rename = "sizeBytes")]
    pub size_bytes: Option<i64>,
    pub owner: String,
    pub permissions: String,
    pub modified: String,
    /// Last metadata change. Android records no creation time.
    pub changed: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct FileInfoResponse {
    /// Null when the device could not stat the path — an answer, not a fault.
    pub info: Option<FileDetails>,
}

/// `destination` is a **host** path this process chose. The daemon writes
/// exactly there; picking it here is what keeps one answer to "where do pulled
/// files go", shared with `export_text`.
#[derive(Debug, Clone, Serialize)]
pub struct FilePullRequest {
    pub serial: String,
    pub path: String,
    pub destination: String,
    #[serde(rename = "asRoot")]
    pub as_root: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct FilePullResponse {
    /// Where it landed, for the Show in folder button.
    pub path: String,
}

// MARK: - the crash buffer

#[derive(Debug, Clone, Serialize)]
pub struct CrashListRequest {
    pub serial: String,
}

/// One crash, as `CrashParser` split it.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CrashReport {
    /// Stable across refetches, so a watch poll does not move the selection.
    pub id: String,
    /// A `CrashReport.Kind` raw value: java, native, reactNative, anr, unknown.
    pub kind: String,
    /// Sent rather than derived here, so the two UIs name a kind the same way.
    #[serde(rename = "kindLabel")]
    pub kind_label: String,
    /// Logcat's own timestamp. A string: logcat prints no year.
    pub timestamp: Option<String>,
    pub process: Option<String>,
    pub pid: Option<i64>,
    pub title: String,
    /// The block as logcat printed it.
    pub raw: String,
    /// The block with the threadtime prefixes stripped.
    pub body: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CrashListResponse {
    /// Newest first.
    pub crashes: Vec<CrashReport>,
}

#[derive(Debug, Clone, Serialize)]
pub struct AppControlRequest {
    pub serial: String,
    #[serde(rename = "packageId")]
    pub package_id: String,
    /// An `AppControlService.AppAction` raw value. A string rather than an
    /// enum: the daemon owns the verb list and rejects an unknown one, so
    /// mirroring it here would only add a place to fall behind.
    pub action: String,
}

/// `{"error":{"code":…,"message":…,"detail":…}}`.
#[derive(Debug, Clone, Deserialize)]
pub struct ErrorEnvelope {
    pub error: ErrorPayload,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ErrorPayload {
    pub code: String,
    pub message: String,
    pub detail: Option<String>,
}

// MARK: - the stream socket

#[derive(Debug, Clone, Serialize)]
pub struct SubscribeCommand {
    pub op: &'static str,
    pub id: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub topic: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<SubscribeParams>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct SubscribeParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub serial: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub filter: Option<String>,
    /// The app whose FPS and memory to sample, for `performance`.
    #[serde(rename = "packageId", skip_serializing_if = "Option::is_none")]
    pub package_id: Option<String>,
    /// Whether to add the per-process table — two extra `dumpsys` calls a
    /// sample, so it is asked for rather than assumed.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub processes: Option<bool>,
}

impl SubscribeCommand {
    pub fn subscribe(id: i64, topic: &'static str, params: Option<SubscribeParams>) -> Self {
        Self {
            op: "subscribe",
            id,
            topic: Some(topic),
            params,
        }
    }

    /// The id alone identifies what to tear down, so no topic is sent.
    pub fn unsubscribe(id: i64) -> Self {
        Self {
            op: "unsubscribe",
            id,
            topic: None,
            params: None,
        }
    }
}

/// A server frame.
///
/// Flat with every payload field optional, exactly like the daemon's
/// `StreamProtocol.Event`, rather than an internally-tagged enum: the wire has
/// one shape and decoding it as one shape is what keeps an unknown future
/// event kind from failing the whole socket.
///
/// `items` stays as raw JSON. Each topic has its own payload type and the only
/// consumer is the UI, so decoding them here would mean maintaining a second
/// copy of every model for no one's benefit.
#[derive(Debug, Clone, Deserialize)]
pub struct StreamEvent {
    pub id: i64,
    pub event: String,
    pub items: Option<Vec<serde_json::Value>>,
    pub count: Option<u64>,
    pub reason: Option<String>,
    pub message: Option<String>,
}

#[cfg(test)]
#[expect(
    clippy::panic_in_result_fn,
    reason = "an assertion is how a test reports failure; the Result is for decoding"
)]
mod tests {
    use super::{FeaturesResponse, StreamEvent};

    /// Real `POST /v1/features/list` output, shared with the UI's own tests.
    ///
    /// Decoding it here is the guard that matters: these structs are a mirror
    /// of Swift types no compiler checks them against, so the only thing
    /// standing between a renamed field and a blank window is a test that
    /// reads what the daemon actually sends. Two rounds of exactly that drift
    /// — `keywords`, then `options` becoming objects — reached a running app
    /// before this existed.
    const FEATURES: &str = include_str!("../../../src/lib/__fixtures__/features.json");

    #[test]
    fn decodes_the_daemons_real_feature_list() -> Result<(), serde_json::Error> {
        let response: FeaturesResponse = serde_json::from_str(FEATURES)?;
        assert!(
            response.features.len() > 50,
            "the fixture should be the whole registry, got {}",
            response.features.len()
        );

        let battery = response
            .features
            .iter()
            .find(|feature| feature.id == "fake-battery");
        let battery = battery.ok_or_else(|| serde::de::Error::custom("no fake-battery"))?;
        assert!(
            !battery.keywords.is_empty(),
            "keywords must survive the wire"
        );
        assert!(battery.is_absorbed_by_hub, "it is a Simulate hub member");

        let slider = battery
            .fields
            .iter()
            .find(|field| field.control == "slider")
            .ok_or_else(|| serde::de::Error::custom("no slider"))?;
        assert!(
            slider.min.is_some() && slider.max.is_some(),
            "a slider needs bounds"
        );

        let locale = response
            .features
            .iter()
            .find(|feature| feature.id == "locale")
            .and_then(|feature| feature.fields.first())
            .ok_or_else(|| serde::de::Error::custom("no locale field"))?;
        let first = locale
            .options
            .first()
            .ok_or_else(|| serde::de::Error::custom("no options"))?;
        assert_ne!(first.value, first.label, "a choice carries both halves");
        Ok(())
    }

    #[test]
    fn an_event_kind_this_build_does_not_know_still_decodes() -> Result<(), serde_json::Error> {
        // Every payload field is optional, so a future event kind lands as a
        // frame we can ignore rather than one that kills the whole socket.
        let event: StreamEvent = serde_json::from_str(r#"{"id":3,"event":"heartbeat"}"#)?;
        assert_eq!(event.id, 3);
        assert_eq!(event.event, "heartbeat");
        assert!(event.items.is_none());
        Ok(())
    }
}
