//! Starting `droidectived` and learning where it landed.
//!
//! Pure and unit-tested, because the alternative is discovering that the port
//! line is parsed wrong only when the whole app comes up blank.

/// The exact line the daemon prints once, to stdout, after binding.
const LISTENING_PREFIX: &str = "droidectived listening 127.0.0.1:";

/// The sidecar's arguments.
///
/// `--port 0` always: the OS picks, the daemon prints what it got, and two
/// Droidectives (or a stale one) can never collide over a fixed port. That is
/// the protocol's reason for having a printed port line at all.
///
/// `--parent-pid` is the orphan guard — a crashed UI otherwise leaves a daemon
/// holding adb children, which users experience as "adb is stuck".
pub fn spawn_args(token_file: &str, parent_pid: u32) -> Vec<String> {
    vec![
        "--port".into(),
        "0".into(),
        "--token-file".into(),
        token_file.into(),
        "--parent-pid".into(),
        parent_pid.to_string(),
    ]
}

/// The port from one complete stdout line, or `None` if that is not what this
/// line is.
///
/// Strict about the prefix and about what follows the port: anything else is
/// either a different message or a daemon we do not understand, and guessing
/// would mean pointing the whole UI at an arbitrary port.
pub fn parse_listening_line(line: &str) -> Option<u16> {
    let line = line.trim_end_matches(['\r', '\n']).trim();
    let port = line.strip_prefix(LISTENING_PREFIX)?;
    // Port 0 is what we asked for, never what we can connect to: seeing it
    // back means the daemon answered before it really bound.
    match port.parse::<u16>() {
        Ok(0) | Err(_) => None,
        Ok(port) => Some(port),
    }
}

/// Finds the port line in a stdout byte stream.
///
/// Chunk boundaries are not line boundaries — the pipe can split the one line
/// we care about — so partial input is held until a newline arrives rather
/// than tested and discarded.
#[derive(Default)]
pub struct PortLineScanner {
    buffer: String,
}

impl PortLineScanner {
    /// Feeds one chunk. Returns the port as soon as a *complete* matching line
    /// has been seen.
    pub fn push(&mut self, chunk: &str) -> Option<u16> {
        self.buffer.push_str(chunk);
        while let Some(index) = self.buffer.find('\n') {
            let line: String = self.buffer.drain(..=index).collect();
            if let Some(port) = parse_listening_line(&line) {
                return Some(port);
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::{parse_listening_line, spawn_args, PortLineScanner};

    #[test]
    fn the_sidecar_always_asks_for_an_os_chosen_port() {
        assert_eq!(
            spawn_args("/tmp/token", 4242),
            vec![
                "--port",
                "0",
                "--token-file",
                "/tmp/token",
                "--parent-pid",
                "4242"
            ]
        );
    }

    #[test]
    fn reads_the_port_the_daemon_actually_prints() {
        assert_eq!(
            parse_listening_line("droidectived listening 127.0.0.1:54123\n"),
            Some(54123)
        );
    }

    #[test]
    fn tolerates_crlf() {
        assert_eq!(
            parse_listening_line("droidectived listening 127.0.0.1:1024\r\n"),
            Some(1024)
        );
    }

    #[test]
    fn rejects_lines_that_are_not_the_port_line() {
        for line in [
            "",
            "\n",
            "droidectived: token abc123\n",
            "droidectived listening 0.0.0.0:54123\n",
            "listening 127.0.0.1:54123\n",
            "prefixed droidectived listening 127.0.0.1:54123\n",
        ] {
            assert_eq!(parse_listening_line(line), None, "should reject {line:?}");
        }
    }

    #[test]
    fn rejects_a_port_it_could_not_connect_to() {
        for tail in ["0", "70000", "-1", "", "54123 and more", "54a23", "5 4123"] {
            let line = format!("droidectived listening 127.0.0.1:{tail}\n");
            assert_eq!(parse_listening_line(&line), None, "should reject {tail:?}");
        }
    }

    #[test]
    fn finds_the_port_when_the_pipe_splits_the_line() {
        let mut scanner = PortLineScanner::default();
        assert_eq!(scanner.push("droidectived list"), None);
        assert_eq!(scanner.push("ening 127.0"), None);
        assert_eq!(scanner.push(".0.1:5412"), None);
        assert_eq!(scanner.push("3\n"), Some(54123));
    }

    #[test]
    fn ignores_chatter_before_the_port_line() {
        let mut scanner = PortLineScanner::default();
        assert_eq!(
            scanner.push("some other line\ndroidectived listening 127.0.0.1:9\n"),
            Some(9)
        );
    }

    #[test]
    fn never_matches_a_line_that_has_not_finished_arriving() {
        // The whole point of buffering: "…:5412" is a valid-looking prefix of
        // a different port, and acting on it would connect to the wrong one.
        let mut scanner = PortLineScanner::default();
        assert_eq!(scanner.push("droidectived listening 127.0.0.1:5412"), None);
        assert_eq!(scanner.push("3\n"), Some(54123));
    }
}
