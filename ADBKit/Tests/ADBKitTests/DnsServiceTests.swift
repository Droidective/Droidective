import Testing
@testable import ADBKit

@Suite struct DnsSetHostnameArgTests {
    @Test func setHostnameQuotesTheHostname() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["-s"], stdout: "")
        let service = DnsService(client: await makeTestClient(runner: runner))

        _ = try await service.setHostname(serial: "S1", "dns.example.com; reboot")
        #expect(runner.invocations.contains {
            $0.arguments == [
                "-s", "S1", "shell", "settings", "put", "global",
                "private_dns_specifier", "'dns.example.com; reboot'",
            ]
        })
    }
}

@Suite struct DnsServiceTests {
    @Test func parsesOff() {
        let status = DnsService.parse(mode: "off", specifier: "null")
        #expect(status.mode == .off)
        #expect(status.hostname == nil)
    }

    @Test func parsesHostname() {
        let status = DnsService.parse(mode: "hostname", specifier: "dns.google")
        #expect(status.mode == .hostname)
        #expect(status.hostname == "dns.google")
    }

    @Test func opportunisticAndUnsetMapToAutomatic() {
        #expect(DnsService.parse(mode: "opportunistic", specifier: "null").mode == .automatic)
        #expect(DnsService.parse(mode: "null", specifier: "").mode == .automatic)
        #expect(DnsService.parse(mode: "", specifier: "").mode == .automatic)
    }
}
