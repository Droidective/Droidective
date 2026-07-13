import Foundation

/// User-defined command macros with {bundleId} / {serial} placeholders.
/// `.adb` commands are tokenized with quote support and passed to adb as
/// discrete arguments — never through a shell. `.shell` commands (plain
/// terminal command lines or script files) run through the user's login shell
/// with its interactive rc sourced best-effort, so aliases and PATH behave
/// like the user's Terminal.
public struct CustomCommandService: Sendable {
    public enum TemplateError: Error, LocalizedError, Equatable {
        case empty
        case unbalancedQuote
        case missingBundle

        public var errorDescription: String? {
            switch self {
            case .empty: return "The command is empty."
            case .unbalancedQuote: return "Unbalanced quote in the command."
            case .missingBundle: return "This command needs a saved bundle — pick one first."
            }
        }
    }

    let client: AdbClient
    let loginShell: String

    public init(
        client: AdbClient,
        loginShell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    ) {
        self.client = client
        self.loginShell = loginShell
    }

    /// Split a template into argv tokens, honoring single/double quotes.
    public static func tokenize(_ template: String) throws(TemplateError) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var hasContent = false

        for char in template {
            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                } else {
                    current.append(char)
                }
            } else if char == "\"" || char == "'" {
                quote = char
                hasContent = true
            } else if char == " " || char == "\t" {
                if hasContent || !current.isEmpty {
                    tokens.append(current)
                    current = ""
                    hasContent = false
                }
            } else {
                current.append(char)
            }
        }
        if quote != nil { throw .unbalancedQuote }
        if hasContent || !current.isEmpty {
            tokens.append(current)
        }
        if tokens.isEmpty { throw .empty }
        return tokens
    }

    /// The line a "run in Terminal" tab types into its shell: placeholders
    /// substituted, adb commands given their `adb` prefix (the tab's
    /// ANDROID_SERIAL export targets the device, but the typed line stays
    /// explicit and editable), shell commands as written.
    public static func terminalLine(
        command: CustomCommand, bundleId: String?, serial: String
    ) throws(TemplateError) -> String {
        let line = try substitute(template: command.command, bundleId: bundleId, serial: serial)
        if command.kind == .adb, !line.hasPrefix("adb ") {
            return "adb \(line)"
        }
        return line
    }

    /// The contents of the temp `.command` script an external terminal app
    /// (Terminal, iTerm2) opens for a "run in Terminal" custom command: the
    /// user's login shell as the interpreter (with `-l` so PATH setup from
    /// the login profile applies), the target device exported as
    /// ANDROID_SERIAL (matching the in-app Terminal's scoping), then the
    /// line as typed. The serial is `shellQuote`d — it reaches a Mac shell
    /// verbatim, and a crafted serial must stay one assignment, not code.
    public static func commandScript(line: String, serial: String, shellPath: String) -> String {
        let shell = shellPath.isEmpty ? "/bin/zsh" : shellPath
        var script = "#!\(shell) -l\n"
        if !serial.isEmpty {
            script += "export ANDROID_SERIAL=\(shellQuote(serial))\n"
        }
        script += line + "\n"
        return script
    }

    /// The kind and stored template for a command line as typed: a leading
    /// `adb` token means the adb runner (tokenized argv — no shell), stored
    /// without the prefix like the presets; anything else is a login-shell
    /// line as written. Multi-line drafts always run through the shell — an
    /// adb argv can't hold several commands, and the shell treats each line
    /// as its own command. Detected via `.newlines`, never `contains("\n")` —
    /// a pasted CRLF pair is one Character and a bare-\n check misses it.
    public static func draftParts(of line: String) -> (kind: CustomCommandKind, command: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: .newlines) == nil else { return (.shell, trimmed) }
        guard trimmed == "adb" || trimmed.hasPrefix("adb ") else { return (.shell, trimmed) }
        return (.adb, String(trimmed.dropFirst("adb".count)).trimmingCharacters(in: .whitespaces))
    }

    /// Substituted values reach the user's *Mac* shell wherever the line runs
    /// as shell code (a terminal tab, the `.command` script, the headless
    /// login-shell runner). A plain serial or package id passes through
    /// untouched — quoting every value would break templates that already
    /// wrap a placeholder — but one carrying shell metacharacters (a USB
    /// serial string is device-controlled) is single-quoted so it stays data,
    /// not code. The tokenized adb path (`buildArgs`) substitutes into argv
    /// and never needs this.
    static func hostShellSafe(_ value: String) -> String {
        let safe = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:/-@,+="
        )
        return value.rangeOfCharacter(from: safe.inverted) == nil ? value : shellQuote(value)
    }

    /// Substitute {bundleId} / {serial} into a template destined for a Mac
    /// shell (see `hostShellSafe`). Throws when the template needs a bundle
    /// and none is selected.
    public static func substitute(
        template: String, bundleId: String?, serial: String
    ) throws(TemplateError) -> String {
        if template.contains("{bundleId}") && (bundleId ?? "").isEmpty {
            throw .missingBundle
        }
        return template
            .replacingOccurrences(of: "{bundleId}", with: hostShellSafe(bundleId ?? ""))
            .replacingOccurrences(of: "{serial}", with: hostShellSafe(serial))
    }

    /// Tokenize, then substitute placeholders *into each token*. The leading
    /// "adb" (if typed) is dropped — the client supplies the binary.
    ///
    /// Substituting after tokenizing keeps a placeholder value that contains
    /// spaces or shell metacharacters (a free-text bundle id, a crafted serial)
    /// as a single argv token, instead of letting it split into extra adb
    /// arguments the way pre-tokenization substitution did.
    public static func buildArgs(
        template: String, bundleId: String?, serial: String
    ) throws(TemplateError) -> [String] {
        if template.contains("{bundleId}") && (bundleId ?? "").isEmpty {
            throw .missingBundle
        }
        var tokens = try tokenize(template).map {
            $0.replacingOccurrences(of: "{bundleId}", with: bundleId ?? "")
                .replacingOccurrences(of: "{serial}", with: serial)
        }
        if tokens.first == "adb" {
            tokens.removeFirst()
        }
        if tokens.isEmpty { throw .empty }
        return tokens
    }

    public func run(command: CustomCommand, bundleId: String?, serial: String) async -> FeatureResult {
        switch command.kind {
        case .adb: return await runAdb(command: command, bundleId: bundleId, serial: serial)
        case .shell: return await runShell(command: command, bundleId: bundleId, serial: serial)
        }
    }

    private func runAdb(command: CustomCommand, bundleId: String?, serial: String) async -> FeatureResult {
        do {
            let args = try CustomCommandService.buildArgs(
                template: command.command, bundleId: bundleId, serial: serial
            )
            // Only a *leading* -s is an adb target flag; "-s" later in the
            // argv belongs to the device-side command (e.g. `pidof -s`).
            let needsSerial = !serial.isEmpty && args.first != "-s"
            let result = try await client.run(needsSerial ? ["-s", serial] + args : args)
            if result.succeeded {
                let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                return FeatureResult(
                    ok: true,
                    message: output.isEmpty ? "\(command.name) done" : String(output.prefix(200))
                )
            }
            return FeatureResult(ok: false, message: friendlyAdbError(result, fallback: "\(command.name) failed"))
        } catch let error as TemplateError {
            return FeatureResult(ok: false, message: error.localizedDescription)
        } catch {
            return FeatureResult(ok: false, message: error.localizedDescription)
        }
    }

    /// Build the login-shell invocation for a `.shell` command line. A plain
    /// `-lc <line>` misses aliases from the user's *interactive* rc file
    /// (`.zshrc`/`.bashrc` are only read by interactive shells), so zsh and
    /// bash get a preamble that sources it best-effort (output suppressed —
    /// interactive rc files print banners and may error without a TTY) and
    /// then `eval`s the line: both shells parse ahead of alias definition, so
    /// without the re-parse a just-sourced alias still wouldn't expand. The
    /// line rides as a positional `$1`, never spliced into the script — no
    /// quoting, no injection surface beyond what the user typed. Other shells
    /// (fish sources its config unconditionally) keep the plain form.
    static func shellInvocation(line: String, shellPath: String) -> (executable: String, arguments: [String]) {
        let shell = shellPath.isEmpty ? "/bin/zsh" : shellPath
        switch URL(fileURLWithPath: shell).lastPathComponent {
        case "zsh":
            return (shell, [
                "-lc",
                "[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1; eval \"$1\"",
                "droidective", line,
            ])
        case "bash":
            return (shell, [
                "-lc",
                "shopt -s expand_aliases; [ -f ~/.bashrc ] && source ~/.bashrc >/dev/null 2>&1; eval \"$1\"",
                "droidective", line,
            ])
        default:
            return (shell, ["-lc", line])
        }
    }

    /// Run a `.shell` command line through the user's login shell, so PATH,
    /// dotfile setup, aliases, and plain script-file paths (e.g.
    /// ~/scripts/reset.sh) behave like Terminal — deliberately not
    /// device-scoped; use the {serial} placeholder to target the selected
    /// device. Recorded on the shared command log like every adb run. The
    /// 10-minute ceiling is a hang stop, sized so real work (a gradle build, a
    /// long pull) isn't cut off like it would be at adb's usual 120s.
    private func runShell(command: CustomCommand, bundleId: String?, serial: String) async -> FeatureResult {
        let line: String
        do {
            line = try CustomCommandService.substitute(
                template: command.command, bundleId: bundleId, serial: serial
            )
        } catch {
            return FeatureResult(ok: false, message: error.localizedDescription)
        }
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
            return FeatureResult(ok: false, message: TemplateError.empty.localizedDescription)
        }
        let clock = ContinuousClock()
        let started = clock.now
        let invocation = CustomCommandService.shellInvocation(line: line, shellPath: loginShell)
        let output = await client.runner.run(
            executable: invocation.executable,
            arguments: invocation.arguments,
            timeout: .seconds(600),
            maxOutputBytes: AdbClient.defaultMaxOutput
        )
        await client.log.record(
            command: line,
            exitCode: output.exitCode,
            duration: clock.now - started,
            stdout: output.stdoutText,
            stderr: output.stderrText
        )
        if output.exitCode == 0 {
            let text = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            return FeatureResult(
                ok: true,
                message: text.isEmpty ? "\(command.name) done" : String(text.prefix(200))
            )
        }
        if output.timedOut {
            return FeatureResult(ok: false, message: "The command timed out.")
        }
        let stderr = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        return FeatureResult(
            ok: false,
            message: stderr.isEmpty
                ? "\(command.name) failed (exit \(output.exitCode.map(String.init) ?? "?"))"
                : String(stderr.prefix(300))
        )
    }
}
