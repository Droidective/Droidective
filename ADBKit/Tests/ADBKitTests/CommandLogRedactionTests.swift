import Testing
@testable import ADBKit

/// The pairing code is the one credential this app puts in an argument
/// vector, and the Command Log is copied out of Settings into bug reports.
@Suite struct CommandLogRedactionTests {
    @Test func thePairingCodeIsMaskedAndTheEndpointIsKept() {
        // "a pair ran here, against this endpoint" is the useful half.
        #expect(AdbClient.loggedCommand(["pair", "192.168.1.42:37123", "aaaabbbbcccc"])
            == "adb pair 192.168.1.42:37123 <pairing code redacted>")
    }

    @Test func theCodeNeverSurvivesInAnyForm() {
        let logged = AdbClient.loggedCommand(["pair", "10.0.0.7:41235", "hunter2hunter2"])
        #expect(!logged.contains("hunter2hunter2"))
    }

    @Test func aDeviceScopedPairIsStillMasked() {
        // `-s <serial>` is the only prefix adb takes before the subcommand;
        // counting from zero would mask the wrong argument.
        #expect(AdbClient.loggedCommand(["-s", "R58M4", "pair", "10.0.0.7:41235", "secretcode12"])
            == "adb -s R58M4 pair 10.0.0.7:41235 <pairing code redacted>")
    }

    @Test func aPairWithNoCodeIsLeftAlone() {
        // adb prompts for the code interactively — there is nothing to mask,
        // and inventing an argument would read as a malformed command.
        #expect(AdbClient.loggedCommand(["pair", "192.168.1.42:37123"])
            == "adb pair 192.168.1.42:37123")
    }

    @Test func everyOtherCommandIsUntouched() {
        #expect(AdbClient.loggedCommand(["connect", "192.168.1.42:40913"])
            == "adb connect 192.168.1.42:40913")
        #expect(AdbClient.loggedCommand(["devices", "-l"]) == "adb devices -l")
        #expect(AdbClient.loggedCommand(["-s", "R58M4", "shell", "getprop"])
            == "adb -s R58M4 shell getprop")
        #expect(AdbClient.loggedCommand([]) == "adb ")
    }

    @Test func theWordPairAsAnArgumentIsNotASubcommand() {
        // Only the subcommand slot counts — masking on any occurrence would
        // redact a real argument someone needs to read.
        #expect(AdbClient.loggedCommand(["shell", "am", "start", "pair", "a", "b"])
            == "adb shell am start pair a b")
    }

    @Test func theRealClientLogsTheMaskedForm() async throws {
        // End to end: what the log actually holds after a pair, not just what
        // the pure helper returns.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["pair"], stdout: "Successfully paired to 192.168.1.42:37123")
        let log = CommandLog()
        let locator = ToolLocator(runner: runner, environment: [:])
        await locator.seed(.adb, path: "/fake/adb")
        let client = AdbClient(locator: locator, runner: runner, log: log)

        _ = try await CommandLog.userInitiated {
            try await client.run(["pair", "192.168.1.42:37123", "aaaabbbbcccc"])
        }
        let entries = await log.snapshot()
        #expect(entries.contains { $0.command.contains("<pairing code redacted>") })
        #expect(!entries.contains { $0.command.contains("aaaabbbbcccc") })
        // The password still reached adb itself — only the log is masked.
        #expect(runner.invocations.contains {
            $0.arguments == ["pair", "192.168.1.42:37123", "aaaabbbbcccc"]
        })
    }
}
