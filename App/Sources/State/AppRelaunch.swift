import Foundation

/// Opening the app again once it has quit.
///
/// macOS hands a running process the privacy permissions it had at launch —
/// AVFoundation keeps the microphone answer for the life of the process and
/// never asks TCC again — so a switch turned on in System Settings only reaches
/// a fresh process. That is the whole reason this exists.
enum AppRelaunch {
    /// Arguments for a `/bin/sh` that waits for `pid` to exit, then hands the
    /// bundle to `opener`. Opening through LaunchServices (`/usr/bin/open`)
    /// makes the new process its own app, not a child of the shell — which is
    /// what TCC attributes the microphone to. Every value rides as a positional
    /// parameter rather than being spliced into the script, so no path needs
    /// quoting.
    static func helperArguments(
        waitingFor pid: Int32, appPath: String, opener: String = "/usr/bin/open"
    ) -> [String] {
        [
            "-c",
            #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; exec "$2" "$3""#,
            "droidective-relaunch", String(pid), opener, appPath,
        ]
    }

    /// Start the helper for this process. Call only once quit is certain: it
    /// opens the app the moment this process is gone, whatever ended it.
    static func scheduleAfterExit() throws {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = helperArguments(
            waitingFor: ProcessInfo.processInfo.processIdentifier,
            appPath: Bundle.main.bundlePath)
        try helper.run()
    }
}
