import Testing
@testable import ADBKit

@Suite struct WirelessEndpointParserTests {
    @Test func splitsHostAndPort() {
        #expect(
            ConnectionService.parseEndpoint("192.168.1.42:37123")
                == WirelessEndpoint(host: "192.168.1.42", port: "37123"))
    }

    @Test func bareHostHasNoPort() {
        #expect(
            ConnectionService.parseEndpoint("192.168.1.42")
                == WirelessEndpoint(host: "192.168.1.42", port: nil))
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(
            ConnectionService.parseEndpoint("  192.168.1.42:5555\n")
                == WirelessEndpoint(host: "192.168.1.42", port: "5555"))
    }

    @Test func acceptsHostnames() {
        #expect(
            ConnectionService.parseEndpoint("pixel.local:5555")
                == WirelessEndpoint(host: "pixel.local", port: "5555"))
    }

    @Test func bracketedIPv6KeepsBrackets() {
        #expect(
            ConnectionService.parseEndpoint("[fe80::1]:37123")
                == WirelessEndpoint(host: "[fe80::1]", port: "37123"))
        #expect(
            ConnectionService.parseEndpoint("[fe80::1]")
                == WirelessEndpoint(host: "[fe80::1]", port: nil))
    }

    @Test func bareIPv6GetsBracketed() {
        #expect(
            ConnectionService.parseEndpoint("fe80::aa:1")
                == WirelessEndpoint(host: "[fe80::aa:1]", port: nil))
    }

    @Test func connectParseDefaultsBareHostToPort5555() {
        #expect(
            ConnectionService.parseConnectEndpoint("10.158.128.7")
                == WirelessEndpoint(host: "10.158.128.7", port: "5555"))
        #expect(
            ConnectionService.parseConnectEndpoint("pixel.local")
                == WirelessEndpoint(host: "pixel.local", port: "5555"))
        #expect(
            ConnectionService.parseConnectEndpoint("fe80::aa:1")
                == WirelessEndpoint(host: "[fe80::aa:1]", port: "5555"))
        #expect(
            ConnectionService.parseConnectEndpoint("[fe80::1]")
                == WirelessEndpoint(host: "[fe80::1]", port: "5555"))
    }

    @Test func connectParseKeepsAnExplicitPort() {
        #expect(
            ConnectionService.parseConnectEndpoint("192.168.1.42:40913")
                == WirelessEndpoint(host: "192.168.1.42", port: "40913"))
        #expect(
            ConnectionService.parseConnectEndpoint("[fe80::1]:37123")
                == WirelessEndpoint(host: "[fe80::1]", port: "37123"))
    }

    @Test func connectParseStillRejectsGarbage() {
        #expect(ConnectionService.parseConnectEndpoint("") == nil)
        #expect(ConnectionService.parseConnectEndpoint("192.168.1.42:") == nil)
        #expect(ConnectionService.parseConnectEndpoint("192.168.1.42 :5555") == nil)
    }

    @Test func rejectsImplausibleHosts() {
        #expect(ConnectionService.parseEndpoint("1.1.1") == nil)
        #expect(ConnectionService.parseEndpoint("1.1.1.") == nil)
        #expect(ConnectionService.parseEndpoint("1.1.1.1.1") == nil)
        #expect(ConnectionService.parseEndpoint("256.1.1.1:5555") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1:5555") == nil)
        #expect(ConnectionService.parseEndpoint("1234.1.1.1") == nil)
        #expect(ConnectionService.parseConnectEndpoint("1.1.1") == nil)
        #expect(ConnectionService.parseEndpoint("[not-an-address]:5555") == nil)
        #expect(ConnectionService.parseEndpoint("-bad-.local:5555") == nil)
        #expect(ConnectionService.parseEndpoint("a..b:5555") == nil)
    }

    @Test func rejectsOutOfRangePorts() {
        #expect(ConnectionService.parseEndpoint("192.168.1.42:0") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42:65536") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42:99999") == nil)
        #expect(ConnectionService.parseConnectEndpoint("192.168.1.42:0") == nil)
        #expect(
            ConnectionService.parseEndpoint("192.168.1.42:65535")
                == WirelessEndpoint(host: "192.168.1.42", port: "65535"))
    }

    @Test func rejectsURLPastes() {
        #expect(ConnectionService.parseEndpoint("http://1.2.3.4:5555") == nil)
        #expect(ConnectionService.parseEndpoint("http://x") == nil)
        #expect(ConnectionService.parseConnectEndpoint("http://1.2.3.4:5555") == nil)
    }

    @Test func acceptsZonedIPv6() {
        #expect(
            ConnectionService.parseEndpoint("[fe80::1%en0]:5555")
                == WirelessEndpoint(host: "[fe80::1%en0]", port: "5555"))
    }

    @Test func rejectsGarbage() {
        #expect(ConnectionService.parseEndpoint("") == nil)
        #expect(ConnectionService.parseEndpoint("   ") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42:") == nil)
        #expect(ConnectionService.parseEndpoint(":5555") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42:port") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42:123456") == nil)
        #expect(ConnectionService.parseEndpoint("192.168.1.42 :5555") == nil)
        #expect(ConnectionService.parseEndpoint("[fe80::1") == nil)
        #expect(ConnectionService.parseEndpoint("[fe80::1]5555") == nil)
    }
}

