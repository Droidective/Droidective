import Foundation

/// User-defined command macros with {bundleId} / {serial} placeholders.
/// `.adb` commands are tokenized with quote support and passed to adb as
/// discrete arguments — never through a shell. `.shell` commands (plain
/// terminal command lines or script files) run through `zsh -lc`, so they
/// behave like the user's Terminal.
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

    public init(client: AdbClient) {
        self.client = client
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

    /// Substitute {bundleId} / {serial} into a template. Throws when the
    /// template needs a bundle and none is selected.
    public static func substitute(
        template: String, bundleId: String?, serial: String
    ) throws(TemplateError) -> String {
        if template.contains("{bundleId}") && (bundleId ?? "").isEmpty {
            throw .missingBundle
        }
        return template
            .replacingOccurrences(of: "{bundleId}", with: bundleId ?? "")
            .replacingOccurrences(of: "{serial}", with: serial)
    }

    /// Substitute placeholders and tokenize. The leading "adb" (if typed) is
    /// dropped — the client supplies the binary.
    public static func buildArgs(
        template: String, bundleId: String?, serial: String
    ) throws(TemplateError) -> [String] {
        let substituted = try substitute(template: template, bundleId: bundleId, serial: serial)
        var tokens = try tokenize(substituted)
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

    /// Run a `.shell` command line through the user's login shell, so PATH,
    /// dotfile setup, and plain script-file paths (e.g. ~/scripts/reset.sh)
    /// behave exactly like Terminal — deliberately not device-scoped; use the
    /// {serial} placeholder to target the selected device. Recorded on the
    /// shared command log like every adb run. The 10-minute ceiling is a hang
    /// stop, sized so real work (a gradle build, a long pull) isn't cut off
    /// like it would be at adb's usual 120s.
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
        let output = await client.runner.run(
            executable: "/bin/zsh",
            arguments: ["-lc", line],
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
