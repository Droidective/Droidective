import ADBKit
import AppKit

extension CustomCommandTerminal {
    var displayName: String {
        switch self {
        case .droidective: return "Droidective Terminal"
        case .defaultTerminal: return "Default Terminal"
        }
    }
}

extension AppState {
    /// Run a custom command's line in the command's chosen terminal: the
    /// in-app Terminal feature (bringing the main window forward — the Quick
    /// Actions panel can't host a PTY), or the Mac's default terminal app via
    /// a temp executable `.command` script — LaunchServices opens whichever
    /// app the user has for those (Terminal.app unless they changed it), and
    /// no automation permission is needed. The script exports ANDROID_SERIAL
    /// so `adb` lines target the selected device, like an in-app shell.
    /// Failures (script write, no handler) surface as a toast.
    func runCustomCommand(line: String, named name: String, serial: String, terminal: CustomCommandTerminal) {
        switch terminal {
        case .droidective:
            runInTerminal(line, named: name)
            activateMainWindow()
        case .defaultTerminal:
            do {
                let script = CustomCommandService.commandScript(
                    line: line, serial: serial,
                    shellPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                )
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("droidective-\(UUID().uuidString.prefix(8)).command")
                try script.write(to: url, atomically: true, encoding: .utf8)
                // Terminal refuses to run a non-executable .command file.
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                if !NSWorkspace.shared.open(url) {
                    showToast(Toast(
                        message: "Couldn't open your default terminal for \(name).",
                        ok: false
                    ))
                }
            } catch {
                showToast(Toast(
                    message: "Couldn't stage the command script — \(error.localizedDescription)",
                    ok: false
                ))
            }
        }
    }
}