@Suite struct ConnectionServiceArgTests {
    private func makeService(runner: MockProcessRunner) async -> ConnectionService {
        let client = await makeTestClient(runner: runner)
        return ConnectionService(client: client, monitor: DeviceMonitor(client: client))
    }

    @Test func pairSendsHostPortAndCode() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["pair"], stdout: "Successfully paired to 192.168.1.42:37123")
        let service = await makeService(runner: runner)

        let result = try await service.pair(host: "192.168.1.42", port: "37123", code: "123456")
        #expect(result.ok)
        #expect(runner.invocations.contains {
            $0.arguments == ["pair", "192.168.1.42:37123", "123456"]
        })
    }

    @Test func pairFailureSurfacesAdbReason() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["pair"], stderr: "failed: wrong code", exitCode: 1)
        let service = await makeService(runner: runner)

        let result = try await service.pair(host: "192.168.1.42", port: "37123", code: "000000")
        #expect(!result.ok)
        #expect(result.message == "failed: wrong code")
    }

    @Test func connectSendsHostPort() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["connect"], stdout: "connected to 192.168.1.42:5555")
        runner.script(argsPrefix: ["devices"], stdout: "List of devices attached\n")
        let service = await makeService(runner: runner)

        let result = try await service.connect(host: "192.168.1.42", port: "5555")
        #expect(result.ok)
        #expect(runner.invocations.contains {
            $0.arguments == ["connect", "192.168.1.42:5555"]
        })
    }

    @Test func connectFailureSurfacesAdbOutput() async throws {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["connect"], stdout: "failed to connect to 192.168.1.42:5555")
        runner.script(argsPrefix: ["devices"], stdout: "List of devices attached\n")
        let service = await makeService(runner: runner)

        let result = try await service.connect(host: "192.168.1.42", port: "5555")
        #expect(!result.ok)
        #expect(result.message == "failed to connect to 192.168.1.42:5555")
    }

    @Test func discoverQueriesMdnsServicesAndMatchesTheHost() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["mdns"], stdout: """
        List of discovered mdns services
        adb-R58M4-pair\t_adb-tls-pairing._tcp\t192.168.1.42:37123
        adb-OTHER-conn\t_adb-tls-connect._tcp\t192.168.1.99:41000
        adb-R58M4-conn\t_adb-tls-connect._tcp\t192.168.1.42:40913
        """)
        let service = await makeService(runner: runner)

        let endpoint = await service.discoverConnectEndpoint(host: "192.168.1.42")
        #expect(endpoint == WirelessEndpoint(host: "192.168.1.42", port: "40913"))
        #expect(runner.invocations.contains { $0.arguments == ["mdns", "services"] })
        // The pairing service and the other device's endpoint never match.
        #expect(endpoint?.port != "37123")
    }

    @Test func discoverRetriesThenGivesUpQuietly() async {
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["mdns"], stdout: "List of discovered mdns services\n")
        let service = await makeService(runner: runner)

        let endpoint = await service.discoverConnectEndpoint(
            host: "192.168.1.42", attempts: 3, delay: .milliseconds(1))
        #expect(endpoint == nil)
        #expect(runner.invocations.filter { $0.arguments == ["mdns", "services"] }.count == 3)
    }

    @Test func discoverTreatsMdnsUnsupportedAsNotFound() async {
        // Older adb: "mdns" is an unknown command on stderr, non-zero exit.
        let runner = MockProcessRunner()
        runner.script(argsPrefix: ["mdns"], stderr: "adb: unknown command mdns", exitCode: 1)
        let service = await makeService(runner: runner)

        let endpoint = await service.discoverConnectEndpoint(
            host: "192.168.1.42", attempts: 2, delay: .milliseconds(1))
        #expect(endpoint == nil)
    }
}

