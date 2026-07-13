import Foundation
import Testing
@testable import ADBKit

@Suite struct CustomCommandTemplateTests {
    @Test func tokenizesSimpleCommand() throws {
        #expect(try CustomCommandService.tokenize("shell input keyevent 82") == ["shell", "input", "keyevent", "82"])
    }

    @Test func honorsQuotes() throws {
        #expect(try CustomCommandService.tokenize(#"shell am broadcast --es msg "hello world""#)
            == ["shell", "am", "broadcast", "--es", "msg", "hello world"])
        #expect(try CustomCommandService.tokenize("shell echo 'a b'") == ["shell", "echo", "a b"])
    }

    @Test func emptyQuotedTokenSurvives() throws {
        #expect(try CustomCommandService.tokenize(#"shell echo """#) == ["shell", "echo", ""])
    }

    @Test func unbalancedQuoteThrows() {
        #expect(throws: CustomCommandService.TemplateError.unbalancedQuote) {
            _ = try CustomCommandService.tokenize(#"shell echo "oops"#)
        }
    }

    @Test func emptyTemplateThrows() {
        #expect(throws: CustomCommandService.TemplateError.empty) {
            _ = try CustomCommandService.tokenize("   ")
        }
    }

    @Test func substitutesPlaceholders() throws {
        let args = try CustomCommandService.buildArgs(
            template: "shell am force-stop {bundleId}", bundleId: "com.app", serial: "S1"
        )
        #expect(args == ["shell", "am", "force-stop", "com.app"])
    }

    @Test func placeholderValueStaysOneTokenEvenWithSpaces() throws {
        // Substitution happens after tokenization, so a value containing spaces
        // or metacharacters can't split into extra adb arguments.
        let args = try CustomCommandService.buildArgs(
            template: "shell am force-stop {bundleId}", bundleId: "com.app extra;arg", serial: "S1"
        )
        #expect(args == ["shell", "am", "force-stop", "com.app extra;arg"])
    }

    @Test func dropsLeadingAdbToken() throws {
        let args = try CustomCommandService.buildArgs(template: "adb devices", bundleId: nil, serial: "")
        #expect(args == ["devices"])
    }

    @Test func bundlePlaceholderWithoutBundleThrows() {
        #expect(throws: CustomCommandService.TemplateError.missingBundle) {
            _ = try CustomCommandService.buildArgs(template: "shell pm clear {bundleId}", bundleId: nil, serial: "S1")
        }
    }

    @Test func runInjectsSerialWhenAbsent() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s", "S1", "shell"], stdout: "done")
        let service = CustomCommandService(client: await makeTestClient(runner: runner))
        let command = CustomCommand(name: "Test", command: "shell echo hi", needsBundle: false, createdAt: 0)

        let result = await service.run(command: command, bundleId: nil, serial: "S1")
        #expect(result.ok)
        #expect(runner.invocations.last?.arguments == ["-s", "S1", "shell", "echo", "hi"])
    }

    @Test func shellKindRunsTheLineThroughTheLoginShell() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-lc"], stdout: "ran")
        let service = CustomCommandService(
            client: await makeTestClient(runner: runner), loginShell: "/bin/zsh"
        )
        let command = CustomCommand(
            name: "Script", command: "~/scripts/reset.sh {serial}", kind: .shell,
            needsBundle: false, createdAt: 0
        )

        let result = await service.run(command: command, bundleId: nil, serial: "S1")
        #expect(result.ok)
        #expect(result.message == "ran")
        let invocation = runner.invocations.last
        #expect(invocation?.executable == "/bin/zsh")
        // The line is not device-scoped (no ANDROID_SERIAL export) — {serial}
        // is the only way a shell command targets the selection. It rides as a
        // positional $1 so rc-sourced aliases expand via eval without any
        // splicing/quoting of the user's line.
        #expect(invocation?.arguments == [
            "-lc",
            "[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1; eval \"$1\"",
            "droidective", "~/scripts/reset.sh S1",
        ])
    }

    @Test func terminalLinePrefixesAdbAndSubstitutes() throws {
        let adb = CustomCommand(
            name: "Force stop", command: "shell am force-stop {bundleId}",
            kind: .adb, needsBundle: true, createdAt: 0
        )
        #expect(try CustomCommandService.terminalLine(command: adb, bundleId: "com.app", serial: "S1")
            == "adb shell am force-stop com.app")

        // An "adb" the user already typed isn't doubled.
        let typed = CustomCommand(
            name: "Typed", command: "adb devices", kind: .adb, needsBundle: false, createdAt: 0
        )
        #expect(try CustomCommandService.terminalLine(command: typed, bundleId: nil, serial: "")
            == "adb devices")

        // Shell lines pass through as written, placeholders substituted.
        let shell = CustomCommand(
            name: "Script", command: "~/scripts/reset.sh {serial}",
            kind: .shell, needsBundle: false, createdAt: 0
        )
        #expect(try CustomCommandService.terminalLine(command: shell, bundleId: nil, serial: "S1")
            == "~/scripts/reset.sh S1")

        let needsBundle = CustomCommand(
            name: "Needs", command: "echo {bundleId}", kind: .shell, needsBundle: true, createdAt: 0
        )
        #expect(throws: CustomCommandService.TemplateError.missingBundle) {
            try CustomCommandService.terminalLine(command: needsBundle, bundleId: nil, serial: "")
        }
    }

    @Test func savesPredatingRunsInTerminalDecodeAsSilent() throws {
        let json = Data("""
        [{"id": "1", "name": "Old", "command": "devices", "needsBundle": false, "createdAt": 0}]
        """.utf8)
        let commands = try JSONDecoder().decode([CustomCommand].self, from: json)
        #expect(commands[0].runsInTerminal == false)
        #expect(commands[0].kind == .adb)
    }

    @Test func decodesLegacySavesWithoutTerminalAsInApp() throws {
        let json = Data("""
        [{"id": "1", "name": "Old", "command": "devices", "needsBundle": false, "createdAt": 0, "runsInTerminal": true}]
        """.utf8)
        let commands = try JSONDecoder().decode([CustomCommand].self, from: json)
        #expect(commands[0].terminal == .droidective)
        #expect(commands[0].pinned == false)
    }

    @Test func unknownTerminalValueDecodesAsInAppNotCorrupt() throws {
        // A retired terminal choice must never set the whole file aside.
        let json = Data("""
        [{"id": "1", "name": "Old", "command": "devices", "needsBundle": false, "createdAt": 0, "terminal": "iterm"}]
        """.utf8)
        let commands = try JSONDecoder().decode([CustomCommand].self, from: json)
        #expect(commands[0].terminal == .droidective)
    }

    @Test func commandScriptExportsQuotedSerialAndRunsTheLine() {
        let script = CustomCommandService.commandScript(
            line: "adb shell am force-stop com.app",
            serial: "emu'; reboot; '",
            shellPath: "/bin/zsh"
        )
        // The serial reaches a Mac shell verbatim — it must stay one quoted
        // assignment, never become code.
        #expect(script == """
        #!/bin/zsh -l
        export ANDROID_SERIAL='emu'\\''; reboot; '\\'''
        adb shell am force-stop com.app

        """)
    }

    @Test func commandScriptSkipsSerialExportWhenEmpty() {
        let script = CustomCommandService.commandScript(
            line: "~/scripts/reset.sh", serial: "", shellPath: "/opt/homebrew/bin/fish"
        )
        #expect(script == "#!/opt/homebrew/bin/fish -l\n~/scripts/reset.sh\n")
    }

    @Test func commandScriptFallsBackToZshForEmptyShell() {
        let script = CustomCommandService.commandScript(line: "ls", serial: "S1", shellPath: "")
        #expect(script.hasPrefix("#!/bin/zsh -l\n"))
    }

    @Test func shellInvocationSourcesTheMatchingRcFile() {
        let zsh = CustomCommandService.shellInvocation(line: "bs", shellPath: "/bin/zsh")
        #expect(zsh.executable == "/bin/zsh")
        #expect(zsh.arguments == [
            "-lc",
            "[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1; eval \"$1\"",
            "droidective", "bs",
        ])

        // bash keeps aliases off in non-interactive shells — the preamble must
        // switch them on before the eval re-parse.
        let bash = CustomCommandService.shellInvocation(line: "bs", shellPath: "/opt/homebrew/bin/bash")
        #expect(bash.executable == "/opt/homebrew/bin/bash")
        #expect(bash.arguments == [
            "-lc",
            "shopt -s expand_aliases; [ -f ~/.bashrc ] && source ~/.bashrc >/dev/null 2>&1; eval \"$1\"",
            "droidective", "bs",
        ])

        // fish (and anything else) sources its own config in every shell — no
        // preamble, and no zsh/bash eval syntax assumed.
        let fish = CustomCommandService.shellInvocation(line: "bs", shellPath: "/opt/homebrew/bin/fish")
        #expect(fish.executable == "/opt/homebrew/bin/fish")
        #expect(fish.arguments == ["-lc", "bs"])

        // An empty SHELL falls back to zsh, the macOS default.
        let fallback = CustomCommandService.shellInvocation(line: "bs", shellPath: "")
        #expect(fallback.executable == "/bin/zsh")
    }

    @Test func shellKindSubstitutesBundleAndReportsFailure() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-lc"], stderr: "boom", exitCode: 1)
        let service = CustomCommandService(
            client: await makeTestClient(runner: runner), loginShell: "/bin/zsh"
        )
        let command = CustomCommand(
            name: "Fails", command: "echo {bundleId}", kind: .shell,
            needsBundle: false, createdAt: 0
        )

        let result = await service.run(command: command, bundleId: "com.app", serial: "")
        #expect(result.ok == false)
        #expect(result.message == "boom")
        #expect(runner.invocations.last?.arguments.last == "echo com.app")
    }

    @Test func shellKindMissingBundleFailsWithoutRunning() async {
        let runner = MockProcessRunner()
        let service = CustomCommandService(client: await makeTestClient(runner: runner))
        let command = CustomCommand(
            name: "NeedsBundle", command: "echo {bundleId}", kind: .shell,
            needsBundle: true, createdAt: 0
        )

        let result = await service.run(command: command, bundleId: nil, serial: "S1")
        #expect(result.ok == false)
        #expect(runner.invocations.isEmpty)
    }

    @Test func savesWithoutKindDecodeAsAdb() throws {
        let legacy = Data(#"""
        {"id":"1","name":"Old","command":"devices","needsBundle":false,"createdAt":0}
        """#.utf8)
        let decoded = try JSONDecoder().decode(CustomCommand.self, from: legacy)
        #expect(decoded.kind == .adb)
        #expect(decoded.command == "devices")
    }
}
