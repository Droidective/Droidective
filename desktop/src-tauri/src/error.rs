use serde::{Serialize, Serializer};

/// Everything that can go wrong between this UI and `droidectived`.
///
/// The daemon already promises one error shape (`{error:{code,message,detail}}`
/// — see `docs/droidectived-protocol.md` §4.1), so this widens that same shape
/// with the failures that happen on our side of the socket rather than
/// inventing a second one for the UI to branch on.
#[derive(Debug, thiserror::Error)]
pub enum DaemonError {
    #[error("droidectived is not running")]
    NotRunning,
    #[error("droidectived did not start: {0}")]
    Launch(String),
    /// The daemon answered, and its answer was "no". `code` is its own stable
    /// machine string, passed through untouched.
    #[error("{message}")]
    Refused {
        code: String,
        message: String,
        detail: Option<String>,
    },
    #[error("could not reach droidectived: {0}")]
    Transport(String),
    #[error("droidectived sent a reply this build cannot read: {0}")]
    Decode(String),
}

impl DaemonError {
    /// The stable machine string the UI switches on.
    pub fn code(&self) -> &str {
        match self {
            Self::NotRunning => "daemon_not_running",
            Self::Launch(_) => "daemon_launch_failed",
            Self::Refused { code, .. } => code,
            Self::Transport(_) => "transport_failed",
            Self::Decode(_) => "decode_failed",
        }
    }

    fn detail(&self) -> Option<&str> {
        match self {
            Self::Refused { detail, .. } => detail.as_deref(),
            _ => None,
        }
    }
}

/// Serialized as the daemon's own error payload so `invoke()` rejections and
/// daemon refusals are indistinguishable to the caller — one error path.
impl Serialize for DaemonError {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        #[derive(Serialize)]
        struct Wire<'a> {
            code: &'a str,
            message: String,
            detail: Option<&'a str>,
        }
        Wire {
            code: self.code(),
            message: self.to_string(),
            detail: self.detail(),
        }
        .serialize(serializer)
    }
}

#[cfg(test)]
#[expect(
    clippy::panic_in_result_fn,
    reason = "an assertion is how a test reports failure; the Result is for the setup steps"
)]
mod tests {
    use super::DaemonError;

    #[test]
    fn a_daemon_refusal_keeps_its_own_code_and_detail() -> Result<(), serde_json::Error> {
        let error = DaemonError::Refused {
            code: "unknown_feature".into(),
            message: "No such feature, or it has no runner.".into(),
            detail: Some("raw adb output".into()),
        };
        let json = serde_json::to_value(&error)?;
        assert_eq!(json["code"], "unknown_feature");
        assert_eq!(json["message"], "No such feature, or it has no runner.");
        assert_eq!(json["detail"], "raw adb output");
        Ok(())
    }

    #[test]
    fn our_own_failures_get_codes_the_daemon_never_sends() -> Result<(), serde_json::Error> {
        let json = serde_json::to_value(DaemonError::NotRunning)?;
        assert_eq!(json["code"], "daemon_not_running");
        assert!(json["detail"].is_null());

        let json = serde_json::to_value(DaemonError::Transport("connection refused".into()))?;
        assert_eq!(json["code"], "transport_failed");
        assert_eq!(
            json["message"],
            "could not reach droidectived: connection refused"
        );
        Ok(())
    }
}
