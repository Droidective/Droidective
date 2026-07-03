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

    @Test func shellKindRunsTheLineThroughZsh() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-lc"], stdout: "ran")
        let service = CustomCommandService(client: await makeTestClient(runner: runner))
        let command = CustomCommand(
            name: "Script", command: "~/scripts/reset.sh {serial}", kind: .shell,
            needsBundle: false, createdAt: 0
        )

        let result = await service.run(command: command, bundleId: nil, serial: "S1")
        #expect(result.ok)
        #expect(result.message == "ran")
        let invocation = runner.invocations.last
        #expect(invocation?.executable == "/bin/zsh")
        #expect(invocation?.arguments == ["-lc", "export ANDROID_SERIAL='S1'; ~/scripts/reset.sh S1"])
    }

    @Test func shellLineExportsTheSelectedSerialQuoted() throws {
        let line = try CustomCommandService.shellLine(
            template: "adb shell pidof {bundleId}", bundleId: "com.app", serial: "192.168.1.5:5555"
        )
        #expect(line == "export ANDROID_SERIAL='192.168.1.5:5555'; adb shell pidof com.app")

        let bare = try CustomCommandService.shellLine(template: "echo hi", bundleId: nil, serial: "")
        #expect(bare == "echo hi")
    }

    @Test func shellKindSubstitutesBundleAndReportsFailure() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-lc"], stderr: "boom", exitCode: 1)
        let service = CustomCommandService(client: await makeTestClient(runner: runner))
        let command = CustomCommand(
            name: "Fails", command: "echo {bundleId}", kind: .shell,
            needsBundle: false, createdAt: 0
        )

        let result = await service.run(command: command, bundleId: "com.app", serial: "")
        #expect(result.ok == false)
        #expect(result.message == "boom")
        #expect(runner.invocations.last?.arguments == ["-lc", "echo com.app"])
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
