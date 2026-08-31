//! Multi-window: one window per device, and who is holding what.
//!
//! The Mac keeps this on `AppCore` because that is its one-per-app place, with
//! the *rules* in `ADBKit.WorkspaceRegistry` so they are pure and tested. The
//! same split holds here: this process is the one-per-app place, so it owns
//! the state and broadcasts it, and the rules live in `lib/workspaces.ts`
//! where they can be tested without a window.
//!
//! What it stores is deliberately small — a window's device and the features
//! it currently has open. That is everything the two questions need: who owns
//! this device, and who is already running the feature you just opened.

use std::collections::HashMap;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder, Wry};

/// Told to every window whenever any window's claim changes.
const CLAIMS_EVENT: &str = "workspace://claims";

/// Sent to one window, asking it to close a feature it owns. See
/// `request_close_feature`.
const CLOSE_FEATURE_EVENT: &str = "workspace://close-feature";

/// What one window is holding.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Claim {
    /// The device this window's bar is pointed at, if any.
    pub serial: Option<String>,
    /// The features it has open — every tab, not only the exclusive ones, so
    /// the rules about which of them matter stay on the page.
    pub features: Vec<String>,
}

/// One row of the snapshot every window receives.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowClaim {
    pub label: String,
    /// 1 for the first window, 2 for the next, and so on. The Mac numbers
    /// windows the same way, and only the ones after the first are tinted.
    pub ordinal: usize,
    #[serde(flatten)]
    pub claim: Claim,
}

#[derive(Debug, Default)]
pub struct Workspaces {
    inner: Mutex<State_>,
}

#[derive(Debug, Default)]
struct State_ {
    claims: HashMap<String, Claim>,
    /// Label → the order it was opened in. Kept separately from `claims` so a
    /// window that has not published yet still has a number, and so closing
    /// and reopening does not renumber the windows that stayed.
    ordinals: HashMap<String, usize>,
    /// Never reused, so two windows can never share a number in one session.
    next_ordinal: usize,
}

impl Workspaces {
    /// The number for a label, minting one the first time it is seen.
    fn ordinal(state: &mut State_, label: &str) -> usize {
        if let Some(found) = state.ordinals.get(label) {
            return *found;
        }
        state.next_ordinal += 1;
        let minted = state.next_ordinal;
        state.ordinals.insert(label.to_owned(), minted);
        minted
    }

    fn snapshot(state: &mut State_) -> Vec<WindowClaim> {
        let labels: Vec<String> = state.claims.keys().cloned().collect();
        let mut rows: Vec<WindowClaim> = labels
            .into_iter()
            .map(|label| {
                let ordinal = Self::ordinal(state, &label);
                let claim = state.claims.get(&label).cloned().unwrap_or_default();
                WindowClaim {
                    label,
                    ordinal,
                    claim,
                }
            })
            .collect();
        // By ordinal, so "Window 2" is the same window in every list.
        rows.sort_by_key(|row| row.ordinal);
        rows
    }

    fn publish(&self, label: String, claim: Claim) -> Vec<WindowClaim> {
        let mut state = self.inner.lock().unwrap_or_else(|poisoned| {
            // A panic while holding this lock would otherwise take every
            // window's registry with it; the claims are advisory, so carrying
            // on with what is there beats refusing to answer.
            poisoned.into_inner()
        });
        state.claims.insert(label, claim);
        Self::snapshot(&mut state)
    }

    fn forget(&self, label: &str) -> Vec<WindowClaim> {
        let mut state = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.claims.remove(label);
        state.ordinals.remove(label);
        Self::snapshot(&mut state)
    }

    fn current(&self) -> Vec<WindowClaim> {
        let mut state = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        Self::snapshot(&mut state)
    }
}

/// Tell every window what every window is holding.
fn broadcast(app: &AppHandle<Wry>, claims: &[WindowClaim]) {
    let _ = app.emit(CLAIMS_EVENT, claims);
}

