//! Files dropped on the window, from the file manager.
//!
//! Tauri's own drop handler would give paths straight away, but turning it on
//! is what stops the page's HTML5 drags working — and those are the tab strip,
//! the sidebar and the mirror wall. Verified rather than assumed: with the
//! handler on, a tab drag does nothing at all.
//!
//! So the handler stays off, the page receives an ordinary web `drop`, and the
//! bytes come through here to be staged in a temp directory. The cost is a
//! copy of the file, which is real and worth stating: a 200 MB `.xapk` is
//! written once before it is installed. The alternative was rewriting every
//! drag in the shell onto pointer events, which is a great deal of working
//! code to put at risk for one gesture.

use std::path::PathBuf;

use tauri::ipc::{InvokeBody, Request};
use tauri::{AppHandle, Manager};

use crate::error::DaemonError;

/// Where staged drops live for this run.
const STAGE_DIRECTORY: &str = "dropped";

/// Write one dropped file and answer where it landed.
///
/// The bytes arrive as a raw request body rather than a JSON array: a
/// hundred-megabyte APK encoded as JSON numbers is several hundred megabytes of
/// text, and the whole point of staging is that it happens once.
///
/// # Errors
///
/// Fails when the body is not raw bytes, when the name would escape the staging
/// directory, or when the write does not land.
#[tauri::command]
#[expect(
    clippy::needless_pass_by_value,
    reason = "tauri's command macro hands AppHandle in by value"
)]
pub fn stage_dropped_file(app: AppHandle, request: Request<'_>) -> Result<String, DaemonError> {
    let InvokeBody::Raw(bytes) = request.body() else {
        return Err(DaemonError::Host(
            "a dropped file must arrive as bytes".into(),
        ));
    };
    let name = request
        .headers()
        .get("x-dropped-name")
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| DaemonError::Host("a dropped file must carry its name".into()))?;

    let directory = stage_directory(&app)?;
    let path = directory.join(crate::commands::safe_file_name(&decode_name(name))?);
    std::fs::write(&path, bytes)
        .map_err(|error| DaemonError::Host(format!("could not stage {name}: {error}")))?;
    Ok(path.to_string_lossy().into_owned())
}

/// Delete a staged file once it has been installed or pushed.
///
/// Best-effort: it is in a temp directory the OS will clear anyway, and a
/// failure here is not worth a message about a file nobody will look for.
#[tauri::command]
pub fn discard_dropped_file(path: String) {
    let _ = std::fs::remove_file(path);
}

fn stage_directory(app: &AppHandle) -> Result<PathBuf, DaemonError> {
    let directory = app
        .path()
        .temp_dir()
        .map_err(|error| DaemonError::Host(format!("no temporary directory: {error}")))?
        .join("Droidective")
        .join(STAGE_DIRECTORY);
    std::fs::create_dir_all(&directory).map_err(|error| {
        DaemonError::Host(format!("could not create {}: {error}", directory.display()))
    })?;
    Ok(directory)
}

/// The header carries the name percent-encoded, because a header value may not
/// hold a newline and a file name may.
fn decode_name(raw: &str) -> String {
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            let hex = std::str::from_utf8(&bytes[index + 1..index + 3]).unwrap_or("");
            if let Ok(byte) = u8::from_str_radix(hex, 16) {
                out.push(byte);
                index += 3;
                continue;
            }
        }
        out.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[cfg(test)]
mod tests {
    use super::decode_name;

    #[test]
    fn a_percent_encoded_name_comes_back_whole() {
        assert_eq!(decode_name("app.apk"), "app.apk");
        assert_eq!(decode_name("my%20app.apk"), "my app.apk");
        assert_eq!(decode_name("caf%C3%A9.txt"), "café.txt");
    }

    /// A stray `%` is a character in a file name, not a broken escape — the
    /// name should survive rather than be truncated at it.
    #[test]
    fn a_stray_percent_is_left_alone() {
        assert_eq!(decode_name("100%.txt"), "100%.txt");
        assert_eq!(decode_name("%zz.txt"), "%zz.txt");
    }
}
