import AppKit
import SwiftTerm
import SwiftUI

/// One real embedded shell (PTY-backed, via SwiftTerm). The Terminal feature's
/// manager owns one session per tab, all held on `AppState` so every shell and
/// its scrollback survive switching features. The login shell is started
/// lazily the first time the tab is shown.
@MainActor
final class TerminalSession {
    private var terminalView: LocalProcessTerminalView?
    /// Latched by `kill()`. SwiftUI's teardown pass can call `view(serial:)`
    /// once more on the dying representable — without the latch that silently
    /// respawned an orphan shell for every closed tab.
    private var killed = false

    /// The session's terminal view, starting the login shell on first use. The
    /// selected device serial is exported as `ANDROID_SERIAL` so `adb` targets
    /// it without `-s`.
    func view(serial: String?) -> LocalProcessTerminalView {
        if let terminalView { return terminalView }
        let view = LocalProcessTerminalView(frame: .zero)
        view.font = Self.terminalFont(size: 12)
        terminalView = view
        guard !killed else { return view } // dead husk for the unmount pass

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        if let serial, !serial.isEmpty {
            environment["ANDROID_SERIAL"] = serial
        }
        view.startProcess(
            executable: environment["SHELL"] ?? "/bin/zsh",
            args: ["-l"],
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        return view
    }

    /// Terminate the shell and drop the view — used when a terminal tab closes.
    /// SwiftTerm's `terminate()` closes the PTY and sends SIGTERM, which an
    /// interactive zsh *ignores* — follow up with SIGHUP, which it honors.
    func kill() {
        killed = true
        if let terminalView {
            let pid = terminalView.process.shellPid
            terminalView.terminate()
            if pid != 0 {
                Darwin.kill(pid, SIGHUP)
            }
        }
        terminalView = nil
    }

    /// A fixed-width Nerd Font so prompt-theme glyphs (powerline separators,
    /// icons) render instead of missing-glyph boxes; falls back to the system
    /// monospace when no Nerd Font is installed.
    static func terminalFont(size: CGFloat) -> NSFont {
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies
        let family = families.first { $0.range(of: "Nerd Font Mono", options: .caseInsensitive) != nil }
            ?? families.first { $0.range(of: "Nerd Font", options: .caseInsensitive) != nil }
            ?? families.first { $0.range(of: "Nerd", options: .caseInsensitive) != nil }
        if let family, let font = manager.font(withFamily: family, traits: [], weight: 5, size: size) {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// SwiftUI host for one terminal session. SwiftUI tears down and recreates the
/// representable when a tab is hidden/reshown; returning the session's view
/// directly let SwiftUI reset it, spawning a fresh-looking shell. Instead we
/// hand SwiftUI a fresh container each time and re-parent the session's one
/// live terminal into it, so the PTY session and scrollback truly persist.
struct NativeTerminalView: NSViewRepresentable {
    let session: TerminalSession
    let serial: String?

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        mount(in: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        mount(in: nsView)
    }

    private func mount(in container: NSView) {
        let terminal = session.view(serial: serial)
        guard terminal.superview !== container else { return }
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