/// This window's device and open features, and the new snapshot back.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle and State in by value"
)]
pub fn publish_claim(
    app: AppHandle<Wry>,
    workspaces: State<'_, Workspaces>,
    label: String,
    claim: Claim,
) -> Vec<WindowClaim> {
    let claims = workspaces.publish(label, claim);
    broadcast(&app, &claims);
    claims
}

/// What every window is holding, for a window that has just opened.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands State in by value"
)]
pub fn workspace_claims(workspaces: State<'_, Workspaces>) -> Vec<WindowClaim> {
    workspaces.current()
}

/// A new workspace window, optionally pointed at a device.
///
/// The serial rides in the query string rather than being pushed after the
/// window exists: "New Window for Device" should open *showing* that device,
/// and a message sent afterwards would paint the wrong one for a frame first —
/// the same reasoning `panel.rs` gives for its own query string.
///
/// # Errors
///
/// Fails only if the platform refuses to create the window.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle and State in by value"
)]
pub fn open_workspace_window(app: AppHandle<Wry>, serial: Option<String>) -> tauri::Result<String> {
    let label = next_label(&app);
    // The label rides in the URL as well as naming the window. Without it the
    // page reads `currentWindowLabel` as `main`, and two windows then share one
    // `localStorage` key — which is not a cosmetic problem: the second window
    // opens on the first's tabs and the two clobber each other's arrangement.
    let query = window_query(&label, serial.as_deref());
    let window = WebviewWindowBuilder::new(
        &app,
        &label,
        WebviewUrl::App(format!("index.html{query}").into()),
    )
    .title("Droidective")
    .inner_size(1100.0, 720.0)
    .min_inner_size(720.0, 480.0)
    // The same as the first window's, and for the same reason: Tauri's native
    // drop handler otherwise swallows the HTML5 tab and sidebar drags.
    .disable_drag_drop_handler()
    .focused(true)
    .build()?;
    window.set_focus()?;
    Ok(label)
}

/// Brings a window to the front — the Focus Window N button, and selecting a
/// device another window is already holding.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle and State in by value"
)]
pub fn focus_workspace_window(app: AppHandle<Wry>, label: String) {
    if let Some(window) = app.get_webview_window(&label) {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

/// Drops a window's claim. Called when its webview goes away.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle and State in by value"
)]
pub fn release_claim(app: AppHandle<Wry>, workspaces: State<'_, Workspaces>, label: String) {
    let claims = workspaces.forget(&label);
    broadcast(&app, &claims);
}

/// Ask the window that owns an exclusive feature to close it.
///
/// Take Over closes the tab in the owning window *first*, so there is never a
/// moment with two live sessions against one device — the Mac's rule, and the
/// reason this is a request to that window rather than this one simply
/// starting its own.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle and State in by value"
)]
pub fn request_close_feature(app: AppHandle<Wry>, label: String, feature: String) {
    // `emit_to`, not a window's own `emit`: in Tauri 2 `Emitter::emit` reaches
    // *every* listener whatever object it is called on, so a take-over asked
    // both windows to close the tab and the asking window lost it too — which
    // is what running it looked like.
    let _ = app.emit_to(&label, CLOSE_FEATURE_EVENT, feature);
}

/// The query string a new window opens with.
///
/// The label rides in the URL as well as naming the window. Without it the page
/// reads `currentWindowLabel` as `main`, and two windows then share one
/// `localStorage` key — which is not cosmetic: the second window opens on the
/// first's tabs and the two clobber each other's arrangement.
fn window_query(label: &str, serial: Option<&str>) -> String {
    let mut query = format!("?w={}", urlencoding_encode(label));
    if let Some(value) = serial {
        use std::fmt::Write as _;
        let _ = write!(query, "&serial={}", urlencoding_encode(value));
    }
    query
}

/// `w1`, `w2`, … — the first free one, so closing and reopening reuses a name
/// rather than counting up forever.
fn next_label(app: &AppHandle<Wry>) -> String {
    let mut index = 1;
    loop {
        let candidate = format!("w{index}");
        if app.get_webview_window(&candidate).is_none() {
            return candidate;
        }
        index += 1;
    }
}