@Suite struct MdnsServicesParserTests {
    @Test func parsesTabSeparatedRowsAndSkipsTheHeader() {
        let output = """
        List of discovered mdns services
        adb-R58M4-pair\t_adb-tls-pairing._tcp\t192.168.1.42:37123
        adb-R58M4-conn\t_adb-tls-connect._tcp\t192.168.1.42:40913
        """
        let services = ConnectionService.parseMdnsServices(output)
        #expect(services == [
            ConnectionService.MdnsService(
                name: "adb-R58M4-pair", type: "_adb-tls-pairing._tcp",
                endpoint: WirelessEndpoint(host: "192.168.1.42", port: "37123")),
            ConnectionService.MdnsService(
                name: "adb-R58M4-conn", type: "_adb-tls-connect._tcp",
                endpoint: WirelessEndpoint(host: "192.168.1.42", port: "40913")),
        ])
    }

    @Test func toleratesSpaceSeparationAndTrailingTypeDot() {
        let services = ConnectionService.parseMdnsServices(
            "adb-X   _adb-tls-connect._tcp.   10.0.0.7:39001")
        #expect(services.count == 1)
        #expect(services.first?.type == "_adb-tls-connect._tcp.")
        #expect(services.first?.endpoint == WirelessEndpoint(host: "10.0.0.7", port: "39001"))
    }

    @Test func crlfSplitsCleanly() {
        let services = ConnectionService.parseMdnsServices(
            "adb-A\t_adb-tls-connect._tcp\t10.0.0.1:40000\r\nadb-B\t_adb-tls-connect._tcp\t10.0.0.2:40001")
        #expect(services.count == 2)
    }

    @Test func skipsMalformedRows() {
        let output = """
        adb-A\t_adb-tls-connect._tcp\tnot-an-endpoint:99999999
        adb-B\t_adb-tls-connect._tcp
        just one field
        adb-C\t_adb-tls-connect._tcp\t10.0.0.3
        """
        // A giant port, a missing column, and a portless endpoint all drop.
        #expect(ConnectionService.parseMdnsServices(output).isEmpty)
    }

    @Test func emptyInputYieldsNothing() {
        #expect(ConnectionService.parseMdnsServices("").isEmpty)
        #expect(ConnectionService.parseMdnsServices("List of discovered mdns services\n").isEmpty)
    }
}

/// The IPv6 literal check is hand-written Swift rather than `inet_pton`, whose
/// `in6_addr`/`AF_INET6` symbols are absent on Windows. These pin the grammar so
/// the replacement cannot quietly drift from what a resolver would accept.
/// Exercised through `parseEndpoint`, since the validator itself is private.
@Suite struct ConnectionServiceIPv6GrammarTests {
    private func accepts(_ literal: String) -> Bool {
        ConnectionService.parseEndpoint("[\(literal)]:5555") != nil
    }

    @Test func acceptsTheFullEightGroupForm() {
        #expect(accepts("2001:0db8:85a3:0000:0000:8a2e:0370:7334"))
        #expect(accepts("2001:db8:85a3:0:0:8a2e:370:7334"))
    }

    @Test func acceptsCompressedForms() {
        #expect(accepts("::"))
        #expect(accepts("::1"))
        #expect(accepts("fe80::"))
        #expect(accepts("fe80::1"))
        #expect(accepts("2001:db8::8a2e:370:7334"))
        // Seven explicit groups plus a run standing for the eighth.
        #expect(accepts("1:2:3:4:5:6:7::"))
    }

    @Test func acceptsATrailingDottedQuad() {
        #expect(accepts("::ffff:192.168.1.1"))
        #expect(accepts("64:ff9b::192.0.2.33"))
        #expect(accepts("1:2:3:4:5:6:1.2.3.4"))
    }

    @Test func rejectsWrongGroupCounts() {
        #expect(!accepts("1:2:3:4:5:6:7"))
        #expect(!accepts("1:2:3:4:5:6:7:8:9"))
        // A compression run must cover at least one group.
        #expect(!accepts("1:2:3:4:5:6:7:8::"))
    }

    @Test func rejectsMalformedGroupsAndSeparators() {
        #expect(!accepts("1::2::3"), "only one compression run is legal")
        #expect(!accepts("fe80:"), "a trailing colon leaves an empty group")
        #expect(!accepts(":1:2:3:4:5:6:7"), "a leading colon leaves an empty group")
        #expect(!accepts("fe80::1::"))
        #expect(!accepts("12345::1"), "a group is at most four hex digits")
        #expect(!accepts("fe8g::1"), "g is not a hex digit")
        #expect(!accepts(""))
    }

    @Test func rejectsABadDottedQuadTail() {
        #expect(!accepts("::ffff:192.168.1.256"))
        #expect(!accepts("::ffff:192.168.1"))
    }

    @Test func toleratesAZoneIndex() {
        #expect(accepts("fe80::1%en0"))
        #expect(accepts("fe80::1%2"))
        #expect(!accepts("%en0"), "a zone with no address is not an address")
    }

    /// `Character.isHexDigit` is also true for fullwidth and other non-ASCII
    /// digit forms, which `inet_pton` — the call this grammar replaced —
    /// rejects. Differential-tested against `inet_pton` over 200k inputs:
    /// these were the only divergences, so the hextet check stays ASCII-only.
    @Test func rejectsNonASCIIHexDigits() {
        #expect(!accepts("\u{FF11}::1"), "U+FF11 FULLWIDTH DIGIT ONE is not a hex digit")
        #expect(!accepts("::\u{FF11}"))
        #expect(!accepts("::\u{FF41}"), "U+FF41 FULLWIDTH LATIN SMALL LETTER A")
        #expect(!accepts("4ac5::\u{FF11}"))
        #expect(!accepts("\u{0663}::1"), "Arabic-Indic digit three")
    }
}
