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

#[derive(Debug, Clone, Serialize)]
pub struct SubscribeParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub serial: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub filter: Option<String>,
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