/// Percent-encodes a serial for the query string.
///
/// Hand-rolled rather than a dependency for one call: a serial is
/// `[A-Za-z0-9._:-]` in practice, but a wireless one carries a colon and an
/// emulator's carries a hyphen, and guessing that they are all safe is how a
/// URL ends up truncated at the first surprise.
fn urlencoding_encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char);
            }
            _ => {
                use std::fmt::Write as _;
                let _ = write!(out, "%{byte:02X}");
            }
        }
    }
    out
}

#[cfg(test)]
#[expect(
    clippy::expect_used,
    reason = "a missing row is how these tests report failure, and the message names which"
)]
mod tests {
    use super::*;

    /// Tauri creates the first window from `tauri.conf.json`, so its label is
    /// fixed; every other one is minted beside it by `next_label`.
    const MAIN_LABEL: &str = "main";

    fn claim(serial: &str, features: &[&str]) -> Claim {
        Claim {
            serial: Some(serial.to_owned()),
            features: features.iter().map(|one| (*one).to_owned()).collect(),
        }
    }

    #[test]
    fn windows_are_numbered_in_the_order_they_first_appear() {
        let workspaces = Workspaces::default();
        workspaces.publish(MAIN_LABEL.into(), claim("a", &[]));
        let rows = workspaces.publish("w1".into(), claim("b", &[]));

        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].label, MAIN_LABEL);
        assert_eq!(rows[0].ordinal, 1);
        assert_eq!(rows[1].ordinal, 2);
    }

    /// A window that publishes twice must not be renumbered — "Window 2" has
    /// to mean the same window every time it is named.
    #[test]
    fn republishing_keeps_a_windows_number() {
        let workspaces = Workspaces::default();
        workspaces.publish("w1".into(), claim("a", &[]));
        workspaces.publish(MAIN_LABEL.into(), claim("b", &[]));
        let rows = workspaces.publish("w1".into(), claim("c", &["scrcpy"]));

        let w1 = rows.iter().find(|row| row.label == "w1").expect("w1");
        assert_eq!(w1.ordinal, 1, "w1 published first, so it is Window 1");
        assert_eq!(w1.claim.serial.as_deref(), Some("c"));
    }

    #[test]
    fn a_closed_window_leaves_the_registry() {
        let workspaces = Workspaces::default();
        workspaces.publish(MAIN_LABEL.into(), claim("a", &[]));
        workspaces.publish("w1".into(), claim("b", &["scrcpy"]));

        let rows = workspaces.forget("w1");
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].label, MAIN_LABEL);
    }

    /// Numbers are never reused inside a session: a window that opened after
    /// another closed must not inherit its name, or a "Focus Window 2" button
    /// held on screen would point somewhere new.
    #[test]
    fn a_reopened_window_gets_a_fresh_number() {
        let workspaces = Workspaces::default();
        workspaces.publish(MAIN_LABEL.into(), claim("a", &[]));
        workspaces.publish("w1".into(), claim("b", &[]));
        workspaces.forget("w1");
        let rows = workspaces.publish("w1".into(), claim("c", &[]));

        let w1 = rows.iter().find(|row| row.label == "w1").expect("w1");
        assert_eq!(w1.ordinal, 3);
    }

    /// The label has to reach the page, not only the window.
    ///
    /// Without it `currentWindowLabel` reads `main` and two windows share one
    /// `localStorage` key — the second opens on the first's tabs and the two
    /// clobber each other. Found by opening a second window, not by reading.
    #[test]
    fn the_query_carries_the_label_and_then_the_device() {
        assert_eq!(window_query("w1", None), "?w=w1");
        assert_eq!(
            window_query("w2", Some("192.168.1.10:5555")),
            "?w=w2&serial=192.168.1.10%3A5555"
        );
    }

    #[test]
    fn a_serial_is_encoded_for_the_query_string() {
        assert_eq!(urlencoding_encode("emulator-5554"), "emulator-5554");
        assert_eq!(
            urlencoding_encode("192.168.1.10:5555"),
            "192.168.1.10%3A5555"
        );
        assert_eq!(urlencoding_encode("a b&c"), "a%20b%26c");
    }
}
